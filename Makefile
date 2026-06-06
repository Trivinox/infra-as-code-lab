.PHONY: up down provision destroy clean all

# Start all containers and wait for readiness
up:
	docker compose up -d --wait
	@echo "[*] LocalStack and target container are ready."

# Stop and remove containers (data volumes preserved)
down:
	docker compose down

# Run Terraform init + apply, then Ansible playbook
provision: tf-apply ansible-run

# Terraform: initialize the working directory
tf-init:
	cd terraform && terraform init

# Terraform: plan without applying
tf-plan: tf-init
	cd terraform && terraform plan

# Terraform: apply infrastructure
tf-apply: tf-init
	cd terraform && terraform apply -auto-approve

# Terraform: destroy infrastructure
tf-destroy:
	cd terraform && terraform destroy -auto-approve

# Run Ansible playbook against the target container
ansible-run:
	ansible-playbook -i ansible/inventory.ini ansible/playbook.yml

# Verify the web server is responding
verify:
	curl -sf http://localhost:8080 && echo "[OK] Web server is up." || echo "[FAIL] Web server did not respond."

# Full teardown: Terraform destroy + containers down
destroy: tf-destroy down

# Remove Terraform state and cached providers
clean:
	rm -rf terraform/.terraform terraform/.terraform.lock.hcl terraform/terraform.tfstate terraform/terraform.tfstate.backup

# One-command full run: bring up infrastructure and configure it
all: up provision verify
