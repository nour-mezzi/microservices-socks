#!/bin/bash
set -euo pipefail

# 60-Minute Test with Complete Data Collection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
TEST_NAME="60MIN-COMPREHENSIVE-${TIMESTAMP}"
LOG_FILE="${RESULTS_DIR}/${TEST_NAME}-execution.log"

mkdir -p "$RESULTS_DIR"

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║        STARTING 60-MINUTE COMPREHENSIVE TEST WITH TRACING         ║"
echo "║                  Duration: 3600 seconds (60 minutes)              ║"
echo "║                  Start: $(date)                  ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "" | tee "$LOG_FILE"

# Configuration
DURATION=3600          # 60 minutes in seconds
USERS=50
RAMPUP=120             # 2 minute ramp-up
JMETER_SCRIPT="${SCRIPT_DIR}/sock-shop-trace-test.jmx"
RESULTS_CSV="${RESULTS_DIR}/${TEST_NAME}-results.csv"
JMETER_LOG="${RESULTS_DIR}/${TEST_NAME}-jmeter.log"

echo "📊 Test Configuration:" | tee -a "$LOG_FILE"
echo "  • Duration: ${DURATION}s (60 minutes)" | tee -a "$LOG_FILE"
echo "  • Users: ${USERS}" | tee -a "$LOG_FILE"
echo "  • Ramp-up: ${RAMPUP}s" | tee -a "$LOG_FILE"
echo "  • Script: $(basename $JMETER_SCRIPT)" | tee -a "$LOG_FILE"
echo "  • Results: $RESULTS_CSV" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Start time tracker
START_TIME=$(date +%s)

# Function to check service health
check_services() {
    echo "🔍 Verifying services are healthy..." | tee -a "$LOG_FILE"
    local services=("http://localhost:8080" "http://localhost:8081" "http://localhost:8082")
    for svc in "${services[@]}"; do
        if timeout 5 curl -s "$svc/health" > /dev/null 2>&1; then
            echo "  ✓ $svc is UP" | tee -a "$LOG_FILE"
        else
            echo "  ✗ $svc is DOWN" | tee -a "$LOG_FILE"
            return 1
        fi
    done
    return 0
}

# Function to check observability
check_observability() {
    echo "📡 Checking observability stack..." | tee -a "$LOG_FILE"
    
    if timeout 5 curl -s http://localhost:3200/ready | grep -q ready; then
        echo "  ✓ Tempo (Tracing) is ready" | tee -a "$LOG_FILE"
    else
        echo "  ⚠ Tempo may not be ready" | tee -a "$LOG_FILE"
    fi
    
    if timeout 5 curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        echo "  ✓ Prometheus (Metrics) is ready" | tee -a "$LOG_FILE"
    else
        echo "  ⚠ Prometheus may not be ready" | tee -a "$LOG_FILE"
    fi
    
    if timeout 5 curl -s http://localhost:3100/ready | grep -q ready; then
        echo "  ✓ Loki (Logs) is ready" | tee -a "$LOG_FILE"
    else
        echo "  ⚠ Loki may not be ready" | tee -a "$LOG_FILE"
    fi
}

# Verify everything
check_services || { echo "❌ Services not ready!"; exit 1; }
check_observability

echo "" | tee -a "$LOG_FILE"
echo "▶️  Starting JMeter test..." | tee -a "$LOG_FILE"
echo "   This will run for 60 minutes. Progress will be logged." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run JMeter with all collection options
jmeter \
  -n \
  -t "$JMETER_SCRIPT" \
  -l "$RESULTS_CSV" \
  -j "$JMETER_LOG" \
  -Jduration=$DURATION \
  -Jthreads=$USERS \
  -Jrampup=$RAMPUP \
  -Jloopcount=1 \
  -Dhttpclient.timeout=60000 \
  -Dcom.sun.jndi.ldap.connect.pool=false \
  2>&1 | tee -a "$LOG_FILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "" | tee -a "$LOG_FILE"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                       TEST EXECUTION COMPLETE                     ║"
echo "╚════════════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Analyze results
if [ -f "$RESULTS_CSV" ]; then
    TOTAL_LINES=$(($(wc -l < "$RESULTS_CSV") - 1))
    PASSED=$(tail -n +2 "$RESULTS_CSV" | awk -F',' '$8=="true"' | wc -l)
    FAILED=$(tail -n +2 "$RESULTS_CSV" | awk -F',' '$8=="false"' | wc -l)
    PASS_RATE=$((PASSED * 100 / TOTAL_LINES))
    
    echo "📊 TEST RESULTS SUMMARY:" | tee -a "$LOG_FILE"
    echo "  • Total Requests: $TOTAL_LINES" | tee -a "$LOG_FILE"
    echo "  • Passed: $PASSED (${PASS_RATE}%)" | tee -a "$LOG_FILE"
    echo "  • Failed: $FAILED" | tee -a "$LOG_FILE"
    echo "  • Elapsed Time: ${ELAPSED}s" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "📂 Output Files:" | tee -a "$LOG_FILE"
echo "  • CSV Results: $(ls -lh $RESULTS_CSV | awk '{print $5}')" | tee -a "$LOG_FILE"
echo "  • JMeter Log: $(ls -lh $JMETER_LOG | awk '{print $5}')" | tee -a "$LOG_FILE"
echo "  • Execution Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "✅ Test execution logged to: $LOG_FILE" | tee -a "$LOG_FILE"

