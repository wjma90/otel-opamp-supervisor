# syntax=docker/dockerfile:1.7

ARG OTEL_VERSION=0.156.0
ARG OTEL_COLLECTOR_DIGEST=sha256:125bdbeb7590cc1952c5b3430ecf14063568980c2c93d5b38676cc0446ed8108
ARG OTEL_SUPERVISOR_DIGEST=sha256:cc645f204fdcd03bb119180b7f7a30c2c19febfcbefde3b59f1576cd021550f6

FROM otel/opentelemetry-collector-contrib:${OTEL_VERSION}@${OTEL_COLLECTOR_DIGEST} AS collector
FROM ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-opampsupervisor:${OTEL_VERSION}@${OTEL_SUPERVISOR_DIGEST} AS supervisor

FROM supervisor AS assembled

COPY --from=collector --chmod=0555 /otelcol-contrib /usr/local/bin/otelcol-contrib
COPY --chmod=0755 otelcol-contrib-wrapper.sh /usr/local/bin/otelcol-contrib-wrapper

FROM scratch AS runtime

COPY --from=assembled / /

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /home/opampsupervisor
USER 10001:10001
EXPOSE 13133 13134 4317 4318

ENTRYPOINT ["/usr/local/bin/opampsupervisor"]
