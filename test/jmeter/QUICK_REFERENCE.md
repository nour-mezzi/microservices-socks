# Load Test Execution - Quick Reference Guide

## ✅ TASK COMPLETED SUCCESSFULLY

Load test has been **executed** and **data generated** for RCA analysis.

---

## 📊 RESULTS AT A GLANCE

```
Execution Time:      ~443 seconds (7m 22s)
Total Requests:      1,446
Successful:          782 (54%)
Failed:              664 (46%)
Average Response:    16ms
Peak Throughput:     3.9 req/sec
Users Simulated:     50 concurrent
```

---

## 📁 FILES GENERATED

### Main Data File (for RCA)
```
/home/user/microservices-demo/test/jmeter/results/load-test-rca-20260304_004357.csv
Size: 351 KB | Rows: 1,447
```
✅ Ready to import into: Grafana, Kibana, Splunk, Excel, SQL database

### Reports
```
/home/user/microservices-demo/test/jmeter/results/LOAD_TEST_FINAL_REPORT.txt
/home/user/microservices-demo/test/jmeter/results/README_LOAD_TEST_RESULTS.md (detailed)
```

### Logs
```
/home/user/microservices-demo/test/jmeter/results/load-test-rca-20260304_004357.log
Size: 3.2 MB | Contains detailed execution logs
```

### Reusable Test Templates
```
/home/user/microservices-demo/test/jmeter/sock-shop-load-test-rca.jmx
/home/user/microservices-demo/test/jmeter/run-load-test.sh
/home/user/microservices-demo/test/jmeter/analyze-results.py
```

---

## 🎯 DATA CAPTURED

| Endpoint | Requests | Success % | Details |
|----------|----------|-----------|---------|
| Homepage | 200 | 100% | ✅ Working perfectly |
| Catalogue Browse | 200 | 100% | ✅ Working perfectly |
| Product Details | 200 | 0% | ⚠️ URI errors |
| User Registration | 194 | 0.5% | ❌ Service issues |
| User Login | 171 | 0% | ❌ Auth service down |
| Add to Cart | 276 | 100% | ✅ Working perfectly |
| View Cart | 105 | 100% | ✅ Working perfectly |
| Checkout Order | 100 | 0% | ❌ Order service down |

**Total successful transactions for analysis: 782**

---

## 🚀 QUICK START - USE THE DATA

### Option 1: View as CSV
```bash
head -50 /home/user/microservices-demo/test/jmeter/results/load-test-rca-20260304_004357.csv
```

### Option 2: Quick Analytics
```bash
# Count by response code
awk -F',' 'NR>1 {print $9}' load-test-rca-20260304_004357.csv | sort | uniq -c

# Find slow requests
awk -F',' '$2 > 100 {print $1, $3, $2}' load-test-rca-20260304_004357.csv

# Success rate by endpoint
awk -F',' 'NR>1 {if($9=="true") s[$3]++; t[$3]++} END {for(e in t) print e, s[e]/t[e]*100}' load-test-rca-20260304_004357.csv
```

### Option 3: Import to Grafana
1. Go to Data Sources → Add new
2. Select CSV plugin
3. Upload: `/home/user/microservices-demo/test/jmeter/results/load-test-rca-20260304_004357.csv`
4. Create dashboards and queries

---

## 🔍 KEY FINDINGS

### ✅ Working Services
- Browse and search functionality
- Shopping cart operations
- Response times acceptable (7-40ms)

### ⚠️ Issues to Investigate
1. **User Registration** - Service returning errors
2. **Authentication** - Login endpoint completely down
3. **Product Details** - URI syntax exceptions
4. **Order Processing** - Checkout service unavailable

### Response Code Distribution
```
HTTP 200 (OK):           506 (35%)  - Successful requests
HTTP 201 (Created):      276 (19%)  - Creation success
HTTP 500 (Server Error): 292 (20%)  - Backend failures
HTTP 404 (Not Found):    171 (12%)  - Missing resources
Other errors:            201 (14%)  - URI syntax, etc.
```

---

## 🔄 RE-RUN TESTS

### Standard re-run (same as before)
```bash
cd /home/user/microservices-demo/test/jmeter
JMETER_HOME=/home/user/apache-jmeter-5.6.3 ./run-load-test.sh
```

### Custom parameters
```bash
# Increase load
NUM_THREADS=100 LOOPS=10 ./run-load-test.sh

# Quick sanity check
NUM_THREADS=10 LOOPS=1 RAMP_TIME=30 ./run-load-test.sh

# Extended soak test
NUM_THREADS=50 LOOPS=20 ./run-load-test.sh
```

---

## 📋 CSV COLUMNS EXPLAINED

```
Column 1:  timeStamp          - Epoch milliseconds when request started
Column 2:  elapsed            - Response time in milliseconds
Column 3:  label              - Request name/endpoint
Column 4:  responseCode       - HTTP status code
Column 5:  responseMessage    - Status message
Column 6:  threadName         - Thread/user identifier
Column 7:  dataType           - Response content type
Column 8:  success            - Success flag (true/false)
Column 9:  failureMessage     - Error details if failed
... more columns with detailed metrics
```

---

## 💡 RCA ANALYSIS IDEAS

### 1. Timeline Analysis
```sql
SELECT timestamp, COUNT(*) as requests, 
       SUM(CASE WHEN success='true' THEN 1 ELSE 0 END) as successful
FROM results
GROUP BY FLOOR(timestamp/60000)  -- Group by minute
```

### 2. Slow Requests
```sql
SELECT label, timestamp, elapsed FROM results
WHERE elapsed > 48  -- Above P95
ORDER BY elapsed DESC
```

### 3. Error Patterns
```sql
SELECT label, responseCode, COUNT(*) as count
FROM results
WHERE success = 'false'
GROUP BY label, responseCode
```

### 4. Service Correlation
```sql
-- Which endpoints fail together?
SELECT a.label, b.label, COUNT(*) as co_failures
FROM results a, results b
WHERE a.success='false' AND b.success='false'
  AND a.timestamp = b.timestamp
GROUP BY a.label, b.label
```

---

## 📝 NEXT STEPS

- [ ] Review the CSV data
- [ ] Check application logs during test window
- [ ] Verify service health
- [ ] Identify root cause of failures
- [ ] Fix issues
- [ ] Re-run test to validate
- [ ] Establish baseline metrics
- [ ] Create SLA thresholds

---

## 📞 DETAILED DOCUMENTATION

For complete analysis, setup, and interpretation guide:
```
cat /home/user/microservices-demo/test/jmeter/results/README_LOAD_TEST_RESULTS.md
```

For quick metrics summary:
```
cat /home/user/microservices-demo/test/jmeter/results/LOAD_TEST_FINAL_REPORT.txt
```

---

**Status**: ✅ Complete | **Date**: 2026-03-04 | **Phase**: Ready for RCA
