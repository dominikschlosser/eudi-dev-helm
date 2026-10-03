# Changelog

## 0.2.0 (2026-10-04)

* Deploys eudi-dev 2.6.0
* Probes call `/healthz` (liveness, startup) and `/readyz` (readiness, checks the storage backend)
* `logFormat=json` writes JSON log records (`EUDI_DEV_LOG_FORMAT`)
* Requests to in-cluster services bypass the outbound proxy, and a restricted NetworkPolicy allows egress on the proxy ports
* Warns when `demo.enabled` is combined with an outbound proxy
* Values for every `wallet serve` flag that applies in Kubernetes: `haip`, `statusList`, `adhocDisplayImages`, `issuance.*`, `presentation.*`, `demoIssuer.clientAuth`, `demoVerifier.trustAnchors`, `imprint.*`, `holderKey`, `issuerKey`, `credentialTemplates` and `importCredentials`

## 0.1.0 (2026-10-03)

* Initial release for eudi-dev 2.5.1
