# Local rehearsal of Demo B — Health Sentinel bad deploy + rollback (Windows PowerShell).
# Requires kubectl on PATH (Docker Desktop / gcloud) and context on the target cluster.

param(
  [string]$Namespace = "idea-board-demo",
  [string]$Deployment = "backend"
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Docker Desktop ships kubectl; ensure PATH sees it in this session.
$ddKubectl = "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin"
if ((Test-Path "$ddKubectl\kubectl.exe") -and ($env:Path -notlike "*$ddKubectl*")) {
  $env:Path = "$ddKubectl;$env:Path"
}

Write-Host "== kubectl context =="
kubectl config current-context
Write-Host "== Snapshot revision =="
kubectl get deployment $Deployment -n $Namespace -o jsonpath="{.metadata.annotations.deployment\.kubernetes\.io/revision}"
Write-Host ""

Write-Host "== Inject FORCE_READINESS_FAIL=1 =="
kubectl set env "deployment/$Deployment" -n $Namespace FORCE_READINESS_FAIL=1

# RollingUpdate keeps the old Ready pod, so deployment still looks 1/1 healthy.
# Delete pods so only the new (failing readiness) revision remains.
Write-Host "== Force replace pods (so old Ready pod cannot mask the failure) =="
kubectl delete pods -n $Namespace -l "app=$Deployment" --wait=false
Start-Sleep -Seconds 20
kubectl get pods -n $Namespace -l "app=$Deployment"

Write-Host "== Run Health Sentinel (undo on failure) =="
python "$Root\scripts\health_sentinel.py" `
  --namespace $Namespace `
  --deployment $Deployment `
  --wait-seconds 90 `
  --max-restarts 3 `
  --undo

Write-Host "== Ensure flag reset =="
kubectl set env "deployment/$Deployment" -n $Namespace FORCE_READINESS_FAIL=0
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=180s
kubectl get pods -n $Namespace -l "app=$Deployment"
Write-Host "Done."
