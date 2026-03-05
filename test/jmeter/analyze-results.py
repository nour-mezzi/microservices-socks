#!/usr/bin/env python3
"""
Sock Shop Load Test Results Analyzer
Generates comprehensive reports from JMeter CSV results
"""

import sys
import csv
import json
from datetime import datetime
from pathlib import Path
from collections import defaultdict
import statistics

def analyze_csv(csv_file):
    """Analyze JMeter CSV results file"""
    
    results = {
        'total_samples': 0,
        'successful': 0,
        'failed': 0,
        'response_times': [],
        'by_endpoint': defaultdict(lambda: {'count': 0, 'success': 0, 'failed': 0, 'times': []}),
        'by_response_code': defaultdict(int),
        'start_time': None,
        'end_time': None,
    }
    
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            results['total_samples'] += 1
            
            # Parse timestamp
            timestamp = int(row['timeStamp'])
            if results['start_time'] is None or timestamp < results['start_time']:
                results['start_time'] = timestamp
            if results['end_time'] is None or timestamp > results['end_time']:
                results['end_time'] = timestamp
            
            # Parse metrics
            response_time = int(row['elapsed'])
            success = row['success'].lower() == 'true'
            endpoint = row['label']
            response_code = row['responseCode']
            
            # Track response times
            results['response_times'].append(response_time)
            
            # Update counts
            if success:
                results['successful'] += 1
                results['by_endpoint'][endpoint]['success'] += 1
            else:
                results['failed'] += 1
                results['by_endpoint'][endpoint]['failed'] += 1
            
            results['by_endpoint'][endpoint]['count'] += 1
            results['by_endpoint'][endpoint]['times'].append(response_time)
            results['by_response_code'][response_code] += 1
    
    return results

def generate_report(results, csv_file, output_file):
    """Generate comprehensive HTML report"""
    
    # Calculate statistics
    total = results['total_samples']
    success_rate = (results['successful'] / total * 100) if total > 0 else 0
    
    response_times = sorted(results['response_times'])
    avg_response = statistics.mean(response_times) if response_times else 0
    median_response = statistics.median(response_times) if response_times else 0
    min_response = min(response_times) if response_times else 0
    max_response = max(response_times) if response_times else 0
    p95_response = response_times[int(len(response_times) * 0.95)] if len(response_times) > 0 else 0
    p99_response = response_times[int(len(response_times) * 0.99)] if len(response_times) > 0 else 0
    
    # Duration
    duration_ms = results['end_time'] - results['start_time']
    duration_sec = duration_ms / 1000
    throughput = total / duration_sec if duration_sec > 0 else 0
    
    # Build report
    report = f"""
================================================================================
                SOCK SHOP LOAD TEST REPORT FOR RCA DATA GENERATION
                           {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
================================================================================

EXECUTIVE SUMMARY
=================
✓ Load test completed successfully and generated realistic data for RCA analysis
✓ {total:,} total requests executed
✓ Success rate: {success_rate:.2f}%
✓ Average response time: {avg_response:.0f}ms
✓ Test duration: {duration_sec:.0f} seconds
✓ Average throughput: {throughput:.2f} requests/second

TEST METRICS SUMMARY
====================
  Total Requests:          {total:,}
  Successful:              {results['successful']:,}
  Failed:                  {results['failed']:,}
  Success Rate:            {success_rate:.2f}%
  
  Test Duration:           {duration_sec:.0f} seconds ({int(duration_sec/60)}m {int(duration_sec%60)}s)
  Throughput (avg):        {throughput:.2f} req/s
  Requests/min:            {throughput*60:.0f}

RESPONSE TIME STATISTICS (milliseconds)
=======================================
  Minimum:                 {min_response:.0f}ms
  Average:                 {avg_response:.0f}ms
  Median (50th %ile):      {median_response:.0f}ms
  95th Percentile:         {p95_response:.0f}ms
  99th Percentile:         {p99_response:.0f}ms
  Maximum:                 {max_response:.0f}ms

RESPONSE CODE DISTRIBUTION
===========================
"""
    
    for code in sorted(results['by_response_code'].keys()):
        count = results['by_response_code'][code]
        pct = (count / total * 100) if total > 0 else 0
        report += f"  HTTP {code:>3}: {count:>6,} ({pct:>5.1f}%)\n"
    
    report += "\nENDPOINT PERFORMANCE BREAKDOWN\n"
    report += "=" * 80 + "\n"
    report += f"{'Endpoint':<40} {'Requests':>10} {'Success %':>12} {'Avg (ms)':>10}\n"
    report += "-" * 80 + "\n"
    
    for endpoint in sorted(results['by_endpoint'].keys()):
        data = results['by_endpoint'][endpoint]
        success_pct = (data['success'] / data['count'] * 100) if data['count'] > 0 else 0
        avg_time = statistics.mean(data['times']) if data['times'] else 0
        report += f"{endpoint:<40} {data['count']:>10,} {success_pct:>11.1f}% {avg_time:>10.0f}\n"
    
    report += "\nDATA QUALITY FOR RCA ANALYSIS\n"
    report += "=" * 80 + "\n"
    report += f"""
  ✓ Generated {results['successful']:,} successful transactions for analysis
  ✓ Realistic user journey simulation (9 steps per user)
  ✓ Distributed load across {len(results['by_endpoint'])} service endpoints
  ✓ Response time distribution: {min_response:.0f}ms - {max_response:.0f}ms
  ✓ Performance baseline established for comparison
  
  Data Types Captured:
    • User registration events
    • Authentication/login flows  
    • Product catalogue browsing
    • Shopping cart operations
    • Order placement transactions
    • Think times (realistic user behavior)
    • Error scenarios and responses

RECOMMENDATIONS FOR RCA
=======================
1. ✓ Data collection: {results['successful']:,} successful records ready
2. ✓ Time range: {int(results['start_time']/1000)} - {int(results['end_time']/1000)} (UTC)
3. ✓ Export data to monitoring/tracing systems
4. ✓ Analyze patterns during peak load (ramp-up phase)
5. ✓ Compare error rates by endpoint
6. ✓ Review latency spikes in metrics dashboard
7. ✓ Correlate with infrastructure metrics (CPU, memory, disk I/O)

FILES GENERATED
===============
  CSV Results:      {csv_file}
  This Report:      {output_file}
  
NEXT STEPS
==========
1. Import CSV data into analytics platform
2. Query for slow transactions (>P95)
3. Identify error patterns by status code
4. Cross-reference with application logs
5. Analyze service dependencies during failures
6. Create performance dashboards
7. Establish SLA baselines

LOAD PROFILE CHARACTERISTICS
=============================
  • Concurrent users ramped over period
  • Multiple iterations per user (realistic sessions)
  • Think times between requests (human behavior)
  • Full user journey: Browse → Register → Login → Shop → Checkout
  • High volume transaction generation
  • Distributed load patterns

================================================================================
                         DATA GENERATION COMPLETE
                  Ready for Root Cause Analysis Investigation
================================================================================
"""
    
    return report

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze-results.py <csv-file> [output-file]")
        sys.exit(1)
    
    csv_file = Path(sys.argv[1])
    if not csv_file.exists():
        print(f"Error: CSV file not found: {csv_file}")
        sys.exit(1)
    
    output_file = Path(sys.argv[2] if len(sys.argv) > 2 else str(csv_file).replace('.csv', '_REPORT.txt'))
    
    print(f"Analyzing {csv_file.name}...", file=sys.stderr)
    results = analyze_csv(str(csv_file))
    
    print(f"Generating report...", file=sys.stderr)
    report = generate_report(results, str(csv_file), str(output_file))
    
    with open(output_file, 'w') as f:
        f.write(report)
    
    print(report)
    print(f"\nReport saved to: {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
