#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chart=$(CDPATH= cd -- "$script_dir/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

expect_failure() {
  name=$1
  shift
  if helm template "$name" "$chart" -n o11y "$@" \
    >"$test_dir/$name.yaml" 2>&1; then
    echo "$name unexpectedly rendered" >&2
    exit 1
  fi
}

cat >"$test_dir/stateful-values.yaml" <<'EOF'
fullnameOverride: o11y-prod
mode: statefulset
identity:
  serviceName: o11y-prod-supervisor
  clusterName: prod
  collectorRole: traces-backend
  baseConfigId: collector-base.prod.traces
workload:
  replicas: 3
statefulSet:
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 1
  persistentVolumeClaimRetentionPolicy:
    enabled: true
    whenDeleted: Retain
    whenScaled: Delete
  headlessService:
    name: otel-backends-traces-collector-headless
    publishNotReadyAddresses: true
    annotations:
      o11y.dev/discovery: traces
    labels:
      o11y.dev/tier: backend
serviceAccount:
  create: false
  name: otelcol-prod
rbac:
  namespacedRules:
    - apiGroups:
        - ""
      resources:
        - endpoints
      verbs:
        - get
        - list
        - watch
podLabels:
  o11y.dev/signal: traces
imagePullSecrets:
  - name: registry-credentials
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: group
              operator: In
              values:
                - traces
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: o11y-prod
persistence:
  enabled: true
  size: 10Gi
  storageClass: managed-premium
  annotations:
    o11y.dev/storage-purpose: supervisor-state
  labels:
    o11y.dev/storage-tier: premium
extraVolumeClaimTemplates:
  - metadata:
      name: storage-vol
      labels:
        o11y.dev/storage-purpose: sending-queue
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: managed-premium
      resources:
        requests:
          storage: 8Gi
  - metadata:
      name: wal-vol
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: managed-premium
      resources:
        requests:
          storage: 4Gi
extraVolumes:
  - name: tls-certs
    secret:
      secretName: otel-collector-tls
  - name: collector-overrides
    configMap:
      name: otel-collector-overrides
extraVolumeMounts:
  - name: tls-certs
    mountPath: /etc/o11y/certs
    readOnly: true
  - name: collector-overrides
    mountPath: /etc/o11y/overrides
    readOnly: true
  - name: storage-vol
    mountPath: /etc/otel/storage
  - name: wal-vol
    mountPath: /etc/otel/wal
extraEnv:
  - name: GRAFANA_CLOUD_OTLP_PASSWORD
    valueFrom:
      secretKeyRef:
        name: grafana-cloud-otlp
        key: password
  - name: COLLECTOR_TENANT
    valueFrom:
      configMapKeyRef:
        name: collector-runtime
        key: tenant
extraEnvFrom:
  - configMapRef:
      name: collector-runtime
  - secretRef:
      name: collector-runtime-secret
initContainers:
  - name: prepare-storage
    image: busybox:1.36
    command:
      - sh
      - -c
      - mkdir -p /etc/otel/storage /etc/otel/wal
    volumeMounts:
      - name: storage-vol
        mountPath: /etc/otel/storage
      - name: wal-vol
        mountPath: /etc/otel/wal
collector:
  featureGates:
    - exporter.prometheusremotewritexporter.RetryOn429
    - exporter.prometheusremotewritexporter.EnableMultipleWorkers
otlpPorts:
  enabled: true
extraContainerPorts:
  - name: monitoring
    containerPort: 8888
    protocol: TCP
service:
  enabled: true
  annotations:
    o11y.dev/exposure: internal
  labels:
    o11y.dev/signal: traces
  extraPorts:
    - name: monitoring
      port: 8888
      targetPort: monitoring
      protocol: TCP
serviceMonitor:
  enabled: true
  labels:
    prometheus: platform
  interval: 60s
  scrapeTimeout: 40s
  port: monitoring
EOF

cat >"$test_dir/deployment-persistence.yaml" <<'EOF'
mode: deployment
persistence:
  enabled: true
  size: 1Gi
  storageClass: standard
EOF

cat >"$test_dir/invalid-vct.yaml" <<'EOF'
mode: deployment
extraVolumeClaimTemplates:
  - metadata:
      name: storage
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
EOF

cat >"$test_dir/invalid-volume-collision.yaml" <<'EOF'
mode: statefulset
extraVolumes:
  - name: opamp-data
    emptyDir: {}
EOF

cat >"$test_dir/invalid-service-target.yaml" <<'EOF'
service:
  enabled: true
  extraPorts:
    - name: monitoring
      port: 8888
      targetPort: missing-port
EOF

helm lint --strict "$chart"
helm lint --strict "$chart" -f "$test_dir/stateful-values.yaml"

helm template deployment-mode "$chart" -n o11y \
  >"$test_dir/deployment.yaml"
helm template daemonset-mode "$chart" -n o11y \
  --set fullnameOverride=o11y-monitoring-supervisor \
  --set mode=daemonset \
  --set rbac.clusterMonitoring=true \
  --set hostMonitoring.enabled=true \
  --set identity.serviceName=o11y-monitoring-supervisor \
  --set identity.collectorRole=cluster-monitoring \
  --set identity.baseConfigId=collector-base.local.monitoring \
  >"$test_dir/daemonset.yaml"
helm template statefulset-mode "$chart" -n o11y \
  -f "$test_dir/stateful-values.yaml" >"$test_dir/statefulset.yaml"
helm template deployment-persistence "$chart" -n o11y \
  -f "$test_dir/deployment-persistence.yaml" \
  >"$test_dir/deployment-persistence-rendered.yaml"
helm template legacy-image "$chart" -n o11y \
  --set image.tag=0.4.1 >"$test_dir/legacy-image.yaml"
helm template long-name "$chart" -n o11y \
  --set-string fullnameOverride=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >"$test_dir/long-name.yaml"
helm template warn-log "$chart" -n o11y \
  --set telemetry.logs.level=warn >"$test_dir/warn-log.yaml"
helm template tls-mode "$chart" -n o11y \
  --set controlPlane.endpoint=https://control-plane.o11y.svc.cluster.local:4320/v1/opamp \
  --set controlPlane.tls.enabled=true \
  --set controlPlane.tls.existingSecret=opamp-server-ca \
  >"$test_dir/tls.yaml"

for rendered in \
  "$test_dir/deployment.yaml" \
  "$test_dir/daemonset.yaml" \
  "$test_dir/statefulset.yaml"; do
  configmap_count=$(rg -c '^kind: ConfigMap$' "$rendered")
  if [ "$configmap_count" -ne 2 ]; then
    echo "render must contain exactly the Supervisor and immutable base ConfigMaps" >&2
    exit 1
  fi
  if rg -q 'Authorization:|name: OPAMP_TOKEN|^kind: Secret$' "$rendered"; then
    echo "disabled auth mode must omit Authorization, token env and generated Secret" >&2
    exit 1
  fi
  if rg -qi 'supervisor/bootstrap|BOOTSTRAP_|bootstrap-data|managed\.yaml' "$rendered"; then
    echo "render must not retain runtime bootstrap or a local managed config" >&2
    exit 1
  fi
  rg -q 'helm.sh/resource-policy: keep' "$rendered"
  rg -q 'o11y.dev/protected-from-control-plane: "true"' "$rendered"
  rg -q '^immutable: true$' "$rendered"
  rg -q 'base.yaml: |' "$rendered"
  rg -q 'supervisor.yaml: |' "$rendered"
  rg -q 'X-O11y-Supervisor-Version: 0.5.4' "$rendered"
  rg -q 'X-O11y-Collector-Version: 0.156.0' "$rendered"
  rg -q 'X-O11y-Base-Config-ID: collector-base\.' "$rendered"
  rg -q 'X-O11y-Base-Config-Revision: "1"' "$rendered"
  rg -q 'X-O11y-Base-Config-Default: "true"' "$rendered"
  rg -q 'X-O11y-Base-Config-Source: ConfigMap/o11y/' "$rendered"
  rg -q 'X-O11y-Base-Config-Managed-By: kubernetes' "$rendered"
  rg -q 'accepts_remote_config: true' "$rendered"
  rg -q 'level: info' "$rendered"
  if rg -q 'ca_file:|mountPath: /etc/o11y/opamp-tls' "$rendered"; then
    echo "default TLS-disabled render must not mount a CA" >&2
    exit 1
  fi
  rg -q 'mountPath: /etc/otelcol/base.yaml' "$rendered"
  rg -q 'name: O11Y_COLLECTOR_FEATURE_GATES' "$rendered"
  rg -q 'receivers:' "$rendered"
  rg -Fq 'nop: {}' "$rendered"
  rg -q 'image: "wjma90/o11y-opamp-supervisor:0.5.4"' "$rendered"
done

rg -q '^kind: Deployment$' "$test_dir/deployment.yaml"
rg -q '^  replicas: 1$' "$test_dir/deployment.yaml"
rg -q '^    type: Recreate$' "$test_dir/deployment.yaml"
if rg -q '^kind: Service$|^kind: StatefulSet$|^kind: PersistentVolumeClaim$' \
  "$test_dir/deployment.yaml"; then
  echo "default Deployment render gained stateful or persistence resources" >&2
  exit 1
fi

rg -q 'X-O11y-Supervisor-Version: 0.4.1' "$test_dir/legacy-image.yaml"
rg -q 'app.kubernetes.io/version: "0.4.1"' "$test_dir/legacy-image.yaml"
rg -q 'image: "wjma90/o11y-opamp-supervisor:0.4.1"' "$test_dir/legacy-image.yaml"
rg -q '^  name: [a-z0-9-]{1,45}-base-[a-f0-9]{12}$' \
  "$test_dir/long-name.yaml"
rg -q 'level: warn' "$test_dir/warn-log.yaml"
rg -q 'ca_file: /etc/o11y/opamp-tls/ca.crt' "$test_dir/tls.yaml"
rg -q 'mountPath: /etc/o11y/opamp-tls' "$test_dir/tls.yaml"
rg -q 'secretName: "opamp-server-ca"' "$test_dir/tls.yaml"
if rg -q '^kind: Secret$' "$test_dir/tls.yaml"; then
  echo "TLS mode unexpectedly generated a Secret" >&2
  exit 1
fi

rg -q '^kind: DaemonSet$' "$test_dir/daemonset.yaml"
rg -q 'mountPath: /hostfs' "$test_dir/daemonset.yaml"
rg -q 'nodes/proxy' "$test_dir/daemonset.yaml"
if rg -q '^kind: StatefulSet$|^kind: PersistentVolumeClaim$' \
  "$test_dir/daemonset.yaml"; then
  echo "DaemonSet render gained stateful or persistence resources" >&2
  exit 1
fi

stateful="$test_dir/statefulset.yaml"
rg -q '^kind: StatefulSet$' "$stateful"
rg -q '^  replicas: 3$' "$stateful"
rg -q '^  serviceName: otel-backends-traces-collector-headless$' "$stateful"
rg -q '^  podManagementPolicy: Parallel$' "$stateful"
rg -q '^    whenDeleted: Retain$' "$stateful"
rg -q '^    whenScaled: Delete$' "$stateful"
rg -q '^  volumeClaimTemplates:$' "$stateful"
rg -q '^        name: opamp-data$' "$stateful"
rg -q '^    - metadata:$' "$stateful"
rg -q '^        name: storage-vol$' "$stateful"
rg -q '^        name: wal-vol$' "$stateful"
if rg -q '^kind: PersistentVolumeClaim$' "$stateful"; then
  echo "StatefulSet persistence must use volumeClaimTemplates, not a standalone PVC" >&2
  exit 1
fi
if awk '
    capture && /^---$/ { exit }
    /^  volumeClaimTemplates:$/ { capture=1 }
    capture { print }
  ' "$stateful" | rg -q 'helm.sh/chart:|app.kubernetes.io/version:'; then
  echo "volumeClaimTemplates must not contain release-version labels because the template is immutable" >&2
  exit 1
fi
rg -q '^  clusterIP: None$' "$stateful"
rg -q '^  name: otel-backends-traces-collector-headless$' "$stateful"
rg -q '^      serviceAccountName: otelcol-prod$' "$stateful"
if rg -q '^kind: ServiceAccount$' "$stateful"; then
  echo "external ServiceAccount mode unexpectedly created a ServiceAccount" >&2
  exit 1
fi
rg -q '^kind: Role$' "$stateful"
rg -q '^kind: RoleBinding$' "$stateful"
if rg -q '^kind: ClusterRole$|^kind: ClusterRoleBinding$' "$stateful"; then
  echo "namespaced RBAC unexpectedly created cluster-wide permissions" >&2
  exit 1
fi
rg -q '^kind: ServiceMonitor$' "$stateful"
rg -q '^[[:space:]]+o11y.dev/service-role: primary$' "$stateful"
rg -q '^[[:space:]]+- key: group$' "$stateful"
rg -q '^[[:space:]]+topologySpreadConstraints:$' "$stateful"
rg -q '^[[:space:]]+imagePullSecrets:$' "$stateful"
rg -q '^[[:space:]]+initContainers:$' "$stateful"
rg -q '^[[:space:]]+name: prepare-storage$' "$stateful"
rg -q '^[[:space:]]+secretName: otel-collector-tls$' "$stateful"
rg -q '^[[:space:]]+name: otel-collector-overrides$' "$stateful"
rg -q '^[[:space:]]+secretKeyRef:$' "$stateful"
rg -q '^[[:space:]]+configMapKeyRef:$' "$stateful"
rg -q '^[[:space:]]+envFrom:$' "$stateful"
rg -q '^[[:space:]]+name: collector-runtime-secret$' "$stateful"
rg -q '^[[:space:]]+- name: O11Y_COLLECTOR_FEATURE_GATES$' "$stateful"
rg -Fq 'exporter.prometheusremotewritexporter.RetryOn429,exporter.prometheusremotewritexporter.EnableMultipleWorkers' "$stateful"
rg -q '^[[:space:]]+- name: monitoring$' "$stateful"
rg -q '^[[:space:]]+o11y.dev/service-role: headless$' "$stateful"

deployment_pvc="$test_dir/deployment-persistence-rendered.yaml"
rg -q '^kind: Deployment$' "$deployment_pvc"
rg -q '^kind: PersistentVolumeClaim$' "$deployment_pvc"
rg -q '^            claimName: o11y-opamp-supervisor-opamp-data$' "$deployment_pvc"

helm template token-mode "$chart" -n o11y \
  --set controlPlane.authMode=token \
  --set controlPlane.existingSecret=opamp-auth >"$test_dir/token.yaml"
if rg -q '^kind: Secret$' "$test_dir/token.yaml"; then
  echo "existingSecret mode unexpectedly generated a Secret" >&2
  exit 1
fi
rg -q 'name: OPAMP_TOKEN' "$test_dir/token.yaml"
rg -q 'secretKeyRef:' "$test_dir/token.yaml"
rg -q 'name: opamp-auth' "$test_dir/token.yaml"
rg -Fq 'Authorization: Bearer ${env:OPAMP_TOKEN}' "$test_dir/token.yaml"

expect_failure invalid-auth --set-string controlPlane.token=must-not-render
expect_failure missing-token --set controlPlane.authMode=token
expect_failure invalid-log-level --set telemetry.logs.level=verbose
expect_failure missing-tls-secret \
  --set controlPlane.endpoint=https://control-plane:4320/v1/opamp \
  --set controlPlane.tls.enabled=true
expect_failure tls-over-http \
  --set controlPlane.tls.enabled=true \
  --set controlPlane.tls.existingSecret=opamp-server-ca
expect_failure ignored-tls-secret \
  --set controlPlane.tls.existingSecret=opamp-server-ca
expect_failure invalid-collector --set collector.version=0.157.0
expect_failure daemonset-persistence \
  --set mode=daemonset --set persistence.enabled=true
expect_failure replicated-deployment-persistence \
  --set mode=deployment --set workload.replicas=2 \
  --set persistence.enabled=true
expect_failure stateful-existing-claim \
  --set mode=statefulset --set persistence.enabled=true \
  --set persistence.existingClaim=shared-data
expect_failure missing-external-service-account \
  --set serviceAccount.create=false
expect_failure deployment-vct -f "$test_dir/invalid-vct.yaml"
expect_failure volume-collision -f "$test_dir/invalid-volume-collision.yaml"
expect_failure service-target -f "$test_dir/invalid-service-target.yaml"
expect_failure invalid-feature-gate \
  --set-json 'collector.featureGates=["valid.gate","unsafe,gate"]'
expect_failure invalid-feature-gate-space \
  --set-json 'collector.featureGates=["unsafe gate"]'
expect_failure feature-gate-with-legacy-image \
  --set image.tag=0.4.1 \
  --set-json 'collector.featureGates=["valid.gate"]'
expect_failure missing-monitoring-service \
  --set serviceMonitor.enabled=true
