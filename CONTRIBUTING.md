# Contributing

## Layout

The repository is the chart: `Chart.yaml`, `values.yaml`, `templates/` and `README.md` sit at the root. `.helmignore` keeps the repository files (`.github/`, `test/`, `Makefile`, ...) out of the package. Add new repository files there too.

Pull requests that change the packaged chart (`Chart.yaml`, `values.yaml`, `templates/`, `README.md`, ...) must raise `version` in `Chart.yaml`. Changes to CI, tests or this file need no new version.

## Development

Requirements: Helm 3.8+, [chart-testing](https://github.com/helm/chart-testing), Node.js (for the README generator), Python 3, and [kind](https://kind.sigs.k8s.io) with Docker for the tests.

```console
make lint     # helm lint and ct lint
make readme   # regenerate the parameter tables from values.yaml
make test     # install the chart into a new kind cluster and check the wallet
```

The parameter tables in `README.md` come from the `@param` comments in `values.yaml`. Run `make readme` after changing values. CI fails when the README is out of date.

## Tests

`test/e2e.sh` installs the chart once per setup and checks the wallet through its API:

| Setup | Checks |
|-------|--------|
| `ci/default-values.yaml` | Memory storage, the in-cluster URLs, PID credentials, the issuer's HTTPS port from another pod |
| `ci/file-storage-values.yaml` | Credentials and the CA survive a pod restart |
| `ci/postgresql-values.yaml` | Two replicas share credentials and the CA |
| `ci/ingress-values.yaml` | The https ingress URL as public URL, strict mode |
| Path prefix (`PREFIX_TESTS=true`) | API, issuer metadata at the host root, redirects (needs eudi-dev 2.6.0 or later) |

With `--kind` the script creates and deletes its own cluster. Without it, it uses the current kubectl context and deletes only its namespaces. Set `KEEP=true` to keep everything for debugging, and `IMAGE_TAG` (with `LOAD_IMAGE` for a local image) to test another eudi-dev version:

```console
docker build -t ghcr.io/dominikschlosser/eudi-dev:dev ../eudi-dev
IMAGE_TAG=dev LOAD_IMAGE=ghcr.io/dominikschlosser/eudi-dev:dev PREFIX_TESTS=true test/e2e.sh --kind
```

CI lints the chart, checks the README, and runs the tests twice: with the image the chart ships and with an image built from eudi-dev's `main` branch.

## Release

1. Raise `version` in `Chart.yaml` (and `appVersion` and `image.tag` for a new eudi-dev release). Once the chart ships eudi-dev 2.6.0 or later, set `PREFIX_TESTS=true` for the release image in `.github/workflows/ci.yaml` too.
2. Add an entry to `CHANGELOG.md`.
3. Merge to `main`.

The release workflow pushes a chart version that has no git tag yet to `oci://ghcr.io/dominikschlosser/charts` and creates a GitHub release with the packaged chart. The release and its git tag are named `v<version>`, such as `v0.1.0`.
