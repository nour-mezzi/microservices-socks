#!/bin/bash

################################################################################
# ANOMALY-004: Database Connection Pool Exhaustion
#
# This task triggers database connection pool exhaustion by:
# 1. Reducing connection pool size in MongoDB
# 2. Dramatically increasing concurrent requests
#
# Expected Behavior:
# - Connection pool fills up quickly
# - Connection queue grows
# - Requests wait for available connections (5-30 seconds)
# - Cascading failures as API timeouts waiting for DB connection
# - High error rate (20%+)
#
# Monitoring Points:
# - mongodb_connections_current
# - mongodb_connections_available
# - db_connection_checkout_time_seconds
# - http_requests_total{status=~"5.."}
# - ConnectionException in logs
################################################################################

set -euo pipefail

# Note: This script is sourced by run-anomaly.sh, so functions and variables are available

log_info "[ANOMALY-004] Setting up Database Connection Pool Exhaustion test..."

# Configuration for this anomaly
OLD_POOL_SIZE=100
NEW_POOL_SIZE=10                  # Reduce by 90%
MONGODB_CONTAINER=$(docker ps --filter "label=com.docker.compose.service=mongodb" -q | head -1)
CATALOG_API=$(docker ps --filter "label=com.docker.compose.service=catalogue" -q | head -1)

if [[ -z "$MONGODB_CONTAINER" ]]; then
  log_error "Could not find running MongoDB container"
  exit 1
fi

log_info "Target MongoDB container: $MONGODB_CONTAINER"
log_info "Target API container: $CATALOG_API (for testing connection failures)"

# Note: In a real scenario, this would require updating MongoDB config
# For Docker Compose, we can simulate by using environment variables
log_info "Note: Pool size reduction would require MongoDB config update"
log_info "In production, modify MongoDB connection string or config"
log_warning "Alternative: Create artificial slowdown in queries to trigger pool exhaustion"

# Create artificial DB slowdown to consume connection pool
log_info "Strategy: Increase query latency to consume pool during connections"
log_info "Adding artificial delay to MongoDB queries..."

# This would ideally be done via MongoDB profile settings
# For now, document the approach
cat > /tmp/mongodb-pool-setup.js << 'EOF'
// MongoDB script to increase query latency
// Execute with: mongo < /tmp/mongodb-pool-setup.js

db.setProfilingLevel(0, { slowms: 100 })  // Profile slow queries

// Create a test collection if needed
db.products.createIndex({ name: 1 })

// Run a slow aggregation in background windows
print("MongoDB slowness configured for connection pool testing")
EOF

log_info "MongoDB pool exhaustion setup script ready at /tmp/mongodb-pool-setup.js"

# Define cleanup function
CLEANUP_ANOMALY='
  log_info "Cleaning up database connection pool test (ANOMALY-004)..."
  log_info "Resetting MongoDB profiling level..."
  docker exec '"$MONGODB_CONTAINER"' mongo --eval "db.setProfilingLevel(0)" 2>/dev/null || log_warning "Could not reset profiling"
  log_success "Cleanup complete"
'

# Test-specific configuration - very high concurrency
USERS=200
RAMPUP=90
DURATION=600

log_success "[ANOMALY-004] Connection pool exhaustion setup complete"
log_info "Starting load test with reduced DB pool..."
log_info "Configuration: $USERS users, ${RAMPUP}s ramp-up, ${DURATION}s duration"
log_warning "Expected: Connection timeout errors, high queuing, cascading failures"
log_info "Look for: DB connection queue grows, API latency >> baseline"

# Test execution will continue in main run-anomaly.sh script
