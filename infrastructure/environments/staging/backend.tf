terraform {
  backend "s3" {
    # Backend configuration will be provided via -backend-config flag
    # or backend.hcl file during terraform init
  }
}
