# OpenTelemetry Instrumentation for Sock Shop Services

## Current Situation

This repository uses **pre-built Docker images** from the Sock Shop demo. The services don't include OpenTelemetry SDKs, and the images use outdated runtimes:

| Service | Language | Runtime Version | OTel Status |
|---------|----------|----------------|-------------|
| **carts** | Java | Spring Boot | ✅ **Working** (Java agent) |
| **orders** | Java | Spring Boot | ✅ **Working** (Java agent) |
| **shipping** | Java | Spring Boot | ✅ **Working** (Java agent) |
| **queue-master** | Java | Spring Boot | ✅ **Working** (Java agent) |
| **front-end** | Node.js | **v4.8.0** (2017) | ❌ Incompatible with modern OTel |
| **catalogue** | Go | Unknown | ❌ Requires source rebuild |
| **payment** | Go | Unknown | ❌ Requires source rebuild |
| **user** | Go | Unknown | ❌ Requires source rebuild |

## ✅ What's Already Working

### Java Services (Full Distributed Tracing)

The following services are **fully instrumented** and sending traces to Tempo:
- carts
- orders  
- shipping
- queue-master

**How it works:**
```yaml
volumes:
  - /home/user/otel/opentelemetry-javaagent.jar:/otel/opentelemetry-javaagent.jar
environment:
  - JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar
  - OTEL_SERVICE_NAME=carts
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
  - OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

The Java agent automatically instruments:
- HTTP requests
- Database queries
- Inter-service calls
- Spring Boot components

**Verify traces:**
```bash
# Generate traffic
curl http://localhost:80/

# Check traces in Grafana
# http://localhost:3000 → Explore → Tempo
```

## ❌ Why Go and Node.js Services Can't Be Auto-Instrumented

### Problem 1: Source Code Required

Unlike Java (which has a **runtime agent**), Go and Node.js OpenTelemetry instrumentation requires:
1. **Code modifications** - Import OpenTelemetry SDKs
2. **Rebuilding** the application from source
3. **Updating dependencies** in the build process

### Problem 2: Outdated Runtimes

- **front-end**: Uses Node.js v4.8.0 (released 2017, EOL 2018)
- Modern OpenTelemetry requires Node.js v14+ (2020+)

### Problem 3: No Source Code Access

This repository contains only:
- Deployment configurations
- Docker Compose files
- Pre-built image references

The actual service source code is in separate repositories:
- https://github.com/microservices-demo/catalogue
- https://github.com/microservices-demo/user
- https://github.com/microservices-demo/payment
- https://github.com/microservices-demo/front-end

## 🔧 Solutions (Ordered by Effort)

### Option 1: Accept Partial Tracing ✅ CURRENT STATE

**Keep the Java services traced** and accept that Go/Node.js services won't emit traces.

**Pros:**
- Working right now
- Covers 50%+ of service interactions
- Zero additional work

**Cons:**
- Missing traces from catalogue, payment, user, front-end
- Incomplete service graphs

**Recommendation:** Good enough for demo/learning purposes.

---

### Option 2: Use Network-Level Tracing (Service Mesh)

**Deploy Istio or Linkerd** for network-level observability without code changes.

**How it works:**
- Sidecar proxies intercept all HTTP traffic
- Proxies emit traces automatically
- Works with ANY language/runtime

**Implementation:**
```bash
# For Kubernetes deployment
cd deploy/kubernetes
kubectl apply -f <(istioctl kube-inject -f manifests/)
```

**Pros:**
- No code changes required
- Works with old runtimes
- Adds traffic management, security, retries

**Cons:**
- Adds complexity
- Requires Kubernetes
- Adds latency (small)
- Not available in Docker Compose setup

---

### Option 3: Rebuild Services with OTel

**Clone source repos and add instrumentation.**

#### For Go Services (catalogue, payment, user)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/microservices-demo/catalogue.git
   cd catalogue
   ```

2. **Add OpenTelemetry dependencies:**
   ```bash
   go get go.opentelemetry.io/otel
   go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
   go get go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
   ```

3. **Modify main.go:**
   ```go
   import (
       "go.opentelemetry.io/otel"
       "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
       sdktrace "go.opentelemetry.io/otel/sdk/trace"
       "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
   )

   func initTracer() (*sdktrace.TracerProvider, error) {
       exporter, err := otlptracegrpc.New(
           context.Background(),
           otlptracegrpc.WithInsecure(),
           otlptracegrpc.WithEndpoint(os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")),
       )
       if err != nil {
           return nil, err
       }

       tp := sdktrace.NewTracerProvider(
           sdktrace.WithBatcher(exporter),
           sdktrace.WithResource(resource.NewWithAttributes(
               semconv.SchemaURL,
               semconv.ServiceNameKey.String(os.Getenv("OTEL_SERVICE_NAME")),
           )),
       )
       otel.SetTracerProvider(tp)
       return tp, nil
   }

   func main() {
       tp, _ := initTracer()
       defer tp.Shutdown(context.Background())

       // Wrap HTTP handlers
       http.Handle("/", otelhttp.NewHandler(myHandler, "catalogue"))
       
       http.ListenAndServe(":80", nil)
   }
   ```

4. **Build and push:**
   ```bash
   docker build -t weaveworksdemos/catalogue:0.3.5-otel .
   docker push weaveworksdemos/catalogue:0.3.5-otel
   ```

5. **Update docker-compose.yml:**
   ```yaml
   catalogue:
     image: weaveworksdemos/catalogue:0.3.5-otel
   ```

#### For Node.js Service (front-end)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/microservices-demo/front-end.git
   cd front-end
   ```

2. **Upgrade Node.js** in Dockerfile:
   ```dockerfile
   FROM node:18-alpine
   # ... rest of Dockerfile
   ```

3. **Add OpenTelemetry packages:**
   ```bash
   npm install --save \
       @opentelemetry/api \
       @opentelemetry/sdk-node \
       @opentelemetry/auto-instrumentations-node \
       @opentelemetry/exporter-trace-otlp-http
   ```

4. **Create instrumentation.js:**
   ```javascript
   const { NodeSDK } = require('@opentelemetry/sdk-node');
   const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
   const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

   const sdk = new NodeSDK({
       traceExporter: new OTLPTraceExporter(),
       instrumentations: [getNodeAutoInstrumentations()],
   });

   sdk.start();
   ```

5. **Update package.json:**
   ```json
   {
       "scripts": {
           "start": "node --require ./instrumentation.js server.js"
       }
   }
   ```

6. **Build and push:**
   ```bash
   docker build -t weaveworksdemos/front-end:0.3.12-otel .
   docker push weaveworksdemos/front-end:0.3.12-otel
   ```

**Pros:**
- Complete tracing coverage
- Modern best practices
- Full control

**Cons:**
- Significant effort (days of work)
- Need to maintain forks
- Requires Go/Node.js expertise

---

### Option 4: Fork and Modernize

**Create a modernized version of Sock Shop** with current best practices.

This would include:
- Latest Node.js (v20+)
- Latest Go (v1.21+)
- OpenTelemetry built-in
- Updated dependencies
- Modern deployment patterns

**Effort:** Weeks of work

---

## 📊 What You Can See Right Now

With Java services traced, you can already:

1. **View distributed traces** for cart, order, and shipping workflows
2. **See service dependencies** in Grafana service graphs
3. **Correlate metrics with traces** using exemplars
4. **Track request latency** across Java services
5. **Debug errors** by viewing the exact trace

## 🎯 Recommended Next Steps

### For Learning/Demo (Recommended)
1. **Keep current setup** - Java services traced
2. **Generate traffic** and explore Grafana/Tempo
3. **Learn** how distributed tracing works
4. **Experiment** with Tempo queries and service graphs

### For Production Use
1. **Deploy a service mesh** (Istio/Linkerd) for complete coverage
2. **Or** rebuild services with modern OTel instrumentation
3. **Add** continuous profiling (Pyroscope)
4. **Define** SLOs and alerting rules

## 🔍 Verifying Current Tracing

```bash
# 1. Generate traffic
for i in {1..50}; do curl -s http://localhost:80/ >/dev/null; done

# 2. Check Tempo has traces
curl "http://localhost:3200/api/search?limit=10" | jq

# 3. View in Grafana
# Open: http://localhost:3000
# Navigate: Explore → Tempo → Run Query
# You'll see traces from carts, orders, shipping

# 4. View service graph
# Navigate: Explore → Prometheus
# Query: traces_service_graph_request_total
# This shows which services call each other
```

## 📚 Additional Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Original Sock Shop Source](https://github.com/microservices-demo/)
- [Istio Service Mesh](https://istio.io/)

## Summary

**What works:** Java services (carts, orders, shipping, queue-master) have full distributed tracing via OpenTelemetry Java agent.

**What doesn't:** Go and Node.js services can't be auto-instrumented without source code access and rebuilding.

**Best path forward:** Keep the current setup for demo/learning, or deploy a service mesh for production use.
