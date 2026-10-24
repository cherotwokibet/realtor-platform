# One Firebase project for one tenant and environment (D1): Firestore,
# Storage, rules, app registrations and empty Secret Manager secrets.

locals {
  t          = var.tenant
  project_id = local.t.firebase.projects[var.env]
  region     = local.t.firebase.region
  labels     = { tenant = local.t.id, env = var.env }
  apis = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "firebase.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firebaserules.googleapis.com",
    "firebasestorage.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

resource "google_project" "this" {
  project_id      = local.project_id
  name            = "${local.t.name} ${var.env}"
  billing_account = var.billing_account
  folder_id       = var.folder_id
  labels          = local.labels
  deletion_policy = var.env == "prod" ? "PREVENT" : "DELETE"
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_firebase_project" "this" {
  provider   = google-beta
  project    = google_project.this.project_id
  depends_on = [google_project_service.apis]
}

resource "google_firestore_database" "default" {
  project                 = google_project.this.project_id
  name                    = "(default)"
  location_id             = local.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = var.env == "prod" ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  depends_on              = [google_firebase_project.this]
}

resource "google_storage_bucket" "media" {
  project                     = google_project.this.project_id
  name                        = "${local.project_id}-media"
  location                    = local.region
  uniform_bucket_level_access = true
  labels                      = local.labels
  depends_on                  = [google_project_service.apis]
}

resource "google_firebase_storage_bucket" "media" {
  provider   = google-beta
  project    = google_project.this.project_id
  bucket_id  = google_storage_bucket.media.name
  depends_on = [google_firebase_project.this]
}

resource "google_firebaserules_ruleset" "firestore" {
  project = google_project.this.project_id
  source {
    files {
      name    = "firestore.rules"
      content = var.firestore_rules
    }
  }
  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_release" "firestore" {
  project      = google_project.this.project_id
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore.name
}

resource "google_firebaserules_ruleset" "storage" {
  project = google_project.this.project_id
  source {
    files {
      name    = "storage.rules"
      content = var.storage_rules
    }
  }
  depends_on = [google_firebase_storage_bucket.media]
}

resource "google_firebaserules_release" "storage" {
  project      = google_project.this.project_id
  name         = "firebase.storage/${google_storage_bucket.media.name}"
  ruleset_name = google_firebaserules_ruleset.storage.name
}

# App registrations: their configs become each flavor's firebase_options.
resource "google_firebase_android_app" "app" {
  provider     = google-beta
  project      = google_project.this.project_id
  display_name = "${local.t.name} (${var.env})"
  package_name = local.t.apps.androidId
  depends_on   = [google_firebase_project.this]
}

resource "google_firebase_apple_app" "app" {
  provider     = google-beta
  project      = google_project.this.project_id
  display_name = "${local.t.name} (${var.env})"
  bundle_id    = local.t.apps.iosId
  depends_on   = [google_firebase_project.this]
}

resource "google_firebase_web_app" "app" {
  provider     = google-beta
  project      = google_project.this.project_id
  display_name = "${local.t.name} (${var.env})"
  depends_on   = [google_firebase_project.this]
}

# Empty secrets only. Values are added in Secret Manager by the realtor's
# admin; Terraform state never holds them.
resource "google_secret_manager_secret" "refs" {
  for_each  = var.secret_ids
  project   = google_project.this.project_id
  secret_id = each.value
  labels    = local.labels
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}
