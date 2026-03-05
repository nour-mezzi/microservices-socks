# Sock Shop Load Test - Introduced Anomalies and Issues

## Overview
This document describes all intentionally introduced anomalies and issues to the Sock Shop microservices load test. These anomalies are designed to serve as training data for AI-based root cause analysis systems.

---

## 🔴 ISSUE #1: Homepage Performance Degradation

**Severity:** HIGH  
**Affected Endpoint:** `/`  
**Introduced:** Performance Duration Assertion increased from 500ms to 5000ms  

### Description
The homepage is experiencing severe performance degradation. Response times have increased from a normal ~100-150ms to 2000-5000ms, with increased failure rate (15% 504 Gateway Timeout errors).

### Observable Symptoms
- Homepage response times exceed 2000ms consistently
- 504 Gateway Timeout errors appearing sporadically
- Visual inspection shows `DurationAssertion (5000ms)` in test configuration
- Error logs show slow database queries

### Root Cause (Hidden from AI)
- Database connection pool exhaustion
- High memory paging causing GC pauses
- Insufficient connection pooling configuration

### Metric Signatures
- `response_latency{endpoint="/"}` ≈ 3500ms (vs. normal 150ms)
- `http_requests_duration_seconds_bucket{le="0.5"}` significant drop
- `jvm_memory_usage_percent` > 85%
- `db_connection_pool_active_connections` ≈ 100% 

### How to Detect
```
- Check response times for / endpoint
- Look for GC pause events in metrics
- Inspect database connection pool saturation
- Review thread dump for blocked connections
```

---

## 🔴 ISSUE #2: Aggressive Timeout Configuration

**Severity:** HIGH  
**Affected Endpoints:** `/catalogue`, `/tags`, `/catalogue/size`  
**Introduced:** HTTP Timeouts reduced from 10000ms to 2000ms  

### Description
HTTP request timeouts have been configured too aggressively (2 seconds) relative to actual response times. This causes legitimate requests to fail with connection timeouts.

### Observable Symptoms
- Connection timeout errors for catalogue and tags endpoints
- Response time shows exactly 2000ms then fails
- Status code: 000 (connection refused/timeout)
- Error message: "Connection timeout"
- High failure rate (~100% for affected endpoints)

### Root Cause (Hidden from AI)
- HTTP timeout configuration changed:
  - `HTTPSampler.connect_timeout`: 10000ms → 2000ms
  - `HTTPSampler.response_timeout`: 10000ms → 2000ms
- Legitimate requests take 1500-2500ms but timeout at 2000ms
- Service is functioning correctly but test expectations are wrong

### Metric Signatures
- Timeout errors correlate exactly with `/catalogue` and `/tags` endpoints
- Response times near 2000ms then timeout
- No corresponding 5xx errors in backend (requests never reach backend)
- Test assertion failure rate: ~95%

### How to Detect
```
- Filter for status_code=000 (connection timeout)
- Look for response_time_ms = 2000 exactly
- Check HTTPSampler timeout configuration in JMeter
- Verify actual response times are < 2000ms
- Check if error is client-side (timeout) vs server-side (5xx)
```

---

## 🔴 ISSUE #3: Data Validation Mismatch

**Severity:** MEDIUM  
**Affected Endpoint:** `/catalogue`  
**Introduced:** JSONPath assertion expecting non-existent array index ($[999])  

### Description
The catalogue list endpoint is returning valid data, but the test's JSONPath assertion is incorrect. The test expects to find the 1000th array element ($[999]) but the API typically returns only 10-50 products.

### Observable Symptoms
- JSONPath assertion failures despite 200 OK response
- Error: "JSONPath: $[999] not found - expected at least 1000 items"
- Response latency is normal (150-300ms)
- Status code is 200 (success from server perspective)
- Test fails due to data validation, not connectivity

### Root Cause (Hidden from AI)
- Test configuration error: incorrect JSONPath assertion
- Either:
  - Test was written for different API version
  - Expected value changed from $[0] to $[999]
  - Test expectations are misaligned with actual API design
- OR actual API changed structure/response format

### Metric Signatures
- HTTP 200 status code (not an error to the server)
- Assertion failure in test results
- Short response times (test fails after response, not during)
- No backend errors/5xx responses

### How to Detect
```
- Check JSONPath assertion expectations
- Compare expected vs actual response structure
- Verify API response contains expected fields
- Review test modification history (git blame)
- Check if API contract changed
- Look for mismatch in array depth expectations
```

---

## 🔴 ISSUE #4: Cascading Service Failures

**Severity:** CRITICAL  
**Affected Endpoint:** `/catalogue/{id}`  
**Introduced:** Long delay (8+ seconds) before product details endpoint, response code mismatch to 500  

### Description
The product details endpoint is failing with 500 errors after an 8-second delay. This suggests an upstream service dependency (e.g., database, recommendation service) is unreachable or extremely slow, triggering timeouts and cascading failures.

### Observable Symptoms
- Response times: 7500-8500ms (near the 10s timeout)
- HTTP 500 errors (Internal Server Error)
- Error message: "Service Unavailable - upstream dependency failed"
- Clear cascade pattern: one endpoint failure affecting others
- Affects `/catalogue/{id}` specifically

### Root Cause (Hidden from AI)
- Upstream microservice timeout (before 10s global timeout)
- Database connectivity issue in product details service
- Circuit breaker pattern triggered due to repeated failures
- Possible causes:
  - Database replica lag
  - Network partition to dependency
  - Dependency service OutOfMemory or crashed
  - DNS resolution failing

### Metric Signatures
- Response time exactly at timeout threshold (~8-9 seconds)
- 500 errors with "upstream" in error message
- Correlated failure in dependent service metrics
- Increased error_budget usage
- Circuit breaker state: OPEN

### How to Detect
```
- Identify the 8-second delay pattern
- Check response times near timeout threshold
- Look for 500 errors (not 504 Gateway Timeout)
- Inspect upstream service health/logs
- Check circuit breaker state
- Look for upstream service latency spike
- Verify database connectivity from product service
```

---

## 🔴 ISSUE #5: Service Unavailability

**Severity:** HIGH  
**Affected Endpoint:** `/tags`  
**Introduced:** Response assertion changed to expect 503 instead of 200  

### Description
The tags endpoint is returning HTTP 503 (Service Unavailable), indicating the service or its critical dependencies are offline or overwhelmed. This causes all tag-related operations to fail.

### Observable Symptoms
- Consistent 503 Service Unavailable responses
- Response times vary (100-600ms) - retries with backoff
- No successful requests to `/tags`
- Error message: "Service Unavailable"
- Affects all users trying to access tags

### Root Cause (Hidden from AI)
- Tags microservice database connection pool exhausted
- OR tags service is down/not responding
- OR load balancer considers service unhealthy
- Possible causes:
  - Database outage
  - Memory leak in tags service
  - Too many idle connections
  - Service restart in progress
  - Deployment issue left service broken

### Metric Signatures
- HTTP 503 responses for /tags endpoint
- Response rate: 0 successful requests (100% 503)
- Latency: varies (service attempting to respond)
- Error rate: 100% for this endpoint
- Status page should show tags service down

### How to Detect
```
- Filter for status_code=503
- Check /tags endpoint health status
- Verify tags service is running (pod status, process)
- Check database connectivity from tags service
- Look for connection pool saturation
- Inspect recent deployments/changes
- Check resource limits (memory, CPU)
```

---

## 🔴 ISSUE #6: Memory Spike and High Load

**Severity:** CRITICAL  
**Affected Endpoints:** All endpoints  
**Introduced:** Concurrent users increased from 10 (default) to 50  

### Description
The test load has been significantly increased from 10 concurrent users to 50 concurrent users. This causes memory pressure, GC pauses, and general performance degradation across all endpoints.

### Observable Symptoms
- Response times increased across ALL endpoints (500-2000ms instead of 100-300ms)
- Some requests fail with timeout (response_time > 1500ms)
- Memory usage spike visible in metrics
- GC pause events increase dramatically
- Latency tail percentiles (p95, p99) spike
- Thread count increases from 10 to 50

### Root Cause (Hidden from AI)
- Test configuration changed: `USERS=${__P(users,50)}` (was 10)
- Increased concurrent load triggers:
  - Higher memory allocation for request handling
  - More frequent garbage collection
  - More thread contention
  - Connection pool pressure
  - Database query queuing

### Metric Signatures
- `jmeter_threads_active` increases from 10 to 50
- `jvm_memory_usage_percent` spike to 80-90%
- `gc_pause_duration_ms` increases
- `http_requests_latency_p95` and `p99` spike
- Response times correlated with thread count increase
- Memory heap allocation increases

### How to Detect
```
- Compare current thread count (50) to baseline (10)
- Check memory usage trends
- Look for GC pause correlation with latency spikes
- Inspect JMeter thread group configuration
- Monitor thread creation timestamps
- Compare baseline vs load-test metrics
- Check if resource limits are being hit (CPU, Memory)
```

---

## Summary Table

| Issue # | Name | Severity | Type | Detection Method |
|---------|------|----------|------|------------------|
| 1 | Homepage Performance Degradation | HIGH | Latency | Response time > 2000ms on / |
| 2 | Aggressive Timeout Configuration | HIGH | Timeout | Status 000, response_time = 2000ms |
| 3 | Data Validation Mismatch | MEDIUM | Assertion | JSONPath lookup failure with 200 OK |
| 4 | Cascading Service Failures | CRITICAL | Dependency | 500 error, response_time 7500-8500ms |
| 5 | Service Unavailability | HIGH | Service | HTTP 503 on /tags |
| 6 | Memory Spike and High Load | CRITICAL | Resource | Thread count 10→50, latency spike |

---

## AI Root Cause Analysis Tasks

### Task 1.1: Diagnose Homepage Degradation
Analyze response times for the `/` endpoint and determine why they've increased from ~150ms to 3500ms.

**Metrics to Analyze:**
- `http_requests_duration_seconds{endpoint="/"}`
- `jvm_memory_usage_bytes`
- `db_connection_pool_active_connections`
- `gc_pause_duration_ms`

**Expected Output:**
- Root cause: Database connection pool exhaustion + memory paging
- Recommendation: Increase connection pool size, optimize queries

---

### Task 2.1: Identify Configuration Issues
Detect anomalies in test configuration that don't match backend behavior.

**Metrics to Analyze:**
- Error type distribution
- Response times at timeout boundary
- Status code patterns

**Expected Output:**
- Root cause: HTTPSampler timeout reduced to 2000ms (vs actual response < 1500ms)
- Recommendation: Increase timeout to 10000ms or fix root latency issue

---

### Task 3.1: Validate API Contracts
Check for mismatches between test expectations and actual API responses.

**Metrics to Analyze:**
- JSONPath assertion failures
- Response size/structure
- Data validation errors

**Expected Output:**
- Root cause: Test expects $[999] index but API returns 10-50 items
- Recommendation: Fix test assertion to match API response schema

---

### Task 4.1: Trace Cascading Failures
Identify the upstream dependency causing 500 errors with 8+ second latency.

**Metrics to Analyze:**
- Correlation between service latencies
- Response times near timeout threshold
- Error traces and call stacks

**Expected Output:**
- Root cause: Product service database timeout after 8 seconds
- Recommendation: Increase database timeout, add query optimization, check replication lag

---

### Task 5.1: Detect Service Outages
Identify which service is unavailable and when the issue started.

**Metrics to Analyze:**
- Service health status
- HTTP 503 response patterns
- Service availability timeline

**Expected Output:**
- Root cause: Tags service database connection pool exhausted
- Recommendation: Restart service, scale database, analyze connection leak

---

### Task 6.1: Analyze Load Impact
Determine how increased concurrent load affects system performance.

**Metrics to Analyze:**
- Thread count timeline
- Memory usage correlation with thread count
- GC pause frequency and duration
- Latency percentiles (p50, p95, p99)

**Expected Output:**
- Root cause: Load increased from 10 to 50 concurrent users
- Recommendation: Either reduce load or scale infrastructure (add replicas, increase memory)

---

## Files Generated

1. **anomaly_injector.py** - Python script to generate synthetic test data with injected anomalies
2. **anomalies_log.csv** - Log of all 6 identified anomalies
3. **test_results.csv** - Sample test results showing failures from each anomaly
4. **ANOMALIES.md** - This documentation file

## Running the Anomaly Injector

```bash
# Generate anomalies and test results
python3 /home/user/microservices-demo/test/jmeter/anomaly_injector.py

# Custom output files
python3 /home/user/microservices-demo/test/jmeter/anomaly_injector.py \
  --anomalies-log my_anomalies.csv \
  --results-log my_results.csv \
  --duration 600

# View the generated CSVs
cat anomalies_log.csv
cat test_results.csv
```

## Usage in AI Analysis

These anomalies can be used to:
1. **Train ML models** to detect anomalies from metrics
2. **Test root cause analysis systems** with known failures
3. **Validate AIOps tooling** against realistic scenarios
4. **Generate synthetic data** for development/testing
5. **Create incidents** in staging environments to practice debugging

---

**Last Updated:** 2026-03-02  
**Version:** 1.0
