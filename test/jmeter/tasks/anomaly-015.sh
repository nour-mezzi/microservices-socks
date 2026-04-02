#!/bin/bash

################################################################################
# ANOMALY-015: Resource Exhaustion (stress-ng noisy neighbor)
#
# This task creates CPU and memory contention in a target service container.
# Preferred path: run stress-ng inside the target container.
# Fallback path: tighten docker CPU/memory limits when stress-ng is unavailable.
#
# Tunables (environment variables):
# - STRESS_TARGET_SERVICE (default: catalogue)
# - STRESS_CPU_WORKERS (default: 2)
# - STRESS_VM_WORKERS (default: 1)
# - STRESS_VM_BYTES (default: 128M)
# - STRESS_FALLBACK_CPUS (default: 0.30)
# - STRESS_FALLBACK_MEMORY (default: 192m)
################################################################################

set -euo pipefail

log_info "[ANOMALY-015] Setting up resource exhaustion with stress-ng..."

TARGETED_SERVICE="${STRESS_TARGET_SERVICE:-catalogue}"
STRESS_CPU_WORKERS="${STRESS_CPU_WORKERS:-2}"
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-1}"
STRESS_VM_BYTES="${STRESS_VM_BYTES:-128M}"
STRESS_FALLBACK_CPUS="${STRESS_FALLBACK_CPUS:-0.30}"
STRESS_FALLBACK_MEMORY="${STRESS_FALLBACK_MEMORY:-192m}"

resolve_target_container() {
  local requested_service="$1"
  local container_id

  container_id=$(docker ps --filter "label=com.docker.compose.service=${requested_service}" -q | head -1)
  if [[ -n "${container_id}" ]]; then
    RESOLVED_SERVICE="${requested_service}"
    printf '%s\n' "${container_id}"
    return 0
  fi

  local fallback_service
  for fallback_service in catalogue front-end carts orders shipping queue-master payment user catalogue-db carts-db orders-db user-db rabbitmq; do
    container_id=$(docker ps --filter "label=com.docker.compose.service=${fallback_service}" -q | head -1)
    if [[ -n "${container_id}" ]]; then
      RESOLVED_SERVICE="${fallback_service}"
      printf '%s\n' "${container_id}"
      return 0
    fi
  done

  return 1
}

if CONTAINER_ID=$(resolve_target_container "${TARGETED_SERVICE}"); then
  :
else
  log_error "No running Sock Shop service containers were found. Start the compose stack before running ANOMALY-015."
  exit 1
fi

if [[ -n "${RESOLVED_SERVICE:-}" && "${RESOLVED_SERVICE}" != "${TARGETED_SERVICE}" ]]; then
  log_warning "Requested service '${TARGETED_SERVICE}' is not running; using '${RESOLVED_SERVICE}' instead"
  TARGETED_SERVICE="${RESOLVED_SERVICE}"
fi

log_info "Target container: ${CONTAINER_ID} (${TARGETED_SERVICE})"

BASELINE_CPU=$(docker stats "${CONTAINER_ID}" --format "{{.CPUPerc}}" --no-stream 2>/dev/null || echo "N/A")
BASELINE_MEM=$(docker stats "${CONTAINER_ID}" --format "{{.MemUsage}}" --no-stream 2>/dev/null || echo "N/A")
log_info "Baseline CPU: ${BASELINE_CPU}"
log_info "Baseline Memory: ${BASELINE_MEM}"

STRESS_LOG_FILE="${RESULTS_DIR}/${ANOMALY_ID}-stress-ng.log"

if docker exec "${CONTAINER_ID}" sh -c 'command -v stress-ng >/dev/null 2>&1'; then
  log_info "Running stress-ng inside target container"
  docker exec "${CONTAINER_ID}" sh -c "stress-ng --cpu ${STRESS_CPU_WORKERS} --vm ${STRESS_VM_WORKERS} --vm-bytes ${STRESS_VM_BYTES} --timeout ${DURATION}s --metrics-brief" > "${STRESS_LOG_FILE}" 2>&1 &
  STRESS_HOST_PID=$!
  log_success "stress-ng started (host pid: ${STRESS_HOST_PID})"

  CLEANUP_ANOMALY='
    log_info "Cleaning up resource exhaustion (ANOMALY-015)..."
    if [[ -n "${STRESS_HOST_PID:-}" ]]; then
      kill "${STRESS_HOST_PID}" 2>/dev/null || true
    fi
    log_info "Post-test CPU: $(docker stats '"${CONTAINER_ID}"' --format "{{.CPUPerc}}" --no-stream 2>/dev/null || echo N/A)"
    log_info "Post-test Memory: $(docker stats '"${CONTAINER_ID}"' --format "{{.MemUsage}}" --no-stream 2>/dev/null || echo N/A)"
  '
else
  log_warning "stress-ng not found in target container; using CPU/memory throttling fallback"
  docker update --cpus "${STRESS_FALLBACK_CPUS}" --memory "${STRESS_FALLBACK_MEMORY}" --memory-swap "${STRESS_FALLBACK_MEMORY}" "${CONTAINER_ID}" > /dev/null
  log_success "Applied fallback limits: cpus=${STRESS_FALLBACK_CPUS}, memory=${STRESS_FALLBACK_MEMORY}"

  CLEANUP_ANOMALY='
    log_info "Cleaning up fallback throttling (ANOMALY-015)..."
    docker update --cpus 1.0 --memory 512m --memory-swap 1g '"${CONTAINER_ID}"' > /dev/null || true
    log_info "Post-test CPU: $(docker stats '"${CONTAINER_ID}"' --format "{{.CPUPerc}}" --no-stream 2>/dev/null || echo N/A)"
    log_info "Post-test Memory: $(docker stats '"${CONTAINER_ID}"' --format "{{.MemUsage}}" --no-stream 2>/dev/null || echo N/A)"
  '
fi

USERS=140
RAMPUP=90
DURATION=${DURATION:-600}

log_success "[ANOMALY-015] Resource exhaustion setup complete"
log_info "Configuration: ${USERS} users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: Elevated latency, timeouts, and CPU/memory contention signatures"
