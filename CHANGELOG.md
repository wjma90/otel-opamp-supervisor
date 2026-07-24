# Changelog

## Unreleased

## Chart 0.5.2 - 2026-07-24

- Expone `controlPlane.tls` y renderiza `server.tls.ca_file` para confiar en
  una CA privada o autofirmada montada desde un Secret existente.
- Exige endpoint HTTPS y no monta CA alguna cuando la capacidad está
  desactivada. La imagen del Supervisor permanece en `0.5.0`.

## Chart 0.5.1 - 2026-07-23

- Expone y valida `telemetry.logs.level` para el proceso Supervisor con los
  niveles `debug`, `info`, `warn` y `error`.
- Conserva `info` como valor por defecto; cada despliegue puede reducir el
  ruido sin modificar la configuración remota del Collector.

## 0.5.0 - 2026-07-21

- Agrega `mode: statefulset` con Service headless, estrategias de actualización,
  política de retención y PVC `opamp-data` independiente por réplica.
- Incorpora claims adicionales para queue/WAL, referencias a ConfigMaps y
  Secrets existentes, env/envFrom, init containers, afinidad, topología,
  ServiceAccount existente, RBAC namespaced, puertos y ServiceMonitor.
- Mantiene compatibles los modos Deployment y DaemonSet y valida colisiones o
  combinaciones de almacenamiento que no son seguras.
- Conserva los values `0.4.1` existentes y reporta en labels/OpAMP el tag real
  de la imagen seleccionada; los feature gates exigen el wrapper `0.5.0`.
- Permite pasar feature gates validados al Collector hijo sin convertirlos en
  argumentos del proceso Supervisor.
- Conserva siempre el sufijo hash del ConfigMap base inmutable, incluso con un
  `fullnameOverride` de longitud máxima.
- Documenta la migración desde CRs `OpenTelemetryCollector`; la remote config
  sigue siendo responsabilidad exclusiva del Control Plane.
- Publica `wjma90/o11y-opamp-supervisor:0.5.0` para AMD64/ARM64 con SBOM,
  provenance y manifest-list
  `sha256:1291e989ddf196bbca168f58bf8195707c95fc171a44ce1c2172be0aae8e76aa`.
- Despliega el chart `0.5.0` en gateway, revisión Helm 9, y monitoring,
  revisión 10; todos los Supervisors confirman `ONLINE` y `APPLIED`.
- Mantiene una excepción temporal para los cinco hallazgos únicos de los
  binarios upstream `0.156.0`, duplicados entre Supervisor y Collector.

## Chart 0.4.1 - 2026-07-21

- Integra el chart reusable dentro del producto y mantiene fuera los values de
  cada despliegue.
- Usa una sola base NOP empaquetada por Helm mediante `.Files.Get`.
- Agrega release autónoma de imagen multi-arquitectura y chart OCI en GHCR, con
  SBOM, provenance y Trivy por arquitectura.
- Mueve la evidencia de seguridad a `docs/security/SCAN.md`.

## 0.4.1 - 2026-07-21

- Retira el endpoint de bootstrap, la descarga del Collector en runtime y el
  cliente Go asociado.
- Vuelve a incorporar Collector Contrib `0.156.0` desde una imagen oficial
  fijada por digest, junto al OpAMP Supervisor upstream de la misma versión.
- Restaura una base NOP local, inmutable y protegida; no incorpora una
  configuración administrada local.
- Conserva únicamente la distribución de remote config por OpAMP y el fallback
  seguro si esa configuración no está disponible o es retirada.
- Reporta las versiones Supervisor/Collector y la identidad efectiva de la base
  local al Control Plane.
- Mantiene auth OpAMP deshabilitada por defecto y Bearer token opcional sin
  exponerlo al proceso Collector.

## 0.4.0 - diseño revocado

- Agrega bootstrap HTTP autenticado según `OPAMP_AUTH_MODE`.
- Selecciona versión y base NOP desde el Control Plane por identidad y atributos.
- Descarga `otelcol-contrib` únicamente desde el catálogo oficial embebido y
  verifica URL, plataforma y SHA-256 antes de extraerlo.
- Genera en runtime la configuración del Supervisor y reporta por OpAMP las
  versiones y la base efectivamente usadas.
- Limita el arranque a cinco intentos con backoff exponencial; un fallo final
  termina el contenedor para delegar el reinicio al runtime.
- Elimina los ConfigMaps Kubernetes de `base.yaml`, `managed.yaml` y
  `supervisor.yaml`.

Este diseño fue retirado por `0.4.1` y no debe desplegarse.
