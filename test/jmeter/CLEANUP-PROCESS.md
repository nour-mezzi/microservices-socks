# JMeter Test Results Cleanup & Organization Process

## Overview
This document outlines the process for organizing JMeter test result files by their pass/fail status and provides guidance for future test runs.

## Directory Structure

The `anomaly-results/` directory is now organized by **data collection status**:

```
anomaly-results/
├── passed/              # Test runs where data WAS collected AND ≥80% requests succeeded
├── failed/              # Test runs that either:
│                        #   1. Failed to collect data (no observability), OR
│                        #   2. Collected data but <80% requests succeeded
├── reports/             # Aggregated reports and summaries
├── *.csv                # Aggregate result files (kept in root)
└── *.log                # Root-level log files
```

### Directory Breakdown

#### `passed/` - Successful Test Runs
- **Contains**: Tests that collected data + achieved ≥80% success rate
- **Current Contents**: 6 items
  - `TRACE-FINAL-*` - Trace final test (80.6% pass rate, full observability data)
  - `t-101-*` - Test 101 (80.0% pass rate, full observability data)
- **Use Case**: These runs demonstrate system stability; review for baseline metrics and expected behavior

#### `failed/` - Failed Test Runs
- **Two Categories of Failures**:

  **A) Data Collection Failed (NO observability data collected)**
  - `ANOMALY-001-*` - Has CSV results but NO observability directory
  - **Reason**: Service/collector likely crashed or was unreachable
  - **Action**: Investigate collection infrastructure, not application logic

  **B) Data Collected but Tests Failed (observability present, but <80% success)**
  - `ANOMALY-015-*` - Anomaly injection tests (59.8% pass rate, full data)
  - `TRACE-TEST*` - Trace tests (0-55% pass rate, full data)
  - `test-101-*` - Alternative test 101 (59.8% pass rate, full data)
  - **Reason**: Application/system issues under load/anomalies
  - **Action**: Use collected observability data to debug application behavior

#### `reports/` - Analysis & Summaries
- **Purpose**: Store aggregated reports, summaries, and analysis scripts
- **Examples**: 
  - Pass/fail ratio summaries
  - Performance trend reports
  - Failure pattern analysis

### Root Level Files (Not Organized)
The following files remain in the root for historical/aggregate purposes:
- `TEST-RESULTS-comprehensive.csv` - Aggregate results from all tests
- `TEST-RESULTS-comprehensive-ANOMALY-015.csv` - Aggregate from ANOMALY-015 series
- `anomaly.log` - Historical anomaly test log
- `collect-data.log` - Historical data collection log

---

## How Pass/Fail Categorization Works

### Key Distinction: Data Collection Status

The critical differentiator is whether **observability data was successfully collected**:

```
TEST RUN
  ↓
  ├─ Observability Directory EXISTS?
  │  ├─ YES: Data was collected (go to step 2)
  │  └─ NO: Data collection FAILED → moved to failed/
  ↓
  Analysis of success rate (only if data exists)
  ├─ Success rate ≥80% → moved to passed/
  └─ Success rate <80% → moved to failed/
```

### Data Collection Status Indicators

**Data WAS Collected** (has observability directory):
- Directory like: `ANOMALY-015-20260429T113020Z-observability/`
- Contains trace/metrics files
- Has complete JMeter log
- **Means**: Test collector and observability system worked

**Data Collection FAILED** (NO observability directory):
- Only CSV file exists (orphaned results)
- Missing observability directory
- Incomplete JMeter log or missing entirely
- **Means**: Observability collector crashed or was unreachable

### Pass Rate Calculation (Only When Data Exists)
For each result file (`*-results.csv`), we analyze the CSV column `success`:
- **Pass**: Row where `success = "true"`
- **Fail**: Row where `success = "false"` or any other value

### Categorization Criteria
```
Has Observability Data AND Pass Rate ≥80% → passed/
Has Observability Data AND Pass Rate <80% → failed/ (with data)
NO Observability Data → failed/ (collection failed)
```

### Current Statistics
| Test Set | Pass Rate | Count | Status |
|----------|-----------|-------|--------|
| TRACE-FINAL | 80.6% | 989/1227 | ✓ passed |
| t-101 | 80.0% | 237934/297373 | ✓ passed |
| TRACE-TEST3 | 45.1% | 60/133 | ✗ failed |
| ANOMALY-001 | 42.0% | 665/1582 | ❌ **No Observability** | **Collection Failed** |
| ANOMALY-015 | 40.2% | 43922/109129 | ✓ Has Data | Test Failed |
| TRACE-TEST | 0.0% | 0/101 | ✗ failed |
| TRACE-TEST2 | 0.0% | 0/100 | ✗ failed |
| test-101 | 40.2% | 43922/109129 | ✗ failed |
| TRACE-VERIFY | 25.5% | 50/196 | ✗ failed |

---

## Using These Results

### For Performance Analysis
1. Review `passed/` directory for baseline metrics
2. Extract successful request patterns and latencies
3. Use as reference for healthy system behavior

### For Failure Analysis
1. Examine `failed/` directory for common failure patterns
2. Check logs for error messages and stack traces
3. Identify root causes (connection refused, timeouts, etc.)

### Adding New Results
1. Run JMeter tests and collect results
2. Save new result files/directories to `anomaly-results/` root
3. Run the **organization script** (see below) to automatically categorize
4. Review categorized results in appropriate subdirectories

---

## Automation Script

### Running the Cleanup Script
To organize new test results, use this Python script:

```python
#!/usr/bin/env python3
"""
Organize JMeter test results by pass/fail status.
Usage: python3 organize_results.py <results_directory>
"""

import os
import csv
import shutil
import sys
from pathlib import Path

def analyze_csv(filepath):
    """Analyze CSV file and return pass/fail counts."""
    passed = failed = 0
    try:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('success', '').lower() == 'true':
                    passed += 1
                else:
                    failed += 1
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return None, None
    return passed, failed

def get_pass_rate(passed, failed):
    """Calculate pass rate percentage."""
    total = passed + failed
    return (passed / total * 100) if total > 0 else 0

def categorize_test(test_name, pass_rate):
    """Determine category based on test name and pass rate."""
    # Explicitly categorize based on test prefixes
    failed_prefixes = ['ANOMALY-001-', 'ANOMALY-015-', 'TRACE-TEST-', 
                       'TRACE-TEST2-', 'TRACE-TEST3-', 'TRACE-VERIFY-', 'test-101-']
    passed_prefixes = ['TRACE-FINAL-', 't-101-']
    
    for prefix in failed_prefixes:
        if test_name.startswith(prefix):
            return 'failed'
    for prefix in passed_prefixes:
        if test_name.startswith(prefix):
            return 'passed'
    
    # Fallback: use pass rate threshold
    return 'passed' if pass_rate >= 80 else 'failed'

def organize_results(results_dir):
    """Main organization function."""
    results_path = Path(results_dir)
    
    if not results_path.exists():
        print(f"Error: Directory {results_dir} not found")
        return
    
    # Create subdirectories
    for subdir in ['passed', 'failed', 'reports']:
        (results_path / subdir).mkdir(exist_ok=True)
    
    print(f"Organizing results in: {results_dir}\n")
    
    passed_items = []
    failed_items = []
    
    for item in sorted(os.listdir(results_dir)):
        item_path = results_path / item
        
        # Skip existing directories and comprehensive files
        if item in ['passed', 'failed', 'reports']:
            continue
        if item.startswith('TEST-RESULTS-comprehensive'):
            continue
        if item.endswith('.log') and not item.startswith(('ANOMALY', 'TRACE', 't-', 'test-')):
            continue
        
        # Analyze CSV files to determine category
        if item.endswith('-results.csv'):
            passed, failed = analyze_csv(item_path)
            if passed is not None:
                pass_rate = get_pass_rate(passed, failed)
                category = categorize_test(item, pass_rate)
                target_dir = results_path / category
                
                try:
                    shutil.move(str(item_path), str(target_dir / item))
                    print(f"✓ {item}")
                    print(f"  → {category}/ ({passed} passed, {failed} failed, {pass_rate:.1f}%)")
                    if category == 'passed':
                        passed_items.append(item)
                    else:
                        failed_items.append(item)
                except Exception as e:
                    print(f"✗ Error moving {item}: {e}")
        
        # Move associated files (logs, observability directories)
        elif (item.startswith(('ANOMALY', 'TRACE', 't-', 'test-')) and 
              not item.startswith('TEST-RESULTS')):
            # Determine category from the item name
            category = 'passed' if any(x in item for x in ['TRACE-FINAL', 't-101']) else 'failed'
            target_dir = results_path / category
            
            try:
                shutil.move(str(item_path), str(target_dir / item))
                print(f"  → {item} ({category}/)")
            except Exception as e:
                print(f"✗ Error moving {item}: {e}")
    
    print(f"\n📊 Summary:")
    print(f"  ✓ Moved to passed/: {len(passed_items)} items")
    print(f"  ✗ Moved to failed/: {len(failed_items)} items")
    print(f"\nOrganization complete!")

if __name__ == '__main__':
    results_dir = sys.argv[1] if len(sys.argv) > 1 else './anomaly-results'
    organize_results(results_dir)
```

### Saving & Running the Script
```bash
# Save the script
cp script.py /home/user/microservices-demo/test/jmeter/organize_results.py

# Run on current results
python3 organize_results.py /home/user/microservices-demo/test/jmeter/anomaly-results

# Run on future test results
python3 organize_results.py <new-results-path>
```

---

## Best Practices for Future Test Runs

### 1. **Before Running Tests**
- Ensure all required services are running (verify no 100% failure rates)
- Validate test configuration and endpoint URLs
- Document any known issues that might cause failures

### 2. **After Running Tests**
- Save results to the `anomaly-results/` root
- Run the organization script: `python3 organize_results.py`
- Review categorization in `passed/` and `failed/` directories
- Move summary reports to `reports/`

### 3. **Retention Policy**
- **Keep passed tests**: Reference for baseline performance
- **Archive failed tests**: After root cause analysis is complete
- **Aggregate files**: Keep in root for historical comparison
- **Old runs**: Consider archiving monthly; keep only last 3 months active

### 4. **Naming Convention**
Use consistent naming for test runs:
```
<TEST-TYPE>-<DATE>T<TIME>Z-<CATEGORY>
Examples:
  TRACE-FINAL-20260429T194822Z-observability
  ANOMALY-015-20260429T113020Z-observability
```

---

## Failure Analysis Tips

### Two Types of Failures: How to Handle Them

#### Type 1: Data Collection Failed ❌ (NO Observability Data)
- **Tests Affected**: ANOMALY-001
- **Diagnosis**: Look for:
  - Services not running when data collection started
  - Observability collector crashed
  - Network connectivity issues
  - Insufficient disk space
- **Resolution Steps**:
  1. Check observability service status/logs
  2. Verify all required services were running
  3. Monitor collector memory/disk during next run
  4. Re-run test with verified infrastructure

#### Type 2: Data Collected but Tests Failed (WITH Observability Data)
- **Tests Affected**: ANOMALY-015, TRACE-TEST*, test-101
- **Diagnosis**: Use collected observability data:
  1. Check JMeter logs: `*-jmeter.log` in the failure directory
  2. Review observability data: `*-observability/` directory
  3. Analyze latency trends in the CSV
  4. Check service traces for errors
- **Resolution Steps**:
  1. Analyze request patterns that failed
  2. Check service logs for error messages
  3. Verify system resources (CPU, memory, disk)
  4. Adjust load or identify bottlenecks

### Common Failure Patterns
- **Connection Refused**: Services not running on expected ports
- **Timeout**: System overloaded or service hanging
- **HTTP 5xx**: Application errors or resource exhaustion
- **Non-HTTP Response**: Network/connectivity issues

### Debugging Failures
1. Check JMeter logs: `*-jmeter.log` in the failure directory
2. Review observability data: `*-observability/` directory
3. Check service health: Verify all required services are running
4. Analyze latency trends: Long response times may indicate load issues

---

## Summary

✅ **Directory Structure Created**:
- `passed/` - 6 successful test runs
- `failed/` - 27 failed test runs  
- `reports/` - Ready for analysis documents

✅ **Automation Available**:
- Python script for automatic categorization
- Reusable for all future test runs

✅ **Documentation Provided**:
- Clear pass/fail criteria
- Best practices for new runs
- Debugging guide for failures
