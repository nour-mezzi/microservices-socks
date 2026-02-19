# Extend the existing catalogue image to add OpenTelemetry instrumentation
# Note: This requires the Go service to be rebuilt with OTel SDK
# This is a placeholder that adds the environment for future instrumentation
FROM golang:1.20-alpine AS otel-builder

# Install OpenTelemetry libraries
RUN apk add --no-cache git && \
    go install go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp@latest && \
    go install go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@latest

# Use the existing catalogue image
FROM weaveworksdemos/catalogue:0.3.5

# Add a startup wrapper script that can be used if needed
USER root
RUN echo '#!/bin/sh' > /usr/local/bin/wrapper.sh && \
    echo 'echo "Service: catalogue - OpenTelemetry environment configured"' >> /usr/local/bin/wrapper.sh && \
    echo 'echo "OTEL_SERVICE_NAME: ${OTEL_SERVICE_NAME}"' >> /usr/local/bin/wrapper.sh && \
    echo 'echo "OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT}"' >> /usr/local/bin/wrapper.sh && \
    echo 'exec /app "$@"' >> /usr/local/bin/wrapper.sh && \
    chmod +x /usr/local/bin/wrapper.sh

USER ${USER:-1000}

# Note: OpenTelemetry will only work if the Go binary is recompiled with OTel SDK
# This image provides the runtime environment but requires source code instrumentation
ENTRYPOINT ["/usr/local/bin/wrapper.sh"]
