#!/bin/bash

set -euo pipefail

SCRIPT_DIR="/home/user/microservices-demo/test/jmeter"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
COMPREHENSIVE_CSV="${RESULTS_DIR}/TEST-RESULTS-comprehensive.csv"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEST_START=$(date +%s)

mkdir -p "$RESULTS_DIR"

echo "[INFO] Starting anomaly test..."
echo "[INFO] Timestamp: $TIMESTAMP"

# Run ANOMALY-001
cd "$SCRIPT_DIR"
ANOMALY_ID="ANOMALY-001"
DURATION=600
USERS=100
RAMPUP=60

# Call run-anomaly script directly (not with bash prefix)
./run-anomaly.sh "$ANOMALY_ID" --duration "$DURATION" --users "$USERS" --rampup "$RAMPUP" 2>&1

TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))

echo "[INFO] Test completed in ${TEST_DURATION}s"
echo "[INFO] Processing data..."

# Create comprehensive CSV
cat > "$COMPREHENSIVE_CSV" << 'CSV_HEADER'
timestamp,data_type,service,metric_name,metric_value,unit,log_level,log_message,notes
CSV_HEADER

# Process JMeter results
JMETER_CSV="${RESULTS_DIR}/${ANOMALY_ID}-results.csv"
if [ -f "$JMETER_CSV" ]; then
  echo "[INFO] Found JMeter results: $JMETER_CSV"
  # Count and add a summary
  JMETER_LINES=$(wc -l < "$JMETER_CSV")
  echo "$TIMESTAMP,jmeter,api,test_results,$JMETER_LINES,count,info,JMeter test completed with $JMETER_LINES results entries" >> "$COMPREHENSIVE_CSV"
else
  echo "[WARNING] No JMeter results found"
fi

# Extract logs
LOGS_DIR="${RESULTS_DIR}/${ANOMALY_ID}-logs"
if [ -d "$LOGS_DIR" ]; then
  echo "[INFO] Found logs directory: $LOGS_DIR"
  for logfile in "$LOGS_DIR"/*.log; do
    if [ -f "$logfile" ]; then
      service=$(basename "$logfile" .log)
      error_count=$(grep -ic "error\|exception" "$logfile" 2>/dev/null || echo "0")
      warning_count=$(grep -ic "warning\|timeout" "$logfile" 2>/dev/null || echo "0")
      
      echo "$TIMESTAMP,logs,$service,error_count,$error_count,count,info,Found $error_count error messages" >> "$COMPREHENSIVE_CSV"
      echo "$TIMESTAMP,logs,$service,warning_count,$warning_count,count,warning,Found $warning_count warning messages" >> "$COMPREHENSIVE_CSV"
    fi
  done
else
  echo "[WARNING] No logs directory found"
fi

# Add test summary
cat >> "$COMPREHENSIVE_CSV" << TEST_SUMMARY
$TIMESTAMP,summary,system,anomaly_id,$ANOMALY_ID,string,info,Test anomaly ID
$TIMESTAMP,summary,system,duration,$TEST_DURATION,seconds,info,Total test duration
$TIMESTAMP,summary,system,users,$USERS,count,info,JMeter concurrent users
$TIMESTAMP,summary,system,rampup,$RAMPUP,seconds,info,Ramp-up time
TEST_SUMMARY

echo ""
echo "================================================================================"
echo "[✓] TEST COMPLETE"
echo "================================================================================"
echo ""
echo "Comprehensive Results: $COMPREHENSIVE_CSV"
echo "Total rows: $(wc -l < "$COMPREHENSIVE_CSV")"
echo ""
echo "Files in results directory:"
ls -lh "$RESULTS_DIR"/ 2>/dev/null | tail -8
echo ""
echo "CSV Preview:"
head -10 "$COMPREHENSIVE_CSV"

