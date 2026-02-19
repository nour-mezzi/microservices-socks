#!/bin/bash
# Build custom Docker images with OpenTelemetry instrumentation

set -e

cd "$(dirname "$0")"

echo "========================================="
echo "Building Custom Images with OpenTelemetry"
echo "========================================="

# Build front-end with Node.js auto-instrumentation
echo ""
echo "Building front-end with OTel..."
docker build -t weaveworksdemos/front-end:0.3.12-otel \
    ./custom-images/front-end/

# Build Go services (placeholders - require source code for full instrumentation)
echo ""
echo "Building catalogue with OTel environment..."
docker build -t weaveworksdemos/catalogue:0.3.5-otel \
    ./custom-images/catalogue/

echo ""
echo "Building payment with OTel environment..."
docker build -t weaveworksdemos/payment:0.4.3-otel \
    ./custom-images/payment/

echo ""
echo "Building user with OTel environment..."
docker build -t weaveworksdemos/user:0.4.4-otel \
    ./custom-images/user/

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "Images built:"
echo "  - weaveworksdemos/front-end:0.3.12-otel"
echo "  - weaveworksdemos/catalogue:0.3.5-otel"
echo "  - weaveworksdemos/payment:0.4.3-otel"
echo "  - weaveworksdemos/user:0.4.4-otel"
echo ""
echo "Next steps:"
echo "  1. Update docker-compose.yml to use -otel tagged images"
echo "  2. Run: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
echo ""
