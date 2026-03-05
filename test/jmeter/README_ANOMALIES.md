# Sock Shop Load Test - Anomalies & Issues for AI Root Cause Analysis

## 📋 Summary

This package introduces **6 intentional anomalies and issues** to the Sock Shop microservices load test for AI-based root cause analysis training and validation. Each issue represents a real-world production problem that an AIOps system should be able to detect and diagnose.

---

## 📁 Files Created

### 1. **anomaly_injector.py** - Main Anomaly Injector Script
Python script that generates synthetic test results with injected anomalies.

```bash
python3 /home/user/microservices-demo/test/jmeter/anomaly_injector.py
```

**Output:**
- `anomalies_log.csv` - Metadata about each introduced issue
- `test_results.csv` - Simulated test results showing failures from anomalies

**Options:**
```bash
--anomalies-log FILE      # Custom output file for anomalies (default: anomalies_log.csv)
--results-log FILE        # Custom output file for test results (default: test_results.csv)
--duration SECONDS        # Test duration in seconds (default: 300)
```

### 2. **anomalies_log.csv** - Issue Metadata
CSV file containing structured data about all 6 introduced anomalies.

**Columns:**
- `issue_id` - Unique issue identifier (1-6)
- `name` - Issue name/title
- `description` - What the issue is
- `affected_endpoint` - Which endpoints are impacted
- `severity` - Impact level (LOW, MEDIUM, HIGH, CRITICAL)
- `root_cause` - Hidden root cause explanation
- `symptom` - Observable symptoms
- `introduced_at` - When anomaly was introduced

### 3. **test_results.csv** - Simulated Test Results
Sample test execution results showing failures caused by anomalies.

**Columns:**
- `timestamp` - When the test ran
- `endpoint` - Which API endpoint was tested
- `response_time_ms` - Response latency in milliseconds
- `status_code` - HTTP status code (or 000 for timeout)
- `success` - Whether test passed
- `anomaly_id` - Which issue caused the failure
- `error_message` - Error details
- `thread_name` - JMeter thread name
- `attempt` - Retry attempt number

### 4. **ANOMALIES.md** - Detailed Documentation
Comprehensive documentation of all 6 anomalies with:
- Root causes (hidden from AI)
- Observable symptoms (visible to AI)
- Metric signatures
- AI analysis tasks
- Detection guidance

### 5. **sock-shop-basic-loadtest.jmx** - Modified JMeter Test
The original load test has been **modified to include all 6 anomalies**:
- ✅ ISSUE #1: Homepage performance degradation
- ✅ ISSUE #2: Aggressive timeout configuration
- ✅ ISSUE #3: Data validation mismatch
- ✅ ISSUE #4: Cascading service failures
- ✅ ISSUE #5: Service unavailability
- ✅ ISSUE #6: Memory spike and high load

---

## 🔴 The 6 Introduced Issues

### ISSUE #1: Homepage Performance Degradation
- **Severity:** HIGH
- **Endpoint:** `/`
- **Change:** Duration assertion increased from 500ms to 5000ms
- **Symptom:** Homepage responses: 3500ms (vs normal 150ms)
- **Root Cause:** Database connection pool exhaustion, memory paging

### ISSUE #2: Aggressive Timeout Configuration
- **Severity:** HIGH
- **Endpoints:** `/catalogue`, `/tags`, `/catalogue/size`
- **Change:** HTTP timeouts reduced from 10000ms to 2000ms
- **Symptom:** Connection timeout errors (Status 000)
- **Root Cause:** Timeout misconfiguration (2000ms vs actual response time 1500-2500ms)

### ISSUE #3: Data Validation Mismatch
- **Severity:** MEDIUM
- **Endpoint:** `/catalogue`
- **Change:** JSONPath assertion changed from `$[0]` to `$[999]`
- **Symptom:** Assertion failures on 200 OK responses
- **Root Cause:** Test expects non-existent array index or API schema changed

### ISSUE #4: Cascading Service Failures
- **Severity:** CRITICAL
- **Endpoint:** `/catalogue/{id}`
- **Changes:** 
  - Added 8-second delay before request
  - Response code expectation changed to 500
  - Duration assertion increased to 8500ms
- **Symptom:** 500 errors after 7500-8500ms delay
- **Root Cause:** Upstream service/database timeout

### ISSUE #5: Service Unavailability
- **Severity:** HIGH
- **Endpoint:** `/tags`
- **Change:** Response code assertion changed from 200 to 503
- **Symptom:** 503 Service Unavailable responses
- **Root Cause:** Tags service database connection pool exhausted

### ISSUE #6: Memory Spike and High Load
- **Severity:** CRITICAL
- **Endpoints:** All endpoints
- **Change:** Concurrent users increased from 10 to 50
- **Symptom:** Latency increases across all endpoints, timeouts appear
- **Root Cause:** Load increased 5x causing memory pressure, GC pauses

---

## 🚀 Usage Examples

### Run Anomaly Injector
```bash
cd /home/user/microservices-demo/test/jmeter/

# Generate default anomalies log and test results
python3 anomaly_injector.py

# Generate with custom output files
python3 anomaly_injector.py \
  --anomalies-log my_anomalies.csv \
  --results-log my_results.csv \
  --duration 600
```

### View Generated Files
```bash
# View anomalies summary
cat anomalies_log.csv | column -t -s,

# View test results
cat test_results.csv | column -t -s, | head -20

# View detailed documentation
cat ANOMALIES.md
```

### Run Modified JMeter Test
```bash
# Run the test with anomalies
jmeter -n -t sock-shop-basic-loadtest.jmx -l results.jtl

# With custom parameters
jmeter -n -t sock-shop-basic-loadtest.jmx \
  -Jusers=50 \
  -Jduration=300 \
  -Jrampup=30 \
  -l results.jtl
```

---

## 📊 AI Analysis Workflow

### Step 1: Collect Metrics
- Pull response times, error rates, latencies from test results
- Collect system metrics (memory, CPU, GC pauses)
- Gather service health status

### Step 2: Detect Anomalies
```
Look for:
- Response time spikes (ISSUE #1, #6)
- Timeout patterns (ISSUE #2)
- Assertion failures with 200 status (ISSUE #3)
- Correlated failures (ISSUE #4)
- Service unavailability (ISSUE #5)
```

### Step 3: Root Cause Analysis
- For each anomaly, analyze metrics to identify root cause
- Correlate with configuration/deployment changes
- Identify affected dependencies

### Step 4: Generate Insights
- Classify as capacity issue, configuration issue, or dependency issue
- Suggest remediation actions
- Predict impact on users

---

## 📈 Metrics to Monitor

### Response Time Metrics
```
- http_requests_duration_seconds (with endpoint labels)
- p50, p95, p99 latency percentiles
- max response time
```

### Error Metrics
```
- http_requests_total (by status code)
- Error rate by endpoint
- Timeout count and percentage
```

### Resource Metrics
```
- jvm_memory_usage_percent
- gc_pause_duration_ms
- threads_active_count
- db_connection_pool_active
- cpu_usage_percent
```

### Service Metrics
```
- service_availability_status
- circuit_breaker_state
- dependency_latency
```

---

## 🔍 Expected AI Findings

| Issue | Expected Detection | Expected Root Cause |
|-------|-------------------|-------------------|
| #1 | High latency on / | DB connection pool saturated |
| #2 | Timeout errors on specific endpoints | Configuration: timeout too low |
| #3 | Assertion failures with 200 OK | JSONPath assertion incorrect |
| #4 | 500 errors with 8-9s latency | Upstream service timeout |
| #5 | 503 errors on /tags | Tags service down/unavailable |
| #6 | Latency spike after load increase | Memory pressure from 50 threads |

---

## 📝 Quick Reference

### Files at a Glance
```
/home/user/microservices-demo/test/jmeter/
├── anomaly_injector.py          # Main script
├── anomalies_log.csv            # Issue metadata
├── test_results.csv             # Simulated test results
├── ANOMALIES.md                 # Detailed documentation
└── sock-shop-basic-loadtest.jmx # Modified JMeter test
```

### Key Changes in JMeter Test
- Line ~26: USERS changed from 10 to 50
- Line ~58: Timeouts reduced from 10000 to 2000ms
- Line ~150: Homepage duration assertion 500→5000ms
- Line ~200: Catalogue JSONPath $[0]→$[999]
- Line ~243: Added 8s delay before product details
- Line ~250: Product response assertion 200→500
- Line ~310: Tags response assertion 200→503

---

## 🎯 Next Steps for AI Implementation

1. **Parse anomalies_log.csv** to understand ground truth
2. **Ingest test_results.csv** as training data
3. **Read ANOMALIES.md** for detailed symptom descriptions
4. **Correlate failures** with specific issues using anomaly_id
5. **Build detection rules** based on symptom patterns
6. **Train ML models** to classify root causes
7. **Validate against** expected findings in documentation

---

**Created:** 2026-03-02  
**Version:** 1.0  
**Purpose:** AI Root Cause Analysis Training Dataset
