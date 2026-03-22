# Sock Shop - Complete Observability Signal Extraction

## Overview
This document outlines all observability signals (Metrics, Logs, and Traces) being extracted from the Sock Shop microservices platform.

---

## 🔴 METRICS (via Prometheus)

### Source Components
- **Prometheus** (Port 9090): Time-series database for metrics
- **Node Exporter** (Port 9100): Host-level metrics
- **cAdvisor** (Port 8080): Container-level metrics
- **Tempo**: Service graph and span metrics
- **Services**: Application metrics endpoints

### Metrics Extracted

#### **1. CPU Usage** ✅
- **Source**: Node Exporter + cAdvisor
- **Metric Names**:
  - `node_cpu_seconds_total` - Host CPU time
  - `container_cpu_usage_seconds_total` - Container CPU usage
  - `node_load1/5/15` - System load average
- **Labels**: `service`, `container_name`, `instance`
- **Scrape Jobs**: `node-exporter`, `cadvisor`
- **Alert**: `HighCPUUsage` (>80% for 2m)
- **Prometheus Query**:
  ```promql
  rate(container_cpu_usage_seconds_total[5m]) * 100
  ```

#### **2. Memory Usage** ✅
- **Source**: Node Exporter + cAdvisor
- **Metric Names**:
  - `node_memory_MemAvailable_bytes` - Available system memory
  - `container_memory_working_set_bytes` - Container memory usage
  - `node_memory_MemTotal_bytes` - Total system memory
- **Labels**: `service`, `container_name`, `instance`
- **Scrape Jobs**: `node-exporter`, `cadvisor`
- **Alert**: `HighMemoryUsage` (>85% for 2m)
- **Prometheus Query**:
  ```promql
  container_memory_working_set_bytes / container_spec_memory_limit_bytes * 100
  ```

#### **3. Request Latency** ✅
- **Source**: Application instrumentation (OTEL) + Tempo metrics generator
- **Metric Names**:
  - `http_request_duration_seconds` - HTTP request duration (histogram)
  - `traces_spanmetrics_duration_seconds` - Span latency from traces
- **Labels**: `service`, `endpoint`, `method`, `status`
- **Percentiles**: P50, P95, P99 (via histogram_quantile)
- **Scrape Jobs**: Individual service endpoints, `tempo`
- **Alert**: `HighRequestLatency` (P95 > 1s), `P99LatencyHigh` (P99 > 2s)
- **Prometheus Queries**:
  ```promql
  # P95 latency
  histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
  
  # P99 latency
  histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
  ```

#### **4. Error Rate** ✅
- **Source**: Application instrumentation + cAdvisor
- **Metric Names**:
  - `http_requests_total` - Total HTTP requests by status
  - `traces_spanmetrics_duration_bucket{status_code="error"}` - Error spans
  - `exceptions_total` - Application exceptions
- **Labels**: `service`, `endpoint`, `status_code`, `error_type`
- **Scrape Jobs**: Service endpoints, `tempo`
- **Alerts**: 
  - `HighErrorRate` (5xx > 10% per minute)
  - `HighErrorRateOnEndpoint` (5xx > 5% per 5m)
  - `HighTraceErrorRate` (trace errors > 5% per 5m)
- **Prometheus Queries**:
  ```promql
  # HTTP 5xx error rate
  rate(http_requests_total{status=~"5.."}[5m])
  
  # Error rate by service
  rate(traces_spanmetrics_duration_bucket{status_code="error"}[5m])
  ```

#### **5. Service Throughput** ✅
- **Source**: Application instrumentation
- **Metric Names**:
  - `http_requests_total` - Total request count
  - `traces_spanmetrics_calls_total` - Total spans from tracing
- **Labels**: `service`, `endpoint`, `method`
- **Scrape Jobs**: Service endpoints, `tempo`
- **Prometheus Query**:
  ```promql
  # Requests per second
  rate(http_requests_total[1m])
  
  # Request distribution by endpoint
  sum(rate(http_requests_total[5m])) by (endpoint)
  ```

#### **6. Container Restart Count** ✅ (NEW)
- **Source**: cAdvisor
- **Metric Names**:
  - `container_last_seen` - Container status changes
  - `container_start_time_seconds` - Container start timestamp
- **Labels**: `container_name`, `pod_name`, `namespace`
- **Scrape Jobs**: `cadvisor`
- **Alert**: `ContainerRestarts` (any restart in 15 minutes)
- **Prometheus Query**:
  ```promql
  # Detect restarts
  increase(container_last_seen[15m]) > 0
  ```

---

## 🟡 LOGS (via Loki + Promtail)

### Source Components
- **Loki** (Port 3100): Log aggregation storage
- **Promtail** (Port 9080): Log collection and shipping
- **Docker**: Container stdout/stderr

### Log Sources

#### **1. Application Errors** ✅
- **Source**: Docker container logs via Promtail
- **Collection**: `docker_sd_configs` - automatic Docker discovery
- **Labels**: `container_name`, `compose_service`, `image`, `job`
- **Patterns**:
  - "ERROR", "Exception", "FAILED", "error"
  - Stack traces
  - Application-specific error codes
- **Loki Query**:
  ```logql
  {compose_service="orders"} | "ERROR"
  ```

#### **2. Timeout Exceptions** ✅
- **Source**: Docker container logs
- **Collection**: Promtail scrapes all `/var/log` and Docker containers
- **Patterns**:
  - "TimeoutException", "timeout", "Timeout", "timed out"
  - "connection timeout", "read timeout", "write timeout"
  - "DeadlineExceededException"
- **Loki Query**:
  ```logql
  {job="docker"} | "timeout" or "Timeout"
  ```

#### **3. Service Crash Logs** ✅
- **Source**: Docker container logs, system logs
- **Collection**: 
  - Docker logs: `docker_sd_configs`
  - System logs: `/var/log` (varlogs job)
- **Patterns**:
  - Application exit/crash indicators
  - Out of memory errors
  - Segmentation faults
- **Loki Query**:
  ```logql
  {job="docker"} | "FATAL" or "crash" or "OOMKilled"
  ```

#### **4. Database Query Errors** ✅
- **Source**: Application logs (MongoDB, MySQL output)
- **Collection**: Promtail Docker log scraping
- **Services with DB**:
  - `orders` (MongoDB)
  - `carts` (MongoDB)
  - `catalogue` (MySQL)
  - `user` (MongoDB)
- **Patterns**:
  - "Connection refused", "No such host"
  - "Query failed", "SQL error"
  - "Index already exists"
- **Loki Query**:
  ```logql
  {compose_service=~"orders|carts|catalogue|user"} | "connection" or "query" or "error"
  ```

---

## 🟢 TRACES (via Tempo + OTEL)

### Source Components
- **Tempo** (Port 3200/4317/4318): Distributed trace storage
  - Port 4317: OTLP gRPC (Java services)
  - Port 4318: OTLP HTTP (Node.js services)
  - Port 9411: Zipkin (legacy support)
- **OpenTelemetry Agent**: Automatic instrumentation
  - Java: `opentelemetry-javaagent.jar`
  - Node.js: `@opentelemetry/auto-instrumentations-node`

### Services Instrumented

| Service | Language | Instrumentation | Endpoint |
|---------|----------|-----------------|----------|
| front-end | Node.js | Auto (OTEL Node) | http://tempo:4318 |
| catalogue | Go | Manual | http://tempo:4318 |
| payment | Node.js | Auto | http://tempo:4318 |
| user | Node.js | Auto | http://tempo:4318 |
| carts | Java | Auto (Agent) | http://tempo:4317 |
| orders | Java | Auto (Agent) | http://tempo:4317 |
| shipping | Java | Auto (Agent) | http://tempo:4317 |
| queue-master | Java | Auto (Agent) | http://tempo:4317 |

### Traces Extracted

#### **1. Span Latency** ✅
- **Source**: OTEL instrumentation
- **Span Types**:
  - HTTP request spans
  - Database query spans
  - RPC/gRPC spans
  - Message queue spans
- **Attributes**: `duration_ms`, `service.name`, `span.kind`
- **Generated Metrics**:
  - `traces_spanmetrics_duration_seconds` - Span duration histogram
  - Histogram quantiles: P50, P95, P99
- **Tempo Query**:
  ```
  Service: any | Span duration > 100ms
  ```

#### **2. Request Path** ✅
- **Source**: HTTP span attributes
- **Span Attributes**:
  - `http.method` - HTTP method (GET, POST, etc.)
  - `http.url` - Full request URL
  - `http.target` - Request path/route
  - `http.host` - Host header
- **Labels for Metrics**: `endpoint`, `method`
- **Tempo Query**:
  ```
  Service: frontend | Span name: HTTP GET
  ```

#### **3. Service Dependencies** ✅
- **Source**: Tempo metrics generator with service-graphs processor
- **Generated Metrics**:
  - `traces_service_graph_request_total` - Requests between services
  - `traces_service_graph_request_duration_seconds` - Latency between services
- **Attributes**: `client`, `server`, `connection_type`
- **Detection**: Automatic via span parent-child relationships
- **Visualization**: Service graph in Tempo UI and Grafana
- **Prometheus Query**:
  ```promql
  traces_service_graph_request_total
  ```

#### **4. Error Spans** ✅
- **Source**: OTEL instrumentation detection
- **Span Attributes**:
  - `status.code` - Error, Unset, Ok
  - `http.status_code` - HTTP status (5xx = error)
  - `exception.type` - Exception class name
  - `exception.message` - Error message
  - `exception.stacktrace` - Stack trace
- **Generated Metrics**:
  - `traces_spanmetrics_duration_bucket{status_code="error"}`
  - Error rate calculated from traces
- **Error Detection**:
  - HTTP 5xx responses
  - RPC errors (grpc status != OK)
  - Exceptions with span events
- **Tempo Query**:
  ```
  Service: orders | Error: true
  ```

---

## 📊 Signal Verification & Testing

### Verify Metrics Collection

```bash
# 1. Check cAdvisor is scraping
curl http://localhost:8080/metrics | grep container

# 2. Check container restart detection
curl http://localhost:9090/api/v1/query?query=container_last_seen

# 3. Check CPU metrics
curl http://localhost:9090/api/v1/query?query=rate\(container_cpu_usage_seconds_total\[5m\]\)

# 4. Check memory metrics
curl http://localhost:9090/api/v1/query?query=container_memory_working_set_bytes

# 5. Check error rates
curl http://localhost:9090/api/v1/query?query=rate\(http_requests_total\{status~\"5..\"\}\[5m\]\)

# 6. Check latency
curl http://localhost:9090/api/v1/query?query=histogram_quantile\(0.95,rate\(http_request_duration_seconds_bucket\[5m\]\)\)

# 7. Check service throughput
curl http://localhost:9090/api/v1/query?query=rate\(http_requests_total\[1m\]\)
```

### Verify Logs

```bash
# 1. Check Promtail is collecting logs
curl http://localhost:3100/api/prom/label

# 2. Query for application errors
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="docker"}|"ERROR"' \
  --data-urlencode 'start=300' \
  --data-urlencode 'end=900'

# 3. Query for timeouts
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="docker"}|"timeout"'

# 4. Query database errors
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={compose_service=~"orders|carts"}|"connection"'
```

### Verify Traces

```bash
# 1. Check Tempo has traces
curl http://localhost:3200/api/search/trace | jq '.traces[0:5]'

# 2. Generate traffic to create traces
for i in {1..20}; do curl -s http://localhost/ >/dev/null; done

# 3. Check service graph metrics
curl "http://localhost:9090/api/v1/query?query=traces_service_graph_request_total"

# 4. Check span latency metrics
curl "http://localhost:9090/api/v1/query?query=traces_spanmetrics_duration_seconds"

# 5. Check error spans
curl "http://localhost:9090/api/v1/query?query=traces_spanmetrics_duration_bucket{status_code=\"error\"}"
```

---

## 📈 Grafana Dashboards

### Recommended Dashboard Queries

**Metrics Dashboard (CPU, Memory, Throughput)**:
```promql
# Top: CPU Usage by Service
sum(rate(container_cpu_usage_seconds_total{job="cadvisor"}[5m])) by (container_name)

# Middle: Memory Usage by Service
container_memory_working_set_bytes{job="cadvisor"} / 1024 / 1024

# Bottom: Request Throughput
rate(http_requests_total[1m])
```

**Error & Latency Dashboard**:
```promql
# Top: Error Rate
rate(http_requests_total{status=~"5.."}[5m]) * 100

# Middle: P95 Latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Bottom: Error Rate by Service
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
```

**Container Health Dashboard**:
```promql
# Top: Container Restarts
increase(container_last_seen[15m])

# Middle: Container Up/Down
up{job="cadvisor"}

# Bottom: Container Status Changes
changes(container_last_seen[1h])
```

---

## ⚠️ Alerts Configured

All these alerts are automatically registered:

| Alert | Condition | Severity |
|-------|-----------|----------|
| HighErrorRate | 5xx > 10% per minute | email |
| HighErrorRateOnEndpoint | 5xx > 5% per 5m | warning |
| HighRequestLatency | P95 > 1s for 2m | warning |
| P99LatencyHigh | P99 > 2s for 2m | critical |
| ContainerRestarts | Container restart detected | warning |
| HighCPUUsage | CPU > 80% for 2m | warning |
| HighMemoryUsage | Memory > 85% for 2m | warning |
| ServiceDown | Service unreachable for 1m | critical |
| HighTimeoutRate | Timeouts > 10/sec per 5m | warning |
| HighTraceErrorRate | Trace errors > 5% | warning |

---

## 🔄 Collection Flow Diagram

```
Applications with OTEL
        ↓
    ├── Metrics Endpoints ──→ Prometheus (9090)
    ├── Logs (stdout/stderr) → Docker → Promtail → Loki (3100)
    └── Traces (OTLP) ──────→ Tempo (4317/4318)

Infrastructure Exporters
        ↓
    ├── Node Exporter (9100) → Prometheus
    └── cAdvisor (8080) ────→ Prometheus

Prometheus (with remote write to Tempo)
        ↓
    ├── Alerts → Alertmanager (9093)
    └── Metrics + Span Metrics → Grafana (3000)

Tempo
        ↓
    ├── Service Graphs → Prometheus
    ├── Span Metrics → Prometheus
    └── Traces → Grafana/Tempo UI

Loki
        ↓
    └── Logs → Grafana
```

---

## 📝 Configuration Files

- **Metrics**: `prometheus.yml` (scrape configs), `alert.rules` (alerts)
- **Logs**: `promtail-config.yml` (log collection), `loki` settings in docker-compose
- **Traces**: `tempo.yaml` (receivers, processors, exporters)
- **Stacks**: `docker-compose.monitoring.yml` (all observability components)

---

## ✅ Checklist: All Signals Verified

- [x] CPU usage (Node Exporter + cAdvisor)
- [x] Memory usage (Node Exporter + cAdvisor)
- [x] Request latency (OTEL + Tempo metrics)
- [x] Error rate (HTTP status codes + trace spans)
- [x] Service throughput (HTTP request count)
- [x] Container restart count (cAdvisor NEW)
- [x] Application errors (Promtail container logs)
- [x] Timeout exceptions (log pattern matching)
- [x] Service crash logs (Docker event logs)
- [x] Database query errors (application logs)
- [x] Span latency (OTEL spans)
- [x] Request path (HTTP span attributes)
- [x] Service dependencies (Tempo service graphs)
- [x] Error spans (span status tracking)

---

*Last Updated: March 18, 2026*
