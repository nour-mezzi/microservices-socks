#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_DIR="${WORKSPACE_ROOT}/deploy/docker-compose"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
# RUN_DIR, ANOMALY_LOG, and COMPREHENSIVE_CSV are set after arg parsing (requires ANOMALY_ID + RUN_ID)

ANOMALY_ID="${1:-}"
DURATION=${DURATION:-600}
USERS=${USERS:-100}
RAMPUP=${RAMPUP:-60}
JMETER_SCRIPT="${SCRIPT_DIR}/sock-shop-realistic-user-journey.jmx"
MONITORING_ENABLED=${MONITORING_ENABLED:-true}
CAPTURE_TRACES=${CAPTURE_TRACES:-true}
CAPTURE_LOGS=${CAPTURE_LOGS:-true}
EXPAND_BEFORE_SECONDS=${EXPAND_BEFORE_SECONDS:-900}
EXPAND_AFTER_SECONDS=${EXPAND_AFTER_SECONDS:-900}
PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:9090}
LOKI_URL=${LOKI_URL:-http://localhost:3100}
TEMPO_URL=${TEMPO_URL:-http://localhost:3200}
PROM_QUERY_STEP_SECONDS=${PROM_QUERY_STEP_SECONDS:-15}
TRACE_SEARCH_LIMIT=${TRACE_SEARCH_LIMIT:-5000}
TRACE_DETAIL_LIMIT=${TRACE_DETAIL_LIMIT:-500}
TRACE_FETCH_CONCURRENCY=${TRACE_FETCH_CONCURRENCY:-10}
DOCKER_LOG_SERVICES=${DOCKER_LOG_SERVICES:-"front-end edge-router catalogue catalogue-db carts carts-db orders orders-db shipping queue-master rabbitmq payment user user-db"}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)

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

  log_info "Collecting observability data for test window [${test_start_epoch} - ${test_end_epoch}]"
  
  local jmeter_start_epoch="${test_start_epoch}"
  local jmeter_end_epoch="${test_end_epoch}"

  local window_start=$((jmeter_start_epoch - EXPAND_BEFORE_SECONDS))
  local window_end=$((jmeter_end_epoch + EXPAND_AFTER_SECONDS))
  if (( window_start < 0 )); then
    window_start=0
  fi
  
  # Cap the expansion window to prevent huge queries (max 24 hours)
  local max_window_duration=$((24 * 3600))
  local current_window_duration=$((window_end - window_start))
  if (( current_window_duration > max_window_duration )); then
    log_warning "Window duration ${current_window_duration}s exceeds 24h limit, capping to actual test window"
    window_start=$jmeter_start_epoch
    window_end=$jmeter_end_epoch
  fi

  local window_start_iso
  local window_end_iso
  window_start_iso=$(to_rfc3339 "$window_start")
  window_end_iso=$(to_rfc3339 "$window_end")

  local export_root="${RUN_DIR}/observability"
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
    log_info "Exporting Prometheus metrics for JMeter test window ${window_start_iso} -> ${window_end_iso}"
    
    # Calculate dynamic step to stay under 11,000 point limit
    local time_range=$((window_end - window_start))
    local prom_step=$((PROM_QUERY_STEP_SECONDS))
    if (( time_range > 0 )); then
      local estimated_points=$((time_range / prom_step))
      if (( estimated_points > 11000 )); then
        prom_step=$((time_range / 11000 + 1))
        log_warning "Adjusted Prometheus step to ${prom_step}s to avoid exceeding 11,000 point limit"
      fi
    fi
    
    # Format: "filename|PromQL query"
    # Queries check both OpenTelemetry-instrumented metrics AND standard Prometheus metrics
    # Memory/CPU filter out containers with no compose service label (!="").
    local prom_queries=(
      # Go services (catalogue, payment, user, frontend): request_duration_seconds histogram
      '01-http_requests_rate|sum(rate(request_duration_seconds_count{route!="metrics"}[1m])) by (job, status_code)'
      '02-http_response_times|histogram_quantile(0.95, sum(rate(request_duration_seconds_bucket{route!="metrics"}[1m])) by (job, le))'
      '03-container_memory|sum(container_memory_usage_bytes{container_label_com_docker_compose_service!=""}) by (container_label_com_docker_compose_service)'
      '04-container_cpu|sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service!=""}[1m])) by (container_label_com_docker_compose_service)'
      '05-service_health|up'
      # Go services 5xx errors
      '06-http_errors|sum(rate(request_duration_seconds_count{status_code=~"5..",route!="metrics"}[1m])) by (job, status_code)'
      # Java/Spring Boot services (shipping, orders, carts, queue-master): counter_status_XXX_<route> pattern
      # Note: __name__ regex with rate() collapses labelsets — must name metrics explicitly
      '07-java_http_2xx_health|sum(rate(counter_status_200_health[1m])) by (job)'
      '08-java_http_4xx|sum(rate(counter_status_404_star_star[1m]) + rate(counter_status_404_browser_star_star[1m]) + rate(counter_status_404_actuator_star_star[1m])) by (job)'
    )

    local entry fname query
    for entry in "${prom_queries[@]}"; do
      fname="${entry%%|*}"
      query="${entry##*|}"
      curl -sS --get "${PROMETHEUS_URL}/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=${window_start}" \
        --data-urlencode "end=${window_end}" \
        --data-urlencode "step=${prom_step}s" \
        -o "${metrics_dir}/${fname}.json" || log_warning "Prometheus export failed for: ${fname}"
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
      --data-urlencode 'query={container_name=~".+"}' \
      --data-urlencode "start=${loki_start_ns}" \
      --data-urlencode "end=${loki_end_ns}" \
      --data-urlencode "limit=5000" \
      -o "${logs_dir}/loki-query-range.json" || log_warning "Loki export failed"

    log_success "Logs exported to ${logs_dir}"
  fi

  if [[ "$CAPTURE_TRACES" == "true" ]]; then
    log_info "Exporting Tempo trace index for test window"

    local trace_start_sec="${jmeter_start_epoch}"
    local trace_end_sec="${jmeter_end_epoch}"

    # Step 1: fetch trace index (traceID + rootServiceName + durationMs)
    curl -sS --get "${TEMPO_URL}/api/search" \
      --data-urlencode "start=${trace_start_sec}" \
      --data-urlencode "end=${trace_end_sec}" \
      --data-urlencode "limit=${TRACE_SEARCH_LIMIT}" \
      -o "${traces_dir}/tempo-traces.json" || log_warning "Tempo search export failed"

    # Step 2: fetch full span detail (tags, attributes, status codes, events) per traceID
    if [[ -f "${traces_dir}/tempo-traces.json" ]]; then
      local trace_ids=()
      mapfile -t trace_ids < <(
        python3 -c "
import json, sys
with open('${traces_dir}/tempo-traces.json') as f:
    data = json.load(f)
for t in data.get('traces', []):
    tid = t.get('traceID') or ''
    if tid:
        print(tid)
" 2>/dev/null | head -n "${TRACE_DETAIL_LIMIT}"
      )
      local total="${#trace_ids[@]}"

      if (( total > 0 )); then
        log_info "Fetching full span detail for ${total} traces (concurrency: ${TRACE_FETCH_CONCURRENCY})"
        local detail_dir="${traces_dir}/details"
        mkdir -p "$detail_dir"

        local pids=()
        local tid
        for tid in "${trace_ids[@]}"; do
          curl -sS "${TEMPO_URL}/api/traces/${tid}" \
            -o "${detail_dir}/${tid}.json" &
          pids+=($!)
          if (( ${#pids[@]} >= TRACE_FETCH_CONCURRENCY )); then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
          fi
        done
        wait

        # Merge all per-trace JSON files into one array
        log_info "Merging span details into tempo-span-details.json"
        python3 - "${detail_dir}" "${traces_dir}/tempo-span-details.json" << 'PYEOF'
import json, os, sys
detail_dir, out_file = sys.argv[1], sys.argv[2]
results = []
for fn in sorted(os.listdir(detail_dir)):
    if not fn.endswith('.json'):
        continue
    path = os.path.join(detail_dir, fn)
    try:
        with open(path) as f:
            results.append(json.load(f))
    except (json.JSONDecodeError, OSError):
        pass
with open(out_file, 'w') as f:
    json.dump(results, f, indent=2)
print(f"Merged {len(results)} trace detail files")
PYEOF
        log_success "Span details saved: ${traces_dir}/tempo-span-details.json (${total} traces)"
        log_success "Individual trace files: ${detail_dir}/"
      else
        log_warning "No trace IDs found in search results — skipping span detail fetch"
      fi
    else
      log_warning "Trace index missing — skipping span detail fetch"
    fi

    log_success "Trace export complete: ${traces_dir}"
  fi

  log_success "Observability export complete: ${export_root}"
}

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
  TRACE_SEARCH_LIMIT      Max traces returned by /api/search (default: 5000)
  TRACE_DETAIL_LIMIT      Max traces to fetch full span detail for (default: 500)
  TRACE_FETCH_CONCURRENCY Parallel curl jobs for span detail fetch (default: 10)

Examples:
  ./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
  ./run-anomaly.sh ANOMALY-002 --duration 300 --users 150
  ./run-anomaly.sh ANOMALY-007 --duration 900 --users 80

EOF
}

if [[ -z "$ANOMALY_ID" ]]; then
  echo -e "${RED}[✗]${NC} Anomaly ID required" >&2
  print_usage
  exit 1
fi

RUN_DIR="${RESULTS_DIR}/${ANOMALY_ID}-${RUN_ID}"
ANOMALY_LOG="${RUN_DIR}/anomaly.log"
COMPREHENSIVE_CSV="${RUN_DIR}/comprehensive-results.csv"
mkdir -p "$RUN_DIR"

{
  echo "================================================================================"
  echo "Sock Shop Anomaly Test: $ANOMALY_ID"
  echo "================================================================================"
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Duration: ${DURATION}s | Users: ${USERS} | Ramp-up: ${RAMPUP}s"
  echo "================================================================================"
} > "$ANOMALY_LOG"

log_info "Starting anomaly test: $ANOMALY_ID"

if [[ -f "${SCRIPT_DIR}/tasks/${ANOMALY_ID,,}.sh" ]]; then
  source "${SCRIPT_DIR}/tasks/${ANOMALY_ID,,}.sh"
  log_success "Loaded task script for $ANOMALY_ID"
else
  log_warning "Task script not found for $ANOMALY_ID, using generic execution"
fi

START_TIME=$(date -u +%s)
TEST_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "Pre-test setup complete. Running anomaly test..."

TEST_RESULT_FILE="${RUN_DIR}/jmeter-results.csv"
log_info "Executing JMeter test"
log_info "Command: jmeter -n -t ${JMETER_SCRIPT} -Jusers=${USERS} -Jrampup=${RAMPUP} -Jduration=${DURATION} -l ${TEST_RESULT_FILE}"

jmeter -n \
  -t "$JMETER_SCRIPT" \
  -Jusers="$USERS" \
  -Jrampup="$RAMPUP" \
  -Jduration="$DURATION" \
  -l "$TEST_RESULT_FILE" \
  -j "${RUN_DIR}/jmeter.log" 2>&1 | tee -a "$ANOMALY_LOG" || {
  log_error "JMeter test failed"
  exit 1
}

END_TIME=$(date -u +%s)
ACTUAL_DURATION=$((END_TIME - START_TIME))

log_success "JMeter test completed in ${ACTUAL_DURATION}s"
collect_observability_data "$START_TIME" "$END_TIME" "$TEST_RESULT_FILE"

if [[ -f "${SCRIPT_DIR}/build-comprehensive-results.py" ]]; then
  log_info "Building comprehensive CSV with JMeter, metrics, logs, and traces"
  python3 "${SCRIPT_DIR}/build-comprehensive-results.py" \
    --results-dir "$RUN_DIR" \
    --anomaly-id "$ANOMALY_ID" \
    --run-id "$RUN_ID" \
    --output "$COMPREHENSIVE_CSV" \
    || log_warning "Could not build comprehensive CSV"
  log_success "Comprehensive CSV: $COMPREHENSIVE_CSV"
fi

if [[ -n "${CLEANUP_ANOMALY:-}" ]]; then
  log_info "Running cleanup for anomaly..."
  eval "$CLEANUP_ANOMALY" 2>&1 | tee -a "$ANOMALY_LOG" || log_warning "Cleanup may have failed"
fi

log_info "Generating test summary..."
cat >> "$ANOMALY_LOG" << EOF

===============================================================================
                            TEST SUMMARY
===============================================================================
Anomaly ID:         $ANOMALY_ID
Run ID:             $RUN_ID
Test Timestamp:     $TEST_TIMESTAMP
Duration:           ${ACTUAL_DURATION}s (requested: ${DURATION}s)
JMeter Users:       $USERS
Ramp-up:            ${RAMPUP}s
Run Directory:      $RUN_DIR

Next Steps:
1. Review JMeter results:    cat ${RUN_DIR}/jmeter-results.csv
2. Review JMeter log:        cat ${RUN_DIR}/jmeter.log
3. Check exported logs:      ls -la ${RUN_DIR}/observability/logs/
4. Check exported metrics:   ls -la ${RUN_DIR}/observability/metrics/
5. Review trace index:       cat ${RUN_DIR}/observability/traces/tempo-traces.json
6. Review full span details: cat ${RUN_DIR}/observability/traces/tempo-span-details.json
7. Comprehensive CSV:        cat ${RUN_DIR}/comprehensive-results.csv

===============================================================================
EOF

log_success "Anomaly test complete!"
log_info "Full log: $ANOMALY_LOG"
log_info "Run directory: $RUN_DIR"

tail -20 "$ANOMALY_LOG"

exit 0
