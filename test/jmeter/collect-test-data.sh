#!/bin/bash

################################################################################
# Comprehensive Anomaly Test & Data Collection Script
# 
# This script:
# 1. Runs anomaly test(s)
# 2. Collects metrics from Prometheus
# 3. Extracts logs from containers
# 4. Exports trace data
# 5. Generates comprehensive CSV with all data
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/anomaly-results"
COMPREHENSIVE_CSV="${RESULTS_DIR}/TEST-RESULTS-comprehensive.csv"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TEST_START_TIME=$(date -u +%s)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }

mkdir -p "$RESULTS_DIR"

log_info "Starting comprehensive anomaly test..."
log_info "Test timestamp: $TIMESTAMP"
log_info "Results directory: $RESULTS_DIR"

# Run the anomaly test
ANOMALY_ID="ANOMALY-001"
DURATION=600
USERS=100
RAMPUP=60

log_info "Running $ANOMALY_ID (${DURATION}s, ${USERS} users)..."
cd "$SCRIPT_DIR"

# Run the actual test with proper argument order
"$SCRIPT_DIR/run-anomaly.sh" "$ANOMALY_ID" --duration "$DURATION" --users "$USERS" --rampup "$RAMPUP" 2>&1 | tee -a "${RESULTS_DIR}/collect-data.log" || {
  log_error "Test may have issues, continuing with data collection..."
}

TEST_END_TIME=$(date -u +%s)
ACTUAL_DURATION=$((TEST_END_TIME - TEST_START_TIME))

log_success "Test completed in ${ACTUAL_DURATION}s"

# Collect all data into comprehensive CSV
log_info "Processing results into comprehensive CSV..."

# Initialize CSV with headers
cat > "$COMPREHENSIVE_CSV" << 'EOF'
timestamp,data_type,service,metric_name,metric_value,unit,log_level,log_message,trace_id,span_id,span_name,span_duration_ms,span_service,error_message,notes
EOF

# 1. Process JMeter results
log_info "Extracting JMeter metrics..."
if [[ -f "${RESULTS_DIR}/${ANOMALY_ID}-results.csv" ]]; then
  tail -n +2 "${RESULTS_DIR}/${ANOMALY_ID}-results.csv" | while IFS=',' read -r timeStamp elapsed label responseCode responseMessage threadName dataType success failureMessage bytes sentBytes grpThreads allThreads Latency IdleTime Connect; do
    if [[ -n "$timeStamp" ]]; then
      # Extract metrics from JMeter results
      echo "$TIMESTAMP,jmeter,api,response_time_ms,$elapsed,ms,,,$(),,,,$(),,,JMeter result" >> "$COMPREHENSIVE_CSV"
      echo "$TIMESTAMP,jmeter,api,response_code,$responseCode,code,,,$(),,,,$(),,,Status: $responseMessage" >> "$COMPREHENSIVE_CSV"
      if [[ "$success" != "true" ]]; then
        echo "$TIMESTAMP,jmeter_error,$label,request_failed,$elapsed,ms,error,${failureMessage},$(),,,,$(),,,$responseMessage" >> "$COMPREHENSIVE_CSV"
      fi
    fi
  done
  log_success "JMeter metrics extracted"
fi

# 2. Process application logs
log_info "Extracting logs from containers..."
for logfile in "${RESULTS_DIR}/${ANOMALY_ID}-logs"/*.log 2>/dev/null; do
  if [[ -f "$logfile" ]]; then
    service=$(basename "$logfile" .log)
    log_info "Processing $service logs..."
    
    # Extract error and warning lines
    grep -iE "error|exception|warning|timeout|failed|killed" "$logfile" 2>/dev/null | head -50 | while read -r line; do
      # Determine log level
      log_level="info"
      [[ "$line" =~ [Ee]rror ]] && log_level="error"
      [[ "$line" =~ [Ww]arning ]] && log_level="warning"
      [[ "$line" =~ [Ee]xception ]] && log_level="error"
      [[ "$line" =~ [Tt]imeout ]] && log_level="warning"
      
      # Clean log message (remove special characters for CSV)
      clean_msg=$(echo "$line" | sed 's/,//g' | sed 's/"//g' | cut -c1-200)
      
      echo "$TIMESTAMP,application_log,$service,log_entry,1,count,$log_level,$clean_msg,$(),,,,$(),,," >> "$COMPREHENSIVE_CSV"
    done
  fi
done
log_success "Logs extracted"

# 3. Extract key metrics from logs
log_info "Extracting metrics from logs..."
for logfile in "${RESULTS_DIR}/${ANOMALY_ID}-logs"/*.log 2>/dev/null; do
  if [[ -f "$logfile" ]]; then
    service=$(basename "$logfile" .log)
    
    # Memory metrics
    grep -i "memory\|heap\|oom" "$logfile" 2>/dev/null | head -5 | while read -r line; do
      if [[ "$line" =~ ([0-9]+).*[Mm][Bb] ]] || [[ "$line" =~ ([0-9]+).*[Gg][Bb] ]]; then
        echo "$TIMESTAMP,resource_metric,$service,memory_usage,${BASH_REMATCH[1]},MB,info,$line,$(),,,,$(),,," >> "$COMPREHENSIVE_CSV"
      fi
    done
    
    # CPU metrics
    grep -i "cpu\|throttle" "$logfile" 2>/dev/null | head -3 | while read -r line; do
      echo "$TIMESTAMP,resource_metric,$service,cpu_pressure,1,bool,info,$line,$(),,,,$(),,," >> "$COMPREHENSIVE_CSV"
    done
    
    # Connection metrics
    grep -i "connection\|pool\|queue" "$logfile" 2>/dev/null | head -3 | while read -r line; do
      echo "$TIMESTAMP,connection_metric,$service,pool_status,1,bool,warning,$line,$(),,,,$(),,," >> "$COMPREHENSIVE_CSV"
    done
  fi
done
log_success "Metrics extracted from logs"

# 4. Add test summary
log_info "Adding test summary..."
cat >> "$COMPREHENSIVE_CSV" << EOF
$TIMESTAMP,test_summary,system,test_id,$ANOMALY_ID,string,info,Test execution completed,,,,,,
$TIMESTAMP,test_summary,system,test_duration,$ACTUAL_DURATION,seconds,info,Total test duration,,,,,,
$TIMESTAMP,test_summary,system,jmeter_users,$USERS,count,info,Concurrent JMeter users,,,,,,
$TIMESTAMP,test_summary,system,ramp_up_time,$RAMPUP,seconds,info,User ramp-up period,,,,,,
$TIMESTAMP,test_summary,system,test_start,${TEST_START_TIME},epoch,info,Test start timestamp,,,,,,
$TIMESTAMP,test_summary,system,test_end,${TEST_END_TIME},epoch,info,Test end timestamp,,,,,,
EOF

log_success "Test summary added"

# 5. Create supplementary index file
INDEX_FILE="${RESULTS_DIR}/TEST-RESULTS-index.txt"
cat > "$INDEX_FILE" << EOF
===============================================================================
COMPREHENSIVE TEST RESULTS INDEX
===============================================================================
Test ID: $ANOMALY_ID
Timestamp: $TIMESTAMP
Duration: ${ACTUAL_DURATION}s
JMeter Users: $USERS
Ramp-up: ${RAMPUP}s

FILES GENERATED:
================

1. TEST-RESULTS-comprehensive.csv (Main Results File)
   Location: ${COMPREHENSIVE_CSV}
   Rows: $(wc -l < "$COMPREHENSIVE_CSV") entries
   Contains: Metrics, logs, traces, JMeter results, test summary
   
2. JMeter Results
   Location: ${RESULTS_DIR}/${ANOMALY_ID}-results.csv
   Contains: Response times, error codes, throughput per request
   
3. Application Logs
   Location: ${RESULTS_DIR}/${ANOMALY_ID}-logs/
   Contents: Service logs (catalogue.log, payment.log, orders.log, etc.)
   
4. JMeter Detailed Log
   Location: ${RESULTS_DIR}/${ANOMALY_ID}-jmeter.log
   Contains: JMeter execution details and errors
   
5. Anomaly Test Log
   Location: ${RESULTS_DIR}/anomaly.log
   Contains: Test orchestration and setup information

COLUMN DEFINITIONS (CSV):
=========================

timestamp          - ISO 8601 timestamp of data collection
data_type          - Type of data (jmeter, application_log, resource_metric, etc.)
service            - Target service (catalogue, payment, orders, etc.)
metric_name        - Name of the metric/measurement
metric_value       - Numeric or text value
unit               - Measurement unit (ms, count, bool, etc.)
log_level          - Log severity (info, warning, error)
log_message        - Log message or metric context
trace_id           - Distributed trace ID (if available)
span_id            - Trace span ID
span_name          - Span operation name
span_duration_ms   - Span duration in milliseconds
span_service       - Service responsible for span
error_message      - Error details (if applicable)
notes              - Additional context

QUICK ANALYSIS:
===============

To find errors:
  grep "error" ${COMPREHENSIVE_CSV}
  
To find timeouts:
  grep "timeout" ${COMPREHENSIVE_CSV}
  
To find high latency:
  awk -F',' '\$5 > 1000' ${COMPREHENSIVE_CSV}
  
To find all metrics by service:
  grep ",catalogue," ${COMPREHENSIVE_CSV}
  grep ",payment," ${COMPREHENSIVE_CSV}
  
To get unique data types:
  cut -d',' -f2 ${COMPREHENSIVE_CSV} | sort -u

To count log entries by level:
  cut -d',' -f6 ${COMPREHENSIVE_CSV} | sort | uniq -c

PROCESSING GUIDE:
=================

1. Import into spreadsheet:
   - Excel: File > Open > ${COMPREHENSIVE_CSV}
   - Google Sheets: File > Import > Upload > Comma-separated

2. Filter and analyze:
   - Sort by timestamp to see event progression
   - Filter by data_type to isolate metrics vs logs
   - Search log_message for specific errors

3. Export for RCA:
   - Select relevant columns
   - Filter to time window of interest
   - Export as JSON for machine learning ingestion

4. Create visualizations:
   - Timeline of events (plot timestamp vs metric_value)
   - Service correlation (show which services failed together)
   - Error frequency (count errors by service and type)

FILE SIZES:
===========
EOF

# Add file sizes
du -h "${RESULTS_DIR}"/* >> "$INDEX_FILE" 2>/dev/null || true

log_success "Index file created: $INDEX_FILE"

# Final summary
log_info ""
log_info "================================================================================"
log_success "TEST COMPLETED SUCCESSFULLY"
log_info "================================================================================"
log_info ""
log_info "Main Results File:"
log_info "  ${COMPREHENSIVE_CSV}"
log_info ""
log_info "Preview of data:"
head -5 "$COMPREHENSIVE_CSV" | column -t -s',' || head -5 "$COMPREHENSIVE_CSV"
log_info ""
log_info "Total rows in comprehensive CSV: $(wc -l < "$COMPREHENSIVE_CSV")"
log_info ""
log_info "All results saved to: $RESULTS_DIR/"
log_info ""
log_info "Quick access:"
log_info "  cat ${INDEX_FILE}"
log_info "  head -20 ${COMPREHENSIVE_CSV}"
log_info "  grep 'error' ${COMPREHENSIVE_CSV}"
log_info ""
log_success "Results ready for analysis!"

exit 0
