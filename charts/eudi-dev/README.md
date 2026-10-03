<!--- app-name: eudi-dev -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/dominikschlosser/eudi-dev/main/docs/assets/logo-readme-dark.png">
    <img src="https://raw.githubusercontent.com/dominikschlosser/eudi-dev/main/docs/assets/logo-readme.png" alt="EUDI Dev Wallet" width="720">
  </picture>
</p>

# Helm chart for eudi-dev

eudi-dev is a developer test wallet for the EUDI ecosystem. It issues, holds and presents SD-JWT VC and mdoc credentials over OpenID4VCI and OpenID4VP, and comes with a demo issuer and verifier.

[Overview of eudi-dev](https://github.com/dominikschlosser/eudi-dev)

## TL;DR

```console
helm install my-release oci://ghcr.io/dominikschlosser/charts/eudi-dev
```

## Introduction

This chart deploys eudi-dev on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. It follows the conventions of the [Bitnami charts](https://github.com/bitnami/charts) and uses their [common library chart](https://github.com/bitnami/charts/tree/main/bitnami/common).

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8.0+
- PV provisioner support in the underlying infrastructure (only for `storage.type=file` with `persistence.enabled=true`)
- A PostgreSQL database (only for `storage.type=postgresql`)

## Installing the Chart

To install the chart with the release name `my-release`:

```console
helm install my-release oci://ghcr.io/dominikschlosser/charts/eudi-dev
```

The command deploys a wallet with PID credentials that approves every request. It is reachable inside the cluster at `http://my-release-eudi-dev.<namespace>.svc.cluster.local:8085`. The [Parameters](#parameters) section lists everything you can configure.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall the `my-release` deployment:

```console
helm uninstall my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release. A PersistentVolumeClaim created for `persistence.enabled=true` is deleted with it.

## Configuration and installation details

### Public URL

The wallet builds all of its URLs from its public URL: issuer identifiers, metadata, credential offers, presentation requests and status list URLs. The chart passes it as `--base-url` and uses:

- `baseURL` when set
- otherwise the ingress URL (`ingress.hostname`, `ingress.path` and `https` when `ingress.tls=true`)
- otherwise the in-cluster service URL

Use an https URL behind an ingress. With an http URL, the wallet serves its own issuer over HTTPS on the next port (8086), which the ingress does not route.

### Storage

`storage.type` selects where the wallet keeps credentials, keys and its activity log:

| Type | State | Replicas |
|------|-------|----------|
| `memory` (default) | In the pod. Lost on restart | 1 |
| `file` | On a volume (`persistence.enabled=true`) | 1 |
| `postgresql` | In the database given in `externalDatabase` | 1 or more |

With more than one replica, keep each browser flow on the same pod, for example with `service.sessionAffinity=ClientIP` or sticky sessions in the ingress. The chart does not deploy a database.

```console
helm install my-release oci://ghcr.io/dominikschlosser/charts/eudi-dev \
  --set storage.type=postgresql \
  --set externalDatabase.host=postgresql.db.svc.cluster.local \
  --set externalDatabase.existingSecret=eudi-db
```

The chart passes the password to the wallet as `PGPASSWORD`, so it may contain any characters.

### Keys

The wallet derives its keys from `seed.value`. The default `auto` uses the public seed `eudi-dev` with memory storage, so a restarted pod keeps the same CA. Anyone can derive keys from that seed. Set your own value (or `seed.existingSecret`) for a shared test bench, or an empty value for random keys.

### Path prefix

To serve the wallet under a path prefix on a shared host, such as `https://example.com/some/context`, set the prefix as the ingress path. This needs eudi-dev 2.6.0 or later.

```yaml
ingress:
  enabled: true
  hostname: example.com
  path: /some/context
  tls: true
```

The specs put issuer metadata at the root of the host, such as `/.well-known/openid-credential-issuer/some/context/issuer`. The ingress and the HTTPRoute add routes for these paths automatically (`ingress.wellKnownPaths`, `httpRoute.wellKnownPaths`). See [behind a reverse proxy](https://github.com/dominikschlosser/eudi-dev/blob/main/docs/reverse-proxy.md) for details.

### Ingress and Gateway API

Set `ingress.enabled=true` to create an Ingress, or `httpRoute.enabled=true` to create a Gateway API HTTPRoute. For TLS, use cert-manager annotations (`ingress.annotations`), your own certificates (`ingress.secrets`) or a self-signed certificate (`ingress.selfSigned=true`).

### Istio and other resources

The chart does not create resources for service meshes. Add them with `extraDeploy`, as with Bitnami charts. This Istio VirtualService serves the wallet under `/some/context` and also routes the issuer metadata paths at the host root:

```yaml
baseURL: https://example.com/some/context
extraDeploy:
  - apiVersion: networking.istio.io/v1
    kind: VirtualService
    metadata:
      name: '{{ include "common.names.fullname" . }}'
    spec:
      hosts: [example.com]
      gateways: [istio-system/public-gateway]
      http:
        - match:
            - uri: { prefix: /.well-known/openid-credential-issuer/some/context }
            - uri: { prefix: /.well-known/oauth-authorization-server/some/context }
            - uri: { prefix: /.well-known/jwt-vc-issuer/some/context }
            - uri: { prefix: /some/context }
          route:
            - destination:
                host: '{{ include "common.names.fullname" . }}'
                port: { number: 8085 }
```

### Outbound proxy and certificates

When issuers and verifiers are only reachable through a forward proxy, set `outboundProxy.httpsProxy` (and `outboundProxy.noProxy`). To trust an internal CA, put the PEM bundle in a secret and set `tls.existingCASecret`.

### Additional environment variables and arguments

Use `extraEnvVars`, `extraEnvVarsCM` or `extraEnvVarsSecret` for environment variables, and `extraArgs` for more `wallet serve` flags (such as `--haip`).

### Sidecars and Init Containers

If you need additional containers to run within the same pod (e.g. an additional metrics or logging exporter), you can do so via the `sidecars` config parameter. Similarly, you can add extra init containers using the `initContainers` parameter.

### Pod affinity

This chart allows you to set your custom affinity using the `affinity` parameter. Find more information about Pod's affinity in the [kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity).

As an alternative, you can use the preset configurations for pod affinity, pod anti-affinity, and node affinity available at the [bitnami/common](https://github.com/bitnami/charts/tree/main/bitnami/common#affinities) chart. To do so, set the `podAffinityPreset`, `podAntiAffinityPreset`, or `nodeAffinityPreset` parameters.

### Resource requests and limits

The chart sets requests and limits from `resourcesPreset` (`micro` by default). Set `resources` for your own values.

## Parameters

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                         | Value   |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                        | `""`    |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                     | `[]`    |
| `global.defaultStorageClass`                          | Global default StorageClass for Persistent Volume(s)                                                                                                                                                                                                                                                                                                                | `""`    |
| `global.security.allowInsecureImages`                 | Allows skipping image verification                                                                                                                                                                                                                                                                                                                                  | `false` |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto`  |

### Common parameters

| Name                     | Description                                                                             | Value           |
| ------------------------ | --------------------------------------------------------------------------------------- | --------------- |
| `kubeVersion`            | Override Kubernetes version                                                             | `""`            |
| `nameOverride`           | String to partially override common.names.name                                          | `""`            |
| `fullnameOverride`       | String to fully override common.names.fullname                                          | `""`            |
| `namespaceOverride`      | String to fully override common.names.namespace                                         | `""`            |
| `commonLabels`           | Labels to add to all deployed objects                                                   | `{}`            |
| `commonAnnotations`      | Annotations to add to all deployed objects                                              | `{}`            |
| `clusterDomain`          | Kubernetes cluster domain name                                                          | `cluster.local` |
| `extraDeploy`            | Array of extra objects to deploy with the release (evaluated as a template)             | `[]`            |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false`         |
| `diagnosticMode.command` | Command to override all containers in the deployment                                    | `["sleep"]`     |
| `diagnosticMode.args`    | Args to override all containers in the deployment                                       | `["infinity"]`  |

### eudi-dev parameters

| Name                       | Description                                                                                                                                                                              | Value                       |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `image.registry`           | eudi-dev image registry                                                                                                                                                                  | `ghcr.io`                   |
| `image.repository`         | eudi-dev image repository                                                                                                                                                                | `dominikschlosser/eudi-dev` |
| `image.tag`                | eudi-dev image tag (immutable tags are recommended)                                                                                                                                      | `v2.5.1`                    |
| `image.digest`             | eudi-dev image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                                                                                 | `""`                        |
| `image.pullPolicy`         | eudi-dev image pull policy                                                                                                                                                               | `IfNotPresent`              |
| `image.pullSecrets`        | eudi-dev image pull secrets                                                                                                                                                              | `[]`                        |
| `baseURL`                  | Public URL of the wallet, such as https://eudi.example.com or https://example.com/some/context. Empty: the ingress URL when the ingress is enabled, otherwise the in-cluster service URL | `""`                        |
| `autoAccept`               | Approve issuance and presentation requests without a consent prompt (`--auto-accept`)                                                                                                    | `true`                      |
| `generatePID`              | Generate the default PID credentials on start (`--pid`)                                                                                                                                  | `true`                      |
| `validationMode`           | Validation mode: `debug` reports problems and continues, `strict` aborts the flow (`--mode`)                                                                                             | `debug`                     |
| `demo.enabled`             | Run the hardened public demo profile (`--demo`)                                                                                                                                          | `false`                     |
| `demo.reset`               | Schedule for resetting the demo to its initial state, such as `1h` or `00:00 Europe/Berlin` (`--demo-reset`). Empty: the eudi-dev default                                                | `""`                        |
| `storage.type`             | Storage backend: `memory` (lost on restart), `file` (on the volume, see `persistence`) or `postgresql` (see `externalDatabase`)                                                          | `memory`                    |
| `seed.value`               | Seed for deriving the wallet's keys. `auto` uses the public seed `eudi-dev` with memory storage and random keys otherwise. Empty: random keys                                            | `auto`                      |
| `seed.existingSecret`      | Name of an existing secret with the seed (`seed.value` is then ignored)                                                                                                                  | `""`                        |
| `seed.existingSecretKey`   | Key of the seed in `seed.existingSecret`                                                                                                                                                 | `seed`                      |
| `tls.verify`               | Verify issuer and verifier certificates: `true`, `false`, or empty for the validation mode default (`--tls-verify`)                                                                      | `""`                        |
| `tls.existingCASecret`     | Name of an existing secret with PEM CA certificates to trust in addition to the system ones (`--tls-ca`)                                                                                 | `""`                        |
| `tls.existingCASecretKey`  | Key of the CA bundle in `tls.existingCASecret`                                                                                                                                           | `ca.crt`                    |
| `outboundProxy.httpsProxy` | Proxy for `https://` URLs (`HTTPS_PROXY`)                                                                                                                                                | `""`                        |
| `outboundProxy.httpProxy`  | Proxy for `http://` URLs (`HTTP_PROXY`)                                                                                                                                                  | `""`                        |
| `outboundProxy.noProxy`    | Comma separated hosts to connect to directly (`NO_PROXY`)                                                                                                                                | `""`                        |
| `extraArgs`                | Extra arguments for `eudi wallet serve`                                                                                                                                                  | `[]`                        |
| `command`                  | Override the default container command (useful when using custom images)                                                                                                                 | `[]`                        |
| `args`                     | Override the default container args (useful when using custom images)                                                                                                                    | `[]`                        |
| `extraEnvVars`             | Array with extra environment variables to add to the eudi-dev container                                                                                                                  | `[]`                        |
| `extraEnvVarsCM`           | Name of existing ConfigMap containing extra env vars for the eudi-dev container                                                                                                          | `""`                        |
| `extraEnvVarsSecret`       | Name of existing Secret containing extra env vars for the eudi-dev container                                                                                                             | `""`                        |

### eudi-dev deployment parameters

| Name                                                | Description                                                                                                                                                                                                       | Value            |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `replicaCount`                                      | Number of eudi-dev replicas. More than one needs `storage.type=postgresql`, and each browser flow must stay on one pod (see `service.sessionAffinity`)                                                            | `1`              |
| `containerPorts.http`                               | eudi-dev HTTP container port                                                                                                                                                                                      | `8085`           |
| `extraContainerPorts`                               | Optionally specify extra list of additional ports for eudi-dev containers                                                                                                                                         | `[]`             |
| `livenessProbe.enabled`                             | Enable livenessProbe on eudi-dev containers                                                                                                                                                                       | `true`           |
| `livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                                                                           | `10`             |
| `livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                                                                  | `10`             |
| `livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                                                                 | `5`              |
| `livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                                                                               | `6`              |
| `livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                                                                               | `1`              |
| `readinessProbe.enabled`                            | Enable readinessProbe on eudi-dev containers                                                                                                                                                                      | `true`           |
| `readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                                                                          | `5`              |
| `readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                                                                 | `10`             |
| `readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                                                                                | `5`              |
| `readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                                                                              | `6`              |
| `readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                                                                              | `1`              |
| `startupProbe.enabled`                              | Enable startupProbe on eudi-dev containers                                                                                                                                                                        | `false`          |
| `startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                                                                            | `5`              |
| `startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                                                                   | `5`              |
| `startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                                                                  | `5`              |
| `startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                                                                                | `30`             |
| `startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                                                                                | `1`              |
| `customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                                                                               | `{}`             |
| `customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                                                                              | `{}`             |
| `customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                                                                                | `{}`             |
| `resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if resources is set (resources is recommended for production). | `micro`          |
| `resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                 | `{}`             |
| `podSecurityContext.enabled`                        | Enabled eudi-dev pods' Security Context                                                                                                                                                                           | `true`           |
| `podSecurityContext.fsGroupChangePolicy`            | Set filesystem group change policy                                                                                                                                                                                | `Always`         |
| `podSecurityContext.sysctls`                        | Set kernel settings using the sysctl interface                                                                                                                                                                    | `[]`             |
| `podSecurityContext.supplementalGroups`             | Set filesystem extra groups                                                                                                                                                                                       | `[]`             |
| `podSecurityContext.fsGroup`                        | Set eudi-dev pod's Security Context fsGroup                                                                                                                                                                       | `1000`           |
| `containerSecurityContext.enabled`                  | Enabled containers' Security Context                                                                                                                                                                              | `true`           |
| `containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                  | `{}`             |
| `containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser                                                                                                                                                                        | `1000`           |
| `containerSecurityContext.runAsGroup`               | Set containers' Security Context runAsGroup                                                                                                                                                                       | `1000`           |
| `containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                                                                                                                                                                     | `true`           |
| `containerSecurityContext.privileged`               | Set container's Security Context privileged                                                                                                                                                                       | `false`          |
| `containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                           | `true`           |
| `containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                         | `false`          |
| `containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                                                                                                                                                                                | `["ALL"]`        |
| `containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                                                                                                                                                                  | `RuntimeDefault` |
| `automountServiceAccountToken`                      | Mount Service Account token in pod                                                                                                                                                                                | `false`          |
| `hostAliases`                                       | eudi-dev pods host aliases                                                                                                                                                                                        | `[]`             |
| `podLabels`                                         | Extra labels for eudi-dev pods                                                                                                                                                                                    | `{}`             |
| `podAnnotations`                                    | Annotations for eudi-dev pods                                                                                                                                                                                     | `{}`             |
| `podAffinityPreset`                                 | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                                                                               | `""`             |
| `podAntiAffinityPreset`                             | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                                                                          | `soft`           |
| `nodeAffinityPreset.type`                           | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                                                                         | `""`             |
| `nodeAffinityPreset.key`                            | Node label key to match. Ignored if `affinity` is set                                                                                                                                                             | `""`             |
| `nodeAffinityPreset.values`                         | Node label values to match. Ignored if `affinity` is set                                                                                                                                                          | `[]`             |
| `affinity`                                          | Affinity for eudi-dev pods assignment                                                                                                                                                                             | `{}`             |
| `nodeSelector`                                      | Node labels for eudi-dev pods assignment                                                                                                                                                                          | `{}`             |
| `tolerations`                                       | Tolerations for eudi-dev pods assignment                                                                                                                                                                          | `[]`             |
| `updateStrategy.type`                               | eudi-dev deployment strategy type                                                                                                                                                                                 | `Recreate`       |
| `revisionHistoryLimit`                              | The number of old history to retain to allow rollback                                                                                                                                                             | `10`             |
| `priorityClassName`                                 | eudi-dev pods' priorityClassName                                                                                                                                                                                  | `""`             |
| `topologySpreadConstraints`                         | Topology Spread Constraints for pod assignment spread across your cluster among failure-domains. Evaluated as a template                                                                                          | `[]`             |
| `schedulerName`                                     | Name of the k8s scheduler (other than default) for eudi-dev pods                                                                                                                                                  | `""`             |
| `terminationGracePeriodSeconds`                     | Seconds eudi-dev pod needs to terminate gracefully                                                                                                                                                                | `""`             |
| `lifecycleHooks`                                    | for the eudi-dev container(s) to automate configuration before or after startup                                                                                                                                   | `{}`             |
| `extraVolumes`                                      | Optionally specify extra list of additional volumes for the eudi-dev pod(s)                                                                                                                                       | `[]`             |
| `extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the eudi-dev container(s)                                                                                                                            | `[]`             |
| `sidecars`                                          | Add additional sidecar containers to the eudi-dev pod(s)                                                                                                                                                          | `[]`             |
| `initContainers`                                    | Add additional init containers to the eudi-dev pod(s)                                                                                                                                                             | `[]`             |
| `pdb.create`                                        | Enable/disable a Pod Disruption Budget creation                                                                                                                                                                   | `true`           |
| `pdb.minAvailable`                                  | Minimum number/percentage of pods that should remain scheduled                                                                                                                                                    | `""`             |
| `pdb.maxUnavailable`                                | Maximum number/percentage of pods that may be made unavailable. Defaults to `1` if both `pdb.minAvailable` and `pdb.maxUnavailable` are empty.                                                                    | `""`             |

### Traffic exposure parameters

| Name                                    | Description                                                                                                                      | Value            |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `service.type`                          | eudi-dev service type                                                                                                            | `ClusterIP`      |
| `service.ports.http`                    | eudi-dev service HTTP port                                                                                                       | `8085`           |
| `service.ports.issuer`                  | eudi-dev service port of the wallet's own HTTPS issuer (used when the base URL is http)                                          | `8086`           |
| `service.nodePorts.http`                | Node port for HTTP                                                                                                               | `""`             |
| `service.nodePorts.issuer`              | Node port for the issuer                                                                                                         | `""`             |
| `service.clusterIP`                     | eudi-dev service Cluster IP                                                                                                      | `""`             |
| `service.loadBalancerIP`                | eudi-dev service Load Balancer IP                                                                                                | `""`             |
| `service.loadBalancerSourceRanges`      | eudi-dev service Load Balancer sources                                                                                           | `[]`             |
| `service.externalTrafficPolicy`         | eudi-dev service external traffic policy                                                                                         | `Cluster`        |
| `service.annotations`                   | Additional custom annotations for eudi-dev service                                                                               | `{}`             |
| `service.extraPorts`                    | Extra ports to expose in eudi-dev service (normally used with the `sidecars` value)                                              | `[]`             |
| `service.sessionAffinity`               | Control where client requests go, to the same pod or round-robin                                                                 | `None`           |
| `service.sessionAffinityConfig`         | Additional settings for the sessionAffinity                                                                                      | `{}`             |
| `networkPolicy.enabled`                 | Specifies whether a NetworkPolicy should be created                                                                              | `true`           |
| `networkPolicy.allowExternal`           | Don't require server label for connections                                                                                       | `true`           |
| `networkPolicy.allowExternalEgress`     | Allow the pod to access any range of port and all destinations.                                                                  | `true`           |
| `networkPolicy.extraIngress`            | Add extra ingress rules to the NetworkPolicy                                                                                     | `[]`             |
| `networkPolicy.extraEgress`             | Add extra egress rules to the NetworkPolicy (ignored if allowExternalEgress=true)                                                | `[]`             |
| `networkPolicy.ingressNSMatchLabels`    | Labels to match to allow traffic from other namespaces                                                                           | `{}`             |
| `networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces                                                                       | `{}`             |
| `ingress.enabled`                       | Enable ingress record generation for eudi-dev                                                                                    | `false`          |
| `ingress.pathType`                      | Ingress path type                                                                                                                | `Prefix`         |
| `ingress.apiVersion`                    | Force Ingress API version (automatically detected if not set)                                                                    | `""`             |
| `ingress.hostname`                      | Default host for the ingress record                                                                                              | `eudi-dev.local` |
| `ingress.ingressClassName`              | IngressClass that will be be used to implement the Ingress (Kubernetes 1.18+)                                                    | `""`             |
| `ingress.path`                          | Ingress path. Empty: the path of `baseURL`, or `/`                                                                               | `""`             |
| `ingress.wellKnownPaths`                | Add routes for the issuer metadata paths at the host root when the wallet is served under a path prefix                          | `true`           |
| `ingress.annotations`                   | Additional annotations for the Ingress resource. To enable certificate autogeneration, place here your cert-manager annotations. | `{}`             |
| `ingress.tls`                           | Enable TLS configuration for the host defined at `ingress.hostname` parameter                                                    | `false`          |
| `ingress.selfSigned`                    | Create a TLS secret for this ingress record using self-signed certificates generated by Helm                                     | `false`          |
| `ingress.extraHosts`                    | An array with additional hostname(s) to be covered with the ingress record                                                       | `[]`             |
| `ingress.extraPaths`                    | An array with additional arbitrary paths that may need to be added to the ingress under the main host                            | `[]`             |
| `ingress.extraTls`                      | TLS configuration for additional hostname(s) to be covered with this ingress record                                              | `[]`             |
| `ingress.secrets`                       | Custom TLS certificates as secrets                                                                                               | `[]`             |
| `ingress.extraRules`                    | Additional rules to be covered with this ingress record                                                                          | `[]`             |
| `httpRoute.enabled`                     | Enable HTTPRoute generation for eudi-dev                                                                                         | `false`          |
| `httpRoute.annotations`                 | Additional annotations for the HTTPRoute resource                                                                                | `{}`             |
| `httpRoute.labels`                      | Additional labels for the HTTPRoute resource                                                                                     | `{}`             |
| `httpRoute.parentRefs`                  | Gateways the HTTPRoute is attached to. If unspecified, it'll be attached to Gateway named 'gateway' in the same namespace.       | `[]`             |
| `httpRoute.hostnames`                   | List of hostnames matching HTTP header                                                                                           | `[]`             |
| `httpRoute.matches`                     | Path matches for the eudi-dev backend. Empty: the path of `baseURL`, or `/`                                                      | `[]`             |
| `httpRoute.wellKnownPaths`              | Add routes for the issuer metadata paths at the host root when the wallet is served under a path prefix                          | `true`           |
| `httpRoute.filters`                     | List of filter rules applied to the HTTPRoute for the default svc backend reference                                              | `[]`             |
| `httpRoute.extraRules`                  | List of extra rules applied to the HTTPRoute                                                                                     | `[]`             |

### Persistence parameters

| Name                        | Description                                                           | Value                 |
| --------------------------- | --------------------------------------------------------------------- | --------------------- |
| `persistence.enabled`       | Enable persistence using Persistent Volume Claims                     | `false`               |
| `persistence.mountPath`     | Path to mount the volume at.                                          | `/home/app/.eudi-dev` |
| `persistence.storageClass`  | Storage class of backing PVC                                          | `""`                  |
| `persistence.annotations`   | Persistent Volume Claim annotations                                   | `{}`                  |
| `persistence.accessModes`   | Persistent Volume Access Modes                                        | `["ReadWriteOnce"]`   |
| `persistence.size`          | Size of data volume                                                   | `1Gi`                 |
| `persistence.existingClaim` | The name of an existing PVC to use for persistence                    | `""`                  |
| `persistence.selector`      | Selector to match an existing Persistent Volume for eudi-dev data PVC | `{}`                  |
| `persistence.dataSource`    | Custom PVC data source                                                | `{}`                  |

### Database parameters

| Name                                         | Description                                                                         | Value      |
| -------------------------------------------- | ----------------------------------------------------------------------------------- | ---------- |
| `externalDatabase.host`                      | Database host                                                                       | `""`       |
| `externalDatabase.port`                      | Database port number                                                                | `5432`     |
| `externalDatabase.user`                      | Database user                                                                       | `eudi`     |
| `externalDatabase.database`                  | Database name                                                                       | `eudi`     |
| `externalDatabase.password`                  | Password for the database user. Ignored if `externalDatabase.existingSecret` is set | `""`       |
| `externalDatabase.existingSecret`            | Name of an existing secret with the database password                               | `""`       |
| `externalDatabase.existingSecretPasswordKey` | Key of the password in `externalDatabase.existingSecret`                            | `password` |
| `externalDatabase.sslMode`                   | PostgreSQL `sslmode`, such as `disable`, `require` or `verify-full`                 | `prefer`   |

### Other parameters

| Name                                          | Description                                                      | Value   |
| --------------------------------------------- | ---------------------------------------------------------------- | ------- |
| `serviceAccount.create`                       | Specifies whether a ServiceAccount should be created             | `true`  |
| `serviceAccount.name`                         | The name of the ServiceAccount to use.                           | `""`    |
| `serviceAccount.annotations`                  | Additional Service Account annotations (evaluated as a template) | `{}`    |
| `serviceAccount.automountServiceAccountToken` | Automount service account token for the server service account   | `false` |

## Troubleshooting

`kubectl logs` on the eudi-dev pod shows every request the wallet handles. The wallet's web UI (see the port-forward command printed after installation) lists its activity and reports protocol problems. Report bugs in the chart at [eudi-dev-helm issues](https://github.com/dominikschlosser/eudi-dev-helm/issues), and bugs in the wallet at [eudi-dev issues](https://github.com/dominikschlosser/eudi-dev/issues).

## Upgrading

### To 0.1.0

First release.

## License

Copyright Dominik Schlosser

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
