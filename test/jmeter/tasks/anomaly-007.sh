#!/bin/bash

################################################################################
# ANOMALY-007: Network Latency Spikes
#
# This task introduces artificial network latency using Linux traffic control (tc).
# This simulates WAN conditions, high-latency datacenters, or congested networks.
#
# Expected Behavior:
# - All inter-service communication slows uniformly
# - No errors, just latency
# - Request latency increases 5-10x (50ms → 300-500ms)
# - Cascading delay through service chain
# - Success rate remains high (95%+)
#
# Monitoring Points:
# - http_request_duration_seconds (all services affected)
# - Network latency metrics
# - No spike in error rates (distinguishes from failures)
#
# Prerequisites:
# - Must run on Linux with tc (traffic control) available
# - May require sudo/root access to container network
################################################################################

set -euo pipefail

# Note: This script is sourced by run-anomaly.sh, so functions and variables are available

log_info "[ANOMALY-007] Setting up Network Latency test..."

# Configuration for this anomaly
LATENCY_MS=500                       # Add 500ms latency
JITTER_MS=20                         # ±20ms jitter
DOCKER_NETWORK="docker-compose_default"

log_info "Latency configuration: ${LATENCY_MS}ms ±${JITTER_MS}ms"

# Resolve the host bridge interface from the Docker network ID
log_info "Detecting Docker bridge interface for network: $DOCKER_NETWORK"
BRIDGE_NET_ID=$(docker network inspect "$DOCKER_NETWORK" --format '{{slice .Id 0 12}}' 2>/dev/null)
if [[ -z "$BRIDGE_NET_ID" ]]; then
  log_error "Docker network '$DOCKER_NETWORK' not found. Is the stack running?"
  exit 1
fi
BRIDGE_IF="br-${BRIDGE_NET_ID}"
log_info "Bridge interface: $BRIDGE_IF"

# tc runner — tries sudo first, falls back to a privileged container with net=host
run_tc() {
  if sudo -n tc "$@" 2>/dev/null; then
    return 0
  fi
  docker run --rm --privileged --net=host alpine \
    sh -c "apk add -q --no-cache iproute2 2>/dev/null && tc $*"
}

# Remove any existing qdisc on the bridge before adding
log_info "Clearing any existing tc qdisc on $BRIDGE_IF..."
run_tc qdisc del dev "$BRIDGE_IF" root 2>/dev/null || true

# Apply netem latency on the Docker bridge — affects all inter-service traffic
log_info "Applying ${LATENCY_MS}ms ±${JITTER_MS}ms netem latency on $BRIDGE_IF..."
run_tc qdisc add dev "$BRIDGE_IF" root netem delay "${LATENCY_MS}ms" "${JITTER_MS}ms" distribution normal || {
  log_error "Failed to apply tc netem rule on $BRIDGE_IF"
  exit 1
}

log_success "Network latency applied on $BRIDGE_IF: ${LATENCY_MS}ms ±${JITTER_MS}ms"

# Define cleanup — mirrors the same run_tc helper (inline for eval context)
CLEANUP_ANOMALY="
  log_info 'Cleaning up network latency (ANOMALY-007)...'
  if sudo -n tc qdisc del dev ${BRIDGE_IF} root 2>/dev/null; then
    true
  else
    docker run --rm --privileged --net=host alpine \
      sh -c 'apk add -q --no-cache iproute2 2>/dev/null && tc qdisc del dev ${BRIDGE_IF} root' 2>/dev/null || true
  fi
  log_success 'Network latency removed from ${BRIDGE_IF}'
"

# Test-specific defaults - only apply if not already set by the caller
USERS=${USERS:-100}
RAMPUP=${RAMPUP:-60}
DURATION=${DURATION:-600}

log_success "[ANOMALY-007] Network latency setup complete"
log_info "Starting load test with artificial network delay..."
log_info "Configuration: $USERS users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: Uniform ~500ms latency increase across all services"
log_warning "Expected: High success rate (>95%), only latency affected"
log_info "Verify: All services show similar latency increase (not isolated to one service)"

# Test execution will continue in main run-anomaly.sh script
