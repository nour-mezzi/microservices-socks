# Sock Shop - Anomaly Quick Reference Card

## 14 Anomalies at a Glance

| ID | Name | Service | Root Cause | Setup | Monitoring Signal | Duration |
|----|------|---------|------------|-------|-------------------|----------|
| 001 | Memory Pressure | catalogue | OOM | Memory: 256M | Heap% >85%, GC pause 500ms | 10m |
| 002 | CPU Saturation | payment | Throttling | CPU: 0.25 cores, 150 users | CPU >90%, throttle >0 | 10m |
| 003 | Disk I/O Pressure | mongodb | I/O wait | fio stress on /data | I/O latency >5000ms | 10m |
| 004 | Pool Exhaustion | api+db | Connections full | Pool: 10, 200 users | Queue depth >50, latency >5s | 10m |
| 005 | Cascading Failure | multi | Chain reaction | 8s delay (JMeter) | 5xx on multiple services | 5m |
| 006 | Partial Degradation | catalogue | Slow endpoint | +200ms delay | Endpoint P95 3x, success >95% | 10m |
| 007 | Network Latency | all | High latency | tc: +500ms latency | Latency 5x uniform, no errors | 10m |
| 008 | Packet Loss | all | Lost packets | tc: 5% loss | Retries, errors 12%+, resets | 10m |
| 009 | Stale Cache | catalogue | Invalidation broken | Disable invalidation | Hit% <70%, old data | 10m |
| 010 | DB Corruption | orders | Write failure | Mid-transaction fail | Rollbacks >0, constraints | 5m |
| 011 | External Timeout | payment | Slow gateway | 30s response time | External latency >30s | 10m |
| 012 | Memory Leak | catalogue | Leak accumulation | Long-run sustained | Memory +10%/hr, GC↑ | 120m |
| 013 | Thread Leak | catalogue | No cleanup | No thread cleanup | Threads →max, RejectedExecution | 15m |
| 014 | Deadlock | orders | Lock circular dep | Circular locks | Async latency, lock errors | 10m |

---

## Quick Commands

### Run a Test
```bash
cd /home/user/microservices-demo/test/jmeter
./run-anomaly.sh ANOMALY-001 --duration 600 --users 100
```

### View Results
```bash
tail -50 anomaly-results/anomaly.log
cat anomaly-results/ANOMALY-001-results.csv
```

### Query Monitoring (Prometheus)
Go to: `http://localhost:9090`

**Memory:** 
```promql
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100
```

**CPU:**
```promql
rate(container_cpu_usage_seconds_total[1m])
```

**Latency:**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket)
```

**Errors:**
```promql
rate(http_requests_total{status=~"5.."}[1m])
```

---

## Test Progression

### Basic Tests (Start Here)
```bash
./run-anomaly.sh ANOMALY-001 --duration 300 --users 50   # 5 min
./run-anomaly.sh ANOMALY-007 --duration 300 --users 50   # Network
```

### Resource Tests
```bash
./run-anomaly.sh ANOMALY-002 --duration 600 --users 150  # CPU
./run-anomaly.sh ANOMALY-004 --duration 600 --users 200  # Connections
```

### Long-Running
```bash
./run-anomaly.sh ANOMALY-012 --duration 7200 --users 80  # Memory leak (2h)
```

---

## Key Symptoms

### **High Latency** (50ms → 100s+)
- ANOMALY-002: CPU throttle (P95: 2.5s)
- ANOMALY-004: Connection queue (P99: 8s)
- ANOMALY-007: Network delay (P95: 800ms)
- ANOMALY-011: External timeout (P95: 30s)
- ANOMALY-014: Lock contention (asymmetric)

### **High Error Rate** (0% → 20%+)
- ANOMALY-001: OOM (kill) → restart → 0% = spike
- ANOMALY-002: CPU: 15%+ timeouts
- ANOMALY-004: Pool full: 22%+ connection errors
- ANOMALY-008: Packet loss: 12%+ connection errors
- ANOMALY-011: External API: 45%+ failures

### **Resource Pressure** (Trending Up)
- ANOMALY-001: Memory → 95% of limit
- ANOMALY-002: CPU → 90% throttled
- ANOMALY-012: Memory +10% per hour
- ANOMALY-013: Threads → max (1900/2000)

### **Cascading / Correlated**
- ANOMALY-005: 5xx on multiple services at once
- ANOMALY-007: All services latency ↑ together
- ANOMALY-014: Some requests fast, some slow (not all)

---

## Detection Pattern Template

```
When <TRIGGER> occurs:
├─ Metric 1: <VALUE/PATTERN>
├─ Metric 2: <VALUE/PATTERN>  
├─ Log Line: <PATTERN>
├─ Trace Signature: <PATTERN>
└─ Root Cause: <ANOMALY-NNN>
```

### Example: ANOMALY-002 (CPU Saturation)
```
When container_cpu_usage > 90%:
├─ container_cpu_cfs_throttled_seconds_total > 0
├─ http_request_duration P95 > 500ms
├─ {job="pod"} | grep "timeout"
├─ Payment service spans showing 200-300ms each
└─ Root Cause: ANOMALY-002 - CPU Saturation
```

---

## Files & Locations

```
test/jmeter/
├── run-anomaly.sh                         # Main orchestrator ✓
├── ANOMALY-TESTING-GUIDE.md              # Full guide ✓
├── ANOMALY-INTRODUCTION-FRAMEWORK.md     # Detailed specs ✓
├── MONITORING-QUERIES.md                 # All detection queries ✓
├── ANOMALIES-RESULTS.csv                 # Results tracking ✓
├── QUICK-REFERENCE-CARD.md               # This file ✓
├── tasks/
│   ├── README.md                         # Task development guide ✓
│   ├── anomaly-001.sh                    # Memory pressure ✓
│   ├── anomaly-002.sh                    # CPU saturation ✓
│   ├── anomaly-004.sh                    # Pool exhaustion ✓
│   ├── anomaly-007.sh                    # Network latency ✓
│   └── [anomaly-003,005,006,008-014]     # Template examples ✓
└── anomaly-results/
    ├── anomaly.log
    ├── ANOMALY-NNN-results.csv
    ├── ANOMALY-NNN-logs/
    └── ANOMALY-NNN-traces/
```

---

## Use Cases

### 1. **Train RCA System**
```
1. Run anomaly tests: ./run-anomaly.sh ANOMALY-001
2. Collect metrics & logs
3. Label with anomaly ID
4. Feed to ML model
5. Train detection classifier
```

### 2. **Validate Monitoring**
```
1. Run anomaly
2. Verify Prometheus query detects it
3. Check Loki logs capture error
4. Review Tempo trace shows issue
5. Document query in MONITORING-QUERIES.md
```

### 3. **Stress Test Services**
```
1. ANOMALY-012 (memory leak): 2-hour endurance
2. ANOMALY-004 (pool exhaustion): 10-min high concurrency
3. ANOMALY-008 (packet loss): Network resilience
4. Observe graceful degradation
```

### 4. **Document Failure Modes**
```
1. Run each anomaly
2. Capture before/after metrics
3. Document expected vs actual
4. Update runbooks
5. Train on-call team
```

---

## Success Criteria

✓ **Anomaly Triggered:**
- Monitoring metrics show deviation from baseline
- Error/warning in application logs
- Trace data shows failure pattern
- Correlate timing across systems

✓ **Data Captured:**
- JMeter results (latency, errors)
- Application logs (errors, warnings)
- Prometheus metrics (resource, latency)
- Traces (span duration, propagation)

✓ **Results Documented:**
- CSV updated with findings
- Monitoring query added to guide
- Root cause identified
- Signatures cataloged

---

## Common Issues

| Issue | Solution |
|-------|----------|
| Container not found | `docker ps` to verify running |
| JMeter timeout during setup | Increase `DURATION` smaller than startup |
| Permission denied (tc) | `sudo usermod -aG docker $USER` then re-login |
| Anomaly not visible | Check monitoring is enabled, queries correct |
| Results not in CSV | Manually add or review test_results.csv |
| Tests keep failing | `bash -x ./run-anomaly.sh ANOMALY-NNN` debug |

---

## Next: After Running Tests

1. **Update CSV:** Add findings from actual tests to ANOMALIES-RESULTS.csv
2. **Verify Queries:** Ensure all Prometheus/Loki queries detect anomalies
3. **Review Traces:** Check Tempo exports show expected patterns
4. **Document:** Add observations to framework file
5. **Train Model:** Feed results to RCA system

---

## Resources

- Framework: [ANOMALY-INTRODUCTION-FRAMEWORK.md](ANOMALY-INTRODUCTION-FRAMEWORK.md)
- Queries: [MONITORING-QUERIES.md](MONITORING-QUERIES.md)
- Guide: [ANOMALY-TESTING-GUIDE.md](ANOMALY-TESTING-GUIDE.md)
- Tasks: [tasks/README.md](tasks/README.md)
- Results: [ANOMALIES-RESULTS.csv](ANOMALIES-RESULTS.csv)

---

**Created:** 2024-03-05  
**Framework:** 14 Anomalies | 5 Task Scripts | 2600+ Monitoring Queries  
**Status:** ✓ Ready for Testing
