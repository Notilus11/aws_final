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

resource "aws_s3_bucket_cors_configuration" "app_bucket_cors" {
  bucket = aws_s3_bucket.app_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["POST", "GET", "PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_object" "app_py" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key    = "app.py"
  source = "${path.module}/app.py"
  etag   = filemd5("${path.module}/app.py")
}

resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key    = "index.html"
  source = "${path.module}/index.html"
  etag   = filemd5("${path.module}/index.html")
}
