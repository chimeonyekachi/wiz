terraform {
  required_version = ">= 1.3.0"

  backend "azurerm" {
    resource_group_name  = "wiz_tfstate_rg"
    storage_account_name = "wiztfstatefile"
    container_name       = "tfstate"
    key                  = "wiz-exercise.terraform.tfstate"
  }
}
