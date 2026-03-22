# Sock Shop - Anomaly Introduction & Testing Guide

## Overview

This guide provides a comprehensive framework for introducing, testing, and analyzing anomalies in the Sock Shop microservices application. The anomalies simulate real-world failures that the AI-based Root Cause Analysis (RCA) system will later identify and diagnose.

## Quick Start

### 1. View Available Anomalies
```bash
cd /home/user/microservices-demo/test/jmeter
./run-anomaly.sh --help
```

### 2. Run Your First Anomaly Test
```bash
# Test ANOMALY-001 (Memory Pressure) for 10 minutes with 100 users
./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
```

### 3. Review Results
```bash
# View test summary
tail -50 anomaly-results/anomaly.log

# Check JMeter results
head -20 anomaly-results/ANOMALY-001-results.csv

# View application logs captured during test
cat anomaly-results/ANOMALY-001-logs/catalogue.log
```

### 4. Query Monitoring Data
Go to Grafana → Explore and use queries from `MONITORING-QUERIES.md` to visualize:
- Prometheus metrics (resource usage, latency, errors)
- Loki logs (error messages, warnings, timestamps)
- Tempo traces (span duration, error propagation, dependencies)

---

## Framework Files

### Main Documentation

| File | Purpose |
|------|---------|
| `ANOMALY-INTRODUCTION-FRAMEWORK.md` | Complete documentation of all 14 anomalies, setup instructions, and expected behaviors |
| `MONITORING-QUERIES.md` | Production-ready queries for Prometheus, Loki, and Tempo to detect each anomaly |
| `tasks/README.md` | Guide for creating and executing individual anomaly task scripts |
| `ANOMALIES-RESULTS.csv` | Template CSV for tracking test results and findings |

### Executable Scripts

| File | Purpose |
|------|---------|
| `run-anomaly.sh` | Main orchestrator script for running anomaly tests |
| `tasks/anomaly-001.sh` | Memory Pressure (OOM) task |
| `tasks/anomaly-002.sh` | CPU Saturation task |
| `tasks/anomaly-004.sh` | Database Connection Pool Exhaustion task |
| `tasks/anomaly-007.sh` | Network Latency Spikes task |

---

## Anomaly Categories

### 1. **Resource Saturation** (Anomalies 001-003)
Trigger memory pressure, CPU throttling, and disk I/O saturation.

**Typical Signals:**
- High resource utilization
- GC pauses / context switches
- Latency increase
- Potential timeouts

### 2. **Service Failures** (Anomalies 004-006)
Database pool exhaustion, cascading failures, and partial degradation.

**Typical Signals:**
- Connection errors
- Growing error rates
- Cascading latency through service chain
- Error propagation visible in traces

### 3. **Network Issues** (Anomalies 007-008)
Network latency spikes and packet loss.

**Typical Signals:**
- Uniform latency increase (all services)
- Retry patterns in logs/traces
- Connection resets
- High-latency but low-error patterns

### 4. **Data Consistency** (Anomalies 009-010)
Stale cache and database corruption.

**Typical Signals:**
- Cache hit ratio drops
- Transaction rollbacks
- Constraint violations
- Data inconsistency errors

### 5. **External Dependencies** (Anomaly 011)
External API timeouts.

**Typical Signals:**
- External call latency > 30 seconds
- Timeout errors
- Retry attempts
- Fallback path activation

### 6. **Application-level** (Anomalies 012-014)
Memory leaks, thread leaks, and deadlocks.

**Typical Signals:**
- Resource usage trending upward/maxed
- Asymmetric latency patterns
- Serialization instead of parallelism
- Lock contention messages

---

## Test Execution Workflow

### Step 1: Prepare Environment
```bash
# Ensure Sock Shop is running
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Verify services are healthy
curl http://localhost/

# Check monitoring stack is running
curl http://localhost:9090  # Prometheus
curl http://localhost:3000  # Grafana
```

### Step 2: Choose Anomaly and Review Docs
```bash
# Example: Review memory pressure anomaly
cat ANOMALY-INTRODUCTION-FRAMEWORK.md | grep -A 30 "ANOMALY-001"

# Check the task script setup
cat tasks/anomaly-001.sh
```

### Step 3: Execute Test
```bash
./run-anomaly.sh ANOMALY-001 --duration 600 --users 100 --rampup 60
```

### Step 4: Analyze Results
```bash
# 1. JMeter metrics
cat anomaly-results/ANOMALY-001-results.csv

# 2. Application logs
grep -i "error\|warning\|exception" anomaly-results/ANOMALY-001-logs/*.log

# 3. Query Prometheus (during or after test)
# Go to: http://localhost:9090
# Try: container_memory_usage_bytes{pod=~"catalogue.*"}
```

### Step 5: Update Results CSV
```bash
# Edit ANOMALIES-RESULTS.csv with findings
# Add: start_time, end_time, latency_p95_peak, error_rate_peak, key_finding
```

---

## Running Multiple Tests

### Sequential Testing (Recommended for first run)
```bash
# Test each anomaly one at a time, reviewing results between tests
for anomaly in ANOMALY-001 ANOMALY-002 ANOMALY-004; do
  echo "Testing $anomaly..."
  ./run-anomaly.sh "$anomaly" --duration 600
  sleep 60  # Cool-down period
  # Review results before proceeding
done
```

### Parallel Testing (Advanced)
```bash
# Run multiple anomalies in parallel (requires separate test environments)
./run-anomaly.sh ANOMALY-001 &
sleep 30
./run-anomaly.sh ANOMALY-007 &
wait
```

---

## Key Monitoring Queries

### For Prometheus (http://localhost:9090)

**Memory Pressure Detection:**
```promql
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 85
```

**CPU Saturation Detection:**
```promql
rate(container_cpu_usage_seconds_total[1m]) > 0.9
```

**High Latency Detection:**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket) > 1
```

**Error Rate Detection:**
```promql
rate(http_requests_total{status=~"5.."}[5m]) > 0.05
```

### For Loki (Grafana → Explore → Logs)

**OutOfMemory Errors:**
```logql
{job="pod"} | grep -i "OutOfMemoryError"
```

**Connection Failures:**
```logql
{job="api"} | grep -i "ConnectionException|connection.*refused"
```

**Timeout Logs:**
```logql
{job="pod"} | grep -i "timeout|deadline"
```

### For Tempo (Grafana → Explore → Traces)

**Long-running Traces:**
- Filter by Service = "catalogue"
- Look for traces with duration > 1 second
- Examine span timeline for bottleneck

**Error Traces:**
- Filter by Error = true
- Check time correlation across services
- Identify service with earliest error timestamp

---

## Common Issues & Solutions

### Issue: Container not found
```bash
# Verify containers are running
docker ps --format "table {{.Names}}\t{{.Status}}"

# Start them if needed
docker compose -f deploy/docker-compose/docker-compose.yml -f deploy/docker-compose/docker-compose.monitoring.yml up -d
```

### Issue: tc (traffic control) not available
```bash
# Install on Linux
sudo apt-get install iproute2

# On Mac (Docker Desktop), traffic control runs inside VM
# Alternative: Use Docker CPU limits instead
```

### Issue: Permission denied for sudo
```bash
# Add current user to sudoers (one-time)
sudo usermod -aG sudo $USER
# Then re-login

# Or run JMeter from root shell
sudo -i
cd /home/user/microservices-demo/test/jmeter
./run-anomaly.sh ANOMALY-007
```

### Issue: Test fails immediately
```bash
# Enable debug logging
bash -x ./run-anomaly.sh ANOMALY-001

# Check if JMeter is installed
jmeter --version

# Install if needed
# See: https://jmeter.apache.org/download_jmeter.cgi
```

---

## Detailed Anomaly List

### ANOMALY-001: Memory Pressure (OOM)
- **Service:** catalogue
- **Method:** Reduce memory limit to 256MB, run sustained load
- **Expected:** GC pause 50ms→500ms+, eventual OOM kill
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-002: CPU Saturation
- **Service:** payment
- **Method:** Set CPU limit to 0.25, high concurrency (150 users)
- **Expected:** Throttling, 8-10x latency spike, timeout errors
- **Duration:** 10 minutes
- **Users:** 150

### ANOMALY-003: Disk I/O Pressure
- **Service:** mongodb
- **Method:** Run concurrent disk-heavy workload (fio stress)
- **Expected:** Query latency 3x, I/O wait high
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-004: Database Connection Pool Exhaustion
- **Service:** API + MongoDB
- **Method:** Reduce pool size to 10, use 200 concurrent users
- **Expected:** Queue depth grows, P99 latency >5 seconds
- **Duration:** 10 minutes
- **Users:** 200

### ANOMALY-005: Cascading Failures
- **Service:** Multiple (catalogue, user, product)
- **Method:** Already in JMeter - 8s delay trigger cascade
- **Expected:** Errors propagate across services within 2 seconds
- **Duration:** 5 minutes
- **Users:** 100

### ANOMALY-006: Partial Degradation
- **Service:** catalogue
- **Method:** Add 200ms artificial delay to specific endpoint
- **Expected:** One endpoint 5x slower, downstream latency +10x
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-007: Network Latency Spikes
- **Service:** All (network-wide)
- **Method:** tc (traffic control) - add 500ms latency
- **Expected:** Uniform latency increase, no error spike
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-008: Packet Loss
- **Service:** All (network-wide)
- **Method:** tc - add 5% packet loss
- **Expected:** Retries visible, error rate 12%+, asymmetric latency
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-009: Stale Cache
- **Service:** catalogue
- **Method:** Disable cache invalidation, manually update products
- **Expected:** Hit rate <70%, front-end shows old data
- **Duration:** 10 minutes
- **Users:** 100

### ANOMALY-010: Database Corruption
- **Service:** orders, user
- **Method:** Inject transaction failure mid-operation
- **Expected:** Rollback rate >0, constraint violations
- **Duration:** 5 minutes
- **Users:** 50

### ANOMALY-011: External API Timeout
- **Service:** payment
- **Method:** Mock payment gateway with 30s response
- **Expected:** 45%+ failure rate, retry attempts, fallback activation
- **Duration:** 10 minutes
- **Users:** 50

### ANOMALY-012: Memory Leak
- **Service:** catalogue
- **Method:** Run sustained load for 2 hours
- **Expected:** Memory grows linearly, GC frequency increases
- **Duration:** 120 minutes
- **Users:** 80

### ANOMALY-013: Thread Leak
- **Service:** catalogue
- **Method:** Create threads without cleanup, high concurrency
- **Expected:** Thread count → max (1900/2000), RejectedExecutionException
- **Duration:** 15 minutes
- **Users:** 150

### ANOMALY-014: Deadlock / Lock Contention
- **Service:** orders
- **Method:** Introduce circular lock dependency
- **Expected:** Asymmetric latency, some requests 50ms / others 5s+
- **Duration:** 10 minutes
- **Users:** 100

---

## Advanced: Adding Custom Anomalies

To create your own anomaly task:

1. **Create file:** `tasks/anomaly-NNN.sh`
2. **Source main script:** `source ../run-anomaly.sh`
3. **Apply anomaly:** Use docker commands, tc rules, or code modifications
4. **Define cleanup:** Set `CLEANUP_ANOMALY` variable
5. **Set parameters:** Configure `USERS`, `RAMPUP`, `DURATION`
6. **Document:** Add to this guide and framework file

Example:
```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/../run-anomaly.sh" 2>/dev/null || true

log_info "[ANOMALY-NNN] Setting up..."

# Apply anomaly
docker update --cpus 0.5 $CONTAINER_ID

# Define cleanup
CLEANUP_ANOMALY='docker update --cpus 1.0 $CONTAINER_ID'

# Configuration
USERS=100
RAMPUP=60
DURATION=600

log_success "[ANOMALY-NNN] Setup complete"
```

---

## Integration with RCA System

Once anomalies have been tested and their monitoring signatures documented:

1. **Feed test results** to AI RCA system training data
2. **Provide monitoring queries** from `MONITORING-QUERIES.md`
3. **Supply trace data** captured during tests
4. **Include logs** from `anomaly-results/ANOMALY-NNN-logs/`
5. **Document root causes** in CSV for supervised learning

The RCA system can then learn patterns to:
- Detect each anomaly type automatically
- Correlate metrics across monitoring systems
- Trace error propagation through service chains
- Recommend remediation actions

---

## Files Generated During Tests

```
anomaly-results/
├── anomaly.log                          # Main test log
├── ANOMALY-NNN-results.csv              # JMeter test results
├── ANOMALY-NNN-jmeter.log              # JMeter detailed log
├── ANOMALY-NNN-logs/
│   ├── catalogue.log                    # Service logs
│   ├── payment.log
│   ├── orders.log
│   └── ...                              # Other services
└── ANOMALY-NNN-traces/
    └── traces.json                      # Tempo traces (if captured)
```

---

## Next Steps

1. ✅ **Setup Complete** - All framework files created
2. **Run Tests** - Execute ANOMALY-001 through ANOMALY-014
3. **Collect Data** - Capture metrics, logs, traces for each
4. **Analyze Results** - Use monitoring queries to identify signatures
5. **Document Findings** - Update ANOMALIES-RESULTS.csv
6. **Train RCA System** - Feed prepared data to AI model

---

## Support

For issues or questions:
- Check `tasks/README.md` for task-specific help
- Review `ANOMALY-INTRODUCTION-FRAMEWORK.md` for detailed anomaly info
- Run with debug: `bash -x ./run-anomaly.sh ANOMALY-001`
- Check logs: `tail -100 anomaly-results/anomaly.log`

---

## References

- JMeter: https://jmeter.apache.org/
- Prometheus: https://prometheus.io/
- Grafana: https://grafana.com/
- Tempo: https://grafana.com/oss/tempo/
- Loki: https://grafana.com/oss/loki/
- tc (Linux Traffic Control): https://linux.die.net/man/8/tc
