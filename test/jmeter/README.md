# JMeter Test Scripts for Sock Shop

This directory contains JMeter test scripts for performance testing the Sock Shop microservices application.

## Available Test Scripts

### 1. sock-shop-realistic-user-journey.jmx
**Description**: Comprehensive end-to-end user journey simulation  
**Complexity**: Advanced  
**Purpose**: Realistic load testing with complete user flows

**Test Flow**:
1. Visit Homepage
2. Browse Product Catalogue
3. View Product Details
4. Register User (dynamic username)
5. Login
6. Add Items to Cart (2 items)
7. View Cart
8. Checkout / Place Order

**Default Configuration**:
- Users: 50 concurrent users
- Ramp-up: 60 seconds
- Iterations: 5 loops per user
- Duration: ~30 minutes
- Think Times: 1-10 seconds (realistic delays)

**Features**:
- Dynamic user creation (unique per thread)
- Cookie-based session management
- Response validation with assertions
- Dynamic value extraction (user ID, order ID)
- Realistic think times with random variation

### 2. sock-shop-basic-loadtest.jmx
**Description**: Simple load test for quick validation  
**Complexity**: Basic  
**Purpose**: Smoke testing and quick health checks

**Test Flow**:
1. Homepage
2. Catalogue List
3. Catalogue Count
4. Product Details
5. Get Tags

**Default Configuration**:
- Users: 10 concurrent users (configurable via CLI)
- Ramp-up: 10 seconds (configurable)
- Duration: 5 minutes (300s, configurable)
- Think Times: 1-4 seconds

**Features**:
- CLI parameter override support
- Duration assertions (performance SLA checks)
- JSON validation
- Lightweight and fast

---

## Quick Start

### Prerequisites

1. **Install JMeter**:
   ```bash
   # Linux
   wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz
   tar -xzf apache-jmeter-5.6.3.tgz
   sudo mv apache-jmeter-5.6.3 /opt/jmeter
   sudo ln -s /opt/jmeter/bin/jmeter /usr/local/bin/jmeter
   
   # macOS
   brew install jmeter
   
   # Verify
   jmeter -v
   ```

2. **Start Sock Shop Application**:
   ```bash
   cd /home/user/microservices-demo/deploy/docker-compose
   docker-compose -f docker-compose.yml up -d
   docker-compose -f docker-compose.monitoring.yml up -d
   
   # Verify app is running
   curl http://localhost/
   ```

---

## Running Tests

### Option 1: GUI Mode (Development/Debugging)

**Use for**: Test script development, debugging, viewing detailed results

```bash
# Navigate to test directory
cd /home/user/microservices-demo/test/jmeter

# Start JMeter GUI
jmeter

# In JMeter:
# File → Open → Select a .jmx file
# Click green "Start" button (or Ctrl+R)
# View results in listeners
```

**Note**: GUI mode consumes significant resources. Use only for development, not for actual load testing.

### Option 2: CLI Mode (Recommended for Load Testing)

**Use for**: Actual load testing, CI/CD, production-like testing

#### Basic Load Test (Quick)

```bash
cd /home/user/microservices-demo/test/jmeter

# Run with default settings (10 users, 5 minutes)
jmeter -n -t sock-shop-basic-loadtest.jmx \
       -l results/basic-loadtest-$(date +%Y%m%d-%H%M%S).jtl \
       -e -o results/basic-loadtest-report

# View HTML report
firefox results/basic-loadtest-report/index.html
```

#### Basic Load Test (Custom Parameters)

```bash
# Override parameters via command line
jmeter -n -t sock-shop-basic-loadtest.jmx \
       -Jusers=20 \
       -Jrampup=20 \
       -Jduration=600 \
       -l results/basic-custom-$(date +%Y%m%d-%H%M%S).jtl \
       -e -o results/basic-custom-report
```

#### Realistic User Journey Test

```bash
cd /home/user/microservices-demo/test/jmeter

# Run with default settings (50 users, 5 iterations)
jmeter -n -t sock-shop-realistic-user-journey.jmx \
       -l results/realistic-journey-$(date +%Y%m%d-%H%M%S).jtl \
       -e -o results/realistic-journey-report

# View results
firefox results/realistic-journey-report/index.html
```

---

## Understanding CLI Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-n` | Non-GUI mode (headless) | `-n` |
| `-t` | Test plan file path | `-t sock-shop-basic-loadtest.jmx` |
| `-l` | Results log file (JTL format) | `-l results/test.jtl` |
| `-e` | Generate HTML dashboard report | `-e` |
| `-o` | Output folder for HTML report | `-o results/report` |
| `-J<property>` | Override JMeter property | `-Jusers=50` |
| `-G<property>` | Define global property | `-Gport=8080` |

### Parameterized Variables (Basic Load Test)

| Variable | Default | Description | CLI Override |
|----------|---------|-------------|--------------|
| `users` | 10 | Number of concurrent users | `-Jusers=50` |
| `rampup` | 10 | Ramp-up period (seconds) | `-Jrampup=60` |
| `duration` | 300 | Test duration (seconds) | `-Jduration=1800` |

**Example**:
```bash
jmeter -n -t sock-shop-basic-loadtest.jmx \
       -Jusers=100 -Jrampup=120 -Jduration=3600 \
       -l results/stress-test.jtl
```

---

## Test Scenarios

### 1. Smoke Test (Quick Validation)
**Purpose**: Verify application is working after deployment  
**Script**: `sock-shop-basic-loadtest.jmx`

```bash
jmeter -n -t sock-shop-basic-loadtest.jmx \
       -Jusers=5 -Jduration=120 \
       -l results/smoke-test.jtl
```

### 2. Load Test (Normal Load)
**Purpose**: Test under expected production load  
**Script**: `sock-shop-realistic-user-journey.jmx`

```bash
jmeter -n -t sock-shop-realistic-user-journey.jmx \
       -l results/load-test.jtl \
       -e -o results/load-test-report
```

### 3. Stress Test (Find Limits)
**Purpose**: Identify system breaking point  
**Script**: `sock-shop-realistic-user-journey.jmx` (modified thread count)

```bash
# Edit .jmx file to increase users from 50 to 200+
# Or run multiple instances
jmeter -n -t sock-shop-realistic-user-journey.jmx \
       -l results/stress-test.jtl \
       -e -o results/stress-test-report
```

### 4. Endurance Test (Soak Test)
**Purpose**: Test stability over extended period  
**Script**: `sock-shop-realistic-user-journey.jmx`

```bash
# Modify duration to 24 hours (86400 seconds)
# Or use scheduler in thread group
jmeter -n -t sock-shop-realistic-user-journey.jmx \
       -l results/soak-test.jtl \
       -e -o results/soak-test-report
```

---

## Monitoring During Tests

### Grafana Dashboards

While JMeter tests are running, monitor the application in real-time:

```bash
# Open Grafana
firefox http://localhost:3000

# Login: admin / foobar
# Navigate to: Dashboards → Sock Shop Performance
```

**Key Metrics to Watch**:
- Request rate per service
- Error rate
- Response times (P50, P95, P99)
- CPU and memory usage
- Database query performance

### Prometheus Queries

```bash
# Open Prometheus
firefox http://localhost:9090

# Example queries:
# Request rate: rate(http_requests_total[5m])
# Error rate: rate(http_requests_total{status=~"5.."}[5m])
# P95 latency: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Tempo Traces

```bash
# View distributed traces during test
# Grafana → Explore → Tempo → Search
# Filter by service_name or duration
```

---

## Analyzing Results

### JMeter HTML Dashboard

The HTML report (generated with `-e -o` flags) provides:

1. **APDEX Score**: Application performance index (0.0 - 1.0)
2. **Statistics**: Requests, errors, response times, throughput
3. **Charts**: 
   - Response Times Over Time
   - Active Threads Over Time
   - Response Time Percentiles
   - Throughput Over Time

### Key Metrics to Review

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Error Rate | < 0.1% | 0.1-1% | > 1% |
| P95 Response Time | < 500ms | 500-1000ms | > 1000ms |
| Throughput | Stable | Decreasing | Dropping |
| APDEX Score | > 0.9 | 0.7-0.9 | < 0.7 |

### JTL Results File

The `.jtl` file contains raw test results. You can:

1. **Re-generate HTML report**:
   ```bash
   jmeter -g results/test.jtl -o results/new-report
   ```

2. **Import into Grafana/InfluxDB** for long-term trending

3. **Analyze with custom scripts** (CSV format)

---

## Troubleshooting

### Issue: Connection Refused

**Symptom**: All requests fail immediately

**Solution**:
```bash
# Verify application is running
docker ps | grep front-end

# Test manually
curl http://localhost/

# Check Docker logs
docker-compose logs front-end
```

### Issue: High Error Rate

**Symptom**: Many HTTP 500 errors

**Solutions**:
1. Reduce user count or ramp-up slower
2. Check application logs for exceptions
3. Monitor resource usage (CPU, memory)
4. Verify database connections

```bash
# Check application logs
docker-compose logs orders carts payment

# Check resource usage
docker stats
```

### Issue: Slow Performance

**Symptom**: Response times much higher than expected

**Solutions**:
1. Check if system resources are exhausted
2. Verify database performance
3. Look for bottlenecks in Grafana
4. Check network latency

```bash
# Monitor system resources
htop

# Check Docker resource usage
docker stats

# Grafana query for slowest services
topk(5, avg(http_request_duration_seconds) by (service))
```

### Issue: JMeter Out of Memory

**Symptom**: `java.lang.OutOfMemoryError`

**Solution**:
```bash
# Increase JMeter heap size
export JVM_ARGS="-Xms1g -Xmx4g"
jmeter -n -t test.jmx ...

# Or edit jmeter startup script
# Edit /opt/jmeter/bin/jmeter
# HEAP="-Xms1g -Xmx4g"
```

---

## Best Practices

### 1. Test Design
- ✅ Start with smoke test (5 users)
- ✅ Gradually increase load
- ✅ Use realistic think times
- ✅ Test one change at a time
- ✅ Run tests multiple times for consistency

### 2. Test Execution
- ✅ Use CLI mode for actual load testing
- ✅ Monitor application during tests
- ✅ Isolate test environment from production
- ✅ Run long tests during off-hours
- ✅ Save all test results with timestamps

### 3. Results Analysis
- ✅ Compare with baseline results
- ✅ Focus on percentiles (P95, P99) not just averages
- ✅ Correlate JMeter results with monitoring data
- ✅ Document findings and recommendations
- ✅ Share results with team

### 4. Continuous Testing
- ✅ Integrate into CI/CD pipeline
- ✅ Run smoke tests on every deployment
- ✅ Schedule weekly load tests
- ✅ Track performance trends over time
- ✅ Set up alerts for performance regression

---

## CI/CD Integration Example

### Jenkins Pipeline

```groovy
stage('Performance Test') {
    steps {
        sh '''
            cd test/jmeter
            jmeter -n -t sock-shop-basic-loadtest.jmx \
                   -Jusers=5 -Jduration=120 \
                   -l results/smoke-test-${BUILD_NUMBER}.jtl \
                   -e -o results/smoke-test-report-${BUILD_NUMBER}
        '''
        perfReport sourceDataFiles: 'test/jmeter/results/*.jtl'
        publishHTML(target: [
            reportDir: 'test/jmeter/results/smoke-test-report-${BUILD_NUMBER}',
            reportFiles: 'index.html',
            reportName: 'JMeter Report'
        ])
    }
}
```

---

## Additional Resources

### Documentation
- [JMeter User Manual](https://jmeter.apache.org/usermanual/index.html)
- [JMeter Best Practices](https://jmeter.apache.org/usermanual/best-practices.html)
- [Local Environment Setup Guide](../../docs/LOCAL-ENVIRONMENT-SETUP-GUIDE.md)
- [E2E User Journey Test Results](../../docs/E2E-USER-JOURNEY-TEST.md)
- [Complete JMeter Testing Guide](../../docs/JMETER-TESTING-GUIDE.md)

### Support
- Check [Troubleshooting section](#troubleshooting) above
- Review application logs: `docker-compose logs <service>`
- Monitor via Grafana: http://localhost:3000
- Analyze traces via Tempo in Grafana Explore

---

## Script Modification Tips

### Change Target Host/Port

Edit in JMeter GUI or modify variables in the .jmx file:

```xml
<elementProp name="HOST" elementType="Argument">
  <stringProp name="Argument.value">your-host.com</stringProp>
</elementProp>
<elementProp name="PORT" elementType="Argument">
  <stringProp name="Argument.value">8080</stringProp>
</elementProp>
```

### Add Custom Assertions

In JMeter GUI:
1. Right-click on HTTP Request → Add → Assertions
2. Choose assertion type (Response, JSON, Duration, etc.)
3. Configure criteria
4. Save test plan

### Extract Dynamic Values

Use Post-Processors:
1. Regular Expression Extractor (for HTML/text)
2. JSON Extractor (for JSON responses)
3. XPath Extractor (for XML)
4. CSS/JQuery Extractor (for HTML)

---

## Version History

- **v1.0** (2026-02-22): Initial test scripts
  - Realistic User Journey script
  - Basic Load Test script
  - Documentation and examples

---

## Contact

For questions or issues with these test scripts, refer to the main project documentation or check the application logs for debugging.
