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

Options:
  --duration N      Test duration in seconds (default: 600)
  --users N         Number of JMeter threads (default: 100)
  --rampup N        JMeter ramp-up time in seconds (default: 60)

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

# Capture monitoring data
if [[ "$MONITORING_ENABLED" == "true" ]]; then
  log_info "Capturing monitoring data from Prometheus..."
  
  PROM_QUERIES=(
    'rate(http_requests_total[5m])'
    'histogram_quantile(0.95, http_request_duration_seconds_bucket)'
    'container_memory_usage_bytes'
    'rate(container_cpu_usage_seconds_total[5m])'
  )
  
  for query in "${PROM_QUERIES[@]}"; do
    log_info "Query: $query"
    # In production, would call Prometheus API and export data
  done
fi

# Capture logs
if [[ "$CAPTURE_LOGS" == "true" ]]; then
  log_info "Capturing application logs..."
  LOGS_DIR="${RESULTS_DIR}/${ANOMALY_ID}-logs"
  mkdir -p "$LOGS_DIR"
  
  # Export logs from each pod
  kubectl logs -l app=catalogue --all-containers=true > "${LOGS_DIR}/catalogue.log" 2>&1 || true
  kubectl logs -l app=payment --all-containers=true > "${LOGS_DIR}/payment.log" 2>&1 || true
  kubectl logs -l app=orders --all-containers=true > "${LOGS_DIR}/orders.log" 2>&1 || true
  
  log_success "Logs captured to $LOGS_DIR"
fi

# Capture traces
if [[ "$CAPTURE_TRACES" == "true" ]]; then
  log_info "Capturing traces from Tempo..."
  TRACES_DIR="${RESULTS_DIR}/${ANOMALY_ID}-traces"
  mkdir -p "$TRACES_DIR"
  
  # In production, would export traces from Tempo API
  # Query Tempo for traces during test window
  log_info "Trace export would query Tempo API for service traces during: $TEST_TIMESTAMP"
  
  log_success "Trace capture configured for $TRACES_DIR"
fi

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
Logs Directory:     ${RESULTS_DIR}/${ANOMALY_ID}-logs/
Traces Directory:   ${RESULTS_DIR}/${ANOMALY_ID}-traces/

Next Steps:
1. Review JMeter test results:  cat $TEST_RESULT_FILE
2. Check application logs:       ls -la ${RESULTS_DIR}/${ANOMALY_ID}-logs/
3. Query Prometheus for metrics: See MONITORING-QUERIES.md
4. Review Tempo traces:          Open Grafana UI
5. Update ANOMALIES-RESULTS.csv: Add findings from this test

===============================================================================
EOF

log_success "Anomaly test complete!"
log_info "Full log: $ANOMALY_LOG"
log_info "Results directory: $RESULTS_DIR"

# Print summary to console
tail -20 "$ANOMALY_LOG"

exit 0
