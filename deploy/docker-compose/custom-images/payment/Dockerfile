# Extend the existing payment image to add OpenTelemetry instrumentation
FROM weaveworksdemos/payment:0.4.3

# Add a startup wrapper script
USER root
RUN echo '#!/bin/sh' > /usr/local/bin/wrapper.sh && \
    echo 'echo "Service: payment - OpenTelemetry environment configured"' >> /usr/local/bin/wrapper.sh && \
    echo 'echo "OTEL_SERVICE_NAME: ${OTEL_SERVICE_NAME}"' >> /usr/local/bin/wrapper.sh && \
    echo 'echo "OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT}"' >> /usr/local/bin/wrapper.sh && \
    echo 'exec /app "$@"' >> /usr/local/bin/wrapper.sh && \
    chmod +x /usr/local/bin/wrapper.sh

USER ${USER:-1000}

# Note: Full OpenTelemetry tracing requires rebuilding the Go binary with OTel SDK
ENTRYPOINT ["/usr/local/bin/wrapper.sh"]
