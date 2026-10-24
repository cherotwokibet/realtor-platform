# Terraform (Phase 1, "Tenant CLI + Terraform")

One module per tenant: Firebase project (dev/stage/prod), Firestore, Storage, rules, indexes, Secret Manager entries, and a Typesense collection. `tenant create <id>` will call it.

Until then, create projects in the Firebase console using the IDs in `tenants/<id>.json` → `firebase.projects`.
