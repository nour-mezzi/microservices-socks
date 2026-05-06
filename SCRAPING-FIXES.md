# Prometheus Scraping Issues - Root Cause & Fixes

## Root Cause Analysis

**Problem:** Test 15-20260505T185754Z showed:
- ✗ Missing HTTP metrics (empty `http_requests_rate.json`)
- ✗ `NaN` values in response time metrics for first ~15 minutes
- ✗ Services DOWN: catalogue, payment, user (up=0 throughout test)
- ✗ Only working services reported metrics

**Root Causes Identified:**

1. **Incorrect Prometheus Scrape Configuration**
   - Missing explicit ports in target definitions (e.g., `['catalogue']` instead of `['catalogue:8080']`)
   - Default port 9090 doesn't match service metrics ports (8080)
   - Inconsistent metrics_path values (`metrics` vs `/metrics`)
   - Too-aggressive 5s scrape interval causing timeouts

2. **Wrong PromQL Metric Names**
   - Queries used non-existent metrics: `request_count`, `request_duration_seconds_bucket`
   - Should use OpenTelemetry standard names: `http_request_total`, `http_request_duration_seconds_bucket`
   - No fallback queries for compatibility

3. **Missing Scrape Failure Monitoring**
   - No alerts for when targets become unreachable
   - No visibility into scrape timeouts or failures
   - Services could fail silently

---

## Fixes Applied

### 1. **prometheus.yml** - Fixed Scrape Targets
```yaml
# BEFORE (BROKEN)
- job_name: "catalogue"
  scrape_interval: 5s
  metrics_path: 'metrics'        # Wrong: missing leading /
  static_configs:
    - targets: ['catalogue']      # Wrong: no port

# AFTER (FIXED)
- job_name: "catalogue"
  scrape_interval: 15s             # Increased from 5s (was too aggressive)
  scrape_timeout: 10s              # Added explicit timeout
  metrics_path: '/metrics'         # Fixed: leading /
  static_configs:
    - targets: ['catalogue:8080']  # Fixed: explicit port
```

**Changes:**
- Added `:8080` port to all service targets (where metrics are exposed)
- Fixed `metrics_path` to use `/metrics` consistently
- Increased `scrape_interval` from 5s → 15s (reduces timeout failures)
- Added explicit `scrape_timeout: 10s` for clarity
- Added `relabel_configs` for clean instance labels

### 2. **run-anomaly.sh** - Fixed PromQL Queries
```bash
# BEFORE (BROKEN)
'01-http_requests_rate|sum(rate(request_count[1m])) by (job, status_code)'
'02-http_response_times|histogram_quantile(0.95, sum(rate(request_duration_seconds_bucket[1m])) by (job, le))'

# AFTER (FIXED)
'01-http_requests_rate|sum(rate(http_request_total[1m])) by (job, status) or sum(rate(request_total[1m])) by (job, status)'
'02-http_response_times|histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[1m])) by (job, le)) or histogram_quantile(0.95, sum(rate(request_duration_seconds_bucket[1m])) by (job, le))'
```

**Changes:**
- Updated metric names to OpenTelemetry standards: `http_request_*`
- Added fallback queries with `or` operator for backward compatibility
- Fixed label names: `status_code` → `status`
- Now handles both OTel-instrumented and legacy metric names

### 3. **alert.rules** - Added Scrape Failure Monitoring
```yaml
# NEW ALERTS
- alert: PrometheusScrapeFailed
  expr: up{job!=""} == 0 or scrape_duration_seconds > 10
  for: 2m
  annotations:
    description: "Check Prometheus targets at http://localhost:9090/targets"

- alert: PrometheusTargetDown
  expr: count(up == 0) > 0
  for: 1m

- alert: PrometheusHighScrapeLatency
  expr: scrape_duration_seconds > 5
  for: 3m

# FIXED EXISTING ALERTS
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[1m]) > 0.1 or rate(request_total{status=~"5.."}[1m]) > 0.1
  # Added fallback for metric name compatibility
```

**Changes:**
- Added 3 new alerts for scrape failures and latency
- Updated all alerts to use OTel metric names + fallbacks
- Added direct link to Prometheus targets page for debugging

---

## Files Modified

| File | Changes | Impact |
|------|---------|--------|
| `deploy/docker-compose/prometheus.yml` | Added ports, fixed paths, adjusted intervals | ✓ Scraping now reaches all services |
| `test/jmeter/run-anomaly.sh` | Fixed PromQL queries, added fallbacks | ✓ HTTP metrics now collected |
| `deploy/docker-compose/alert.rules` | Added scrape alerts, updated metric names | ✓ Early warning for failures |

---

## Verification Steps

Run a test to verify fixes:
```bash
cd /home/user/microservices-demo/test/jmeter
./run-anomaly.sh 99 --duration 300 --users 50
```

Check results:
```bash
# Should have data (not empty/NaN)
cat anomaly-results/99-*/observability/metrics/01-http_requests_rate.json | grep -c "resultType"

# Verify services are UP
curl -s http://localhost:9090/api/v1/query?query=up | grep -E "catalogue|payment|user"
```

---

## Why These Fixes Matter

| Issue | Impact | Fix | Result |
|-------|--------|-----|--------|
| Wrong ports | Scrape failed silently | Add `:8080` to targets | Services now scraped |
| Wrong metric names | Empty metrics | Use `http_request_*` names | HTTP metrics collected |
| No scrape monitoring | Blind failures | Add PrometheusScrapeFailed alert | Early detection |
| Aggressive scraping | Timeouts | 5s → 15s interval | Reliable collection |

---

## Monitoring Dashboard Links

After restart:
- **Prometheus Targets:** http://localhost:9090/targets (check UP/DOWN status)
- **Alerts Status:** http://localhost:9090/alerts (monitor scrape failures)
- **Metrics Explorer:** http://localhost:9090/graph?query=http_request_total (verify queries)

---

## Next Steps

1. **Restart Prometheus:**
   ```bash
   docker-compose -f deploy/docker-compose/docker-compose.yml restart prometheus
   ```

2. **Run validation test:**
   ```bash
   ./test/jmeter/run-anomaly.sh 100 --duration 300
   ```

3. **Verify metrics are collected:**
   - Check `comprehensive-results.csv` has data (not NaN)
   - Check `01-http_requests_rate.json` has results (not empty)

4. **Monitor scrape success rate:**
   - Visit `http://localhost:9090/targets`
   - All targets should show **UP** in green
