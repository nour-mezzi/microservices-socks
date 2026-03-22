# Sock Shop - Monitoring Queries for Anomaly Detection

This document contains production-ready monitoring queries for Prometheus, Loki, and Tempo to detect and diagnose various anomalies introduced in the Sock Shop application.

---

## ANOMALY-001: MEMORY PRESSURE & OOM

### Prometheus Queries

**Query 1: Memory Usage Relative to Limit (Percentage)**
```promql
(container_memory_usage_bytes{pod=~"catalogue.*"} / container_spec_memory_limit_bytes{pod=~"catalogue.*"}) * 100
```
*Alert if > 85% for > 5 minutes*

**Query 2: Memory Growth Rate (per minute)**
```promql
rate(container_memory_usage_bytes{pod=~"catalogue.*"}[5m])
```
*Alert if positive trend for > 10 minutes*

**Query 3: JVM Heap Usage**
```promql
jvm_memory_usage_bytes{area="heap", pod=~"catalogue.*"} / jvm_memory_max_bytes{area="heap"} * 100
```
*Alert if approaching 95% of max*

**Query 4: GC Pause Duration (99th percentile)**
```promql
histogram_quantile(0.99, jvm_gc_pause_seconds_bucket{gc="G1 Young Generation", pod=~"catalogue.*"})
```
*Alert if > 0.5 seconds*

**Query 5: GC Frequency (Young Generation events per minute)**
```promql
rate(jvm_gc_pause_seconds_count{gc="G1 Young Generation", pod=~"catalogue.*"}[1m])
```
*Alert if > 10 events/minute*

**Query 6: Full GC with Collection Time**
```promql
increase(jvm_gc_pause_seconds_count{gc=~"G1 Old Generation", pod=~"catalogue.*"}[5m]) > 0
```
*Any Full GC indicates pressure*

**Query 7: Memory Committed vs Max**
```promql
jvm_memory_committed_bytes{area="heap", pod=~"catalogue.*"} / jvm_memory_max_bytes{area="heap"}
```
*Alert if committed is consistently using more than 80% of available*

### Loki Queries

**Query 1: Out of Memory Errors**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "OutOfMemoryError"
```

**Query 2: Process Killed**
```logql
{job="pod", pod=~"catalogue.*"} | grep "Killed"
```

**Query 3: Java Memory Pressure Logs**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "java.lang.OutOfMemory"
```

**Query 4: Container OOM Kill Events**
```logql
{job="kubelet"} | grep -i "OOMKilled"
```

**Query 5: Increasing Heap Size Messages**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "Increasing.*heap"
```

**Query 6: Memory Warning Logs**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "memory.*warning|critical"
```

### Tempo Queries

**Query 1: Broken/Incomplete Traces During Memory Crisis**
```
Resource attributes: service.name="catalogue" AND severity="error"
Look for: Traces with missing spans after timestamp during memory spike
Pattern: Complete trace until restart, then gaps
```

**Query 2: Span Duration Spike for GC Pause**
```
Service: catalogue
Look for: All spans with duration > 500ms at same timestamp
Pattern: Synchronized pause across all spans
```

**Query 3: Trace Tree Analysis**
- Navigate to Trace Detail view
- Filter: Service = "catalogue" during anomaly window
- Look for: Spans during GC pause time (visible in span details)

---

## ANOMALY-002: CPU SATURATION

### Prometheus Queries

**Query 1: CPU Usage Percentage (relative to limit)**
```promql
(rate(container_cpu_usage_seconds_total{pod=~"payment.*"}[1m]) / container_spec_cpu_quota{pod=~"payment.*"}) * 100
```
*Alert if > 90% for > 3 minutes*

**Query 2: CPU Throttling Rate**
```promql
rate(container_cpu_cfs_throttled_seconds_total{pod=~"payment.*"}[1m]) > 0
```
*Alert if any throttling detected*

**Query 3: Throttled Time Accumulation**
```promql
increase(container_cpu_cfs_throttled_seconds_total{pod=~"payment.*"}[5m])
```
*Alert if > 1 second of throttle time in 5mins*

**Query 4: CPU Context Switches (kernel perspective)**
```promql
rate(node_context_switches_total[1m])
```
*Alert if > 100k switches/sec (indicates heavy scheduler load)*

**Query 5: HTTP Request Latency P95 (correlation with CPU)**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{service="payment"}[5m]))
```
*Alert if > 1 second while CPU > 90%*

**Query 6: Throughput Drop (requests per second)**
```promql
rate(http_requests_total{service="payment"}[1m])
```
*Compare with baseline; alert if drop > 30% while CPU high*

**Query 7: Error Rate While CPU Saturated**
```promql
rate(http_requests_total{service="payment", status=~"5.."}[1m]) and on(pod) (rate(container_cpu_usage_seconds_total[1m]) > 0.8)
```

### Loki Queries

**Query 1: Timeout Messages**
```logql
{job="pod", pod=~"payment.*"} | grep -i "timeout"
```

**Query 2: Rejected Requests**
```logql
{job="pod", pod=~"payment.*"} | grep -i "rejected\|queue.*full"
```

**Query 3: Deadline Exceeded**
```logql
{job="pod", pod=~"payment.*"} | grep -i "deadline.*exceeded"
```

**Query 4: Resource Exhaustion**
```logql
{job="pod", pod=~"payment.*"} | grep -i "resource.*exhausted|too many\|limit"
```

**Query 5: CPU Throttle Signals**
```logql
{job="pod", pod=~"payment.*"} | grep -i "cfs_period|cgroup.*limit"
```

### Tempo Queries

**Query 1: Service Spans Duration Spike**
```
Service: payment
ServiceName span attribute
Look for: 3-5x increase in span.duration during anomaly window
Example: Normal 50ms → Peak 200-300ms
```

**Query 2: Downstream Cascade in Traces**
```
Look for: Single slow span → Multiple children with increased duration
Pattern: payment service slow → downstream services also slow
```

**Query 3: Retry Patterns in Traces**
```
Look for: Repeated trace operations on same parent
Count child spans: Normal 1 call, Under CPU stress: 3+ retries
```

---

## ANOMALY-003: DISK I/O PRESSURE

### Prometheus Queries

**Query 1: Disk I/O Utilization**
```promql
node_disk_io_time_ms{device="sda1"}
```
*Alert if increasing rapidly*

**Query 2: Read Operations Per Second**
```promql
rate(node_disk_reads_completed_total{device="sda1"}[1m])
```
*Alert if > baseline + 100%*

**Query 3: Write Operations Per Second**
```promql
rate(node_disk_writes_completed_total{device="sda1"}[1m])
```

**Query 4: I/O Wait Time for MongoDB**
```promql
container_fs_io_time_seconds_total{pod=~"mongodb.*"}
```

**Query 5: Disk Latency (weighted I/O time)**
```promql
node_disk_io_time_weighted_ms{device="sda1"}
```
*Higher values = longer I/O operations*

**Query 6: Database Query Latency Correlation**
```promql
histogram_quantile(0.95, rate(mongodb_query_duration_ms_bucket[5m])) and on(instance) (rate(node_disk_io_time_weighted_ms[1m]) > 1000)
```

### Loki Queries

**Query 1: I/O Errors**
```logql
{job="pod"} | grep -i "I/O error"
```

**Query 2: Disk Full Errors**
```logql
{job="pod"} | grep -i "disk full|no space"
```

**Query 3: Seek Errors**
```logql
{job="pod"} | grep -i "seek|bad sector"
```

**Query 4: MongoDB I/O Warnings**
```logql
{job="mongodb"} | grep -i "slow|io|disk|latency"
```

### Tempo Queries

**Query 1: Database Query Spanning Long Time**
```
Look for: Database operation spans > 5 seconds
Service: mongodb or any service querying DB
Pattern: Consistent P95 increase during anomaly window
```

---

## ANOMALY-004: DATABASE CONNECTION POOL EXHAUSTION

### Prometheus Queries

**Query 1: Active Connections Relative to Limit**
```promql
(mongodb_connections_current / mongodb_connections_available) * 100
```
*Alert if > 80%*

**Query 2: Connection Pool Utilization Over Time**
```promql
mongodb_connections_current
```
*Alert if constantly at max*

**Query 3: Connection Checkout Time (95th percentile)**
```promql
histogram_quantile(0.95, db_connection_checkout_time_seconds_bucket)
```
*Alert if > 5 seconds*

**Query 4: Failed Connection Attempts**
```promql
rate(mongodb_connection_failures_total[1m])
```
*Alert if > 0*

**Query 5: Connection Wait Queue Size**
```promql
mongodb_connection_queue_size
```
*Alert if non-zero*

**Query 6: Database Error Rate (connection-related)**
```promql
rate(mongodb_errors_total{type="connection"}[1m])
```

**Query 7: API Request Latency During Pool Exhaustion**
```promql
histogram_quantile(0.99, http_request_duration_seconds_bucket) and on(service) (mongodb_connections_current / mongodb_connections_available > 0.9)
```

### Loki Queries

**Query 1: Connection Pool Exhausted**
```logql
{job="mongodb|api"} | grep -i "connection.*pool.*exhausted|getConnection"
```

**Query 2: Too Many Connections**
```logql
{job="mongodb"} | grep -i "too many connections"
```

**Query 3: Connection Timeout**
```logql
{job="api"} | grep -i "ConnectionException|connection.*timeout"
```

**Query 4: Connection Refused**
```logql
{job="api"} | grep -i "connection.*refused"
```

**Query 5: Queue Timeout**
```logql
{job="api"} | grep -i "queue.*timeout|wait.*timeout"
```

### Tempo Queries

**Query 1: Database Operation Spans Showing Queue Wait**
```
Look for: Spans with very long duration
Service: API service
Look for children: Database operation span duration >> normal
Message pattern: "Waiting for connection from pool"
```

**Query 2: Cascading Latency in Traces**
```
Pattern: API service slow → triggers timeout → downstream 5xx
Trace shows: API request → waiting for connection → timeout → error response
```

---

## ANOMALY-005: CASCADING FAILURES

### Prometheus Queries

**Query 1: 5xx Error Rate by Service**
```promql
rate(http_requests_total{status=~"5.."}[1m]) by (service)
```
*Alert if > 0.05 (5%)*

**Query 2: Error Rate Spike Correlation**
```promql
(rate(http_requests_total{status=~"5..", service="catalogue"}[1m]) > 0) 
and 
(rate(http_requests_total{status=~"5..", service="user"}[1m]) > 0)
```
*Multiple services failing simultaneously*

**Query 3: Request Latency P99**
```promql
histogram_quantile(0.99, http_request_duration_seconds_bucket) by (service)
```
*Alert if > 10 seconds (cascading delay)*

**Query 4: Downstream Service Latency Increase**
```promql
(histogram_quantile(0.95, http_request_duration_seconds_bucket{service="front-end"}) / histogram_quantile(0.95, http_request_duration_seconds_bucket{service="front-end"}) offset 1h) > 5
```
*5x latency increase = cascading effect*

**Query 5: Successful Request Rate Drop**
```promql
rate(http_requests_total{status="200"}[1m]) by (service)
```
*Look for coordinated drop across services*

### Loki Queries

**Query 1: Upstream Service Unavailable**
```logql
{job="api"} | grep -i "upstream.*unavailable|service.*down"
```

**Query 2: Circuit Breaker Triggered**
```logql
{job="api"} | grep -i "circuit.*breaker|open|tripped"
```

**Query 3: Dependency Failure Messages**
```logql
{job="api"} | grep -i "dependency.*failed|cannot reach"
```

**Query 4: Cascading Error Chain**
```logql
{job="api"} | grep "service.*error" | grep "triggered by"
```

### Tempo Queries

**Query 1: Trace Error Count by Time**
```
Aggregate traces by 1-minute interval
Count traces with tag: error=true
Look for: Sudden spike in error count
```

**Query 2: Error Propagation in Single Trace**
```
Find trace with multiple errors
Trace tree view: Error at one service → propagates to children
All downstream spans show same error time
```

**Query 3: Root Cause Service Identification**
```
Filter: error=true AND service.name="*"
Look for: Service with earliest error timestamp
Other services' errors occur 100ms later = cascading
```

---

## ANOMALY-006: PARTIAL DEGRADATION

### Prometheus Queries

**Query 1: Latency Increase for Specific Endpoint**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket{endpoint="/catalogue"}) / histogram_quantile(0.95, http_request_duration_seconds_bucket{endpoint="/catalogue"} offset 30m)
```
*Alert if > 3x*

**Query 2: Success Rate Maintained**
```promql
rate(http_requests_total{status="200", service="catalogue"}[1m]) / rate(http_requests_total{service="catalogue"}[1m]) * 100
```
*Should remain > 95% even during degradation*

**Query 3: Latency by Endpoint**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket) by (endpoint)
```
*One endpoint much higher than others*

**Query 4: Throughput Still Present**
```promql
rate(http_requests_total{service="catalogue"}[1m])
```
*Should not drop significantly*

**Query 5: Downstream Latency Response**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket{service="front-end"}) and on(service) (histogram_quantile(0.95, http_request_duration_seconds_bucket{service="catalogue"}) > 1)
```
*Front-end latency increases as catalogue degrades*

### Loki Queries

**Query 1: Slow Request Logs**
```logql
{job="catalogue"} | json | request_duration_ms > 1000
```

**Query 2: Degradation Pattern**
```logql
{job="catalogue"} | json request_duration_ms | stats avg(request_duration_ms) by endpoint
```
*One endpoint with avg >> others*

**Query 3: Resource Usage During Degradation**
```logql
{job="catalogue"} | json | stats avg(cpu_usage), avg(memory_usage) by endpoint
```

### Tempo Queries

**Query 1: Single Slow Span in Trace**
```
Find spans for specific endpoint
Look for: One service 500%+ slower
Trace tree: downstream services waiting on this service
```

**Query 2: Service-Specific Slowness**
```
Filter by service.name="catalogue"
Filter by span.name="listProducts"
Metric: span.duration > 1 second (vs normal 50ms)
```

---

## ANOMALY-007: NETWORK LATENCY SPIKES

### Prometheus Queries

**Query 1: HTTP Request Latency for External Calls**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket{destination="external"})
```
*Alert if > 2 seconds*

**Query 2: Network Transmit/Receive Rate**
```promql
rate(network_transmit_bytes_total{device="eth0"}[5m])
rate(network_receive_bytes_total{device="eth0"}[5m])
```

**Query 3: Network Errors**
```promql
rate(node_network_transmit_errors_total{device="eth0"}[1m])
rate(node_network_receive_errors_total{device="eth0"}[1m])
```
*Alert if > 0*

**Query 4: TCP Retransmissions**
```promql
rate(node_netstat_Tcp_RetransSegs[1m])
```
*Alert if > normal baseline*

**Query 5: Latency Delta (External vs Internal)**
```promql
(histogram_quantile(0.95, http_request_duration_seconds_bucket{destination="external"}) / 
histogram_quantile(0.95, http_request_duration_seconds_bucket{destination="internal"})) > 3
```

### Loki Queries

**Query 1: Connection Timeout**
```logql
{job="api"} | grep -i "connection.*timeout|read.*timeout"
```

**Query 2: Deadline Exceeded**
```logql
{job="api"} | grep -i "deadline.*exceeded"
```

**Query 3: Slow Network Diagnosis**
```logql
{job="api"} | json latency_ms | latency_ms > 1000
```

### Tempo Queries

**Query 1: External Service Call Spans**
```
Filter: span.tags["rpc.service", "http.url"]
Range: spans with local calls 50ms vs external calls 500ms+
Pattern: 10x difference during anomaly
```

**Query 2: Network Round Trip Time**
```
Look at: RPC/gRPC spans to external services
Duration > 1 second = network degradation
Correlate with other services' normal RTT
```

---

## ANOMALY-008: PACKET LOSS

### Prometheus Queries

**Query 1: Retransmission Rate**
```promql
rate(node_netstat_Tcp_RetransSegs[1m])
```
*Alert if > 1000 retrans/sec*

**Query 2: Connection Resets**
```promql
rate(node_netstat_Tcp_OutRsts[1m])
```
*Alert if > 0*

**Query 3: Error Rate Correlation with Retransmissions**
```promql
rate(http_requests_total{status=~"5.."}[1m]) and on() (rate(node_netstat_Tcp_RetransSegs[1m]) > 1000)
```

**Query 4: TCP Timeout Count**
```promql
node_netstat_TcpExt_TCPTimeouts
```

### Loki Queries

**Query 1: Connection Reset Messages**
```logql
{job="api"} | grep -i "RST|connection.*reset|broken.*pipe"
```

**Query 2: Dropped Connection**
```logql
{job="api"} | grep -i "dropped|connection.*lost"
```

**Query 3: Retry Attempts**
```logql
{job="api"} | grep -i "retry|attempt.*[0-9]"
```

### Tempo Queries

**Query 1: Retried Operations in Traces**
```
Look for: Multiple child spans with same operation name
Pattern: span A (failed) → span A retry (failed) → span A retry (success)
Parent duration = sum of all retries
```

**Query 2: Failed Span Visible in Trace**
```
Filter: error=true
Correlation: Error timestamp + retry timestamp
Visual: Tree shows branching for retry logic
```

---

## ANOMALY-009: STALE CACHE

### Prometheus Queries

**Query 1: Cache Hit Ratio**
```promql
rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m]))
```
*Alert if < 70%*

**Query 2: Cache Miss Rate**
```promql
rate(cache_misses_total[1m])
```
*Alert if increase > 50% vs baseline*

**Query 3: Cache Eviction Rate**
```promql
rate(cache_evictions_total[1m])
```
*Alert if > normal*

**Query 4: Data Mismatch Events (if tracked)**
```promql
rate(cache_mismatch_errors_total[1m])
```
*Alert if > 0*

### Loki Queries

**Query 1: Cache Mismatch Detection**
```logql
{job="catalogue"} | grep -i "cache.*mismatch|stale.*data"
```

**Query 2: Cache Invalidation Failures**
```logql
{job="catalogue"} | grep -i "failed.*invalidate|invalidation.*error"
```

**Query 3: Data Consistency Warnings**
```logql
{job="catalogue"} | grep -i "consistency|validation.*failed"
```

### Tempo Queries

**Query 1: Cache Lookup Spans**
```
Look for spans tagged: cache_name="catalogue"
Duration: should be < 10ms
Check: timestamps of cache lookup vs actual DB query
```

---

## ANOMALY-010: DATABASE CORRUPTION

### Prometheus Queries

**Query 1: Transaction Rollback Rate**
```promql
rate(db_transaction_rollbacks_total[1m])
```
*Alert if > 0*

**Query 2: Integrity Check Failures**
```promql
rate(db_integrity_checks_failed_total[1m])
```

**Query 3: Write Error Rate**
```promql
rate(db_write_errors_total[1m])
```

**Query 4: Constraint Violation Errors**
```promql
rate(db_constraint_violations_total[1m])
```

### Loki Queries

**Query 1: Data Validation Failures**
```logql
{job="mongodb|api"} | grep -i "validation.*failed"
```

**Query 2: Constraint Violation**
```logql
{job="mongodb"} | grep -i "constraint.*violation|duplicate.*key"
```

**Query 3: Orphaned Records**
```logql
{job="api"} | grep -i "orphan|missing.*reference"
```

**Query 4: Transaction Rollback**
```logql
{job="mongodb|api"} | grep -i "rollback|transaction.*failed"
```

### Tempo Queries

**Query 1: Database Error Spans**
```
Filter: error=true AND span.tags["db.system", "mongodb"]
Look for: Error message containing "validation" or "constraint"
Pattern: Write operation followed by error
```

---

## ANOMALY-011: EXTERNAL API TIMEOUT

### Prometheus Queries

**Query 1: External API Response Time**
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket{destination="payment-gateway"})
```
*Alert if > 30 seconds*

**Query 2: External API Error Rate**
```promql
rate(http_requests_total{destination="payment-gateway", status=~"5.."}[1m])
```
*Alert if intermittent 503s*

**Query 3: Timeout Count**
```promql
rate(external_api_timeouts_total[1m])
```
*Alert if > 0*

**Query 4: Retry Attempt Count**
```promql
rate(external_api_retry_total[1m])
```

**Query 5: Fallback Usage** (if applicable)
```promql
rate(external_api_fallback_used_total[1m])
```
*Non-zero = external service slow/down*

### Loki Queries

**Query 1: External Service Timeout**
```logql
{job="payment"} | grep -i "external.*timeout|gateway.*timeout"
```

**Query 2: Retry Attempts to External API**
```logql
{job="payment"} | grep -i "retry.*payment|attempt.*[0-9]"
```

**Query 3: Fallback Activation**
```logql
{job="payment"} | grep -i "using.*fallback|fallback.*activated"
```

### Tempo Queries

**Query 1: External Service Call Spans**
```
Filter: span.kind="CLIENT" AND (span.tags["http.url"] contains "payment" OR span.tags["rpc.method"] = "ChargePayment")
Watch: All spans > 30 seconds duration
Correlate: Client timeout = 30s + span duration
```

**Query 2: Retry Pattern in Traces**
```
Look for: Multiple child spans with same service name
Timeline: Each retry adds 30s delay
Parent span duration = N retries × 30s + overhead
```

---

## ANOMALY-012: MEMORY LEAK

### Prometheus Queries

**Query 1: Steady Memory Growth (Linear Regression)**
```promql
deriv(container_memory_usage_bytes{pod=~"catalogue.*"}[1h]) > 0
```
*Alert if positive for multiple hours*

**Query 2: Memory as Percentage of Container Limit**
```promql
(1 - (container_memory_working_set_bytes{pod=~"catalogue.*"} / container_spec_memory_limit_bytes{pod=~"catalogue.*"})) * 100
```
*Alert if decreasing over time (less free space)*

**Query 3: GC Frequency Increase (indicator of pressure)**
```promql
rate(jvm_gc_pause_seconds_count[1h])
```
*Should be relatively flat; increasing = leak*

**Query 4: Memory Not Reclaimed After GC**
```promql
jvm_memory_usage_bytes{area="heap"} / jvm_gc_pause_seconds_count 
```
*Ratio increasing = leak*

**Query 5: Process Uptime vs Memory**
```promql
container_memory_usage_bytes{pod=~"catalogue.*"} / (time() - container_start_time_seconds)
```
*Alert if memory/uptime ratio growing*

### Loki Queries

**Query 1: Memory Allocation Warnings**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "unable.*allocate|memory.*pressure"
```

**Query 2: Potential Leak Indicators**
```logql
{job="pod", pod=~"catalogue.*"} | json object_count | stats max(object_count) by time 10m
```
*Look for steady increase*

**Query 3: Resource Exhaustion Notice**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "low.*memory|available.*memory.*low"
```

### Tempo Queries

**Query 1: Trace Duration Over Time**
```
Extract traces over 24-hour period
Compute: avg(span.duration) by 1-hour
Alert: If avg increases 10% per hour = leak
```

**Query 2: GC Pause Duration Trend**
```
Filter span.tags["gc.pause"] = true
Plot: GC duration over 24 hours
Alert: If duration increasing = pressure from leak
```

---

## ANOMALY-013: THREAD LEAK

### Prometheus Queries

**Query 1: Thread Count Trend**
```promql
jvm_threads_live{pod=~"catalogue.*"}
```
*Alert if reaching jvm_threads_max*

**Query 2: Live vs Max Threads**
```promql
(jvm_threads_live{pod=~"catalogue.*"} / jvm_threads_max) * 100
```
*Alert if > 80%*

**Query 3: Peak Thread Count**
```promql
jvm_threads_peak{pod=~"catalogue.*"}
```
*Alert if increasing over time*

**Query 4: Daemon vs Total**
```promql
jvm_threads_live - jvm_threads_daemon
```
*Alert if non-daemon threads accumulating*

**Query 5: Thread Pool Queue Depth** (if available)
```promql
app_executor_queue_size
```
*Alert if growing*

### Loki Queries

**Query 1: Thread Pool Exhaustion**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "thread.*pool.*full|threads.*exhausted"
```

**Query 2: Rejected Execution**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "RejectedExecutionException"
```

**Query 3: Thread Creation Messages**
```logql
{job="pod", pod=~"catalogue.*"} | grep -i "creating.*thread|thread.*created"
```

### Tempo Queries

**Query 1: Blocking Spans (Threads Waiting)**
```
Filter spans with high duration but minimal actual work
Tag: thread_name="thread-pool-*"
Correlate: Increasing count of blocked spans
```

---

## ANOMALY-014: DEADLOCK / LOCK CONTENTION

### Prometheus Queries

**Query 1: Lock Contention Metric**
```promql
rate(app_lock_wait_time_seconds_total[1m])
```
*Alert if > 100ms/sec*

**Query 2: Lock Hold Time**
```promql
histogram_quantile(0.95, app_lock_hold_time_seconds_bucket)
```
*Alert if > 500ms*

**Query 3: Deadlock Count**
```promql
rate(app_deadlocks_total[1m])
```
*Alert if > 0*

**Query 4: Response Latency Under Contention**
```promql
histogram_quantile(0.99, http_request_duration_seconds_bucket) and on(pod) (rate(app_lock_wait_time_seconds_total[1m]) > 0.1)
```

### Loki Queries

**Query 1: Deadlock Detection**
```logql
{job="pod"} | grep -i "deadlock|circular.*wait"
```

**Query 2: Lock Timeout**
```logql
{job="pod"} | grep -i "lock.*timeout|waited.*for.*lock"
```

**Query 3: Contention Messages**
```logql
{job="pod"} | grep -i "contention|lock.*held|waiting.*lock"
```

**Query 4: Thread Dump Requests (Manual debugging)**
```logql
{job="pod"} | grep -i "thread.*dump|full.*thread.*trace"
```

### Tempo Queries

**Query 1: Asymmetric Latency Pattern**
```
Compare multiple traces for same operation:
- Some complete in 50ms
- Others take 5+ seconds
Pattern: Lock holders slow = contention
```

**Query 2: Serialization in Traces**
```
Look for spans that should be parallel:
- Service A and B normally concurrent
- Under contention: B waits for A
Timeline view: Clear stall window
```

---

## Quick Reference: Common Anomaly Signatures

| Anomaly | Prometheus Signature | Loki Signature | Tempo Signature |
|---------|---|---|---|
| Memory Pressure | Memory% > 85%, GC freq high | OutOfMemoryError | Broken traces at restart |
| CPU Saturation | CPU > 90%, throttling > 0 | "timeout", "rejected" | 3x span duration on service |
| Disk I/O | I/O weighted time growing | "I/O error", "seek" | DB queries 5s+ |
| Pool Exhaustion | Connections@max, checkout>5s | "pool exhausted" | DB spans queued |
| Cascading Failure | 5xx on multiple services | "upstream unavailable" | Error propagation in tree |
| Partial Degradation | P95 3x spike, success >95% | "slow" for endpoint | Single service slow |
| Network Latency | External P95 > 2s | "timeout" | External spans 500%+ slower |
| Packet Loss | Retrans > 1000/sec | "connection reset" | Retry spans in trace |
| Stale Cache | Hit% < 70%, miss spike | "cache mismatch" | Cache lookup expired |
| DB Corruption | Rollback > 0, constraint fail | "validation failed" | DB error in trace |
| External Timeout | External P95 > 30s | "gateway timeout" | 30s+ client span |
| Memory Leak | Memory grows linear, +10%/hr | Allocation warnings | GC duration trending up |
| Thread Leak | Threads → max, peak↑ | "RejectedExecutionException" | Growing blocked spans |
| Deadlock | Lock wait > 100ms/sec | "deadlock" | Asymmetric latency |

---

## How to Use These Queries

### For Prometheus
1. Open Prometheus UI: `http://prometheus:9090`
2. Go to "Graph" tab
3. Paste query from above
4. Set time range to anomaly window
5. Look for anomaly pattern

### For Loki
1. Open Grafana: `http://grafana:3000`
2. Explore → Logs
3. Select Loki data source
4. Paste LogQL query
5. Adjust label filters for specific service

### For Tempo
1. Open Grafana: `http://grafana:3000`
2. Explore → Traces (select Tempo)
3. Use Service Name filter
4. Look for traces during anomaly time
5. Click on trace to see span details

---

## Adding Custom Alerts

Add to `prometheus.yml` alert rules:
```yaml
- alert: MemoryPressure
  expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.85
  for: 5m
  labels:
    severity: warning
    anomaly: "001"
```

This enables automated alerting during anomaly tests.
