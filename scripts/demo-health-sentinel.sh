#!/usr/bin/env bash
# Local rehearsal of Demo B — Health Sentinel bad deploy + rollback.
# Requires kubectl context already pointed at GCP or Azure demo cluster.
set -euo pipefail

NAMESPACE="${1:-idea-board-demo}"
DEPLOYMENT="${2:-backend}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Snapshot revision =="
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'

echo "== Inject FORCE_READINESS_FAIL=1 =="
kubectl set env "deployment/${DEPLOYMENT}" -n "$NAMESPACE" FORCE_READINESS_FAIL=1

# RollingUpdate keeps the old Ready pod — delete so only the failing revision remains.
echo "== Force replace pods =="
kubectl delete pods -n "$NAMESPACE" -l "app=${DEPLOYMENT}" --wait=false
sleep 20
kubectl get pods -n "$NAMESPACE" -l "app=${DEPLOYMENT}"

echo "== Run Health Sentinel (undo on failure) =="
python "${ROOT}/scripts/health_sentinel.py" \
  --namespace "$NAMESPACE" \
  --deployment "$DEPLOYMENT" \
  --wait-seconds 90 \
  --max-restarts 3 \
  --undo

echo "== Ensure flag reset =="
kubectl set env "deployment/${DEPLOYMENT}" -n "$NAMESPACE" FORCE_READINESS_FAIL=0
kubectl rollout status "deployment/${DEPLOYMENT}" -n "$NAMESPACE" --timeout=180s
kubectl get pods -n "$NAMESPACE" -l "app=${DEPLOYMENT}"
echo "Done."
