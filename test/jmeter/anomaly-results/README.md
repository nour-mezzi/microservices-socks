# Test Results Organization

## Key Principle: Data Collection Status

Results are organized by **whether data was successfully collected**, not just by test pass rates.

```
anomaly-results/
├── passed/              (49M) - Data collected AND ≥80% requests succeeded
│   ├── TRACE-FINAL      (80.6% pass, full observability)
│   └── t-101            (80.0% pass, full observability)
│
├── failed/              (177M) - Either:
│   │
│   ├── Data Collection Failed (NO observability):
│   │   └── ANOMALY-001  (CSV exists but NO observability data)
│   │
│   └── Data Collected but Tests Failed (with observability):
│       ├── ANOMALY-015  (59.8% pass, full data)
│       ├── TRACE-TEST*  (0-55% pass, full data)
│       └── test-101     (59.8% pass, full data)
│
├── reports/             (empty) - For analysis reports and summaries
├── *.csv                - Aggregate result files
└── *.log                - Historical log files
```

## Why This Matters

### Failed Data Collection (ANOMALY-001)
- **Problem**: Test results CSV exists but NO observability data collected
- **Cause**: Observability infrastructure failure, not application issue
- **Action**: Fix observability collection, not application code

### Tests Failed but Data Collected (ANOMALY-015, TRACE-*, test-101)
- **Problem**: Observability data exists, but <80% requests succeeded
- **Cause**: Application/system under stress/anomaly conditions
- **Action**: Use observability data to debug application behavior

## Quick Start

### Reviewing Results
```bash
# View successful tests (data collected + healthy)
cd passed/
ls -la

# View failed tests (investigate why)
cd failed/
ls -la

# Check if data was collected
ls -la ANOMALY-001*        # No observability/ dirs → data collection failed
ls -la ANOMALY-015*        # Has observability/ dirs → data collection worked
```

### Troubleshooting Failures

**If test is in failed/ANOMALY-001:**
- ✗ No observability directory found
- Problem: Data collection infrastructure issue
- Next: Check observability service/collector logs

**If test is in failed/ANOMALY-015:**
- ✓ Observability directory found
- Problem: Application/test failure (not infrastructure)
- Next: Use observability data to debug application

### For New Test Runs
```bash
# 1. Save new test results to root
cp new-test-results/*.csv ./
cp new-test-results/*-observability ./

# 2. Run organization script
python3 organize_results.py .

# 3. Review categorized results
ls passed/    # Successful tests
ls failed/    # Failed tests or collection failures
```

## Documentation

See `CLEANUP-PROCESS.md` for:
- Data collection vs. test failure distinction
- Detailed categorization logic
- Complete automation script
- Best practices for future runs
- Comprehensive failure analysis guide

## Statistics

| Category | Items | Total Size | Fate |
|----------|-------|-----------|------|
| **Passed** | 6 | 49M | ✓ Baseline reference |
| **Failed (No Data)** | 2 | 0.3M | ⚠️ Infrastructure issue |
| **Failed (With Data)** | 25 | 177M | ⚠️ App/test issue |
| **Aggregate Files** | 4 | 96M | 📊 Historical reference |
| **TOTAL** | 37 | 226M | — |

---

*Last organized: 2026-05-02*
*Key distinction: Data Collection Status vs. Test Result Pass Rate*
