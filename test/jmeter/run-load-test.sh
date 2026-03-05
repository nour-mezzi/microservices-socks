#!/bin/bash

#################################################################################
# Sock Shop Load Test Runner for RCA Data Generation
# Purpose: Execute load test and generate comprehensive performance report
#################################################################################

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_NAME="load-test-rca-$TIMESTAMP"
CSV_RESULTS="$RESULTS_DIR/${TEST_NAME}.csv"
TEST_LOG="$RESULTS_DIR/${TEST_NAME}.log"
REPORT_FILE="$RESULTS_DIR/${TEST_NAME}_REPORT.txt"

# JMeter Configuration
JMETER_HOME="${JMETER_HOME:- /opt/jmeter}"
JMETER_BIN="$JMETER_HOME/bin/jmeter"
JMX_FILE="$SCRIPT_DIR/sock-shop-load-test-rca.jmx"

# Test Parameters (can be overridden via environment variables)
NUM_THREADS="${NUM_THREADS:- 100}"
RAMP_TIME="${RAMP_TIME:- 120}"
LOOPS="${LOOPS:- 10}"
HOST="${HOST:- localhost}"
PORT="${PORT:- 80}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#################################################################################
# Utility Functions
#################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if JMeter is installed
    if [ ! -f "$JMETER_BIN" ]; then
        log_error "JMeter not found at $JMETER_BIN"
        log_info "Install JMeter with: wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz && tar -xzf apache-jmeter-5.6.3.tgz -C /opt"
        exit 1
    fi
    
    # Check if test file exists
    if [ ! -f "$JMX_FILE" ]; then
        log_error "JMX test file not found: $JMX_FILE"
        exit 1
    fi
    
    # Check if application is running
    if ! curl -s http://$HOST:$PORT/ > /dev/null 2>&1; then
        log_warning "Application not responding at http://$HOST:$PORT/"
        log_info "Please ensure Sock Shop is running: cd $PROJECT_ROOT/deploy/docker-compose && docker-compose up -d"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Application is running at http://$HOST:$PORT/"
    fi
    
    log_success "All prerequisites met"
}

create_results_directory() {
    log_info "Creating results directory..."
    mkdir -p "$RESULTS_DIR"
    log_success "Results directory ready: $RESULTS_DIR"
}

run_jmeter_test() {
    log_info "Starting JMeter load test..."
    log_info "Test Configuration:"
    log_info "  - Users: $NUM_THREADS"
    log_info "  - Ramp-up: $RAMP_TIME seconds"
    log_info "  - Loops: $LOOPS iterations per user"
    log_info "  - Host: $HOST"
    log_info "  - Port: $PORT"
    log_info "  - Total expected requests: $((NUM_THREADS * LOOPS * 9))"
    echo ""
    
    # Run JMeter in non-GUI mode
    "$JMETER_BIN" \
        -n \
        -t "$JMX_FILE" \
        -l "$CSV_RESULTS" \
        -j "$TEST_LOG" \
        -Jjmeter.save.samplerData=true \
        -J"HOST=$HOST" \
        -J"PORT=$PORT" \
        -J"NUM_THREADS=$NUM_THREADS" \
        -J"RAMP_TIME=$RAMP_TIME" \
        -J"LOOPS=$LOOPS" \
        -Duser.timezone=UTC
    
    if [ $? -eq 0 ]; then
        log_success "JMeter test completed successfully"
    else
        log_error "JMeter test failed"
        exit 1
    fi
}

generate_report() {
    log_info "Generating comprehensive report..."
    
    local total_samples=$(awk 'NR>1' "$CSV_RESULTS" | wc -l)
    local successful=$(awk 'NR>1 && $8=="true"' "$CSV_RESULTS" | wc -l)
    local failed=$((total_samples - successful))
    local success_rate=$(awk "BEGIN {printf \"%.2f\", ($successful/$total_samples)*100}")
    
    # Calculate timing statistics
    local avg_response_time=$(awk 'NR>1 {sum+=$2; count++} END {if(count>0) printf "%.0f", sum/count}' "$CSV_RESULTS")
    local min_response_time=$(awk 'NR>1 {if(NR==2 || $2<min) min=$2} END {printf "%.0f", min}' "$CSV_RESULTS")
    local max_response_time=$(awk 'NR>1 {if($2>max) max=$2} END {printf "%.0f", max}' "$CSV_RESULTS")
    
    # Calculate throughput
    local start_time=$(awk 'NR>1' "$CSV_RESULTS" | head -1 | awk '{print $1}')
    local end_time=$(awk 'NR>1' "$CSV_RESULTS" | tail -1 | awk '{print $1}')
    local duration_ms=$((end_time - start_time))
    local duration_sec=$(awk "BEGIN {printf \"%.0f\", $duration_ms/1000}")
    local throughput=$(awk "BEGIN {printf \"%.2f\", ($total_samples/$duration_sec)}")
    
    # Get unique endpoints
    local endpoints=$(awk -F',' 'NR>1 {print $3}' "$CSV_RESULTS" | sort | uniq -c | sort -rn)
    
    # Generate report file
    cat > "$REPORT_FILE" << EOF
================================================================================
                SOCK SHOP LOAD TEST REPORT FOR RCA
                    Generated: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================

TEST CONFIGURATION
==================
  Test File:          $JMX_FILE
  Number of Threads:  $NUM_THREADS concurrent users
  Ramp-up Time:       $RAMP_TIME seconds
  Loops per User:     $LOOPS iterations
  Expected Duration:  ~$((RAMP_TIME + (NUM_THREADS * LOOPS * 9 * 3 / NUM_THREADS))) seconds
  Host:               $HOST:$PORT

OVERALL PERFORMANCE METRICS
=============================
  Total Requests:     $total_samples
  Successful:         $successful
  Failed:             $failed
  Success Rate:       $success_rate%
  
  Throughput:         $throughput requests/second
  Total Duration:     $duration_sec seconds
  
RESPONSE TIME STATISTICS (milliseconds)
========================================
  Average:            $avg_response_time ms
  Minimum:            $min_response_time ms
  Maximum:            $max_response_time ms

ENDPOINT BREAKDOWN
===================
$endpoints

TEST RESULTS BY TRANSACTION
=============================
EOF

    # Detailed breakdown by transaction
    awk -F',' 'NR>1 {
        label=$3
        if(label != prev_label) {
            if(prev_label != "") printf "  %-40s: %5d requests (%.2f%% success)\n", prev_label, prev_count, (prev_success/prev_count)*100
            prev_label=label
            prev_count=0
            prev_success=0
        }
        prev_count++
        if($8=="true") prev_success++
    }
    END {
        if(prev_label != "") printf "  %-40s: %5d requests (%.2f%% success)\n", prev_label, prev_count, (prev_success/prev_count)*100
    }' "$CSV_RESULTS" >> "$REPORT_FILE"

    cat >> "$REPORT_FILE" << EOF

KEY FINDINGS FOR RCA ANALYSIS
==============================
✓ Data Generation Status:      Complete
✓ Test Data Volume:            $total_samples transactions
✓ Data Quality:                Success rate $success_rate%
✓ Performance Baseline:        $avg_response_time ms average response time
✓ Load Simulation:             $NUM_THREADS concurrent users
✓ Scalability Test:            ${success_rate}% success under load

ACTION ITEMS
=============
1. Review detailed results in: $CSV_RESULTS
2. Import data for RCA analysis in monitoring/tracing systems
3. Check for error patterns in: $TEST_LOG
4. Monitor application logs during high load periods
5. Consider repeat tests with varying load profiles

OUTPUT FILES
=============
  CSV Results:        $CSV_RESULTS
  Test Log:           $TEST_LOG
  This Report:        $REPORT_FILE

NEXT STEPS FOR RCA
===================
1. Execute queries on generated data
2. Analyze latency patterns
3. Check for bottlenecks in service mesh
4. Review CPU/Memory usage during test
5. Validate data consistency across microservices

================================================================================
                            END OF REPORT
================================================================================
EOF

    log_success "Report generated: $REPORT_FILE"
}

print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   LOAD TEST COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    log_info "Results Summary:"
    head -50 "$REPORT_FILE" | tail -40
    echo ""
    log_info "Full report saved to: $REPORT_FILE"
    log_info "CSV data saved to: $CSV_RESULTS"
    log_info "Test log saved to: $TEST_LOG"
    echo ""
}

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Sock Shop Load Test Runner for RCA Data Generation      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    create_results_directory
    run_jmeter_test
    generate_report
    print_summary
}

# Execute main function
main "$@"
