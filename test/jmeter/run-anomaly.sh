#!/bin/bash

################################################################################
# Sock Shop - Anomaly Testing Suite
# Master script to run individual anomaly scenarios
#
# Usage: ./run-anomaly.sh <anomaly-id> [options]
# Example: ./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_DIR="${WORKSPACE_ROOT}/deploy/docker-compose"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
ANOMALY_LOG="${RESULTS_DIR}/anomaly.log"

# Default values
ANOMALY_ID="${1:-}"
DURATION=${DURATION:-600}          # seconds
USERS=${USERS:-100}
RAMPUP=${RAMPUP:-60}
JMETER_SCRIPT="${SCRIPT_DIR}/sock-shop-basic-loadtest.jmx"
MONITORING_ENABLED=${MONITORING_ENABLED:-true}
CAPTURE_TRACES=${CAPTURE_TRACES:-true}
CAPTURE_LOGS=${CAPTURE_LOGS:-true}
EXPAND_BEFORE_SECONDS=${EXPAND_BEFORE_SECONDS:-900}
EXPAND_AFTER_SECONDS=${EXPAND_AFTER_SECONDS:-900}
PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:9090}
LOKI_URL=${LOKI_URL:-http://localhost:3100}
TEMPO_URL=${TEMPO_URL:-http://localhost:3200}
PROM_QUERY_STEP_SECONDS=${PROM_QUERY_STEP_SECONDS:-15}
DOCKER_LOG_SERVICES=${DOCKER_LOG_SERVICES:-"front-end edge-router catalogue catalogue-db carts carts-db orders orders-db shipping queue-master rabbitmq payment user user-db"}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --duration)
      DURATION=$2
      shift 2
      ;;
    --users)
      USERS=$2
      shift 2
      ;;
    --rampup)
      RAMPUP=$2
      shift 2
      ;;
    *)
      if [[ -z "$ANOMALY_ID" ]]; then
        ANOMALY_ID=$1
      fi
      shift
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$ANOMALY_LOG"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$ANOMALY_LOG"
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $*" | tee -a "$ANOMALY_LOG"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*" | tee -a "$ANOMALY_LOG"
}

to_rfc3339() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

collect_observability_data() {
  local test_start_epoch="$1"
  local test_end_epoch="$2"
  local results_file="$3"

  local jmeter_start_epoch="$test_start_epoch"
  local jmeter_end_epoch="$test_end_epoch"
  local jmeter_start_ms
  local jmeter_end_ms

  if [[ -f "$results_file" ]]; then
    jmeter_start_ms=$(awk -F',' 'NR > 1 && $1 ~ /^[0-9]+$/ { if (min == "" || $1 < min) min = $1 } END { print min }' "$results_file")
    jmeter_end_ms=$(awk -F',' 'NR > 1 && $1 ~ /^[0-9]+$/ { if (max == "" || $1 > max) max = $1 } END { print max }' "$results_file")

    if [[ -n "${jmeter_start_ms:-}" && -n "${jmeter_end_ms:-}" ]]; then
      jmeter_start_epoch=$((jmeter_start_ms / 1000))
      jmeter_end_epoch=$((jmeter_end_ms / 1000))
      log_info "Using timestamps from JMeter results for export window"
    else
      log_warning "Could not parse JMeter timestamps, using runtime window"
    fi
  fi

  local window_start=$((jmeter_start_epoch - EXPAND_BEFORE_SECONDS))
  local window_end=$((jmeter_end_epoch + EXPAND_AFTER_SECONDS))
  if (( window_start < 0 )); then
    window_start=0
  fi

  local window_start_iso
  local window_end_iso
  window_start_iso=$(to_rfc3339 "$window_start")
  window_end_iso=$(to_rfc3339 "$window_end")

  local export_root="${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}-observability"
  local metrics_dir="${export_root}/metrics"
  local logs_dir="${export_root}/logs"
  local traces_dir="${export_root}/traces"
  mkdir -p "$metrics_dir" "$logs_dir" "$traces_dir"

  cat > "${export_root}/export-metadata.json" << EOF
{
  "anomaly_id": "${ANOMALY_ID}",
  "run_id": "${RUN_ID}",
  "jmeter_results_file": "${results_file}",
  "jmeter_test_start_epoch": ${jmeter_start_epoch},
  "jmeter_test_end_epoch": ${jmeter_end_epoch},
  "expanded_window_start_epoch": ${window_start},
  "expanded_window_end_epoch": ${window_end},
  "expanded_window_start": "${window_start_iso}",
  "expanded_window_end": "${window_end_iso}",
  "expand_before_seconds": ${EXPAND_BEFORE_SECONDS},
  "expand_after_seconds": ${EXPAND_AFTER_SECONDS},
  "prometheus_url": "${PROMETHEUS_URL}",
  "loki_url": "${LOKI_URL}",
  "tempo_url": "${TEMPO_URL}"
}
EOF

  if [[ "$MONITORING_ENABLED" == "true" ]]; then
    log_info "Exporting Prometheus metrics for expanded window ${window_start_iso} -> ${window_end_iso}"
    local prom_queries=(
      'sum(rate(http_requests_total[1m])) by (service,status)'
      'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le,service))'
      'sum(container_memory_usage_bytes) by (container_label_com_docker_compose_service)'
      'sum(rate(container_cpu_usage_seconds_total[1m])) by (container_label_com_docker_compose_service)'
      'up'
    )

    local i=1
    local query
    for query in "${prom_queries[@]}"; do
      local safe_name
      safe_name=$(echo "$query" | tr '[:space:]' '_' | sed 's#[^a-zA-Z0-9_-]#_#g' | cut -c1-80)
      curl -sS --get "${PROMETHEUS_URL}/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=${window_start}" \
        --data-urlencode "end=${window_end}" \
        --data-urlencode "step=${PROM_QUERY_STEP_SECONDS}s" \
        -o "${metrics_dir}/${i}-${safe_name}.json" || log_warning "Prometheus export failed for query: ${query}"
      i=$((i + 1))
    done
    log_success "Prometheus exports saved to ${metrics_dir}"
  fi

  if [[ "$CAPTURE_LOGS" == "true" ]]; then
    log_info "Exporting Docker service logs for expanded window"
    local service
    for service in ${DOCKER_LOG_SERVICES}; do
      local container_id
      container_id=$(docker ps --filter "label=com.docker.compose.service=${service}" -q | head -1)
      if [[ -n "$container_id" ]]; then
        docker logs --since "$window_start_iso" --until "$window_end_iso" "$container_id" > "${logs_dir}/${service}.log" 2>&1 || true
      fi
    done

    local loki_start_ns=$((window_start * 1000000000))
    local loki_end_ns=$((window_end * 1000000000))
    curl -sS --get "${LOKI_URL}/loki/api/v1/query_range" \
      --data-urlencode 'query={container=~".+"}' \
      --data-urlencode "start=${loki_start_ns}" \
      --data-urlencode "end=${loki_end_ns}" \
      --data-urlencode "limit=5000" \
      -o "${logs_dir}/loki-query-range.json" || log_warning "Loki export failed"

    log_success "Logs exported to ${logs_dir}"
  fi

  if [[ "$CAPTURE_TRACES" == "true" ]]; then
    log_info "Exporting Tempo traces for expanded window"
    curl -sS --get "${TEMPO_URL}/api/search" \
      --data-urlencode "start=${window_start}" \
      --data-urlencode "end=${window_end}" \
      --data-urlencode "limit=1000" \
      -o "${traces_dir}/tempo-search-seconds.json" || log_warning "Tempo export failed (seconds query)"

    local tempo_start_ns=$((window_start * 1000000000))
    local tempo_end_ns=$((window_end * 1000000000))
    curl -sS --get "${TEMPO_URL}/api/search" \
      --data-urlencode "start=${tempo_start_ns}" \
      --data-urlencode "end=${tempo_end_ns}" \
      --data-urlencode "limit=1000" \
      -o "${traces_dir}/tempo-search-nanoseconds.json" || log_warning "Tempo export failed (nanoseconds query)"

    log_success "Trace export saved to ${traces_dir}"
  fi

  log_success "Observability export complete: ${export_root}"
}

# Print usage
print_usage() {
  cat << EOF
Sock Shop Anomaly Testing Suite

Usage: ./run-anomaly.sh <anomaly-id> [OPTIONS]

Anomalies:
  ANOMALY-001    Memory Pressure (OOM)
  ANOMALY-002    CPU Saturation
  ANOMALY-003    Disk I/O Pressure
  ANOMALY-004    Database Connection Pool Exhaustion
  ANOMALY-005    Cascading Failures
  ANOMALY-006    Partial Degradation
  ANOMALY-007    Network Latency Spikes
  ANOMALY-008    Packet Loss
  ANOMALY-009    Stale Cache
  ANOMALY-010    Database Corruption (Simulated)
  ANOMALY-011    External API Timeout
  ANOMALY-012    Memory Leak (Long-running test)
  ANOMALY-013    Thread Leak / Thread Pool Exhaustion
  ANOMALY-014    Deadlock / Lock Contention
  ANOMALY-015    Resource Exhaustion (stress-ng noisy neighbor)

Options:
  --duration N      Test duration in seconds (default: 600)
  --users N         Number of JMeter threads (default: 100)
  --rampup N        JMeter ramp-up time in seconds (default: 60)

Environment Variables:
  EXPAND_BEFORE_SECONDS   Seconds before test window to export (default: 900)
  EXPAND_AFTER_SECONDS    Seconds after test window to export (default: 900)
  PROMETHEUS_URL          Prometheus API base URL (default: http://localhost:9090)
  LOKI_URL                Loki API base URL (default: http://localhost:3100)
  TEMPO_URL               Tempo API base URL (default: http://localhost:3200)
  PROM_QUERY_STEP_SECONDS Prometheus range query step in seconds (default: 15)

Examples:
  ./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
  ./run-anomaly.sh ANOMALY-002 --duration 300 --users 150
  ./run-anomaly.sh ANOMALY-007 --duration 900 --users 80

EOF
}

# Validate inputs
if [[ -z "$ANOMALY_ID" ]]; then
  log_error "Anomaly ID required"
  print_usage
  exit 1
fi

# Setup results directory
mkdir -p "$RESULTS_DIR"

# Initialize log
{
  echo "================================================================================"
  echo "Sock Shop Anomaly Test: $ANOMALY_ID"
  echo "================================================================================"
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Duration: ${DURATION}s | Users: ${USERS} | Ramp-up: ${RAMPUP}s"
  echo "================================================================================"
} > "$ANOMALY_LOG"

log_info "Starting anomaly test: $ANOMALY_ID"

# Load anomaly-specific configuration
if [[ -f "${SCRIPT_DIR}/tasks/${ANOMALY_ID,,}.sh" ]]; then
  source "${SCRIPT_DIR}/tasks/${ANOMALY_ID,,}.sh"
  log_success "Loaded task script for $ANOMALY_ID"
else
  log_warning "Task script not found for $ANOMALY_ID, using generic execution"
fi

# Record start time
START_TIME=$(date -u +%s)
TEST_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "Pre-test setup complete. Running anomaly test..."

# Run JMeter test
TEST_RESULT_FILE="${RESULTS_DIR}/${ANOMALY_ID}-results.csv"
log_info "Executing JMeter test"
log_info "Command: jmeter -n -t ${JMETER_SCRIPT} -Jusers=${USERS} -Jrampup=${RAMPUP} -Jduration=${DURATION} -l ${TEST_RESULT_FILE}"

jmeter -n \
  -t "$JMETER_SCRIPT" \
  -Jusers="$USERS" \
  -Jrampup="$RAMPUP" \
  -Jduration="$DURATION" \
  -l "$TEST_RESULT_FILE" \
  -j "${RESULTS_DIR}/${ANOMALY_ID}-jmeter.log" 2>&1 | tee -a "$ANOMALY_LOG" || {
  log_error "JMeter test failed"
  exit 1
}

# Record end time
END_TIME=$(date -u +%s)
ACTUAL_DURATION=$((END_TIME - START_TIME))

log_success "JMeter test completed in ${ACTUAL_DURATION}s"
collect_observability_data "$START_TIME" "$END_TIME" "$TEST_RESULT_FILE"

# Cleanup anomaly conditions (if applicable)
if [[ -n "${CLEANUP_ANOMALY:-}" ]]; then
  log_info "Running cleanup for anomaly..."
  eval "$CLEANUP_ANOMALY" 2>&1 | tee -a "$ANOMALY_LOG" || log_warning "Cleanup may have failed"
fi

# Generate summary
log_info "Generating test summary..."
cat >> "$ANOMALY_LOG" << EOF

===============================================================================
                            TEST SUMMARY
===============================================================================
Anomaly ID:         $ANOMALY_ID
Test Timestamp:     $TEST_TIMESTAMP
Duration:           ${ACTUAL_DURATION}s (requested: ${DURATION}s)
JMeter Users:       $USERS
Ramp-up:            ${RAMPUP}s
Results File:       $TEST_RESULT_FILE
Observability Data: ${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}-observability/

Next Steps:
1. Review JMeter test results:  cat $TEST_RESULT_FILE
2. Check exported logs:          ls -la ${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}-observability/logs/
3. Check exported metrics:       ls -la ${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}-observability/metrics/
4. Review exported traces:       ls -la ${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}-observability/traces/
5. Update ANOMALIES-RESULTS.csv: Add findings from this test

===============================================================================
EOF

log_success "Anomaly test complete!"
log_info "Full log: $ANOMALY_LOG"
log_info "Results directory: $RESULTS_DIR"

# Print summary to console
tail -20 "$ANOMALY_LOG"

exit 0
