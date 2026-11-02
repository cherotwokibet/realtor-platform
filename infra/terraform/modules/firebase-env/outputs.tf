output "project_id" {
  value = google_project.this.project_id
}

output "media_bucket" {
  value = google_storage_bucket.media.name
}

output "app_ids" {
  value = {
    android = google_firebase_android_app.app.app_id
    ios     = google_firebase_apple_app.app.app_id
    web     = google_firebase_web_app.app.app_id
    admin   = google_firebase_web_app.admin.app_id
  }
}

output "app_url" {
  value = google_firebase_hosting_site.app.default_url
}

output "admin_url" {
  value = google_firebase_hosting_site.admin.default_url
}

output "share_pages_url" {
  value = one(google_cloud_run_v2_service.share_pages[*].uri)
}

output "share_pages_repo" {
  value = "${local.region}-docker.pkg.dev/${google_project.this.project_id}/${google_artifact_registry_repository.share_pages.repository_id}"
}

output "share_url" {
  value = google_firebase_hosting_site.share.default_url
}
