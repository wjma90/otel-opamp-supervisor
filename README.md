# O11y OpAMP Supervisor

Ejecuta OpenTelemetry Collector Contrib bajo el
OpAMP Supervisor oficial. La versión publicada y desplegada `0.5.0` contiene
ambos binarios upstream `0.156.0`, obtenidos desde imágenes fijadas por digest
durante el build, e incorpora el soporte StatefulSet descrito más adelante.

No existe bootstrap, descarga ni upgrade de binarios en runtime. El Supervisor
sólo usa OpAMP HTTP polling para recibir y validar la remote config del
Collector.

## Arranque y fallback

1. `/usr/local/bin/opampsupervisor` arranca como PID 1 con el YAML montado por
   el chart.
2. El chart monta una base NOP local desde un ConfigMap con nombre derivado del
   contenido, `immutable: true`, retención Helm y marca de protección frente al
   Control Plane.
3. La base se declara en `config_files` y `startup_fallback_configs`; por eso el
   Collector puede arrancar de forma segura aun cuando el Control Plane no esté
   disponible.
4. OpAMP mantiene `accepts_remote_config: true`. Cuando llega una configuración
   administrada, el Supervisor la valida con el Collector embebido y la activa.
5. El wrapper elimina `OPAMP_TOKEN` antes de crear el proceso Collector, de modo
   que una remote config no puede expandir la credencial de la flota.

La base sólo contiene `health_check`, receivers/exporters `nop` y pipelines NOP
para traces, metrics y logs. No se incluye una configuración administrada local:
la configuración funcional de monitoring o gateway llega exclusivamente por
OpAMP.

La única fuente de esa base vive en
[`charts/o11y-opamp-supervisor/collector-base/base.yaml`](./charts/o11y-opamp-supervisor/collector-base/base.yaml).
Helm la incorpora con `.Files.Get`; el template no mantiene una segunda copia.

## Versiones e identidad reportada

| Componente | Versión
|---|---|
| Producto O11y Supervisor | `0.5.0`
| OpAMP Supervisor upstream | `0.156.0`
| Collector Contrib upstream | `0.156.0`

Los manifiestos de plataforma publicados son para AMD64 y ARM64.

El YAML generado por el chart reporta mediante headers que el Control Plane ya
entiende:

- versión de producto `X-O11y-Supervisor-Version`;
- versión de binario `X-O11y-Collector-Version`;
- ID, source `ConfigMap/...`, revisión, default local y responsable Kubernetes
  de la base;
- servicio, cluster, rol, transporte e intervalo de polling.

El source local permite que el Control Plane derive `Immutable=true`. La
disponibilidad OpAMP y la confirmación de remote config continúan siendo estados
distintos.

## Autenticación

El default local es `controlPlane.authMode=disabled`: el chart no genera Secret,
variable `OPAMP_TOKEN` ni header `Authorization`. En modo `token`, el token se
lee mediante `secretKeyRef` y el YAML agrega
`Authorization: Bearer ${env:OPAMP_TOKEN}` únicamente para el Supervisor.

El nivel de los logs propios del Supervisor se configura independientemente de
los logs del Collector:

```yaml
telemetry:
  logs:
    level: warn
```

Los niveles aceptados son `debug`, `info`, `warn` y `error`.

TLS hacia OpAMP es opt-in y usa el soporte `server.tls.ca_file` del Supervisor
upstream. El chart monta una CA desde un Secret existente:

```yaml
controlPlane:
  endpoint: https://control-plane.o11y.svc.cluster.local:4320/v1/opamp
  tls:
    enabled: true
    existingSecret: opamp-server-ca
    caKey: ca.crt
```

El SAN del certificado debe coincidir con el hostname del endpoint. Con
`enabled: false` no se renderiza `server.tls`, no se monta el Secret y el flujo
HTTP actual permanece intacto. Esta CA sólo protege la conexión Supervisor →
Control Plane; los certificados de receptores/exportadores OTLP del Collector
siguen perteneciendo a su remote config y pueden usar otros Secrets/montajes.

## Interfaz de la imagen

- Usuario: `10001:10001`.
- Supervisor: `/usr/local/bin/opampsupervisor`.
- Collector fijo: `/usr/local/bin/otelcol-contrib`.
- Wrapper: `/usr/local/bin/otelcol-contrib-wrapper`.
- Configuración esperada: `--config=/etc/supervisor/supervisor.yaml`.
- Base esperada: `/etc/otelcol/base.yaml`.
- Estado OpAMP: `/var/lib/opamp` en Kubernetes.
- Health: Collector `13133`, Supervisor `13134`.

`supervisor.yaml` conserva un ejemplo local sin autenticación. El chart reusable
forma parte del producto en
[`charts/o11y-opamp-supervisor`](./charts/o11y-opamp-supervisor).

## Modos de workload Kubernetes

El mismo chart soporta los tres patrones sin cambiar el contrato OpAMP:

| `mode` | Uso recomendado | Persistencia `opamp-data` |
|---|---|---|
| `deployment` | gateway simple de una réplica | `emptyDir`, PVC creado por el chart o `existingClaim` |
| `daemonset` | recolección por nodo | sólo `emptyDir`; no admite PVC compartido |
| `statefulset` | balancers/backends con identidad y disco por réplica | un `volumeClaimTemplate` `opamp-data` por pod |

En `statefulset`, el chart crea además un Service headless y lo asigna como
`serviceName`. `persistence` pertenece exclusivamente al estado del Supervisor;
colas persistentes, WAL y `file_storage` del Collector deben usar claims
separados en `extraVolumeClaimTemplates` y montajes en `extraVolumeMounts`.

El chart puede referenciar ConfigMaps y Secrets ya existentes mediante
`extraVolumes`, `extraEnv` y `extraEnvFrom`; no crea ni incorpora sus datos. Las
opciones adicionales cubren `initContainers`, afinidad, distribución topológica,
ServiceAccount existente, RBAC namespaced, puertos adicionales y ServiceMonitor.
La configuración funcional del Collector continúa llegando desde el Control
Plane: estos valores no sustituyen la remote config OpAMP.

## Instalar el chart desde estas fuentes

Desde la raíz de este producto:

```bash
helm upgrade --install o11y-opamp-supervisor \
  ./charts/o11y-opamp-supervisor \
  --namespace o11y \
  --create-namespace \
  --set image.repository=wjma90/o11y-opamp-supervisor \
  --set image.tag=0.5.0 \
  --set image.digest=sha256:1291e989ddf196bbca168f58bf8195707c95fc171a44ce1c2172be0aae8e76aa \
  --set controlPlane.endpoint=http://control-plane.o11y.svc.cluster.local:4320/v1/opamp
```

Un consumidor real debe aportar su identidad, modo de workload, recursos,
imagen inmutable y demás diferencias mediante su propio `values.yaml`. La base
NOP no se reemplaza desde values. `collector.featureGates` requiere la imagen
`0.5.0` o posterior porque el wrapper `0.4.1` no transmite esos gates al
Collector hijo.

## Instalar el chart publicado en GHCR

Los tags Git `v<versión>` publican la imagen multi-arquitectura y el chart OCI.
Sustituye `<owner>` por el propietario en minúsculas del repositorio:

```bash
helm registry login ghcr.io

helm upgrade --install o11y-opamp-supervisor \
  oci://ghcr.io/<owner>/charts/o11y-opamp-supervisor \
  --version 0.5.0 \
  --namespace o11y \
  --create-namespace \
  --set image.repository=ghcr.io/<owner>/o11y-opamp-supervisor \
  --set image.tag=0.5.0 \
  --set controlPlane.endpoint=http://control-plane.o11y.svc.cluster.local:4320/v1/opamp
```

Para un entorno estable, usa `image.digest=sha256:...`; cuando existe digest,
el chart ignora el tag para ejecutar exactamente el manifest-list verificado.
