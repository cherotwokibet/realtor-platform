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
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "firebase.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firebasehosting.googleapis.com",
    "firebaserules.googleapis.com",
    "firebasestorage.googleapis.com",
    "firestore.googleapis.com",
    "identitytoolkit.googleapis.com",
    "pubsub.googleapis.com",
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

# Composite indexes from the repo's firestore.indexes.json (the same file
# the Firebase CLI and the emulator read), keyed by collection and fields.
resource "google_firestore_index" "composite" {
  for_each = {
    for ix in var.firestore_indexes.indexes :
    "${ix.collectionGroup}:${join(",", [for f in ix.fields : "${f.fieldPath}-${lookup(f, "order", lookup(f, "arrayConfig", ""))}"])}" => ix
  }
  project     = google_project.this.project_id
  database    = google_firestore_database.default.name
  collection  = each.value.collectionGroup
  query_scope = lookup(each.value, "queryScope", "COLLECTION")

  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path   = fields.value.fieldPath
      order        = lookup(fields.value, "order", null)
      array_config = lookup(fields.value, "arrayConfig", null)
    }
  }
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

# Cloud Functions (2nd gen) needs these service agents to hold roles before
# the first deploy: storage events reach Eventarc through Pub/Sub, and the
# functions run as the Compute default service account. The Firebase CLI
# tries to grant them itself and fails without project-owner rights.
data "google_storage_project_service_account" "gcs" {
  project    = google_project.this.project_id
  depends_on = [google_project_service.apis]
}

# Eventarc's agent validates the media bucket when the storage trigger is
# created; its role arrives late on a fresh project, so grant it up front.
resource "google_project_service_identity" "eventarc" {
  provider   = google-beta
  project    = google_project.this.project_id
  service    = "eventarc.googleapis.com"
  depends_on = [google_project_service.apis]
}

resource "google_project_service_identity" "pubsub" {
  provider   = google-beta
  project    = google_project.this.project_id
  service    = "pubsub.googleapis.com"
  depends_on = [google_project_service.apis]
}

locals {
  compute_sa = "serviceAccount:${google_project.this.number}-compute@developer.gserviceaccount.com"
  functions_agent_roles = {
    gcs_publishes_events = { member = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}", role = "roles/pubsub.publisher" }
    pubsub_signs_tokens  = { member = "serviceAccount:${google_project_service_identity.pubsub.email}", role = "roles/iam.serviceAccountTokenCreator" }
    functions_invoke_run = { member = local.compute_sa, role = "roles/run.invoker" }
    functions_get_events = { member = local.compute_sa, role = "roles/eventarc.eventReceiver" }
  }
}

resource "google_project_iam_member" "functions_agents" {
  for_each   = local.functions_agent_roles
  project    = google_project.this.project_id
  role       = each.value.role
  member     = each.value.member
  depends_on = [google_project_service.apis]
}

# Staff admin (P5): its own web app and Hosting site. Hosting serves the
# linked app's config at /__/firebase/init.json, so no config is committed.
resource "google_firebase_web_app" "admin" {
  provider     = google-beta
  project      = google_project.this.project_id
  display_name = "${local.t.name} admin (${var.env})"
  depends_on   = [google_firebase_project.this]
}

resource "google_firebase_hosting_site" "admin" {
  provider = google-beta
  project  = google_project.this.project_id
  # Site ids are at most 30 characters.
  site_id = "${trimsuffix(substr(local.project_id, 0, 24), "-")}-admin"
  app_id  = google_firebase_web_app.admin.app_id
}

# Sign-in (D14): email + password here. Google is switched on once in the
# Firebase console (Authentication > Sign-in method > Google), which makes
# its OAuth client without a client secret ever entering this state. Staff
# roles are custom claims set by the setStaffRole Function, never here.
resource "google_identity_platform_config" "auth" {
  project = google_project.this.project_id
  authorized_domains = [
    "localhost",
    "${local.project_id}.firebaseapp.com",
    "${local.project_id}.web.app",
    "${google_firebase_hosting_site.admin.site_id}.web.app",
    "${google_firebase_hosting_site.admin.site_id}.firebaseapp.com",
  ]
  sign_in {
    allow_duplicate_emails = false
    email {
      enabled           = true
      password_required = true
    }
  }
  depends_on = [google_project_service.apis, google_firebase_project.this]
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

# Share pages (D2): a Cloud Run service that only reads Firestore. Created once
# an image is given; Firebase Hosting rewrites the share domain to it.
resource "google_service_account" "share_pages" {
  project      = google_project.this.project_id
  account_id   = "share-pages"
  display_name = "Share pages (read-only Firestore)"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "share_pages_firestore" {
  project = google_project.this.project_id
  role    = "roles/datastore.viewer"
  member  = "serviceAccount:${google_service_account.share_pages.email}"
}

resource "google_cloud_run_v2_service" "share_pages" {
  count               = var.share_pages_image == null ? 0 : 1
  project             = google_project.this.project_id
  name                = "share-pages"
  location            = local.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  labels              = local.labels
  deletion_protection = var.env == "prod"

  template {
    service_account = google_service_account.share_pages.email
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
    containers {
      image = var.share_pages_image
      env {
        name  = "FIRESTORE_PROJECT"
        value = google_project.this.project_id
      }
      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }
      startup_probe {
        http_get {
          path = "/healthz"
        }
      }
    }
  }
  depends_on = [google_project_iam_member.share_pages_firestore]
}

# Public pages: anyone (and Hosting) may call the service.
resource "google_cloud_run_v2_service_iam_member" "share_pages_public" {
  count    = var.share_pages_image == null ? 0 : 1
  project  = google_project.this.project_id
  location = local.region
  name     = google_cloud_run_v2_service.share_pages[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
