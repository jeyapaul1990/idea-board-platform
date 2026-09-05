# GitHub Actions — secrets & demo

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `ci.yml` (**CI/CD**) | push / PR | pytest → build → **Trivy (CRITICAL)** → push GHCR → on **`main`**: deploy GKE + Health Sentinel |
| `deploy-health-sentinel.yml` | `workflow_dispatch` | Manual/demo sentinel (incl. bad-deploy rollback) |

## Required secrets

| Secret | Used by | How to create |
| --- | --- | --- |
| `GCP_SA_KEY` | GKE deploy + sentinel | JSON key for a SA with `container.developer` on `idea-board-platform` |
| `AZURE_CREDENTIALS` | Azure path | Output of `az ad sp create-for-rbac --sdk-auth` with AKS access |
| `GEMINI_API_KEY` | Optional | [Google AI Studio](https://aistudio.google.com/apikey) — LLM incident summary |
| `OPENAI_API_KEY` | Optional | Fallback if Gemini unset |

Without an LLM key the sentinel still decides and rolls back; it only skips the prose summary.

**Trivy** is open source ([Aqua Trivy](https://github.com/aquasecurity/trivy), Apache-2.0). The workflow fails the job on **CRITICAL** findings (`ignore-unfixed: true`).

## Demo B — bad deploy + auto rollback

**Actions UI:** Actions → **Deploy Health Sentinel** → Run workflow  
- `cloud`: `gcp` or `azure`  
- `demo_bad_deploy`: **true**

**Local (no GitHub):**

```bash
# kubectl already on the target cluster
bash scripts/demo-health-sentinel.sh idea-board-demo backend
```

What happens:
1. Sets `FORCE_READINESS_FAIL=1` → `/readyz` returns 503 → pods not Ready  
2. Sentinel waits, marks **UNHEALTHY**, runs `kubectl rollout undo`  
3. Resets the env flag and confirms pods Ready again  

## GCP service account (minimal)

```bash
gcloud iam service-accounts create github-actions \
  --project=idea-board-platform

gcloud projects add-iam-policy-binding idea-board-platform \
  --member="serviceAccount:github-actions@idea-board-platform.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud iam service-accounts keys create gcp-sa.json \
  --iam-account=github-actions@idea-board-platform.iam.gserviceaccount.com

# Paste gcp-sa.json into GitHub → Settings → Secrets → GCP_SA_KEY
# Then delete the local key file.
```

Prefer Workload Identity Federation later; SA key is the fastest path for the case-study demo.
