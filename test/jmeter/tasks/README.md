# Sock Shop - Anomaly Task Scripts

This directory contains individual task scripts for introducing and testing various anomalies in the Sock Shop microservices application. Each script is designed to be sourced by the main `run-anomaly.sh` script.

## Overview

Each anomaly task script (`anomaly-NNN.sh`) performs:

1. **Setup**: Applies necessary constraints or modifications to trigger the anomaly
2. **Configuration**: Sets appropriate load test parameters (users, duration, ramp-up)
3. **Cleanup**: Restores services to normal state after test completes

## Available Anomaly Tasks

### ANOMALY-001: Memory Pressure (OOM)
**File:** `anomaly-001.sh`

Reduces container memory limit and runs sustained load to trigger memory pressure, garbage collection overhead, and eventual Out-of-Memory conditions.

**Setup:**
- Memory limit: 256MB (reduced from 512MB)
- Target service: `catalogue`

**Expected signals:**
- Memory usage > 85% of limit
- GC pause time: 50ms → 500ms+
- GC frequency: 1/sec → 5/sec
- Container restart/kill events

**Usage:**
```bash
./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
```

---

### ANOMALY-002: CPU Saturation
**File:** `anomaly-002.sh`

Reduces CPU quota and increases concurrent load until CPU throttling occurs, causing cascading latency and timeouts.

**Setup:**
- CPU limit: 0.25 cores (reduced from 1.0)
- Target service: `payment`
- High concurrency: 150 users, 120s ramp-up

**Expected signals:**
- CPU throttling detected (cfs_throttled_seconds > 0)
- Request latency: 50ms → 500ms+
- Error rate spike to 15%+
- Timeout errors in logs

**Usage:**
```bash
./run-anomaly.sh ANOMALY-002 --duration 600 --users 150
```

---

### ANOMALY-004: Database Connection Pool Exhaustion
**File:** `anomaly-004.sh`

Reduces maximum database connections and increases concurrency to trigger connection pool exhaustion, queuing, and cascading failures.

**Setup:**
- Connection pool size: 10 (reduced from 100)
- Very high concurrency: 200 users
- Extended ramp-up: 120 seconds

**Expected signals:**
- Connection pool at capacity
- Connection queue grows linearly
- Request latency: 50ms → 5000ms+
- ConnectionException errors
- Error rate: 20%+

**Usage:**
```bash
./run-anomaly.sh ANOMALY-004 --duration 600 --users 200
```

---

### ANOMALY-007: Network Latency Spikes
**File:** `anomaly-007.sh`

Uses Linux `tc` (traffic control) to add artificial network latency, simulating WAN conditions or network degradation.

**Setup:**
- Added latency: 500ms ±20ms (via netem qdisc)
- Network interface: eth0 (in container)
- Moderate load: 100 users

**Expected signals:**
- HTTP request latency increases uniformly across all services
- High success rate maintained (>95%)
- No error spike (only latency)
- All downstream services affected similarly

**Prerequisites:**
- Linux system with `tc` available
- May require sudo/root access to apply network rules

**Usage:**
```bash
./run-anomaly.sh ANOMALY-007 --duration 600 --users 100
```

---

## Adding New Anomaly Tasks

To create a new anomaly task:

1. **Create file:** `anomaly-NNN.sh` following the template pattern
2. **Implement these sections:**
   ```bash
   # 1. Logging setup
   log_info "[ANOMALY-NNN] Setting up..."
   
   # 2. Identify target containers
   CONTAINER_ID=$(docker ps --filter "..." -q | head -1)
   
   # 3. Apply anomaly conditions
   docker update --memory "256m" "$CONTAINER_ID"
   
   # 4. Define cleanup
   CLEANUP_ANOMALY='docker update --memory "512m"...'
   
   # 5. Set test parameters
   USERS=100
   RAMPUP=60
   DURATION=600
   
   # 6. Log completion
   log_success "[ANOMALY-NNN] Setup complete"
   ```

3. **Document:**
   - Brief description of anomaly
   - Setup steps and parameters
   - Expected monitoring signals
   - Prerequisites (if any)

4. **Test:** Run the task script with the main runner
   ```bash
   ./run-anomaly.sh ANOMALY-NNN --duration 600
   ```

---

## Template Structure

```bash
#!/bin/bash

################################################################################
# ANOMALY-NNN: [Brief Description]
#
# This task... (detailed explanation)
#
# Expected Behavior:
# - Behavior 1
# - Behavior 2
# - Behavior 3
#
# Monitoring Points:
# - prometheus_metric_1
# - prometheus_metric_2
################################################################################

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../run-anomaly.sh" 2>/dev/null || true

log_info "[ANOMALY-NNN] Setting up [Anomaly Name]..."

# Configuration
TARGET_SERVICE="service-name"
CONTAINER_ID=$(docker ps --filter "label=com.docker.compose.service=$TARGET_SERVICE" -q | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
  log_error "Could not find container for $TARGET_SERVICE"
  exit 1
fi

# Apply anomaly
log_info "Applying [anomaly type]..."
# ... command to apply anomaly ...
log_success "Anomaly applied"

# Define cleanup
CLEANUP_ANOMALY='
  log_info "Cleaning up..."
  # ... cleanup commands ...
  log_success "Cleanup complete"
'

# Test parameters
USERS=100
RAMPUP=60
DURATION=600

log_success "[ANOMALY-NNN] Setup complete"
log_info "Starting load test..."

# Main script continues...
```

---

## Common Commands

### Apply Docker resource limits
```bash
# Memory limit
docker update --memory 256m <container_id>

# CPU limit  
docker update --cpus 0.25 <container_id>

# Both
docker update --memory 256m --cpus 0.25 <container_id>
```

### Network simulation with tc
```bash
# Add 500ms latency
sudo tc qdisc add dev eth0 root netem delay 500ms

# Add jitter
sudo tc qdisc add dev eth0 root netem delay 100ms 20ms

# Add packet loss
sudo tc qdisc add dev eth0 root netem loss 5%

# Remove qdisc
sudo tc qdisc del dev eth0 root
```

### Check container resource usage
```bash
# Real-time stats
docker stats <container_id>

# Single snapshot
docker stats <container_id> --no-stream

# Memory usage
docker stats <container_id> --format "{{.MemUsage}}" --no-stream

# CPU usage
docker stats <container_id> --format "{{.CPUPerc}}" --no-stream
```

---

## Debugging Failed Tasks

If a task script fails:

1. **Check prerequisites:**
   - Container running? `docker ps --filter "..."`
   - Tool available? `command -v <tool>`
   - Permissions? (sudo for tc/network commands)

2. **Run with debug output:**
   ```bash
   bash -x ./run-anomaly.sh ANOMALY-NNN
   ```

3. **Check logs:**
   - Main log: `anomaly-results/anomaly.log`
   - JMeter log: `anomaly-results/ANOMALY-NNN-jmeter.log`
   - Application logs: `anomaly-results/ANOMALY-NNN-logs/`

4. **Manual verification:**
   ```bash
   # Check if anomaly conditions applied
   docker stats <container_id>
   docker logs <container_id>
   tc qdisc show dev eth0
   ```

---

## Integration with Monitoring

Each task script generates:
- **JMeter results CSV:** `anomaly-results/ANOMALY-NNN-results.csv`
- **Application logs:** `anomaly-results/ANOMALY-NNN-logs/`
- **Trace data:** `anomaly-results/ANOMALY-NNN-traces/` (Tempo integration)

To analyze results:

1. **Prometheus queries:** See `MONITORING-QUERIES.md`
2. **Update CSV:** Add findings to `ANOMALIES-RESULTS.csv`
3. **Review traces:** Open Grafana → Explore → Traces (Tempo)

---

## Anomaly-Specific Tips

### For Resource Limit Tests (Memory/CPU)
- Slowly increase load to see when limits activate
- Monitor both resource usage AND latency impact
- Unexpected behavior may indicate kernel page cache effects

### For Network Tests
- Ensure latency applies uniformly to all services
- High jitter can cause timeout cascade
- Packet loss + retries create asymmetric behavior

### For Database Tests
- Monitor connection pool metrics continuously
- Connections may not free immediately after test ends
- Check for connection leaks in application

---

## Next Steps

1. Execute ANOMALY-001 to verify setup:
   ```bash
   ./run-anomaly.sh ANOMALY-001 --duration 300 --users 50
   ```

2. Review results:
   ```bash
   tail -50 anomaly-results/anomaly.log
   cat anomaly-results/ANOMALY-001-results.csv
   ```

3. Query monitoring data using queries from `MONITORING-QUERIES.md`

4. Add findings to `ANOMALIES-RESULTS.csv`

5. Proceed with remaining anomaly tests
