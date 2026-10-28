# Root config: one state per tenant and environment. Everything comes from
# tenants/<tenant_id>.json; this file holds no realtor values.
#
#   terraform init -backend-config="prefix=<tenant_id>/<env>"
#   terraform plan -var tenant_id=<id> -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX

terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 7.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 7.0" }
  }
  backend "gcs" {
    bucket = "realtor-platform-tfstate"
  }
}

variable "tenant_id" {
  type = string
}

variable "env" {
  type = string
}

variable "billing_account" {
  type = string
}

variable "folder_id" {
  type    = string
  default = null
}

variable "transcode_image" {
  description = "Image for the video transcoder Cloud Run job (D15); leave unset until one is pushed."
  type        = string
  default     = null
}

variable "share_pages_image" {
  description = "Image for the share pages Cloud Run service; leave unset until one is pushed."
  type        = string
  default     = null
}

locals {
  repo        = "${path.module}/../../.."
  tenant_json = file("${local.repo}/tenants/${var.tenant_id}.json")
  tenant      = jsondecode(local.tenant_json)
  # Every "secret://<id>" anywhere in the tenant file.
  secret_ids = toset(flatten(regexall("secret://([a-z0-9-]+)", local.tenant_json)))
}

provider "google" {
  region = local.tenant.firebase.region
}

provider "google-beta" {
  region = local.tenant.firebase.region
}

module "env" {
  source          = "../modules/firebase-env"
  tenant          = local.tenant
  env             = var.env
  billing_account = var.billing_account
  folder_id       = var.folder_id
  secret_ids      = local.secret_ids
  firestore_rules = file("${local.repo}/firestore.rules")
  storage_rules   = file("${local.repo}/storage.rules")

  firestore_indexes = jsondecode(file("${local.repo}/firestore.indexes.json"))

  share_pages_image = var.share_pages_image
  transcode_image   = var.transcode_image
}

output "project_id" {
  value = module.env.project_id
}

output "app_ids" {
  value = module.env.app_ids
}

output "share_pages_url" {
  value = module.env.share_pages_url
}

output "admin_url" {
  value = module.env.admin_url
}

output "share_pages_repo" {
  value = module.env.share_pages_repo
}

output "share_url" {
  value = module.env.share_url
}
