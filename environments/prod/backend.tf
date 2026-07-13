terraform {
  backend "s3" {
    bucket = "elden-state-bucket"
    key    = "environments/prod/terraform.tfstate"
    region = "ap-southeast-1"
  }
}


