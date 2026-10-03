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
#   PREFIX_TESTS=true  also test a wallet under a path prefix (needs eudi-dev 2.6.0 or later)
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
    kubectl delete deployment,service postgres --ignore-not-found >/dev/null 2>&1 || true
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
  kubectl create namespace "$ns" >/dev/null
  helm install "$name" "$CHART" --namespace "$ns" --wait --timeout 300s "${IMAGE_ARGS[@]+"${IMAGE_ARGS[@]}"}" "$@" >/dev/null
}

# forward NS TARGET LOCAL_PORT forwards LOCAL_PORT to the wallet and waits until it answers.
forward() {
  kubectl -n "$1" port-forward "$2" "$3:8085" >/dev/null 2>&1 &
  PF_PIDS+=("$!")
  for _ in $(seq 1 60); do
    curl -fs "http://localhost:$3/api/version" >/dev/null && return
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

log "Default values: memory storage and the in-cluster URL"
install default -f "$CHART/ci/default-values.yaml"
forward t-default svc/default-eudi-dev 18200
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

log "Ingress: public https URL and strict mode"
install ingress -f "$CHART/ci/ingress-values.yaml"
forward t-ingress svc/ingress-eudi-dev 18205
config=$(curl -fs http://localhost:18205/api/config)
expect "base URL" "$(json base_url <<<"$config")" https://eudi.example.com
expect "issuer URL" "$(json issuer_url <<<"$config")" https://eudi.example.com
expect "validation mode" "$(json validation_mode <<<"$config")" strict
expect "auto-accept" "$(json auto_accept <<<"$config")" False

if [ "${PREFIX_TESTS:-}" = true ]; then
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
fi

log "All checks passed"
