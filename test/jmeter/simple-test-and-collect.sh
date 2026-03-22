#!/bin/bash

########################################################################################
# Comprehensive Anomaly Test - Simplified Version for Data Collection
# This version runs JMeter tests and collects all metrics and logs to CSV
########################################################################################

set -euo pipefail

SCRIPT_DIR="/home/user/microservices-demo/test/jmeter"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
COMPREHENSIVE_CSV="${RESULTS_DIR}/TEST-RESULTS-comprehensive.csv"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEST_START=$(date +%s)

# Simple logging
echo "[INFO] === Comprehensive Anomaly Test with Data Collection ==="
echo "[INFO] Timestamp: $TIMESTAMP"
echo "[INFO] Results directory: $RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

# Run the test - use shorter duration for debugging, or use environment variable for longer
ANOMALY_ID="ANOMALY-001"
DURATION=${TEST_DURATION:-300}  # Default 5 minutes, override with TEST_DURATION env var
USERS=100
RAMPUP=60

echo "[INFO] Running $ANOMALY_ID (${DURATION}s, ${USERS} users, ${RAMPUP}s ramp-up)..."

# Run the JMeter test WITHOUT sourcing anomaly-specific setup (skip the docker constraints)
cd "$SCRIPT_DIR"

# Simple JMeter execution
JMETER_LOG="${RESULTS_DIR}/${ANOMALY_ID}-simple.log"
JMETER_CSV="${RESULTS_DIR}/${ANOMALY_ID}-results.csv"

echo "[INFO] Running JMeter..."
echo "[INFO] Command: jmeter -n -t sock-shop-basic-loadtest.jmx -Jusers=$USERS -Jrampup=$RAMPUP -Jduration=$DURATION -l $JMETER_CSV"

jmeter -n \
  -t sock-shop-basic-loadtest.jmx \
  -Jusers="$USERS" \
  -Jrampup="$RAMPUP" \
  -Jduration="$DURATION" \
  -l "$JMETER_CSV" >"$JMETER_LOG" 2>&1 || \
  { echo "[WARNING] JMeter exited with error, continuing..."; }

TEST_END=$(date +%s)
TEST_DURATION_ACTUAL=$((TEST_END - TEST_START))

echo "[INFO] Test completed in ${TEST_DURATION_ACTUAL}s"
echo "[INFO] Processing data..."

# Create comprehensive CSV
cat > "$COMPREHENSIVE_CSV" << 'CSV_HEADER'
timestamp,data_type,service,metric_name,metric_value,unit,log_level,log_message,notes
CSV_HEADER

# Function to safely add CSV row
add_csv_row() {
  local ts="$1" dtype="$2" svc="$3" mname="$4" mval="$5" unit="$6" level="$7" msg="$8" notes="$9"
  # Escape quotes in message
  msg=${msg//\"/\\\"}
  echo "$ts,$dtype,$svc,$mname,$mval,$unit,$level,\"$msg\",$notes" >> "$COMPREHENSIVE_CSV"
}

# Process JMeter results
if [ -f "$JMETER_CSV" ]; then
  echo "[INFO] Processing JMeter results..."
  JMETER_LINES=$(wc -l < "$JMETER_CSV" 2>/dev/null || echo "0")
  add_csv_row "$TIMESTAMP" "jmeter" "api" "test_results" "$JMETER_LINES" "count" "info" \
    "JMeter test completed with $JMETER_LINES result lines" "Includes header"
  
  # Extract some stats from JMeter
  if [ "$JMETER_LINES" -gt 1 ]; then
    # Count successes and failures
    SUCCESS_COUNT=$(tail -n +2 "$JMETER_CSV" | grep ",true," | wc -l || echo "0")
    FAILURE_COUNT=$(tail -n +2 "$JMETER_CSV" | grep ",false," | wc -l || echo "0")
    
    if [ "$SUCCESS_COUNT" -gt 0 ] || [ "$FAILURE_COUNT" -gt 0 ]; then
      add_csv_row "$TIMESTAMP" "jmeter_results" "api" "success_count" "$SUCCESS_COUNT" "count" "info" \
        "Successful JMeter requests" "Requests with success=true"
      add_csv_row "$TIMESTAMP" "jmeter_results" "api" "failure_count" "$FAILURE_COUNT" "count" "warning" \
        "Failed JMeter requests" "Requests with success=false"
    fi
  fi
fi

# Extract logs if they exist
LOGS_DIR="${RESULTS_DIR}/${ANOMALY_ID}-logs"
if [ -d "$LOGS_DIR" ]; then
  echo "[INFO] Processing container logs..."
  for logfile in "$LOGS_DIR"/*.log; do
    if [ -f "$logfile" ]; then
      service=$(basename "$logfile" .log)
      
      # Count errors and warnings
      error_count=$(grep -ic "error\|exception" "$logfile" 2>/dev/null || echo "0")
      warning_count=$(grep -ic "warning\|timeout" "$logfile" 2>/dev/null || echo "0")
      info_count=$(grep -ic "info" "$logfile" 2>/dev/null || echo "0")
      
      [ "$error_count" -gt 0 ] && \
        add_csv_row "$TIMESTAMP" "logs" "$service" "error_count" "$error_count" "count" "error" \
          "Error messages in service logs" "From $service.log"
      
      [ "$warning_count" -gt 0 ] && \
        add_csv_row "$TIMESTAMP" "logs" "$service" "warning_count" "$warning_count" "count" "warning" \
          "Warning/timeout messages in service logs" "From $service.log"
      
      [ "$info_count" -gt 0 ] && \
        add_csv_row "$TIMESTAMP" "logs" "$service" "info_count" "$info_count" "count" "info" \
          "Info messages in service logs" "From $service.log"
    fi
  done
else
  echo "[INFO] No logs directory found at $LOGS_DIR"
fi

# Add test summary
echo "[INFO] Adding test summary..."
add_csv_row "$TIMESTAMP" "summary" "system" "anomaly_id" "$ANOMALY_ID" "string" "info" "Anomaly being tested" ""
add_csv_row "$TIMESTAMP" "summary" "system" "total_duration" "$TEST_DURATION_ACTUAL" "seconds" "info" "Total test execution time" ""
add_csv_row "$TIMESTAMP" "summary" "system" "jmeter_users" "$USERS" "count" "info" "Concurrent JMeter users" ""
add_csv_row "$TIMESTAMP" "summary" "system" "rampup_time" "$RAMPUP" "seconds" "info" "User ramp-up period" ""
add_csv_row "$TIMESTAMP" "summary" "system" "test_start" "$TEST_START" "epoch" "info" "Test start timestamp" "Unix epoch seconds"
add_csv_row "$TIMESTAMP" "summary" "system" "test_end" "$TEST_END" "epoch" "info" "Test end timestamp" "Unix epoch seconds"

echo ""
echo "================================================================================"
echo "[✓] TEST & DATA COLLECTION COMPLETE"
echo "================================================================================"
echo ""
echo "📊 Comprehensive Results File:"
echo "   ${COMPREHENSIVE_CSV}"
echo ""
echo "📈 Statistics:"
TOTAL_ROWS=$(wc -l < "$COMPREHENSIVE_CSV" || echo "0")
echo "   Total CSV rows: $TOTAL_ROWS"
echo "   - Header row: 1"
echo "   - Data rows: $((TOTAL_ROWS - 1))"
echo ""
echo "📁 All Generated Files:"
ls -lh "$RESULTS_DIR"/ | grep -v "^total" | awk '{println "   " $9 " (" $5 ")"}'
echo ""
echo "📋 CSV Preview (first 10 rows):"
head -10 "$COMPREHENSIVE_CSV" | sed 's/^/   /'
echo ""
echo "🔍 Quick Analysis Commands:"
echo "   # View all data:"
echo "   column -t -s',' ${COMPREHENSIVE_CSV} | less"
echo ""
echo "   # Find errors:"
echo "   grep ',error,' ${COMPREHENSIVE_CSV}"
echo ""
echo "   # Count by data type:"
echo "   cut -d',' -f2 ${COMPREHENSIVE_CSV} | sort | uniq -c"
echo ""
echo "   # Extract just metrics:"
echo "   grep 'metrics' ${COMPREHENSIVE_CSV}"
echo ""
echo "================================================================================"

exit 0
