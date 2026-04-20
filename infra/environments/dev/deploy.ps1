param([switch]$Apply)
$ErrorActionPreference = 'Stop'

if ($Apply) {
    terraform apply -var-file=terraform.tfvars -target=module.bridge_ecs -auto-approve
} else {
    terraform plan -var-file=terraform.tfvars -target=module.bridge_ecs
}
