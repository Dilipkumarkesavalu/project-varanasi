# Copy these into the GitHub repository's "staging" environment variables
# (see docs/runbooks/staging-deploy.md). None of them is a secret.

output "github_variables" {
  description = "Set these as GitHub environment variables for the 'staging' environment."
  value = {
    AWS_REGION            = var.region
    AWS_DEPLOY_ROLE_ARN   = aws_iam_role.deploy.arn
    ECR_REGISTRY          = local.ecr_registry
    STAGING_INSTANCE_ID   = aws_instance.app.id
    STAGING_DEPLOY_BUCKET = aws_s3_bucket.deploy.bucket
    STAGING_URL           = local.public_origin
  }
}
