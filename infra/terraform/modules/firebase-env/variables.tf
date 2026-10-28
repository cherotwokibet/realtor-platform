variable "tenant" {
  description = "Decoded tenants/<id>.json."
  type        = any
}

variable "env" {
  description = "dev, stage or prod: picks the project id from tenant.firebase.projects."
  type        = string
  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
  }
}

variable "billing_account" {
  description = "The realtor's own billing account (D1: the client pays cloud costs)."
  type        = string
}

variable "folder_id" {
  description = "Optional GCP folder for the project."
  type        = string
  default     = null
}

variable "secret_ids" {
  description = "Secret Manager ids referenced as secret://<id> in the tenant file. Created empty; values are added by hand, never by Terraform."
  type        = set(string)
  default     = []
}

variable "firestore_rules" {
  description = "Contents of firestore.rules."
  type        = string
}

variable "storage_rules" {
  description = "Contents of storage.rules."
  type        = string
}

variable "transcode_image" {
  description = "Video transcoder image (functions/transcode.Dockerfile, D15). Null skips the Cloud Run job; video uploads are then refused with a note."
  type        = string
  default     = null
}

variable "share_pages_image" {
  description = "Share pages image (apps/share_pages/Dockerfile) in Artifact Registry. Null skips the Cloud Run service."
  type        = string
  default     = null
}

variable "firestore_indexes" {
  description = "Decoded firestore.indexes.json: its `indexes` list becomes composite indexes."
  type        = any
  default     = { indexes = [] }
}
