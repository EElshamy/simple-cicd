# Simple CI/CD + Terraform (AWS, EC2 + Docker Compose)

## What this is

This is a minimal Express app with Terraform that provisions:
- VPC, IGW, public subnet and route table
- ECR repository
- IAM instance profile (ECR pull + SSM)
- EC2 instance on Ubuntu 24.04 running the app via Docker Compose
- cloud-init that installs Docker + docker-compose plugin + AWS CLI v2
- systemd timer that polls SSM for a new image tag every 60 seconds and runs `docker compose up -d` via a small deploy script
- SSM Parameter Store to track the deployed image tag (so CI/CD never needs to mutate Terraform state)

CI/CD consists of two GitHub Actions workflows:
1. `ci.yml` (existing): build/test/lint-like checks and builds the Docker image (doesn't deploy).
2. `deploy.yml` (new): on push to `main`, builds/pushes the image to ECR, writes the new tag to SSM, invokes `deploy.sh` on the EC2 instance via SSM Run Command, and runs a smoke test against `APP_URL`. This is zero-downtime-ish (container recreated after pulling the new image when tag changes).
3. `infrastructure.yml` (new): manual workflow to run `terraform plan` or `terraform apply` (with a confirmation gate).

## Prerequisites

- AWS account with permissions to create VPC, EC2, ECR, IAM, SSM, Security Groups, Key Pairs
- AWS CLI configured locally or IAM user/role for GitHub Actions
- Terraform >= 1.6 (if running locally)
- GitHub repository variables/secrets as below

## 1) First-time Terraform bootstrap (local)

1. Copy the example tfvars:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Edit `terraform.tfvars`:
   - `aws_region` (e.g. `eu-central-1`)
   - `project_name` and `environment`
   - `ssh_allowed_cidrs` - leave `[]` to disable SSH entirely (recommended: use AWS SSM Session Manager instead). If you want SSH, set to `["YOUR_IP/32"]`.
   - `http_port` and `container_port` (default 80->3000). Opening port 80 on the instance means no reverse proxy needed.
3. (Optional, highly recommended) Enable remote state + locking. Uncomment and configure the S3 backend in `versions.tf`, then:
   ```bash
   terraform init -backend-config="bucket=<tfstate-bucket>" \
                   -backend-config="key=simple-cicd/terraform.tfstate" \
                   -backend-config="region=<region>" \
                   -backend-config="dynamodb_table=<tf-locks>" \
                   -backend-config="encrypt=true"
   ```
   If you don't want remote state yet, just `terraform init`.
4. Plan and apply:
   ```bash
   terraform plan
   terraform apply
   ```
5. Capture the outputs:
   ```bash
   terraform output
   ```
   Key outputs:
   - `app_url` - public URL to hit
   - `public_ip` - instance IP
   - `ecr_repository_url` (or `ecr_registry_id` + `ecr_repository_name`)
   - `ssm_image_tag_parameter` - SSM parameter name the pipeline updates
   - `instance_id` - for SSM sessions (`aws ssm start-session --target <instance_id>`)

## 2) GitHub Actions setup

Create the following **Repository Variables** (not secrets) in GitHub (`Settings > Secrets and variables > Actions > Variables`):

| Variable | Example | Description |
|---|---|---|
| `AWS_REGION` | `eu-central-1` | Region used for AWS resources |
| `APP_NAME` | `simple-cicd-prod` | Must match Terraform `project_name`-`environment` naming used (we used local.name). If you kept defaults, `simple-cicd-prod`. |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-actions-deploy` | Role assumed by `deploy.yml` to push to ECR, write SSM, and run SSM commands. |
| `AWS_TERRAFORM_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-actions-terraform` | Role assumed by `infrastructure.yml` for Terraform operations. |
| `ECR_REPOSITORY_NAME` | `simple-cicd-prod-app` | ECR repo name (from `terraform output ecr_repository_name`). |
| `SSM_IMAGE_TAG_PARAMETER` | `/simple-cicd-prod/image_tag` | SSM param name (from `terraform output ssm_image_tag_parameter`). |
| `APP_URL` | `http://1.2.3.4` or `http://your.domain` | Used for the smoke test in `deploy.yml` (from `terraform output app_url`). |

### IAM roles (OIDC recommended)

Use GitHub OIDC (no long-lived keys). Create two roles trust policies scoped to this repo:

- `github-actions-deploy` needs:
  - `ecr:*` on the repo (or `ecr:*` scoped to the specific repo ARN) and `ecr:GetAuthorizationToken`
  - `ssm:PutParameter`, `ssm:GetParameter`, `ssm:SendCommand`, `ssm:ListCommandInvocations`, `ssm:DescribeInstanceInformation` (scoped to your resources)
  - `iam:PassRole` not needed for this workflow
- `github-actions-terraform` needs full (or least-privilege) permissions to manage the resources Terraform creates. Also needs to read/write state if using S3+DynamoDB.

Trust policy example (replace `OWNER` and `REPO`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
        "StringLike": {"token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:*"}
      }
    }
  ]
}
```

## 3) How deployments work

1. Push to `main` triggers `deploy.yml`.
2. Image built and pushed with tags `sha-<short>` and `latest`.
3. Workflow writes `sha-<full>` (or the short tag) to SSM parameter `SSM_IMAGE_TAG_PARAMETER`.
4. SSM Run Command executes `/opt/<app>/deploy.sh` on the instance (targeted by tag `Name=<app-name>-server`).
5. The deploy script:
   - pulls the new image (`docker compose pull`)
   - recreates the container only if the image ID changed
   - waits for the container to become healthy (via Docker healthcheck)
6. Smoke test curls `APP_URL`. If it fails, the workflow fails.

The EC2 instance also polls SSM every 60s via systemd timer, so even if SSM Run Command fails, it will eventually converge to the tag in SSM.

## 4) Infrastructure changes

Run Terraform via the `infrastructure.yml` workflow (manual dispatch):
- Select `operation: plan` first to review changes.
- Select `operation: apply` and type `APPLY` in the confirmation field to actually apply.

You can still run locally with your AWS credentials, but using OIDC + a dedicated role + manual dispatch is safer for CI.

## 5) Operations

- Connect to the instance without SSH: `aws ssm start-session --target $(terraform output -raw instance_id)`
- View logs: `journalctl -u app-deploy.service -n 50` or `docker compose logs -f` inside `/opt/<app>`
- Force an immediate deploy: `sudo /opt/<app>/deploy.sh` or re-run the deploy workflow
- Roll back: set the SSM parameter back to a previous tag (e.g. `aws ssm put-parameter --name <param> --value sha-abc123 --overwrite`) and wait ~60s or trigger a deploy

## Security notes

- SSH disabled by default (empty `ssh_allowed_cidrs`). Enable only if necessary and tightly scoped.
- IMDSv2 enforced (`http_tokens = "required"`).
- ECR has image scanning on push and a lifecycle policy to keep the last N images.
- Docker container logs capped (`max-size: 10m`, `max-file: 3`).
- Instance EBS volume encrypted. All egress allowed (adjust `allowed_http_cidrs` and NACLs if you want to restrict outbound).
- Never commit `terraform.tfvars` or generated private keys. `.gitignore` already excludes them.

## Tips

- If the smoke test fails after deploy, check the instance logs via SSM session or CloudWatch (you can also ship logs to CloudWatch Logs later).
- The timer accuracy is 10s; `deploy_interval_seconds` controls polling frequency.
- To use a custom domain, put an ALB in front (not included here) and point DNS to it; then update `APP_URL` and security groups. The current setup is simple and exposes the instance directly on the chosen port.

## License

ISC (same as the app).