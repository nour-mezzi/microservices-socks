#!/bin/bash

################################################################################
# ANOMALY-001: Memory Pressure (OOM)
# 
# This task introduces memory pressure by reducing container memory limits
# and running a sustained load test.
#
# Expected Behavior:
# - Memory usage increases quickly
# - Garbage collection frequency increases
# - GC pause times elongate (50ms → 500ms+)
# - Eventually: Out of memory errors or container kill
#
# Monitoring Points:
# - container_memory_usage_bytes → container_spec_memory_limit_bytes (ratio)
# - jvm_gc_pause_seconds_bucket (duration)
# - jvm_gc_pause_seconds_count (frequency)
# - Container restart/kill events in logs
################################################################################

set -euo pipefail

# Note: This script is sourced by run-anomaly.sh, so functions and variables are available

log_info "[ANOMALY-001] Setting up Memory Pressure test..."

# Configuration for this anomaly
MEMORY_LIMIT="256m"          # Reduced from default 512m
TARGETED_SERVICE="catalogue"
CONTAINER_ID=$(docker ps --filter "label=com.docker.compose.service=$TARGETED_SERVICE" -q | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
  log_error "Could not find running container for $TARGETED_SERVICE"
  exit 1
fi

log_info "Target container: $CONTAINER_ID ($TARGETED_SERVICE)"

# Pre-test baseline
log_info "Capturing baseline memory metrics..."
BASELINE_MEMORY=$(docker stats "$CONTAINER_ID" --format "{{.MemUsage}}" --no-stream)
log_info "Baseline memory: $BASELINE_MEMORY"

# Apply memory pressure
log_info "Applying memory limit: $MEMORY_LIMIT"
docker update --memory "$MEMORY_LIMIT" "$CONTAINER_ID" > /dev/null
log_success "Memory limit updated to $MEMORY_LIMIT"

# Define cleanup function
CLEANUP_ANOMALY='
  log_info "Cleaning up memory pressure (ANOMALY-001)..."
  docker update --memory 512m '"$CONTAINER_ID"' > /dev/null
  log_info "Memory limit restored to 512m"
  sleep 5
  log_info "Service memory stats after cleanup: $(docker stats '"$CONTAINER_ID"' --format \"{{.MemUsage}}\" --no-stream)"
'

# Test-specific configuration
USERS=100
RAMPUP=60
DURATION=600

log_success "[ANOMALY-001] Memory pressure setup complete"
log_info "Starting load test with reduced memory ($MEMORY_LIMIT)..."
log_info "Configuration: $USERS users, ${RAMPUP}s ramp-up, ${DURATION}s duration"

# Test execution will continue in main run-anomaly.sh script
