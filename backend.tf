#######################################
# Azure state isolation
#######################################

terraform {
  # The previous AWS terraform.tfstate is intentionally left untouched.
  # Run `terraform init -reconfigure`; do not migrate the AWS state.
  backend "local" {
    path = "azure.tfstate"
  }
}
