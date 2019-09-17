module "example_app_with_two_images" {
  source              = "modules/application_with_ecr"
  name                = "Example application with two container images"
  identifier          = "EXAPP2ECR"
  business_unit       = "Digital Delivery"
  budget_holder_email = "your.budget.holder@communities.gov.uk"
  tech_contact_email  = "probably.your.team.email@communities.gov.uk"
  stage               = "dev"
  ecr_repo_names      = ["frontend", "backend"]
}

output "ecr_repo_arns" {
  value = "${module.example_app_with_two_images.ecr_repo_arns}"
}

output "ecr_repo_urls" {
  description = "Push container images to these URLs"
  value       = "${module.example_app_with_two_images.ecr_repo_urls}"
}

output "application_iam_role_arn" {
  value = "${module.example_app_with_two_images.application_iam_role_arn}"
}

output "application_iam_role_name" {
  value = "${module.example_app_with_two_images.application_iam_role_name}"
}

output "application_ci_user_name" {
  value = "${module.example_app_with_two_images.application_ci_user_name}"
}
