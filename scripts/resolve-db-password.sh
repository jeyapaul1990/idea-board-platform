#!/usr/bin/env bash
# Resolve database password from contract secret_ref — keeps password out of Terraform state in Stage 1.
set -euo pipefail

PROVIDER="${1:?usage: resolve-db-password.sh <gcp|azure|aws> ...}"
shift

case "$PROVIDER" in
  gcp)
    PROJECT="${1:?project_id}"
    SECRET_ID="${2:?secret_id}"
    gcloud secrets versions access latest --secret="$SECRET_ID" --project="$PROJECT"
    ;;
  azure)
    VAULT="${1:?vault name}"
    SECRET="${2:?secret name}"
    az keyvault secret show --vault-name "$VAULT" --name "$SECRET" --query value -o tsv
    ;;
  aws)
    ARN="${1:?secret arn}"
    aws secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text
    ;;
  *)
    echo "Unknown provider: $PROVIDER" >&2
    exit 1
    ;;
esac
