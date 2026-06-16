# S3 bucket for the application (ensure a globally unique name using random string)
resource "random_string" "s3_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "app_bucket" {
  bucket        = "${var.project_name}-assets-${random_string.s3_suffix.result}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-bucket"
  }
}
