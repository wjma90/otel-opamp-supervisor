{{- define "o11y-opamp-supervisor.name" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.fullname" -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "o11y-opamp-supervisor.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/component: {{ .Values.component }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "o11y-opamp-supervisor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "o11y-opamp-supervisor.fullname" . }}
{{- end -}}

{{- define "o11y-opamp-supervisor.serviceAccountName" -}}
{{- default (include "o11y-opamp-supervisor.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.headlessServiceName" -}}
{{- default (printf "%s-headless" (include "o11y-opamp-supervisor.fullname" .) | trunc 63 | trimSuffix "-") .Values.statefulSet.headlessService.name -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.namespacedRoleName" -}}
{{- printf "%s-namespaced" (include "o11y-opamp-supervisor.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.clusterRoleName" -}}
{{- default (printf "%s-cluster-monitoring" (include "o11y-opamp-supervisor.fullname" .)) .Values.rbac.clusterRoleName -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.dataClaimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-opamp-data" (include "o11y-opamp-supervisor.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.controlPlaneSecretName" -}}
{{- default (printf "%s-control-plane" (include "o11y-opamp-supervisor.fullname" .)) .Values.controlPlane.existingSecret -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.baseConfig" -}}
{{- required "collector-base/base.yaml must contain the immutable NOP base" (.Files.Get "collector-base/base.yaml") -}}
{{- end -}}

{{- define "o11y-opamp-supervisor.baseConfigName" -}}
{{- $digest := (include "o11y-opamp-supervisor.baseConfig" . | sha256sum | trunc 12) -}}
{{- $prefix := (include "o11y-opamp-supervisor.fullname" . | trunc 45 | trimSuffix "-") -}}
{{- printf "%s-base-%s" $prefix $digest -}}
{{- end -}}
