# Extend the existing front-end image to add OpenTelemetry auto-instrumentation
# Note: The base image uses an old Node.js version (4.8.0) which doesn't support modern OTel
# This approach creates a multi-stage build with a newer Node.js base

FROM node:14-alpine AS otel-base

WORKDIR /app

# Install OpenTelemetry packages in a compatible Node.js environment
RUN npm install --production \
    @opentelemetry/api@^1.4.0 \
    @opentelemetry/sdk-node@^0.41.0 \
    @opentelemetry/auto-instrumentations-node@^0.39.0 \
    @opentelemetry/exporter-trace-otlp-http@^0.41.0

# Use the base image but this will have limitations due to old Node.js version
FROM weaveworksdemos/front-end:0.3.12

USER root

# Copy OTel modules from the compatible Node version
# Note: This may not work due to Node.js version incompatibility
# A proper fix requires updating the base image's Node.js version
COPY --from=otel-base /app/node_modules /usr/src/app/node_modules

USER node

# The environment variables in docker-compose.yml will configure OTel
# However, full functionality requires the service to be rebuilt with modern Node.js
