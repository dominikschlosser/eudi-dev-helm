#!/usr/bin/env bash
# Installs the chart into a Kubernetes cluster and checks the wallet through its API.
#
# Usage: test/e2e.sh [--kind]
#
#   --kind    create a kind cluster for the run and delete it afterwards
#
# Without --kind the tests use the current kubectl context.
#
# Environment:
#   IMAGE_TAG          image tag to test instead of the chart default
#   LOAD_IMAGE         local image to load into the kind cluster, such as one built from eudi-dev main
#   KEEP=true          keep the cluster and namespaces for debugging
#   CLUSTER_NAME       kind cluster name (default eudi-helm-test)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHART=$ROOT
CLUSTER_NAME=${CLUSTER_NAME:-eudi-helm-test}
KIND=false
[ "${1:-}" = "--kind" ] && KIND=true

IMAGE_ARGS=()
if [ -n "${IMAGE_TAG:-}" ]; then
  IMAGE_ARGS=(--set "image.tag=$IMAGE_TAG" --set image.pullPolicy=IfNotPresent)
fi

PF_PIDS=()
NAMESPACES=()
FAILED=false

log() { printf '\n==> %s\n' "$*"; }
fail() {
  echo "FAIL: $*" >&2
  FAILED=true
  return 1
}

cleanup() {
  for pid in "${PF_PIDS[@]+"${PF_PIDS[@]}"}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  if [ "$FAILED" = true ] || [ "${KEEP:-}" = true ]; then
    log "Pods and logs"
    kubectl get pods -A || true
    for ns in "${NAMESPACES[@]+"${NAMESPACES[@]}"}"; do
      kubectl -n "$ns" logs -l app.kubernetes.io/name=eudi-dev --all-containers --tail=50 --prefix || true
    done
  fi
  if [ "${KEEP:-}" = true ]; then
    return
  fi
  if [ "$KIND" = true ]; then
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  else
    for ns in "${NAMESPACES[@]+"${NAMESPACES[@]}"}"; do kubectl delete namespace "$ns" --wait=false >/dev/null 2>&1 || true; done
    kubectl delete deployment,service postgres proxy --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap 'FAILED=true' ERR
trap cleanup EXIT

# install NAME [helm args...] installs the chart as release NAME in namespace t-NAME.
install() {
  local name=$1
  shift
  local ns=t-$name
  NAMESPACES+=("$ns")
  # The namespace may exist already with resources the values reference.
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns" >/dev/null
  helm install "$name" "$CHART" --namespace "$ns" --wait --timeout 300s "${IMAGE_ARGS[@]+"${IMAGE_ARGS[@]}"}" "$@" >/dev/null
}

# forward NS TARGET LOCAL_PORT forwards LOCAL_PORT to the wallet and waits until it answers.
forward() {
  # A port still forwarded to another wallet would answer in its place.
  if curl -s -o /dev/null "http://localhost:$3/"; then
    fail "port $3 is already in use"
  fi
  kubectl -n "$1" port-forward "$2" "$3:8085" >/dev/null 2>&1 &
  PF_PIDS+=("$!")
  for _ in $(seq 1 60); do
    curl -fs "http://localhost:$3/readyz" >/dev/null && return
    sleep 0.5
  done
  fail "no answer from $2 in $1"
}

# json reads a field from the JSON on stdin.
json() { python3 -c "import json, sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }

# expect NAME GOT WANT
expect() {
  if [ "$2" != "$3" ]; then
    fail "$1: got '$2', want '$3'"
  fi
  echo "ok: $1 = $2"
}

credential_count() { curl -fsI "http://localhost:$1/api/credentials" | tr -d '\r' | awk -F': ' 'tolower($1) == "x-total-count" {print $2}'; }

issue() {
  curl -fs -X POST "http://localhost:$1/api/issue" -H 'Content-Type: application/json' \
    -d '{"format":"sdjwt","vct":"urn:example:e2e"}' | json id
}

ca_hash() { curl -fs "http://localhost:$1/api/certificates/ca" | shasum | cut -c1-16; }

# in_cluster COMMAND runs a shell command in a curl pod inside the cluster and prints its output.
in_cluster() {
  local pod=probe-$RANDOM
  kubectl run "$pod" --restart=Never --image=curlimages/curl:8.11.1 --command -- sh -c "$1" >/dev/null
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$pod" --timeout=120s >/dev/null
  kubectl logs "$pod"
  kubectl delete pod "$pod" --wait=false >/dev/null
}

if [ "$KIND" = true ]; then
  log "Creating kind cluster $CLUSTER_NAME"
  kind create cluster --name "$CLUSTER_NAME" --wait 120s
  if [ -n "${LOAD_IMAGE:-}" ]; then
    kind load docker-image "$LOAD_IMAGE" --name "$CLUSTER_NAME"
  fi
fi

helm dependency build "$CHART" >/dev/null

log "Deploying PostgreSQL for ci/postgresql-values.yaml"
kubectl create deployment postgres --image=postgres:16-alpine --port=5432 >/dev/null
kubectl set env deployment/postgres POSTGRES_USER=eudi POSTGRES_PASSWORD=eudi POSTGRES_DB=eudi >/dev/null
kubectl expose deployment postgres --port=5432 >/dev/null
kubectl rollout status deployment/postgres --timeout=180s >/dev/null

# probe_path NS DEPLOYMENT PROBE prints the HTTP path of a container probe.
probe_path() { kubectl -n "$1" get deployment "$2" -o "jsonpath={.spec.template.spec.containers[0].$3.httpGet.path}"; }

log "Default values: memory storage and the in-cluster URL"
install default -f "$CHART/ci/default-values.yaml"
forward t-default svc/default-eudi-dev 18200
expect "liveness probe" "$(probe_path t-default default-eudi-dev livenessProbe)" /healthz
expect "readiness probe" "$(probe_path t-default default-eudi-dev readinessProbe)" /readyz
expect "liveness" "$(curl -fs http://localhost:18200/healthz | json status)" ok
expect "readiness" "$(curl -fs http://localhost:18200/readyz | json status)" ok
config=$(curl -fs http://localhost:18200/api/config)
expect "storage" "$(json storage <<<"$config")" memory
expect "base URL" "$(json base_url <<<"$config")" http://default-eudi-dev.t-default.svc.cluster.local:8085
expect "issuer URL" "$(json issuer_url <<<"$config")" https://default-eudi-dev.t-default.svc.cluster.local:8086
expect "PID credentials" "$(credential_count 18200)" 2
issuer=$(in_cluster 'curl -fsk https://default-eudi-dev.t-default.svc.cluster.local:8086/.well-known/jwt-vc-issuer')
expect "issuer metadata over the issuer port" "$(json issuer <<<"$issuer")" https://default-eudi-dev.t-default.svc.cluster.local:8086

log "File storage: state survives a pod restart"
install file-storage -f "$CHART/ci/file-storage-values.yaml"
forward t-file-storage svc/file-storage-eudi-dev 18201
issue 18201 >/dev/null
count=$(credential_count 18201)
ca=$(ca_hash 18201)
kubectl -n t-file-storage delete pod -l app.kubernetes.io/name=eudi-dev --wait >/dev/null
kubectl -n t-file-storage rollout status deployment/file-storage-eudi-dev --timeout=180s >/dev/null
forward t-file-storage svc/file-storage-eudi-dev 18202
expect "credentials after restart" "$(credential_count 18202)" "$count"
expect "CA after restart" "$(ca_hash 18202)" "$ca"

log "PostgreSQL: two replicas share one wallet"
install postgresql -f "$CHART/ci/postgresql-values.yaml"
pods=$(kubectl -n t-postgresql get pods -l app.kubernetes.io/name=eudi-dev -o name)
first=$(sed -n 1p <<<"$pods")
second=$(sed -n 2p <<<"$pods")
forward t-postgresql "$first" 18203
forward t-postgresql "$second" 18204
expect "storage" "$(curl -fs http://localhost:18203/api/config | json storage)" postgres
before=$(credential_count 18204)
id=$(issue 18203)
expect "credentials on the other replica" "$(credential_count 18204)" $((before + 1))
expect "credential on the other replica" "$(curl -fs -o /dev/null -w '%{http_code}' "http://localhost:18204/api/credentials/$id")" 200
expect "same CA on both replicas" "$(ca_hash 18204)" "$(ca_hash 18203)"
logs=$(kubectl -n t-postgresql logs "$first")
expect "JSON log records" "$(python3 -c '
import json, sys
lines = sys.stdin.read().splitlines()
print(all(json.loads(line)["level"] for line in lines) and len(lines) > 0)' <<<"$logs")" True

log "Ingress: public https URL and strict mode"
install ingress -f "$CHART/ci/ingress-values.yaml"
forward t-ingress svc/ingress-eudi-dev 18205
config=$(curl -fs http://localhost:18205/api/config)
expect "base URL" "$(json base_url <<<"$config")" https://eudi.example.com
expect "issuer URL" "$(json issuer_url <<<"$config")" https://eudi.example.com
expect "validation mode" "$(json validation_mode <<<"$config")" strict
expect "auto-accept" "$(json auto_accept <<<"$config")" False

log "Outbound proxy: requests to issuers go through the proxy"
kubectl create deployment proxy --image=python:3.13-alpine --port=3128 -- python -u -c '
import http.server
class Proxy(http.server.BaseHTTPRequestHandler):
    def answer(self):
        print(self.requestline)
        self.send_error(502)
    do_GET = do_POST = do_CONNECT = answer
http.server.ThreadingHTTPServer(("", 3128), Proxy).serve_forever()' >/dev/null
kubectl expose deployment proxy --port=3128 >/dev/null
kubectl rollout status deployment/proxy --timeout=180s >/dev/null
install proxy -f "$CHART/ci/proxy-values.yaml"
forward t-proxy svc/proxy-eudi-dev 18207
no_proxy=$(kubectl -n t-proxy get deployment proxy-eudi-dev -o 'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="NO_PROXY")].value}')
expect "NO_PROXY" "$no_proxy" internal.example,.svc,.cluster.local
expect "egress to the proxy port" "$(kubectl -n t-proxy get networkpolicy proxy-eudi-dev -o 'jsonpath={.spec.egress[*].ports[*].port}')" "53 53 3128"
for uri in http://issuer.example.test/offer https://issuer.example.test/offer; do
  curl -s -X POST http://localhost:18207/api/offers -H 'Content-Type: application/json' \
    -d "{\"uri\":\"openid-credential-offer://?credential_offer_uri=$uri\"}" >/dev/null || true
done
proxied=$(kubectl logs deployment/proxy)
# seen PATTERN TEXT prints yes when TEXT contains PATTERN. The wallet may retry, so a
# request can appear more than once.
seen() { grep -qF "$1" <<<"$2" && echo yes || echo no; }
expect "http request through the proxy" "$(seen 'GET http://issuer.example.test/offer' "$proxied")" yes
expect "https tunnel through the proxy" "$(seen 'CONNECT issuer.example.test:443' "$proxied")" yes

log "Path prefix: https://example.com/some/context"
install prefix --set ingress.enabled=true --set ingress.hostname=example.com \
  --set ingress.path=/some/context --set ingress.tls=true --set ingress.selfSigned=true
forward t-prefix svc/prefix-eudi-dev 18206
# Requests as the ingress forwards them, with the prefix kept.
get() { curl -s -o /dev/null -w '%{http_code}' -H 'Host: example.com' -H 'X-Forwarded-Proto: https' "http://localhost:18206$1"; }
expect "API under the prefix" "$(get /some/context/api/version)" 200
expect "demo issuer metadata at the host root" "$(get /.well-known/openid-credential-issuer/some/context/issuer)" 200
expect "wallet issuer metadata at the host root" "$(get /.well-known/jwt-vc-issuer/some/context)" 200
metadata=$(curl -fs -H 'Host: example.com' http://localhost:18206/.well-known/openid-credential-issuer/some/context/issuer)
expect "demo issuer identifier" "$(json credential_issuer <<<"$metadata")" https://example.com/some/context/issuer
location=$(curl -s -o /dev/null -D - -H 'Host: example.com' http://localhost:18206/some/context/decoder | tr -d '\r' | awk -F': ' 'tolower($1) == "location" {print $2}')
expect "redirect stays under the prefix" "$location" /some/context/decoder/

log "Wallet options: flags, keys, templates, imprint and imported credentials"
kubectl create namespace t-options >/dev/null
workdir=$(mktemp -d)
for key in holder issuer; do
  openssl ecparam -name prime256v1 -genkey -noout -out "$workdir/$key.pem" 2>/dev/null
  kubectl -n t-options create secret generic "e2e-$key-key" --from-file=key.pem="$workdir/$key.pem" >/dev/null
done
# A credential and a CA from the default wallet, so the demo verifier trusts a foreign issuer.
curl -fs "http://localhost:18200/api/credentials/$(issue 18200)" | json raw >"$workdir/employee.sdjwt"
kubectl -n t-options create configmap e2e-credentials --from-file=employee.sdjwt="$workdir/employee.sdjwt" >/dev/null
curl -fs http://localhost:18200/api/certificates/ca >"$workdir/ca.pem"
install options -f "$CHART/ci/options-values.yaml" --set-file "demoVerifier.trustAnchors=$workdir/ca.pem"
rm -rf "$workdir"
forward t-options svc/options-eudi-dev 18208
config=$(curl -fs http://localhost:18208/api/config)
expect "HAIP" "$(json require_haip <<<"$config")" True
expect "VCI version" "$(json vci_version <<<"$config")" 1.1
expect "session transcript" "$(json session_transcript <<<"$config")" iso
expect "preferred format" "$(json preferred_format <<<"$config")" mso_mdoc
expect "key attestation level" "$(json key_attestation_level <<<"$config")" none
expect "encrypted requests required" "$(json require_encrypted_request <<<"$config")" True
expect "client attestation" "$(json force_client_attestation <<<"$config")" True
expect "ad hoc display images" "$(json adhoc_display_images <<<"$config")" True
expect "status list" "$([ -n "$(json status_list_url <<<"$config")" ] && echo set)" set
expect "PID and imported credentials" "$(credential_count 18208)" 3
expect "credential template" "$(curl -fs http://localhost:18208/api/templates/employee-card | json vct)" urn:example:employee
expect "imprint" "$(curl -fs http://localhost:18208/imprint | grep -c 'E2E operator')" 1

log "All checks passed"
