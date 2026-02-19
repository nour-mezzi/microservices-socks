# Complete Observability Stack - Explained

## Overview

This microservices application now has a comprehensive observability stack that follows the **Three Pillars of Observability**:
1. **Metrics** - Time-series data (Prometheus)
2. **Logs** - Event records (Loki + Promtail) 
3. **Traces** - Request flows (Tempo + OpenTelemetry)

---

## How Distributed Tracing Works

### Architecture

```
┌────────────┐        ┌────────────┐        ┌────────────┐
│  front-end │───────▶│   carts    │───────▶│  carts-db  │
│  (Node.js) │        │   (Java)   │        │  (MongoDB) │
└─────┬──────┘        └─────┬──────┘        └────────────┘
      │                     │
      │ Trace Context       │ Trace Context
      │ Propagation         │ Propagation
      ▼                     ▼
┌──────────────────────────────────────────┐
│           Tempo (Trace Backend)          │
│  • Receives spans via OTLP & Zipkin      │
│  • Stores traces                         │
│  • Generates service graph metrics       │
└──────────────┬───────────────────────────┘
               │
               │ Metrics from Traces
               ▼
         ┌──────────┐
         │Prometheus│
         └──────────┘
```

### Tracing Implementation by Service

#### Java Services (carts, orders, shipping, queue-master)
**Method**: OpenTelemetry Java Agent + Spring Sleuth

```yaml
volumes:
  - /home/user/otel/opentelemetry-javaagent.jar:/otel/opentelemetry-javaagent.jar
environment:
  # OpenTelemetry Java Agent (automatic instrumentation)
  - JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar
  - OTEL_SERVICE_NAME=carts
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
  - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
  
  # Spring Sleuth (legacy Zipkin support)
  - JAVA_OPTS=-Dspring.zipkin.enabled=true -Dspring.zipkin.baseUrl=http://tempo:9411 -Dspring.sleuth.sampler.percentage=1.0
```

**How it works**:
1. **OpenTelemetry Java Agent** attaches to the JVM at startup
2. **Automatic Instrumentation**: Intercepts HTTP requests, database calls, and other operations
3. **Span Creation**: Creates a trace span for each operation with:
   - Trace ID (unique per request)
   - Span ID (unique per operation)
   - Parent Span ID (for nested operations)
   - Timing data (start/end timestamps)
   - Attributes (HTTP method, status code, etc.)
4. **Context Propagation**: Injects trace context into outgoing HTTP headers (W3C Trace Context format)
5. **Export**: Sends spans to Tempo via gRPC (port 4317)

#### Go Services (catalogue, payment, user)
**Method**: OpenTelemetry environment variables (requires code instrumentation)

```yaml
environment:
  - OTEL_SERVICE_NAME=catalogue
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4318
  - OTEL_TRACES_EXPORTER=otlp
```

**Status**: ⚠️ **Partially Configured**
- Environment variables are set
- **However**: Pre-built Docker images may not have OpenTelemetry SDK included
- **To fully enable**: Services need to import `go.opentelemetry.io/otel` and instrument HTTP handlers

**What's needed for full tracing**:
```go
// Example for Go services
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Wrap HTTP handlers
handler = otelhttp.NewHandler(handler, "catalogue")
```

#### Node.js Service (front-end)
**Method**: OpenTelemetry auto-instrumentation

```yaml
environment:
  - OTEL_SERVICE_NAME=front-end
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4318
  - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
  - NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register
```

**Status**: ⚠️ **Partially Configured**
- Environment variables configured
- **However**: Pre-built image may not have `@opentelemetry/auto-instrumentations-node` package installed
- **To fully enable**: Rebuild image with OpenTelemetry dependencies

**What's needed**:
```bash
npm install --save @opentelemetry/auto-instrumentations-node
npm install --save @opentelemetry/exporter-trace-otlp-http
```

---

## Tempo Configuration

### Receivers
Tempo accepts traces in multiple formats:

| Protocol | Port | Used By |
|----------|------|---------|
| OTLP gRPC | 4317 | Java services (primary) |
| OTLP HTTP | 4318 | Go & Node.js services |
| Zipkin | 9411 | Java services (Spring Sleuth) |

### Metrics Generator
Tempo's unique feature: **Generates metrics FROM traces**

```yaml
metrics_generator:
  processor:
    service_graphs:        # Creates service-to-service call graphs
      enable_client_server_prefix: true
    span_metrics:         # Latency & error rate metrics
      dimensions:
        - service.namespace
  storage:
    remote_write:
      - url: http://prometheus:9090/api/v1/write  # Push to Prometheus
```

**Generated Metrics**:
- `traces_service_graph_request_total` - Request count between services
- `traces_spanmetrics_latency_bucket` - Request duration histograms
- `traces_spanmetrics_calls_total` - Total spans by service

---

## Current Observability Stack

### ✅ What You Have

| Component | Purpose | Status |
|-----------|---------|--------|
| **Prometheus** | Metrics collection & storage | ✅ Active |
| **Grafana** | Visualization dashboard | ✅ Active |
| **Tempo** | Distributed tracing backend | ✅ Active |
| **Loki** | Log aggregation | ✅ Active |
| **Promtail** | Log collection agent | ✅ Active |
| **Node Exporter** | System metrics | ✅ Active |
| **Alertmanager** | Alert routing | ✅ Active |

### ⚠️ What's Partially Working

| Service | Issue | Solution |
|---------|-------|----------|
| **Go Services** | Images don't have OTel SDK | Rebuild with instrumentation |
| **front-end** | Missing OTel Node.js packages | Rebuild with dependencies |
| **edge-router** | No tracing support (nginx) | Add OpenTelemetry nginx module |

---

## Missing Components for Full Observability

### 1. ❌ **Application Performance Monitoring (APM) Features**

**What's missing**:
- **Database query tracing**: Can't see slow SQL queries in traces
- **Continuous profiling**: No CPU/memory profiling
- **Real User Monitoring (RUM)**: No browser-side tracing

**Recommendation**: Add **Pyroscope** for continuous profiling

```yaml
pyroscope:
  image: grafana/pyroscope:latest
  ports:
    - 4040:4040
```

### 2. ❌ **Error Tracking & Exception Monitoring**

**What's missing**:
- No centralized exception tracking
- Can't group similar errors
- No stack trace enrichment with source code

**Recommendation**: Add **Sentry** or use Loki's error aggregation

```yaml
environment:
  - SENTRY_DSN=https://your-sentry-dsn
  - SENTRY_TRACES_SAMPLE_RATE=1.0
```

### 3. ❌ **Log-Trace Correlation**

**Issue**: Logs and traces are separate; can't jump from log to trace

**Recommendation**: Add trace context to logs

**For Java services**:
```yaml
environment:
  - JAVA_OPTS=-Dlogging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} [%X{traceId}/%X{spanId}] %-5level %logger{36} - %msg%n
```

**For Go services**:
```go
logger.Info("processing request",
    "traceID", span.SpanContext().TraceID().String(),
    "spanID", span.SpanContext().SpanID().String(),
)
```

### 4. ❌ **Synthetic Monitoring**

**What's missing**: Proactive endpoint checks from multiple locations

**Recommendation**: Add **Blackbox Exporter**

```yaml
blackbox:
  image: prom/blackbox-exporter
  ports:
    - 9115:9115
  volumes:
    - ./blackbox.yml:/etc/blackbox/config.yml
```

```yaml
# blackbox.yml
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: ip4
```

### 5. ❌ **Service Level Objectives (SLOs)**

**What's missing**: Defined SLOs and error budgets

**Recommendation**: Use **Sloth** to generate SLO rules

```yaml
# slo.yml
slos:
  - name: cart-availability
    objective: 99.9
    description: Cart service availability
    sli:
      error_query: rate(http_requests_total{job="carts",code=~"5.."}[5m])
      total_query: rate(http_requests_total{job="carts"}[5m])
```

### 6. ❌ **Security Monitoring**

**What's missing**:
- No authentication/authorization tracking
- No anomaly detection
- No audit logs

**Recommendation**: Add **Falco** for runtime security

### 7. ❌ **Network Observability**

**What's missing**: Layer 4 network metrics (TCP retransmits, connection states)

**Recommendation**: Add **eBPF-based monitoring** with **Cilium** or **Pixie**

### 8. ❌ **Business Metrics**

**What's missing**: Application-specific metrics (orders/sec, revenue, etc.)

**Recommendation**: Add custom metrics to services

**Example**:
```java
// In Java services
@Autowired
MeterRegistry registry;

Counter.builder("orders.placed")
    .description("Number of orders placed")
    .register(registry).increment();
```

### 9. ❌ **Cost Monitoring**

**What's missing**: Resource cost tracking (if running in cloud)

**Recommendation**: Add **OpenCost** for Kubernetes cost monitoring

### 10. ❌ **Change Tracking**

**What's missing**: Correlation of deployments with metric changes

**Recommendation**: Add deployment annotations to Grafana

```bash
# Post-deployment
curl -X POST http://grafana:3000/api/annotations \
  -d '{
    "text": "Deployed cart service v2.0",
    "tags": ["deployment", "carts"]
  }'
```

---

## Recommended Priority Fixes

### High Priority (Do First)

1. **Rebuild Go services with OpenTelemetry instrumentation**
   - Enables complete distributed tracing
   - Critical for understanding service interactions

2. **Add trace-log correlation**
   - Inject trace IDs into logs
   - Makes debugging 10x faster

3. **Configure database query tracing**
   - See which queries are slow
   - Often the root cause of performance issues

### Medium Priority

4. **Add continuous profiling (Pyroscope)**
   - Identify CPU/memory hotspots
   - Useful for optimization

5. **Set up proper alerting rules**
   - Define SLOs
   - Alert on SLO violations

6. **Add synthetic monitoring**
   - Catch issues before users do

### Low Priority (Nice to Have)

7. **Add error tracking (Sentry)**
8. **Business metrics instrumentation**
9. **Security monitoring**

---

## How to Verify Tracing is Working

### 1. Check Java Services (should work immediately)

```bash
# Generate some traffic
curl http://localhost:80/

# Check Tempo has traces
curl http://localhost:3200/api/search?limit=10

# View in Grafana
# Go to: http://localhost:3000
# Explore > Tempo > Query
```

### 2. View Service Graph

```
Grafana > Explore > Prometheus > Query:
traces_service_graph_request_total
```

This shows requests between services as a graph.

### 3. Correlate Metrics & Traces

In Grafana, you can:
- See a spike in latency in Prometheus
- Click "Exemplars" to jump to the actual trace in Tempo
- See the exact request that was slow

---

## Data Flow Summary

```
User Request → edge-router → front-end → catalogue/carts/orders/etc.
                    ↓              ↓              ↓
                Logs only     Traces (if       Traces + Metrics
                              instrumented)    (Java: working)
                    ↓              ↓              ↓
                Promtail       Tempo          Tempo
                    ↓              ↓              ↓
                Loki           Storage     Metrics Generator
                                               ↓
                                          Prometheus
                                               ↓
                          ┌──────────┬─────────┴─────────┐
                          ↓          ↓                   ↓
                      Grafana    Alertmanager      Service Graph
```

---

## Next Steps

1. **Immediate**: Restart services to apply tracing configuration
   ```bash
   cd /home/user/microservices-demo/deploy/docker-compose
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
   ```

2. **Short-term**: Rebuild Go and Node.js services with OpenTelemetry SDKs

3. **Long-term**: Add missing observability components based on priorities above

---

## Summary

### What Works Now ✅
- **Java services**: Full distributed tracing via OpenTelemetry
- **Tempo**: Collecting, storing, and visualizing traces
- **Service graphs**: Automatic from trace data
- **Metrics**: Prometheus collecting from all services
- **Logs**: Loki aggregating Docker container logs

### What Needs Code Changes ⚠️
- **Go services**: Need OpenTelemetry SDK integrated in code
- **Node.js front-end**: Needs OpenTelemetry packages installed
- **edge-router**: Needs nginx OpenTelemetry module

### What's Missing Completely ❌
- Continuous profiling
- Error tracking system
- Log-trace correlation
- Synthetic monitoring
- Defined SLOs
- Business metrics
- Security monitoring
- Network-level observability
- Cost tracking
- Deployment tracking

---

## Conclusion

You have a **solid foundation** for observability with the three pillars (metrics, logs, traces) in place. The Java services are fully traced, but Go and Node.js services need code-level instrumentation to emit traces.

To achieve **full-stack observability**, prioritize:
1. Completing trace instrumentation for all services
2. Adding profiling for performance optimization  
3. Implementing SLOs for reliability tracking
4. Correlating logs with traces for faster debugging

This will give you **end-to-end visibility** into your microservices architecture and enable you to:
- Debug production issues in minutes instead of hours
- Optimize performance with data-driven decisions
- Proactively detect issues before users notice
- Track the business impact of technical changes
