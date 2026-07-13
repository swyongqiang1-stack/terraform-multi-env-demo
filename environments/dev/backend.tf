terraform {
  backend "s3" {
    bucket = "elden-state-bucket"
    key    = "environments/dev/terraform.tfstate"
    region = "ap-southeast-1"
  }
}


