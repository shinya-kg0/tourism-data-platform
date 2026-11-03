terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }

  # バケットは backend.hcl で渡す（terraform init -backend-config=backend.hcl）
  backend "gcs" {}
}
