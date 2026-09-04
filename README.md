# Idea Board — Outmarket DevOps Case Study

Full-stack app + cloud-agnostic Terraform platform. Phase 1 (local) is complete; Phase 2 adds reusable IaC modules.

## Run locally (Phase 1)

```bash
docker compose up --build
```

Open **http://localhost:8080**

- Frontend: port **8080** (nginx proxies `/api/*` to backend)
- Backend API: **http://localhost:8000**
- Postgres: **localhost:5433** (host) → 5432 (container)

## Infrastructure (Phase 2)

Terraform uses **reusable modules** with a shared **contract**:

| Stage | Path | What it does |
| --- | --- | --- |
| **Stage 1** | `infra/10-cloud/` | One module per cloud (`cloud-gcp`, `cloud-azure`, `cloud-aws`). Switch with `cloud = "gcp"` in tfvars. |
| **Stage 2** | `infra/20-platform/` | Kubernetes only — identical on every cloud. Reads contract from remote state. |

See **[infra/README.md](infra/README.md)** for deploy steps, contract shape, and `secret_ref` password handling.

```
infra/10-cloud/modules/
  cloud-gcp/    → GKE + Cloud SQL + VPC (live deploy)
  cloud-azure/  → same contract (Phase 3)
  cloud-aws/    → same contract (plan only)
```

## API

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/ideas` | List all ideas |
| POST | `/api/ideas` | Body: `{"content": "My new idea"}` |
| GET | `/healthz` | Liveness (no DB check) |
| GET | `/readyz` | Readiness (checks Postgres) |
| GET | `/metrics` | Prometheus metrics |

## Demo hooks (for later video)

**Bad deploy / rollback demo (AI 2 — Health Sentinel):** set `FORCE_READINESS_FAIL=1` on the backend service. `/readyz` returns 503. The sentinel detects Not Ready pods and runs `kubectl rollout undo`.

```yaml
# docker-compose.override.yml (do not commit for normal use)
services:
  backend:
    environment:
      FORCE_READINESS_FAIL: "1"
```

**CI demo:** GitHub → Actions → **Deploy Health Sentinel** → Run workflow with `demo_bad_deploy=true` (needs `GCP_SA_KEY` or `AZURE_CREDENTIALS`; see [`.github/README.md`](.github/README.md)).

**Local demo:**

```bash
bash scripts/demo-health-sentinel.sh
```

**Risky migration demo (AI 1):** copy `apps/backend/demo/demo_drop_content_column.py` into `alembic/versions/` on branch `demo/risky-migration`. Do not apply on `main`.

## Project layout

```
apps/backend/          FastAPI + Alembic + Postgres
apps/frontend/         React + Vite, nginx in production
infra/10-cloud/        Stage 1 — reusable cloud modules
infra/20-platform/     Stage 2 — cloud-agnostic Kubernetes
scripts/               kubeconfig, resolve-db-password, health_sentinel
.github/workflows/     CI (GHCR) + Deploy Health Sentinel
docker-compose.yml
```
