variable "region" {
  description = "AWS region. Frozen by ADR-0011 (A-016)."
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = var.region == "ap-south-1"
    error_message = "ADR-0011 freezes the primary region to ap-south-1 (Mumbai)."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, as owner/name (e.g. acme/project-varanasi)."
  type        = string
}

variable "app_instance_type" {
  description = "Staging app server (Graviton/ARM). Adjustable per ADR-0011."
  type        = string
  default     = "m7g.large"
}

variable "db_instance_class" {
  description = "Staging RDS size. Adjustable per ADR-0011."
  type        = string
  default     = "db.t4g.micro"
}

variable "postgres_engine_version" {
  description = "RDS PostgreSQL version; keep the major version in step with docker-compose.yml."
  type        = string
  default     = "17"
}

variable "domain_name" {
  description = "Optional staging hostname (e.g. staging.example.com). Empty = HTTP on the ALB DNS name."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Hosted zone for domain_name. Required when domain_name is set."
  type        = string
  default     = ""
}
