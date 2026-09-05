# Reusable Terraform modules (Stage 1 + Stage 2)

Cloud-agnostic deployment uses **reusable modules** and a fixed **contract** between stages.

## Layout

```
infra/
├── 10-cloud/                 # Stage 1 — ONLY cloud-specific code
│   ├── main.tf               #   picks module by var.cloud
│   └── modules/
│       ├── cloud-gcp/        #   GKE + Cloud SQL + VPC + Secret Manager
│       ├── cloud-azure/      #   AKS + Flexible Server + Key Vault (live)
│       └── cloud-aws/        #   same contract (plan-clean, no apply)
├── 20-platform/              # Stage 2 — ZERO cloud providers (kubernetes only)
└── envs/
    ├── gcp.tfvars            #   cloud = "gcp"
    ├── azure.tfvars
    ├── aws.tfvars
    ├── platform-gcp.tfvars
    └── platform-azure.tfvars
```

## The contract (every cloud module emits this)

```hcl
contract = {
  cloud = "gcp" | "azure" | "aws"
  cluster = {
    name, endpoint, ca_certificate, ...
  }
  database = {
    host, port, name, username,
    secret_ref = { provider, ... }   # NOT the password
  }
}
```

Stage 2 reads `contract` from remote state and deploys identical Kubernetes resources on every cloud.

**Password handling:** Stage 1 stores the password in Secret Manager / Key Vault / Secrets Manager. CI resolves it with `scripts/resolve-db-password.sh` and passes `-var='database_password=...'` to Stage 2 only. It never appears in Stage 1 outputs or state.

## Switching clouds

Change one variable in a tfvars file:

```hcl
# infra/envs/gcp.tfvars
cloud = "gcp"

# infra/envs/azure.tfvars
cloud = "azure"
```

Root `main.tf` uses `count` to select exactly one reusable module:

```hcl
module "cloud_gcp" { count = var.cloud == "gcp" ? 1 : 0 ... }
module "cloud_azure" { count = var.cloud == "azure" ? 1 : 0 ... }
local.contract = one(concat(module.cloud_gcp[*].contract, ...))
```

Adding a fourth cloud = implement one new module that outputs `contract`. Stage 2 unchanged.

## Deploy GCP (manual)

### Prerequisites

- Terraform >= 1.5, gcloud CLI, kubectl
- GCS bucket for remote state
- Enable APIs: `container`, `sqladmin`, `compute`, `servicenetworking`, `secretmanager`

### Stage 1 — cloud infrastructure

```bash
cd infra/10-cloud
cp backend.tf.example backend.tf   # set your bucket
terraform init
terraform plan -var-file=../envs/gcp.tfvars
terraform apply -var-file=../envs/gcp.tfvars
```

### Stage 2 — platform (Kubernetes)

```bash
# After apply, read outputs
terraform output -json contract

# Configure kubectl (the one cloud-aware seam)
./scripts/kubeconfig.sh gcp YOUR_PROJECT asia-south1-a idea-board-demo-gke

# Resolve DB password from secret_ref
export DB_PASS=$(./scripts/resolve-db-password.sh gcp YOUR_PROJECT idea-board-demo-db-password)

cd infra/20-platform
cp backend.tf.example backend.tf
terraform init
terraform plan \
  -var-file=../envs/platform-gcp.tfvars \
  -var="database_password=$DB_PASS"
terraform apply \
  -var-file=../envs/platform-gcp.tfvars \
  -var="database_password=$DB_PASS"

kubectl get svc frontend -n idea-board-demo
```

Public URL = `EXTERNAL-IP` of the frontend LoadBalancer service.

## Validate without apply

```bash
cd infra/10-cloud && terraform init -backend=false && terraform validate
cd infra/20-platform && terraform init -backend=false && terraform validate
```

AWS module: run `terraform plan` with AWS credentials for a stronger claim than `validate` alone (no resources created).
