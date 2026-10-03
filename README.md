<!-- markdownlint-disable MD041 -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/dominikschlosser/eudi-dev/main/docs/assets/logo-readme-dark.png">
    <img src="https://raw.githubusercontent.com/dominikschlosser/eudi-dev/main/docs/assets/logo-readme.png" alt="EUDI Dev Wallet" width="720">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/dominikschlosser/eudi-dev-helm/actions/workflows/ci.yaml"><img src="https://github.com/dominikschlosser/eudi-dev-helm/actions/workflows/ci.yaml/badge.svg" alt="CI"></a>
  <a href="https://github.com/dominikschlosser/eudi-dev-helm/releases"><img src="https://img.shields.io/github/v/release/dominikschlosser/eudi-dev-helm" alt="Release"></a>
  <a href="https://github.com/dominikschlosser/eudi-dev"><img src="https://img.shields.io/github/v/release/dominikschlosser/eudi-dev?label=eudi-dev" alt="eudi-dev release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/dominikschlosser/eudi-dev-helm" alt="License"></a>
</p>

# The eudi-dev Helm charts

[eudi-dev](https://github.com/dominikschlosser/eudi-dev), ready to launch on Kubernetes using [Helm](https://github.com/helm/helm). eudi-dev is a developer test wallet for the EUDI ecosystem with a demo issuer and verifier.

The charts follow the conventions of the [Bitnami charts](https://github.com/bitnami/charts) and use their [common library chart](https://github.com/bitnami/charts/tree/main/bitnami/common). Values, labels and helpers work the way they do in Bitnami charts.

## TL;DR

```console
helm install my-release oci://ghcr.io/dominikschlosser/charts/eudi-dev
```

## Charts

| Chart | Description |
|-------|-------------|
| [eudi-dev](charts/eudi-dev) | The wallet with its demo issuer and verifier |

## Before you begin

### Prerequisites

- Kubernetes 1.25+
- Helm 3.8.0+

### Setup a Kubernetes Cluster

Any conformant cluster works. For a local cluster, use [kind](https://kind.sigs.k8s.io/docs/user/quick-start/), [minikube](https://minikube.sigs.k8s.io/docs/start/) or the Kubernetes built into Docker Desktop. For other platforms, see the Kubernetes [getting started guide](https://kubernetes.io/docs/setup/).

### Install Helm

Helm is a tool for managing Kubernetes charts. Charts are packages of pre-configured Kubernetes resources.

To install Helm, refer to the [Helm install guide](https://helm.sh/docs/intro/install/) and ensure that the `helm` binary is in the `PATH` of your shell.

### Using Helm

The charts are published as OCI artifacts on GitHub Container Registry, so no `helm repo add` is needed.

Please refer to the [Quick Start guide](https://helm.sh/docs/intro/quickstart/) if you wish to get running in just a few commands, otherwise, the [Using Helm Guide](https://helm.sh/docs/intro/using_helm/) provides detailed instructions on how to use the Helm client to manage packages on your Kubernetes cluster.

Useful Helm Client Commands:

- Install a chart: `helm install my-release oci://ghcr.io/dominikschlosser/charts/<chart>`
- Show a chart's default values: `helm show values oci://ghcr.io/dominikschlosser/charts/<chart>`
- Upgrade your application: `helm upgrade my-release oci://ghcr.io/dominikschlosser/charts/<chart>`
- List installed releases: `helm list`
- Uninstall a release: `helm uninstall my-release`

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to lint, test and release the charts.

## License

Copyright Dominik Schlosser

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
