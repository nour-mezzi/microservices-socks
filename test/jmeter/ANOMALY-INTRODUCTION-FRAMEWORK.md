# Sock Shop - Anomaly Introduction Framework

## Overview
This framework provides a systematic approach to introduce various anomalies and failure modes into the Sock Shop microservices application. These anomalies simulate real-world issues that the RCA (Root Cause Analysis) system will later identify and debug.

---

## Anomaly Categories

### 1. **RESOURCE SATURATION ANOMALIES**

#### 1.1 Memory Pressure (OOM Scenarios)
**Goal:** Trigger Out-of-Memory conditions and long GC pauses

**How to Introduce:**
- Reduce Docker memory limits for services (start at 256MB, then 128MB)
- Run extended load tests (10-15 minutes) with slow ramp-up (120 seconds)
- Monitor for memory fragmentation and GC overhead

**Services to Target:**
- `catalogue` (most stateful queries)
- `user` (session management)
- `orders` (complex transactions)

**Monitoring Signals (Prometheus):**
```
container_memory_usage_bytes{pod=~"catalogue.*"}
container_memory_max_usage_bytes{pod=~"catalogue.*"}
jvm_memory_usage_bytes{area="heap"}
jvm_gc_pause_seconds_sum{gc="G1 Young Generation"}
jvm_memory_committed_bytes
```

**Monitoring Signals (Loki):**
```
{job="pod"} | grep "OutOfMemoryError"
{job="pod"} | grep "Killed process"
{job="pod"} | grep -i "java.lang.OutOfMemoryError"
{job="pod"} | grep "Increasing heap size"
```

**Monitoring Signals (Tempo):**
- Broken/incomplete traces during memory crisis
- Missing trace segments after restart
- Spike in trace duration during GC pause

**Task:** [ANOMALY-001-MEMORY-PRESSURE]

---

#### 1.2 CPU Saturation
**Goal:** Exceed CPU limits and trigger throttling/timeouts

**How to Introduce:**
- Set Docker CPU limits (0.25 CPU, then 0.1 CPU)
- Gradually increase JMeter threads (start 50, increment to 200)
- Monitor for CPU throttling and latency degradation

**Services to Target:**
- `front-end` (regex matching, template rendering)
- `payment` (encryption/hashing)
- `catalogue` (search/filtering)

**Monitoring Signals (Prometheus):**
```
rate(container_cpu_usage_seconds_total{pod=~"payment.*"}[1m])
container_cpu_cfs_throttled_seconds_total
rate(container_cpu_cfs_throttled_seconds_total[1m])
histogram_quantile(0.95, http_request_duration_seconds_bucket{job="api"})
container_processes_running
```

**Monitoring Signals (Loki):**
```
{job="pod"} | grep "timeout"
{job="pod"} | grep -i "rejected"
{job="pod"} | grep "deadline exceeded"
{job="pod"} | grep "Queue full"
```

**Monitoring Signals (Tempo):**
- Increased span duration for affected service
- Downstream timeouts visible in trace
- Cascading latency through call chain

**Task:** [ANOMALY-002-CPU-SATURATION]

---

#### 1.3 Disk I/O Pressure
**Goal:** Simulate disk contention and I/O wait conditions

**How to Introduce:**
- Add concurrent disk-heavy workloads (logs, temp files)
- Run `fio` stress tool on MongoDB volume
- Monitor iowait and disk utilization

**Monitoring Signals (Prometheus):**
```
node_disk_io_time_ms{device="sda1"}
node_disk_reads_completed_total
node_disk_writes_completed_total
node_disk_io_time_weighted_ms
rate(node_disk_ios_completed_total[5m])
```

**Monitoring Signals (Loki):**
```
{job="pod"} | grep "I/O error"
{job="pod"} | grep "disk full"
{job="pod"} | grep -i "seek"
```

**Task:** [ANOMALY-003-DISK-IO-PRESSURE]

---

### 2. **SERVICE FAILURE ANOMALIES**

#### 2.1 Database Connection Pool Exhaustion
**Goal:** Trigger connection timeout errors and cascading failures

**How to Introduce:**
- Reduce MongoDB connection pool size (default 100 → 10)
- Increase JMeter thread count dramatically (500+ concurrent)
- Introduce slow queries (sleep in MongoDB aggregation)

**Monitoring Signals (Prometheus):**
```
mysql_connections_active
mysql_connections_available
mysql_connections_limit_percent  (if available)
rate(mysql_commands_error_total[1m])
db_connection_checkout_time_ms
```

**Monitoring Signals (Loki):**
```
{job="mongodb"} | grep "getConnection"
{job="mongodb"} | grep "Connection pool exhausted"
{job="api"} | grep "ConnectionException"
{job="db"} | grep "too many connections"
```

**Monitoring Signals (Tempo):**
- Database operation spans showing 10s+ durations
- Pending queue visible in trace metadata
- Many retries on a single query

**Task:** [ANOMALY-004-DB-POOL-EXHAUSTION]

---

#### 2.2 Cascading Failures (Chain Reaction)
**Goal:** Simulate failure propagation through service mesh

**How to Introduce:**
- Automatically trigger via upstream latency (in JMeter)
- Add 8s delay before product-details requests
- Expect downstream 500s as timeouts ripple

**Monitoring Signals (Prometheus):**
```
http_requests_total{status="500|503|504"}
histogram_quantile(0.99, http_request_duration_seconds_bucket)
service_request_latency_seconds{quantile="0.95"}
rate(errors_total[5m])
```

**Monitoring Signals (Loki):**
```
{job="api"} status=500
{job="api"} | grep "upstream unavailable"
{job="api"} | grep "circuit breaker"
{job="api"} | grep -i "dependency.*failed"
```

**Monitoring Signals (Tempo):**
- All downstream traces show errors within time window
- Clear trace of timeout → 500 → client error
- Correlated start/end times across services

**Task:** [ANOMALY-005-CASCADE-FAILURE] (Already in JMeter)

---

#### 2.3 Partial Service Degradation
**Goal:** Service available but significantly slower

**How to Introduce:**
- Restart service with added sleep in request handler (middleware)
- Add 100-500ms artificial delay to specific endpoints
- Keep success rate high but throughput low

**Monitoring Signals (Prometheus):**
```
histogram_quantile(0.50, http_request_duration_seconds_bucket)
histogram_quantile(0.95, http_request_duration_seconds_bucket)
histogram_quantile(0.99, http_request_duration_seconds_bucket)
http_requests_total{service="catalogue"}
rate(http_requests_total[1m])
```

**Monitoring Signals (Loki):**
```
{job="catalogue"} "request_duration_ms" | pattern "request_duration_ms=<duration>"
{job="catalogue"} | stats avg(duration) by service
```

**Monitoring Signals (Tempo):**
- Specific endpoint shows 500%+ increased span duration
- Other endpoints unaffected
- Pattern: slow endpoint → cascade through dependent services

**Task:** [ANOMALY-006-PARTIAL-DEGRADATION]

---

### 3. **NETWORK ANOMALIES**

#### 3.1 Network Latency Spikes
**Goal:** Introduce artificial network delays

**How to Introduce:**
- Use `tc` (traffic control) to add latency: `tc qdisc add dev eth0 root netem delay 500ms`
- Introduce jitter: `tc qdisc add dev eth0 root netem delay 100ms 20ms`
- Run for 5 minutes during load test

**Monitoring Signals (Prometheus):**
```
probe_http_duration_seconds
rate(network_transmit_bytes_total[1m])
rate(network_receive_bytes_total[1m])
node_network_transmit_errors_total
node_network_receive_errors_total
```

**Monitoring Signals (Loki):**
```
{job="pod"} | grep -i "connection.*timeout"
{job="pod"} | grep -i "deadline"
{job="pod"} | grep "read timeout"
```

**Monitoring Signals (Tempo):**
- Network spans (external calls) show 2-3x increase in duration
- Local processing unaffected
- Clear correlation with event time

**Task:** [ANOMALY-007-NETWORK-LATENCY]

---

#### 3.2 Packet Loss
**Goal:** Simulate unreliable network conditions

**How to Introduce:**
- Use `tc` with loss: `tc qdisc add dev eth0 root netem loss 5%`
- Vary loss percentage (5% → 25%)
- Monitor retry behavior

**Monitoring Signals (Prometheus):**
```
rate(http_request_errors_total{reason="connection_dropped"}[1m])
rate(tcp_connection_resets_total[1m])
http_request_retries_total
```

**Monitoring Signals (Loki):**
```
{job="pod"} | grep -i "RST"
{job="pod"} | grep -i "connection reset"
{job="pod"} | grep -i "dropped"
{job="api"} | grep "retry"
```

**Monitoring Signals (Tempo):**
- Retried spans visible in same trace
- Parent span shows increased duration due to retries
- Multiple child operations for single logical request

**Task:** [ANOMALY-008-PACKET-LOSS]

---

### 4. **DATA CONSISTENCY ANOMALIES**

#### 4.1 Stale Cache/Data Mismatch
**Goal:** Introduce cache invalidation issues

**How to Introduce:**
- Disable cache invalidation for catalogue service
- Update product data in MongoDB directly
- Observe front-end showing stale data

**Monitoring Signals (Prometheus):**
```
cache_hit_ratio
cache_misses_total
cache_evictions_total
```

**Monitoring Signals (Loki):**
```
{job="catalogue"} "cache_mismatch"
{job="catalogue"} "stale_data"
```

**Monitoring Signals (Tempo):**
- Cache lookup spans not invalidated
- Mismatch between data retrieved and current state

**Task:** [ANOMALY-009-STALE-CACHE]

---

#### 4.2 Database Corruption (Simulated)
**Goal:** Simulate data integrity issues

**How to Introduce:**
- Inject MongoDB write failures midway through transaction
- Create orphaned records (user without associated orders)
- Trigger validation errors

**Monitoring Signals (Prometheus):**
```
db_transaction_rollbacks_total
db_integrity_checks_failed_total
db_write_errors_total
```

**Monitoring Signals (Loki):**
```
{job="mongodb"} "validation failed"
{job="api"} "data integrity error"
{job="api"} "constraint violation"
```

**Task:** [ANOMALY-010-DB-CORRUPTION]

---

### 5. **EXTERNAL DEPENDENCY ANOMALIES**

#### 5.1 External API Timeout
**Goal:** Simulate slow/unavailable external services (payment gateway, etc.)

**How to Introduce:**
- Mock external API with 30s response time
- Return intermittent 503 errors
- Trigger client-side timeout logic

**Monitoring Signals (Prometheus):**
```
external_api_request_duration_seconds
external_api_error_rate
rate(external_api_timeouts_total[1m])
```

**Monitoring Signals (Loki):**
```
{job="payment"} "external.*timeout"
{job="payment"} | grep "retry attempt"
```

**Monitoring Signals (Tempo):**
- External service spans showing 30s+ duration
- Retry logic visible in trace
- Client-side timeout after configured threshold

**Task:** [ANOMALY-011-EXTERNAL-TIMEOUT]

---

### 6. **APPLICATION-LEVEL ANOMALIES**

#### 6.1 Memory Leak
**Goal:** Simulate memory leak without immediate OOM

**How to Introduce:**
- Java: Add accumulating collection without cleanup
- Python: Keep references to large objects in daemon thread
- Monitor memory growth over time

**Monitoring Signals (Prometheus):**
```
jvm_memory_usage_bytes{area="heap"}  # Should show steady growth
container_memory_usage_bytes  # Linear increase over time
jvm_gc_pause_seconds_count  # Increasing GC frequency
```

**Monitoring Signals (Loki):**
```
{job="service"} "unable to allocate"
{job="service"} | stats max(memory_usage_mb) by time interval
```

**Monitoring Signals (Tempo):**
- Trace duration increases over time
- GC pause spans appear with increasing frequency

**Task:** [ANOMALY-012-MEMORY-LEAK]

---

#### 6.2 Thread Leak / Thread Pool Exhaustion
**Goal:** Simulate thread resource exhaustion

**How to Introduce:**
- Create new threads without cleanup
- Reduce thread pool size
- Trigger scenarios requiring many concurrent threads

**Monitoring Signals (Prometheus):**
```
jvm_threads_live  # Should increase to limit
jvm_threads_daemon
jvm_threads_peak
```

**Monitoring Signals (Loki):**
```
{job="service"} | grep "thread pool"
{job="service"} | grep "Thread.*rejected"
{job="service"} | grep "RejectedExecutionException"
```

**Task:** [ANOMALY-013-THREAD-LEAK]

---

#### 6.3 Deadlock / Lock Contention
**Goal:** Simulate resource contention and potential deadlock

**How to Introduce:**
- Introduce locks in circular dependency
- High concurrency on shared resources
- Monitor for timeout patterns

**Monitoring Signals (Prometheus):**
```
app_lock_wait_time_seconds
app_lock_contention
rate(app_deadlocks_total[1m])
```

**Monitoring Signals (Loki):**
```
{job="service"} | grep -i "deadlock"
{job="service"} | grep -i "lock.*timeout"
{job="service"} | grep "waited for.*lock"
```

**Monitoring Signals (Tempo):**
- Spans blocked on lock acquisition
- Asymmetric latency (some requests much slower)

**Task:** [ANOMALY-014-DEADLOCK]

---

## Execution Strategy

### Phase 1: Setup
1. Document baseline metrics for each service
2. Configure alert thresholds
3. Prepare test infrastructure

### Phase 2: Anomaly Introduction
1. Introduce one anomaly at a time
2. Run for 5-15 minutes with consistent load
3. Capture metrics, logs, and traces
4. Record timestamps and affected services

### Phase 3: Analysis & Documentation
1. Verify anomaly presence in monitoring data
2. Document correlation patterns
3. Create RCA queries
4. Update results CSV

---

## Test Configuration Template

```bash
#!/bin/bash
# test-anomaly-[ID].sh

ANOMALY_ID="[ID]"
ANOMALY_NAME="[NAME]"
DURATION_MINUTES=10
JMETER_USERS=100
JMETER_RAMPUP=60

# 1. Apply resource constraints / simulated failures
# docker update --memory 256m <container_id>
# tc qdisc add dev eth0 root netem delay 500ms

# 2. Start test
python3 run-load-test.sh --users $JMETER_USERS --rampup $JMETER_RAMPUP --duration $((DURATION_MINUTES * 60))

# 3. Capture results
# Prometheus queries exported to anomalies-results.csv
# Logs exported to logs/
# Traces exported to traces/

# 4. Cleanup
# docker update --memory 512m <container_id>
# tc qdisc del dev eth0 root
```

---

## Results Tracking

Results are logged to `anomalies-results.csv` with:
- Anomaly ID & Name
- Start / End Time
- Duration
- Affected Service(s)
- Root Metric (the most obvious anomaly signal)
- Latency Impact (P50, P95, P99)
- Error Rate Impact
- Resource Utilization at Peak
- Query to Reproduce

---

## Quick Reference: Detection Queries

### Memory Issues
```
avg(container_memory_usage_bytes) / avg(container_spec_memory_limit_bytes) > 0.8
histogram_quantile(0.99, jvm_gc_pause_seconds_bucket) > 0.5
```

### CPU Issues
```
rate(container_cpu_usage_seconds_total[5m]) > 0.9
rate(container_cpu_cfs_throttled_seconds_total[1m]) > 0
```

### Latency Issues
```
histogram_quantile(0.95, http_request_duration_seconds_bucket) > 1
rate(http_requests_total{status=~"5.."}[5m]) > 0.05
```

### Connection Issues
```
rate(errors_total{type="connection"}[1m]) > 0
mysql_connections_active > mysql_connections_max * 0.8
```

---

## Next Steps

1. Implement individual anomaly task scripts in `tasks/` directory
2. Populate `anomalies-results.csv` with baseline data
3. Create `monitoring-queries.md` with all RCA queries
4. Run through each anomaly scenario sequentially
5. Validate that AI RCA system can identify root causes
