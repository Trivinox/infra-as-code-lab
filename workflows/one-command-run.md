# One-Command Reproducible Run

This document describes the fully automated workflow triggered by a single `make all` command. It specifies what the operator must do once and what the toolchain handles automatically from that point forward.

- `[MANUAL]` - an action that requires human execution
- `[AUTO]` - a process that runs without further operator input

---

## Prerequisites

`[MANUAL]` Install the required tools on the host machine before the first run. This is a one-time setup.

| Tool | Minimum version | Installation reference |
|------|----------------|----------------------|
| Docker Desktop (or Engine + Compose plugin) | 24.x | https://docs.docker.com/get-docker/ |
| Terraform | 1.7.x | https://developer.hashicorp.com/terraform/install |
| Ansible | 2.16.x | https://docs.ansible.com/ansible/latest/installation_guide/ |
| GNU Make | 4.x | Included in most Linux distros; on macOS install via Homebrew |

`[MANUAL]` Clone or copy the project to the local machine and navigate to the project root:

```bash
cd infra-as-code-lab
```

---

## The Single Command

`[MANUAL]` Run:

```bash
make all
```

Everything from this point forward is `[AUTO]`.

---

## What Runs Automatically

The `all` target chains three sub-targets in order: `up`, `provision`, and `verify`.

---

### Stage 1 - `make up` (Container Startup)

`[AUTO]` `docker compose up -d --wait` is executed.

`[AUTO]` Docker pulls any missing images:
- `localstack/localstack:3.4`
- `geerlingguy/docker-ubuntu2204-ansible`

`[AUTO]` Two containers start:

| Container | Purpose | Exposed port |
|-----------|---------|-------------|
| `infra-lab-localstack` | AWS API emulator | 4566 |
| `infra-lab-target` | Ansible target node (Ubuntu + nginx) | 2222 (SSH), 8080 (HTTP) |

`[AUTO]` Docker Compose polls both healthchecks and blocks until both containers report `healthy`. The command does not return until the environment is ready.

`[AUTO]` A readiness message is printed:

```
[*] LocalStack and target container are ready.
```

---

### Stage 2 - `make provision` (Infrastructure + Configuration)

`provision` chains `tf-apply` and `ansible-run`.

#### 2a - `make tf-apply` (Terraform)

`[AUTO]` `terraform init` runs inside the `terraform/` directory.

`[AUTO]` The HashiCorp AWS provider is downloaded and cached under `terraform/.terraform/`.

`[AUTO]` `terraform apply -auto-approve` runs. The `-auto-approve` flag skips the interactive confirmation prompt.

`[AUTO]` Terraform creates six resources against LocalStack:

| Resource | Name |
|----------|------|
| VPC | `infra-lab-vpc` |
| Subnet | `infra-lab-public-subnet` |
| Internet Gateway | `infra-lab-igw` |
| Security Group | `infra-lab-web-sg` |
| S3 Bucket | `infra-lab-artifacts-dev` |
| S3 Bucket Versioning | (attached to the bucket above) |

`[AUTO]` Terraform writes state to `terraform/terraform.tfstate`.

`[AUTO]` Outputs are printed to stdout:
- `vpc_id`
- `subnet_id`
- `security_group_id`
- `s3_bucket_name`
- `s3_bucket_arn`
- `localstack_endpoint`

#### 2b - `make ansible-run` (Ansible)

`[AUTO]` `ansible-playbook -i ansible/inventory.ini ansible/playbook.yml` runs from the project root.

`[AUTO]` Ansible connects to the target container over SSH (port 2222).

`[AUTO]` Ansible gathers facts from the target (OS family, hostname, network interfaces, etc.).

`[AUTO]` The `webserver` role executes the following tasks in sequence:

| # | Task | Ansible module |
|---|------|----------------|
| 1 | Install nginx | `ansible.builtin.apt` |
| 2 | Enable and start nginx service | `ansible.builtin.service` |
| 3 | Render and deploy `index.html` | `ansible.builtin.template` |
| 4 | Render and deploy nginx virtual host config | `ansible.builtin.template` |
| 5 | Enable the virtual host symlink | `ansible.builtin.file` |
| 6 | Remove the default nginx site | `ansible.builtin.file` |

`[AUTO]` After all notifying tasks complete, the `Reload nginx` handler fires once and reloads the nginx configuration.

`[AUTO]` Two post-tasks run:
- HTTP GET to `localhost:80` on the target to confirm the web server returns HTTP 200
- Debug message prints the confirmed status code

`[AUTO]` Ansible prints a play recap:

```
PLAY RECAP *****
target : ok=9  changed=6  unreachable=0  failed=0
```

On subsequent runs (idempotent re-runs), the recap reads `changed=0`.

---

### Stage 3 - `make verify` (Health Check)

`[AUTO]` `curl -sf http://localhost:8080` sends an HTTP GET from the host to the target container's mapped port.

`[AUTO]` One of two messages is printed:

- `[OK] Web server is up.` - the server responded with HTTP 200
- `[FAIL] Web server did not respond.` - the request failed or returned a non-200 status

---

## Expected Total Runtime

| Stage | Approximate duration (first run) | Approximate duration (re-run) |
|-------|----------------------------------|-------------------------------|
| Container startup (image pull included) | 2-5 min | 15-30 s |
| Terraform apply | 20-40 s | 10-20 s |
| Ansible playbook | 60-90 s | 20-30 s |
| Verification | < 5 s | < 5 s |

---

## Re-running (Idempotency)

`[MANUAL]` If the containers are already running, `make all` can be re-executed at any time:

```bash
make all
```

`[AUTO]` Docker Compose detects that the containers are already healthy and skips the startup phase.

`[AUTO]` Terraform computes the delta against the existing state file. If no configuration changed, it reports `No changes. Infrastructure is up-to-date.`

`[AUTO]` Ansible re-evaluates every task. Tasks whose desired state already matches the actual state report `ok` instead of `changed`. No unnecessary changes are applied.

---

## Teardown

`[MANUAL]` To destroy all infrastructure and stop the containers:

```bash
make destroy
```

`[AUTO]` `terraform destroy -auto-approve` removes all six resources from LocalStack.

`[AUTO]` `docker compose down` stops and removes both containers.

`[MANUAL]` To also remove the Terraform state and provider cache:

```bash
make clean
```

---

## Notes

- `make all` does not require a real AWS account. All API calls target LocalStack at `http://localhost:4566`.
- The `-auto-approve` flag in `tf-apply` is intentional for this lab context. For production pipelines, remove it and gate the apply on a plan review step.
- The target container uses `geerlingguy/docker-ubuntu2204-ansible`, which ships with Python 3 and systemd configured for Docker - a requirement for Ansible's `service` module to work correctly inside a container.
- If `make all` fails at the Ansible stage due to an SSH timeout, wait 10 seconds and re-run. The target container's SSH daemon occasionally needs an extra moment after the healthcheck passes.
