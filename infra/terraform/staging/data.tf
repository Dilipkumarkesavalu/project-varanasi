# PostgreSQL (RDS), object storage (S3), container registry (ECR) and app secrets.

# --- RDS PostgreSQL: private, encrypted, master password managed by Secrets Manager ---

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "main" {
  identifier                  = local.name
  engine                      = "postgres"
  engine_version              = var.postgres_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "varanasi"
  username                    = "varanasi_admin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  multi_az                    = false # staging; production enables Multi-AZ (ADR-0011)
  backup_retention_period     = 7
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${local.name}-final"
  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
}

# --- Application secrets: DB role passwords (ADR-0006 roles), generated here ---

resource "random_password" "db_role" {
  for_each = toset(["migrator", "platform", "billing", "hrms"])
  length   = 32
  special  = false
}

resource "aws_secretsmanager_secret" "app" {
  name        = "varanasi/staging/app"
  description = "Varanasi staging application secrets (DB role passwords)"
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    for role, pw in random_password.db_role : "${role}_password" => pw.result
  })
}

# --- S3: tenant files (ADR-0006 tenants/{tenant_id}/ prefixes) and deploy bundles ---

resource "aws_s3_bucket" "files" {
  bucket_prefix = "${local.name}-files-"
}

resource "aws_s3_bucket" "deploy" {
  bucket_prefix = "${local.name}-deploy-"
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each                = { files = aws_s3_bucket.files.id, deploy = aws_s3_bucket.deploy.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = { files = aws_s3_bucket.files.id, deploy = aws_s3_bucket.deploy.id }
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    id     = "expire-old-bundles"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

# --- ECR: one repository per image; tags are immutable ---

resource "aws_ecr_repository" "images" {
  for_each             = toset(["varanasi-backend", "varanasi-web"])
  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 30 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}
