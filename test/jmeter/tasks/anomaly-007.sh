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
LATENCY_MS=500                    # Add 500ms latency
JITTER_MS=20                      # ±20ms jitter
NETWORK_INTERFACE="eth0"          # Common in Docker
DOCKER_NETWORK="microservices-demo_default"  # Adjust to actual network name

log_info "Latency configuration: ${LATENCY_MS}ms ±${JITTER_MS}ms"
log_info "Network interface: $NETWORK_INTERFACE"

# Check if tc is available and user has permissions
if ! command -v tc &> /dev/null; then
  log_error "traffic control (tc) not available. Install with: apt-get install iproute2"
  exit 1
fi

# Find the correct network interface for Docker Compose services
log_info "Detecting Docker network interface..."

# Get a running container from the network
SAMPLE_CONTAINER=$(docker ps --filter "network=$DOCKER_NETWORK" -q | head -1)
if [[ -z "$SAMPLE_CONTAINER" ]]; then
  log_warning "Could not find container on network $DOCKER_NETWORK"
  log_info "Using container namespace approach instead..."
  # Alternative: use veth interface directly
fi

# Pre-test verification
log_info "Verifying network baseline..."
BASELINE_LATENCY=$(ping -c 1 localhost 2>/dev/null | grep "time=" | sed 's/.*time=\([^ ]*\).*/\1/' || echo "N/A")
log_info "Baseline latency to localhost: $BASELINE_LATENCY"

# Apply network latency using tc
log_info "Applying network latency with tc..."

# Method 1: Apply to all eth0 interfaces in container namespace
if sudo tc qdisc show dev "$NETWORK_INTERFACE" 2>/dev/null | grep -q "root"; then
  log_warning "tc qdisc already exists, removing..."
  sudo tc qdisc del dev "$NETWORK_INTERFACE" root 2>/dev/null || true
fi

# Add netem (network emulation) qdisc
log_info "Command: sudo tc qdisc add dev $NETWORK_INTERFACE root netem delay ${LATENCY_MS}ms ${JITTER_MS}ms distribution normal"
sudo tc qdisc add dev "$NETWORK_INTERFACE" root netem delay "${LATENCY_MS}ms" "${JITTER_MS}ms" distribution normal || {
  log_error "Failed to apply tc rule. May need: sudo usermod -aG docker $USER"
  exit 1
}

log_success "Network latency applied: ${LATENCY_MS}ms ±${JITTER_MS}ms"

# Verify latency was applied
sleep 1
ACTUAL_LATENCY=$(ping -c 1 localhost 2>/dev/null | grep "time=" | sed 's/.*time=\([^ ]*\).*/\1/' || echo "N/A")
log_info "Actual latency to localhost after tc: $ACTUAL_LATENCY"

# Define cleanup function
CLEANUP_ANOMALY='
  log_info "Cleaning up network latency (ANOMALY-007)..."
  log_info "Removing tc qdisc..."
  sudo tc qdisc del dev '"$NETWORK_INTERFACE"' root 2>/dev/null || log_warning "tc qdisc not found"
  sleep 1
  FINAL_LATENCY=$(ping -c 1 localhost 2>/dev/null | grep "time=" | sed "s/.*time=\([^ ]*\).*/\1/" || echo "N/A")
  log_info "Network latency after cleanup: $FINAL_LATENCY"
  log_success "Network latency cleanup complete"
'

# Test-specific configuration - moderate load to avoid other confounds
USERS=100
RAMPUP=60
DURATION=600

log_success "[ANOMALY-007] Network latency setup complete"
log_info "Starting load test with artificial network delay..."
log_info "Configuration: $USERS users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: Uniform ~500ms latency increase across all services"
log_warning "Expected: High success rate (>95%), only latency affected"
log_info "Verify: All services show similar latency increase (not isolated to one service)"

# Test execution will continue in main run-anomaly.sh script
