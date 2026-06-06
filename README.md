# infra-as-code-lab

Infrastructure-as-Code laboratory: Terraform provisions resources (on LocalStack, no cloud costs) and Ansible configures the server idempotently. Fully reproducible with a single command.

## Stack

- **LocalStack** - AWS API emulator running locally via Docker
- **Terraform** - provisions VPC, subnet, security group, and S3 bucket against LocalStack
- **Ansible** - configures an nginx web server on a Docker target container
- **Docker Compose** - orchestrates both LocalStack and the target node

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Docker + Docker Compose | 24.x |
| Terraform | 1.7.x |
| Ansible | 2.16.x |
| GNU Make | 4.x |

## Quick start

```bash
make all
```

This single command:
1. Starts LocalStack and the target container
2. Runs `terraform apply` against LocalStack
3. Runs the Ansible playbook against the target container
4. Verifies the web server is responding at `http://localhost:8080`

## Individual targets

| Command | Description |
|---------|-------------|
| `make up` | Start containers |
| `make provision` | Run Terraform + Ansible |
| `make verify` | Check web server health |
| `make destroy` | Tear down infrastructure and containers |
| `make clean` | Remove Terraform state and cached providers |

## Project layout

```
infra-as-code-lab/
- terraform/          Terraform configuration (main, variables, outputs)
- ansible/            Inventory, playbook, and webserver role
- workflows/          Step-by-step workflow documentation
- docker-compose.yml  LocalStack + target node
- Makefile            Automation targets
```

## Idempotency

Re-running `make provision` is safe. Terraform computes only the delta against existing state. Ansible tasks are written to be idempotent - running the playbook multiple times produces the same result without side effects.
