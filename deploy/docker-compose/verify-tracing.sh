#!/bin/bash
# Verify OpenTelemetry tracing is working

set -e

echo "========================================="
echo "OpenTelemetry Tracing Verification"
echo "========================================="
echo ""

# Check if services are running
echo "1. Checking if services are running..."
if ! docker ps | grep -q "tempo"; then
    echo "❌ Tempo container not running!"
    echo "   Run: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
    exit 1
fi
echo "✅ Tempo is running"
echo ""

# Generate some traffic
echo "2. Generating traffic to create traces..."
for i in {1..20}; do
    curl -s http://localhost:80/ >/dev/null 2>&1 || true
done
echo "✅ Traffic generated"
echo ""

# Wait for traces to be processed
echo "3. Waiting for traces to be processed..."
sleep 3
echo ""

# Check if Tempo has traces
echo "4. Checking Tempo for traces..."
TRACE_COUNT=$(curl -s "http://localhost:3200/api/search?limit=100" 2>/dev/null | jq -r '.traces | length' 2>/dev/null || echo "0")

if [ "$TRACE_COUNT" = "0" ] || [ "$TRACE_COUNT" = "null" ]; then
    echo "⚠️  No traces found yet. This might be normal if:"
    echo "   - Services just started (wait 1-2 minutes)"
    echo "   - No Java services were called"
    echo "   - Tempo is still initializing"
    echo ""
    echo "   Try running this script again in a minute."
else
    echo "✅ Found $TRACE_COUNT traces in Tempo!"
    echo ""
    echo "   Sample traces:"
    curl -s "http://localhost:3200/api/search?limit=5" 2>/dev/null | \
        jq -r '.traces[0:3][] | "   • Trace ID: \(.traceID[0:16])... | Service: \(.rootServiceName) | Duration: \(.durationMs)ms"' 2>/dev/null || true
fi
echo ""

# Check service graph metrics
echo "5. Checking service graph metrics..."
SERVICE_GRAPH=$(curl -s "http://localhost:9090/api/v1/query?query=traces_service_graph_request_total" 2>/dev/null | \
    jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$SERVICE_GRAPH" != "0" ]; then
    echo "✅ Service graph metrics available! ($SERVICE_GRAPH series)"
    echo ""
    echo "   Service relationships detected:"
    curl -s "http://localhost:9090/api/v1/query?query=traces_service_graph_request_total" 2>/dev/null | \
        jq -r '.data.result[0:5][] | "   • \(.metric.client) → \(.metric.server)"' 2>/dev/null || true
else
    echo "⚠️  No service graph metrics yet"
    echo "   These are generated from traces and may take a few minutes"
fi
echo ""

# Check which services are traced
echo "6. Services with tracing enabled:"
echo ""
echo "   ✅ carts (Java + OpenTelemetry agent)"
echo "   ✅ orders (Java + OpenTelemetry agent)"  
echo "   ✅ shipping (Java + OpenTelemetry agent)"
echo "   ✅ queue-master (Java + OpenTelemetry agent)"
echo ""
echo "   ⚠️  front-end (Node.js v4.8.0 - incompatible with modern OTel)"
echo "   ⚠️  catalogue (Go - requires source rebuild)"
echo "   ⚠️  payment (Go - requires source rebuild)"
echo "   ⚠️  user (Go - requires source rebuild)"
echo ""

echo "========================================="
echo "How to View Traces"
echo "========================================="
echo ""
echo "Grafana (Recommended):"
echo "  1. Open: http://localhost:3000"
echo "  2. Login: admin / foobar"
echo "  3. Navigate: Explore → Tempo"
echo "  4. Click 'Run Query' or search by service name"
echo ""
echo "Service Graph:"
echo "  1. Open: http://localhost:3000"
echo "  2. Navigate: Explore → Prometheus"
echo "  3. Query: traces_service_graph_request_total"
echo "  4. Visualization: Graph"
echo ""
echo "Tempo API:"
echo "  curl 'http://localhost:3200/api/search?limit=10' | jq"
echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "See TRACING-README.md for:"
echo "  • Why Go/Node.js services can't be auto-instrumented"
echo "  • How to add full tracing (requires source code)"
echo "  • Alternative solutions (service mesh)"
echo ""
