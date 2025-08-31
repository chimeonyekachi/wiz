## provider variables
variable "subscription_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type = string
}

## iac variables
variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "prefix" {
  type = string
}

variable "admin_username" {
  type = string
}

# SSH Public Key to use your public key
variable "ssh_public_key" {
  type = string
}

# the Mongo DB backup container name
variable "backup_container_name" {
  type = string
}

# AKS node count/size
variable "aks_node_count" {
  type    = number
  default = 2
}

variable "aks_node_size" {
  type    = string
  default = "Standard_DS2_v2"
}
