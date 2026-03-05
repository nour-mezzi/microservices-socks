#!/usr/bin/env python3
"""
Anomaly and Issue Injector for Sock Shop Load Test
Generates synthetic test results with introduced anomalies for AI root cause analysis

This script simulates various production issues:
- Performance degradation
- Timeout failures
- Service unavailability
- Data validation failures
- Cascading failures
- Memory spikes
"""

import csv
import json
import random
import time
from datetime import datetime, timedelta
from typing import Dict, List
import argparse


class AnomalyInjector:
    """Injects anomalies into load test data"""
    
    def __init__(self, output_csv: str = "anomalies_log.csv"):
        self.output_csv = output_csv
        self.anomalies: List[Dict] = []
        self.test_results: List[Dict] = []
        
    def add_anomaly(self, issue_id: int, name: str, description: str, 
                    affected_endpoint: str, severity: str, 
                    root_cause: str, symptom: str) -> Dict:
        """Add an anomaly to tracking"""
        anomaly = {
            "issue_id": issue_id,
            "name": name,
            "description": description,
            "affected_endpoint": affected_endpoint,
            "severity": severity,
            "root_cause": root_cause,
            "symptom": symptom,
            "introduced_at": datetime.now().isoformat(),
        }
        self.anomalies.append(anomaly)
        return anomaly
    
    def generate_test_result(self, timestamp: datetime, endpoint: str, 
                            response_time_ms: int, status_code: int,
                            success: bool, anomaly_id: int = None,
                            error_message: str = None) -> Dict:
        """Generate a single test result"""
        result = {
            "timestamp": timestamp.isoformat(),
            "endpoint": endpoint,
            "response_time_ms": response_time_ms,
            "status_code": status_code,
            "success": success,
            "anomaly_id": anomaly_id,
            "error_message": error_message or "",
            "thread_name": f"Thread-{random.randint(1, 50)}",
            "attempt": random.randint(1, 3)
        }
        self.test_results.append(result)
        return result
    
    def inject_issue_1_homepage_degradation(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #1: Homepage Performance Degradation
        
        Simulates: Frontend service experiencing performance degradation
        Symptoms: Response times increase from 100-200ms to 2000-5000ms
        Root Cause: High memory usage, database connection pool exhaustion
        """
        self.add_anomaly(
            issue_id=1,
            name="Homepage Performance Degradation",
            description="Frontend homepage responses slow from ~150ms to ~3500ms",
            affected_endpoint="/",
            severity="HIGH",
            root_cause="Database connection pool exhausted, high memory paging",
            symptom="Increased response latency, timeouts, page load failures"
        )
        
        # Generate degraded responses
        current_time = start_time
        for i in range(int(duration_sec / 2)):  # Every 2 seconds
            # Degraded response times (2-5 seconds)
            response_time = random.randint(2000, 5000)
            status = 200 if random.random() > 0.15 else 504
            success = status == 200
            
            self.generate_test_result(
                timestamp=current_time,
                endpoint="/",
                response_time_ms=response_time,
                status_code=status,
                success=success,
                anomaly_id=1,
                error_message="Gateway Timeout" if status == 504 else None
            )
            current_time += timedelta(seconds=2)
    
    def inject_issue_2_aggressive_timeouts(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #2: Aggressive Timeout Configuration
        
        Simulates: Timeout settings too strict for current load
        Symptoms: Requests fail with connection timeouts
        Root Cause: Reduced connection timeout (2s instead of 10s)
        """
        self.add_anomaly(
            issue_id=2,
            name="Aggressive Timeout Configuration",
            description="Connection timeout reduced from 10s to 2s causing failures",
            affected_endpoint="/catalogue, /tags, /catalogue/size",
            severity="HIGH",
            root_cause="Test configuration changed: connect_timeout=2000ms, response_timeout=2000ms",
            symptom="Connection timeout errors, failed assertions, elevated error rate"
        )
        
        # Generate timeout failures
        current_time = start_time
        endpoints = ["/catalogue", "/tags", "/catalogue/size"]
        for i in range(int(duration_sec / 3)):
            endpoint = random.choice(endpoints)
            # Timeouts after 2 seconds
            self.generate_test_result(
                timestamp=current_time,
                endpoint=endpoint,
                response_time_ms=2000,
                status_code=000,
                success=False,
                anomaly_id=2,
                error_message="Connection timeout"
            )
            current_time += timedelta(seconds=3)
    
    def inject_issue_3_data_validation_mismatch(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #3: Data Validation Mismatch
        
        Simulates: Test expectations don't match actual API responses
        Symptoms: JSONPath assertions fail, data format changes
        Root Cause: API schema changed or test assertion incorrect
        """
        self.add_anomaly(
            issue_id=3,
            name="Data Validation Mismatch",
            description="Catalogue endpoint returning different JSON structure than expected",
            affected_endpoint="/catalogue",
            severity="MEDIUM",
            root_cause="API response schema changed or test expects non-existent array index $[999]",
            symptom="JSONPath assertion failures, data validation errors"
        )
        
        current_time = start_time
        for i in range(int(duration_sec / 4)):
            self.generate_test_result(
                timestamp=current_time,
                endpoint="/catalogue",
                response_time_ms=random.randint(150, 300),
                status_code=200,
                success=False,
                anomaly_id=3,
                error_message="JSONPath: $[999] not found - expected at least 1000 items"
            )
            current_time += timedelta(seconds=4)
    
    def inject_issue_4_cascading_failures(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #4: Cascading Failures
        
        Simulates: One service failure causing downstream failures
        Symptoms: Product details endpoint fails, impacts other endpoints
        Root Cause: Upstream service unreachable, circuit breaker triggered
        """
        self.add_anomaly(
            issue_id=4,
            name="Cascading Service Failures",
            description="Product details request fails due to upstream service dependency",
            affected_endpoint="/catalogue/{id}",
            severity="CRITICAL",
            root_cause="Upstream microservice unavailable, 8+ second delay before timeout",
            symptom="500 errors, cascading timeout failures, increased latency"
        )
        
        current_time = start_time
        for i in range(int(duration_sec / 5)):
            self.generate_test_result(
                timestamp=current_time,
                endpoint="/catalogue/03fef6ac-1896-4ce8-bd69-b798f85c6e0b",
                response_time_ms=random.randint(7500, 8500),
                status_code=500,
                success=False,
                anomaly_id=4,
                error_message="Service Unavailable - upstream dependency failed"
            )
            current_time += timedelta(seconds=5)
    
    def inject_issue_5_service_unavailability(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #5: Service Unavailability
        
        Simulates: Tags endpoint temporarily unavailable
        Symptoms: 503 Service Unavailable responses
        Root Cause: Database maintenance, replication lag, resource exhaustion
        """
        self.add_anomaly(
            issue_id=5,
            name="Service Unavailability",
            description="Tags endpoint returns 503 Service Unavailable",
            affected_endpoint="/tags",
            severity="HIGH",
            root_cause="Tags service database connection pool exhausted",
            symptom="503 errors, test failures, user-facing service degradation"
        )
        
        current_time = start_time
        for i in range(int(duration_sec / 6)):
            self.generate_test_result(
                timestamp=current_time,
                endpoint="/tags",
                response_time_ms=random.randint(100, 600),
                status_code=503,
                success=False,
                anomaly_id=5,
                error_message="Service Unavailable"
            )
            current_time += timedelta(seconds=6)
    
    def inject_issue_6_load_spike(self, start_time: datetime, duration_sec: int = 300):
        """ISSUE #6: Memory Spike and High Load
        
        Simulates: Increased concurrent users causing memory pressure
        Symptoms: Increased response times, memory errors, GC pauses
        Root Cause: User count increased from 10 to 50 concurrent users
        """
        self.add_anomaly(
            issue_id=6,
            name="Memory Spike and High Load",
            description="Concurrent users increased from 10 to 50, causing memory pressure",
            affected_endpoint="All endpoints",
            severity="CRITICAL",
            root_cause="Test configuration increased USERS from 10 to 50",
            symptom="High memory usage, GC pauses, increased latency across all endpoints"
        )
        
        current_time = start_time
        endpoints = ["/", "/catalogue", "/catalogue/size", "/tags"]
        for i in range(int(duration_sec / 2)):
            endpoint = random.choice(endpoints)
            # Increased latency under load
            response_time = random.randint(500, 2000)
            self.generate_test_result(
                timestamp=current_time,
                endpoint=endpoint,
                response_time_ms=response_time,
                status_code=200,
                success=response_time < 1500,
                anomaly_id=6,
                error_message="Request timeout" if response_time >= 1500 else None
            )
            current_time += timedelta(seconds=2)
    
    def save_anomalies_log(self, filename: str = None):
        """Save anomalies to CSV"""
        if filename is None:
            filename = self.output_csv
            
        print(f"\n📋 Saving {len(self.anomalies)} identified anomalies to: {filename}")
        
        with open(filename, 'w', newline='') as f:
            fieldnames = [
                'issue_id', 'name', 'description', 'affected_endpoint',
                'severity', 'root_cause', 'symptom', 'introduced_at'
            ]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.anomalies)
        
        print(f"✅ Anomalies log saved!")
    
    def save_test_results(self, filename: str = None):
        """Save test results to CSV"""
        if filename is None:
            filename = "test_results.csv"
        
        print(f"\n📊 Saving {len(self.test_results)} test results to: {filename}")
        
        with open(filename, 'w', newline='') as f:
            fieldnames = [
                'timestamp', 'endpoint', 'response_time_ms', 'status_code',
                'success', 'anomaly_id', 'error_message', 'thread_name', 'attempt'
            ]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.test_results)
        
        print(f"✅ Test results saved!")
    
    def print_summary(self):
        """Print summary of all anomalies"""
        print("\n" + "="*80)
        print("🔴 SOCK SHOP ANOMALIES SUMMARY - For AI Root Cause Analysis")
        print("="*80)
        
        for anomaly in self.anomalies:
            print(f"\n📌 ISSUE #{anomaly['issue_id']}: {anomaly['name']}")
            print(f"   Severity: {anomaly['severity']}")
            print(f"   Endpoint: {anomaly['affected_endpoint']}")
            print(f"   Description: {anomaly['description']}")
            print(f"   Symptom: {anomaly['symptom']}")
            print(f"   Root Cause: {anomaly['root_cause']}")
        
        print("\n" + "="*80)
        print(f"Total Anomalies Injected: {len(self.anomalies)}")
        print(f"Total Test Results Generated: {len(self.test_results)}")
        print("="*80 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Inject anomalies into Sock Shop load test data"
    )
    parser.add_argument(
        "--anomalies-log",
        default="anomalies_log.csv",
        help="Output file for anomalies log (default: anomalies_log.csv)"
    )
    parser.add_argument(
        "--results-log",
        default="test_results.csv",
        help="Output file for test results (default: test_results.csv)"
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=300,
        help="Duration of test in seconds (default: 300)"
    )
    
    args = parser.parse_args()
    
    # Initialize injector
    injector = AnomalyInjector(output_csv=args.anomalies_log)
    
    # Use current time as start
    start_time = datetime.now() - timedelta(seconds=args.duration)
    
    # Inject all issues
    print("🔧 Injecting anomalies...\n")
    
    print("  • Injecting ISSUE #1: Homepage Performance Degradation")
    injector.inject_issue_1_homepage_degradation(start_time, args.duration)
    
    print("  • Injecting ISSUE #2: Aggressive Timeout Configuration")
    injector.inject_issue_2_aggressive_timeouts(start_time, args.duration)
    
    print("  • Injecting ISSUE #3: Data Validation Mismatch")
    injector.inject_issue_3_data_validation_mismatch(start_time, args.duration)
    
    print("  • Injecting ISSUE #4: Cascading Service Failures")
    injector.inject_issue_4_cascading_failures(start_time, args.duration)
    
    print("  • Injecting ISSUE #5: Service Unavailability")
    injector.inject_issue_5_service_unavailability(start_time, args.duration)
    
    print("  • Injecting ISSUE #6: Memory Spike and High Load")
    injector.inject_issue_6_load_spike(start_time, args.duration)
    
    # Save results
    injector.save_anomalies_log(args.anomalies_log)
    injector.save_test_results(args.results_log)
    
    # Print summary
    injector.print_summary()
    
    print(f"📁 Anomalies saved to: {args.anomalies_log}")
    print(f"📁 Test results saved to: {args.results_log}")


if __name__ == "__main__":
    main()
