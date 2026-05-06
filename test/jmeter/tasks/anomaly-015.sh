#!/bin/bash

################################################################################
# ANOMALY-015: Resource Exhaustion (stress-ng noisy neighbor)
#
# This task creates CPU and memory contention in one service or in all live
# Sock Shop services. If stress-ng is present inside a container, it runs there.
# Otherwise the task falls back to Docker CPU/memory throttling for that service.
#
# Tunables (environment variables):
# - STRESS_TARGET_SERVICE (default: catalogue)
# - STRESS_TARGET_SERVICES (default: all)
# - STRESS_CPU_WORKERS (default: 2)
# - STRESS_VM_WORKERS (default: 1)
# - STRESS_VM_BYTES (default: 128M)
# - STRESS_FALLBACK_CPUS (default: 0.30)
# - STRESS_FALLBACK_MEMORY (default: 192m)
################################################################################

set -euo pipefail

log_info "[ANOMALY-015] Setting up resource exhaustion with stress-ng..."

TARGETED_SERVICE="${STRESS_TARGET_SERVICE:-catalogue}"
TARGETED_SERVICES="${STRESS_TARGET_SERVICES:-all}"
STRESS_CPU_WORKERS="${STRESS_CPU_WORKERS:-2}"
STRESS_VM_WORKERS="${STRESS_VM_WORKERS:-1}"
STRESS_VM_BYTES="${STRESS_VM_BYTES:-128M}"
STRESS_FALLBACK_CPUS="${STRESS_FALLBACK_CPUS:-0.30}"
STRESS_FALLBACK_MEMORY="${STRESS_FALLBACK_MEMORY:-192m}"

ALL_STRESS_SERVICES=(front-end edge-router catalogue catalogue-db carts carts-db orders orders-db shipping queue-master rabbitmq payment user user-db)
STRESS_TARGET_CONTAINER_IDS=()
STRESS_TARGET_CONTAINER_SERVICES=()
STRESS_FALLBACK_CONTAINER_IDS=()
STRESS_EXEC_PIDS=()

resolve_target_services() {
  local services_spec="$1"
  local service

  if [[ "$services_spec" == "all" ]]; then
    printf '%s\n' "${ALL_STRESS_SERVICES[@]}"
    return 0
  fi

  IFS=',' read -r -a service_list <<< "$services_spec"
  for service in "${service_list[@]}"; do
    service="${service// /}"
    if [[ -n "$service" ]]; then
      printf '%s\n' "$service"
    fi
  done
}

resolve_target_container() {
  local requested_service="$1"
  local container_id

  container_id=$(docker ps --filter "label=com.docker.compose.service=${requested_service}" -q | head -1)
  if [[ -n "$container_id" ]]; then
    RESOLVED_SERVICE="$requested_service"
    printf '%s\n' "$container_id"
    return 0
  fi

  return 1
}

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  if container_id=$(resolve_target_container "$service"); then
    STRESS_TARGET_CONTAINER_IDS+=("$container_id")
    STRESS_TARGET_CONTAINER_SERVICES+=("${RESOLVED_SERVICE:-$service}")
  elif [[ "$TARGETED_SERVICES" != "all" ]]; then
    log_warning "Requested service '${service}' is not running"
  fi
done < <(resolve_target_services "$TARGETED_SERVICES")

if [[ ${#STRESS_TARGET_CONTAINER_IDS[@]} -eq 0 ]]; then
  if [[ "$TARGETED_SERVICES" == "all" ]]; then
    log_error "No running Sock Shop service containers were found. Start the compose stack before running ANOMALY-015."
  else
    log_error "No running Sock Shop service containers were found for the requested service list: ${TARGETED_SERVICES}"
  fi
  exit 1
fi

if [[ "$TARGETED_SERVICES" == "all" ]]; then
  log_info "Applying resource exhaustion to live services: ${STRESS_TARGET_CONTAINER_SERVICES[*]}"
else
  log_info "Applying resource exhaustion to requested services: ${STRESS_TARGET_CONTAINER_SERVICES[*]}"
fi

for index in "${!STRESS_TARGET_CONTAINER_IDS[@]}"; do
  CONTAINER_ID="${STRESS_TARGET_CONTAINER_IDS[$index]}"
  SERVICE_NAME="${STRESS_TARGET_CONTAINER_SERVICES[$index]}"

  BASELINE_CPU=$(docker stats "$CONTAINER_ID" --format "{{.CPUPerc}}" --no-stream 2>/dev/null || echo "N/A")
  BASELINE_MEM=$(docker stats "$CONTAINER_ID" --format "{{.MemUsage}}" --no-stream 2>/dev/null || echo "N/A")
  log_info "Target container: ${CONTAINER_ID} (${SERVICE_NAME})"
  log_info "Baseline CPU: ${BASELINE_CPU}"
  log_info "Baseline Memory: ${BASELINE_MEM}"

  STRESS_LOG_FILE="${RESULTS_DIR}/${ANOMALY_ID}-${SERVICE_NAME}-stress-ng.log"

  if docker exec "$CONTAINER_ID" sh -c 'command -v stress-ng >/dev/null 2>&1'; then
    log_info "Running stress-ng inside ${SERVICE_NAME}"
    docker exec "$CONTAINER_ID" sh -c "stress-ng --cpu ${STRESS_CPU_WORKERS} --vm ${STRESS_VM_WORKERS} --vm-bytes ${STRESS_VM_BYTES} --timeout ${DURATION}s --metrics-brief" > "$STRESS_LOG_FILE" 2>&1 &
    STRESS_EXEC_PIDS+=("$!")
    log_success "stress-ng started for ${SERVICE_NAME}"
  else
    log_warning "stress-ng not found in ${SERVICE_NAME}; using CPU/memory throttling fallback"
    docker update --cpus "$STRESS_FALLBACK_CPUS" --memory "$STRESS_FALLBACK_MEMORY" --memory-swap "$STRESS_FALLBACK_MEMORY" "$CONTAINER_ID" > /dev/null
    STRESS_FALLBACK_CONTAINER_IDS+=("$CONTAINER_ID")
    log_success "Applied fallback limits to ${SERVICE_NAME}: cpus=${STRESS_FALLBACK_CPUS}, memory=${STRESS_FALLBACK_MEMORY}"
  fi
done

CLEANUP_ANOMALY='
  log_info "Cleaning up resource exhaustion (ANOMALY-015)..."
  for pid in "${STRESS_EXEC_PIDS[@]:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for container_id in "${STRESS_FALLBACK_CONTAINER_IDS[@]:-}"; do
    if [[ -n "$container_id" ]]; then
      docker update --cpus 1.0 --memory 512m --memory-swap 1g "$container_id" > /dev/null || true
    fi
  done
'

USERS=${USERS:-140}
RAMPUP=${RAMPUP:-90}
DURATION=${DURATION:-600}

log_success "[ANOMALY-015] Resource exhaustion setup complete"
log_info "Configuration: ${USERS} users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: Elevated latency, timeouts, and CPU/memory contention signatures"
