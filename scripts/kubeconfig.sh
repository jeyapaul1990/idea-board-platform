#!/usr/bin/env bash
# The single cloud-aware seam: fetch kube credentials before Stage 2 apply.
set -euo pipefail

CLOUD="${1:?usage: kubeconfig.sh <gcp|azure|aws> [extra args]}"
shift

case "$CLOUD" in
  gcp)
    # kubeconfig.sh gcp PROJECT_ID ZONE CLUSTER_NAME
    PROJECT_ID="${1:?project_id required}"
    ZONE="${2:?zone required}"
    CLUSTER="${3:?cluster name required}"
    gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID"
    ;;
  azure)
    # kubeconfig.sh azure RESOURCE_GROUP CLUSTER_NAME
    RG="${1:?resource group required}"
    CLUSTER="${2:?cluster name required}"
    az aks get-credentials --resource-group "$RG" --name "$CLUSTER" --overwrite-existing
    ;;
  aws)
    # kubeconfig.sh aws REGION CLUSTER_NAME
    REGION="${1:?region required}"
    CLUSTER="${2:?cluster name required}"
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
    ;;
  *)
    echo "Unknown cloud: $CLOUD" >&2
    exit 1
    ;;
esac

echo "Kubeconfig updated for $CLOUD"
