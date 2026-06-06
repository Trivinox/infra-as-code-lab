# Manual Workflow - Step by Step

This document describes how to execute the full workflow command by command. Each step is labeled to indicate whether it requires human action or runs automatically.

- `[MANUAL]` - a command or decision that must be executed by the operator
- `[AUTO]` - a process triggered automatically once the preceding command runs

---

## Phase 1 - Environment Setup

### 1.1 Verify prerequisites

`[MANUAL]` Check that all required tools are installed and meet minimum versions:

```bash
docker --version         # expected: 24.x or higher
docker compose version   # expected: v2.x
terraform --version      # expected: 1.7.x or higher
ansible --version        # expected: 2.16.x or higher
make --version           # expected: 4.x or higher
```

If any tool is missing, install it before continuing.

### 1.2 Start containers

`[MANUAL]` Start LocalStack and the target container:

```bash
docker compose up -d --wait
```

`[AUTO]` Docker Compose pulls missing images, creates the containers, and blocks until the healthchecks for both services pass.

### 1.3 Confirm containers are healthy

`[MANUAL]` Verify both containers are running and healthy:

```bash
docker compose ps
```

Expected output: both `infra-lab-localstack` and `infra-lab-target` show `healthy` status.

`[MANUAL]` Confirm LocalStack is accepting requests:

```bash
curl http://localhost:4566/_localstack/health
```

Expected: JSON response listing the active services (ec2, s3, etc.).

---

## Phase 2 - Terraform (Infrastructure Provisioning)

### 2.1 Initialize Terraform

`[MANUAL]` Navigate to the Terraform directory and initialize the working directory:

```bash
cd terraform
terraform init
```

`[AUTO]` Terraform downloads the AWS provider plugin and sets up the `.terraform` cache directory.

### 2.2 Review the execution plan

`[MANUAL]` Generate and inspect the plan before applying:

```bash
terraform plan
```

`[AUTO]` Terraform connects to LocalStack and computes the list of resources to create:
- `aws_vpc.main`
- `aws_subnet.public`
- `aws_internet_gateway.main`
- `aws_security_group.web`
- `aws_s3_bucket.artifacts`
- `aws_s3_bucket_versioning.artifacts`

`[MANUAL]` Read the plan output. Confirm the number of resources to add matches expectations (6 to add, 0 to change, 0 to destroy on first run).

### 2.3 Apply the infrastructure

`[MANUAL]` Apply the plan:

```bash
terraform apply
```

`[MANUAL]` Type `yes` when prompted to confirm the apply.

`[AUTO]` Terraform provisions all resources against LocalStack. On success, outputs are printed:
- `vpc_id`
- `subnet_id`
- `security_group_id`
- `s3_bucket_name`
- `localstack_endpoint`

### 2.4 Verify provisioned resources

`[MANUAL]` Return to the project root and confirm the VPC exists via the AWS CLI (pointing at LocalStack):

```bash
cd ..
aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs --region us-east-1
```

`[MANUAL]` Confirm the S3 bucket exists:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls --region us-east-1
```

---

## Phase 3 - Ansible (Configuration Management)

### 3.1 Confirm SSH connectivity to the target container

`[MANUAL]` Test SSH access before running the playbook:

```bash
ssh -o StrictHostKeyChecking=no -p 2222 ansible@127.0.0.1
```

Password: `ansible`

`[MANUAL]` Once inside, verify Python is available and exit:

```bash
python3 --version
exit
```

### 3.2 Test Ansible connectivity

`[MANUAL]` Run an Ansible ping to confirm the inventory is configured correctly:

```bash
ansible -i ansible/inventory.ini webservers -m ping
```

Expected output:

```
target | SUCCESS => {
    "ping": "pong"
}
```

### 3.3 Review the playbook and role

`[MANUAL]` Inspect the playbook before executing it:

- `ansible/playbook.yml` - top-level play definition and task ordering
- `ansible/roles/webserver/tasks/main.yml` - individual tasks
- `ansible/roles/webserver/templates/` - Jinja2 templates for nginx config and the index page
- `ansible/roles/webserver/handlers/main.yml` - nginx reload handler

### 3.4 Dry-run the playbook (check mode)

`[MANUAL]` Run the playbook in check mode to preview changes without applying them:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --check
```

`[AUTO]` Ansible connects to the target, gathers facts, and reports which tasks would change state. No actual changes are made to the container.

### 3.5 Apply the playbook

`[MANUAL]` Execute the playbook:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

`[AUTO]` Ansible runs each task in the webserver role sequentially:

1. Installs nginx via apt
2. Enables and starts the nginx service
3. Deploys the rendered `index.html` from the Jinja2 template
4. Deploys the nginx virtual host configuration
5. Enables the virtual host symlink
6. Removes the default nginx site
7. Triggers the `Reload nginx` handler once all notifying tasks complete
8. Runs the post-task health check (HTTP GET to `localhost:80`)

`[AUTO]` Ansible prints a recap showing changed, ok, and failed counts per host.

---

## Phase 4 - Verification

### 4.1 Check the web server from the host machine

`[MANUAL]` Send an HTTP request to the mapped port:

```bash
curl -s http://localhost:8080
```

Expected: HTML page showing the host name, environment name, and tool tags (Terraform, Ansible).

### 4.2 Inspect nginx logs on the target container

`[MANUAL]` Open a shell on the target container and check access logs:

```bash
docker exec -it infra-lab-target bash
tail -f /var/log/nginx/infra-lab.local.access.log
```

`[MANUAL]` Exit the container:

```bash
exit
```

### 4.3 Confirm idempotency

`[MANUAL]` Re-run the playbook a second time:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

`[AUTO]` Ansible re-evaluates every task. Because the desired state already matches the actual state, all tasks report `ok` (not `changed`) and the handler does not fire.

---

## Phase 5 - Teardown

### 5.1 Destroy Terraform resources

`[MANUAL]` Remove the resources from LocalStack:

```bash
cd terraform
terraform destroy
```

`[MANUAL]` Type `yes` to confirm destruction.

`[AUTO]` Terraform deletes all six resources. LocalStack state is cleared.

### 5.2 Stop and remove containers

`[MANUAL]` Return to the project root and stop the environment:

```bash
cd ..
docker compose down
```

`[AUTO]` Docker Compose stops and removes both containers. The `localstack-data` volume is preserved unless explicitly removed.

### 5.3 (Optional) Clean Terraform cache

`[MANUAL]` Remove the local Terraform state and provider cache:

```bash
make clean
```

---

## Notes

- All Terraform operations target LocalStack at `http://localhost:4566`. No real AWS account or credentials are required.
- The `ansible_ssh_pass` in `inventory.ini` is intentional for this local lab. Do not use password-based SSH in production.
- The `geerlingguy/docker-ubuntu2204-ansible` image is purpose-built for Ansible testing and ships with Python and systemd support pre-configured.
