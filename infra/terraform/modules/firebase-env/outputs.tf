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
  }
}
