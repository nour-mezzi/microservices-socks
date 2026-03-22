#!/bin/bash

################################################################################
# ANOMALY-002: CPU Saturation
#
# This task introduces CPU saturation by reducing CPU limit and increasing
# concurrent load until throttling occurs.
#
# Expected Behavior:
# - CPU usage reaches 100% (or limit)
# - CPU throttling occurs (cfs_throttled_seconds increases)
# - Request latency increases dramatically (50ms → 500ms+)
# - Timeout errors appear
# - Success rate may drop to 80-90%
#
# Monitoring Points:
# - rate(container_cpu_usage_seconds_total[1m])
# - container_cpu_cfs_throttled_seconds_total
# - http_request_duration_seconds (P95/P99)
# - http_requests_total{status=~"5.."}
################################################################################

set -euo pipefail

# Note: This script is sourced by run-anomaly.sh, so functions and variables are available

log_info "[ANOMALY-002] Setting up CPU Saturation test..."

# Configuration for this anomaly
CPU_LIMIT="0.25"              # Reduced from 1.0
TARGETED_SERVICE="payment"    # CPU-intensive service
CONTAINER_ID=$(docker ps --filter "label=com.docker.compose.service=$TARGETED_SERVICE" -q | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
  log_warning "Could not find running container for $TARGETED_SERVICE, trying alternative..."
  CONTAINER_ID=$(docker ps --filter "name=$TARGETED_SERVICE" -q | head -1)
fi

if [[ -z "$CONTAINER_ID" ]]; then
  log_error "Could not find running container for $TARGETED_SERVICE"
  exit 1
fi

log_info "Target container: $CONTAINER_ID ($TARGETED_SERVICE)"

# Pre-test baseline
log_info "Capturing baseline CPU metrics..."
BASELINE_CPU=$(docker stats "$CONTAINER_ID" --format "{{.CPUPerc}}" --no-stream)
log_info "Baseline CPU: $BASELINE_CPU"

# Apply CPU limit
log_info "Applying CPU limit: $CPU_LIMIT"
docker update --cpus "$CPU_LIMIT" "$CONTAINER_ID" > /dev/null
log_success "CPU limit updated to $CPU_LIMIT"

# Define cleanup function
CLEANUP_ANOMALY='
  log_info "Cleaning up CPU saturation (ANOMALY-002)..."
  docker update --cpus 1.0 '"$CONTAINER_ID"' > /dev/null
  log_info "CPU limit restored to 1.0"
  sleep 5
  log_info "Service CPU stats after cleanup: $(docker stats '"$CONTAINER_ID"' --format \"{{.CPUPerc}}\" --no-stream)"
'

# Test-specific configuration - higher concurrency to trigger saturation
USERS=150
RAMPUP=120
DURATION=600

log_success "[ANOMALY-002] CPU saturation setup complete"
log_info "Starting load test with CPU limit ($CPU_LIMIT)..."
log_info "Configuration: $USERS users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: High latency, throttling, possible 5xx errors"

# Test execution will continue in main run-anomaly.sh script
