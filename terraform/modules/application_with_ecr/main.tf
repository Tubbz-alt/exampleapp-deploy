variable "name" {
  description = "Full name of this application, e.g. 'Energy Performance Certificate Register'"
}

variable "identifier" {
  description = <<HEREDOC
Short, unique identifier of this application, such as a prefix in JIRA - eg. 'EPC'
This will be used for two purposes -
1. Cost allocation
2. Access control to ECR repos for your choice of CI service
- so it must be unique, and once set, changing it can be fiddly.
HEREDOC
}

variable "ecr_repo_names" {
  type        = "list"
  description = "Names of container repositories(s) for this application. Do *not* include image tags"
}

# The following variables are used for tagging resources and cost allocation
variable "stage" {
  description = "One of dev, staging or production"
}

variable "tech_contact_email" {
  description = "Email address of the main technical contact for this application"
}

variable "business_unit" {
  description = "E.g. Digital Delivery, Digital Land, etc"
}

variable "budget_holder_email" {
  description = "Email address of the main budget holder for this application"
}

# Tag everything with this map:
locals {
  common_tags = {
    application-name       = "${var.name}"
    application-identifier = "${var.identifier}"
    business_unit          = "${var.business_unit}"
    stage                  = "${var.stage}"
    tech-contact-email     = "${var.tech_contact_email}"
    budget-holder-email    = "${var.budget_holder_email}"
  }
}

# create the ECR repositories
resource "aws_ecr_repository" "ecr_repositories_list" {
  count = "${length(var.ecr_repo_names)}"
  name  = "${element(var.ecr_repo_names, count.index)}"

  tags = "${local.common_tags}"
}

# role to be assumed by the running application
# It's up to the individual application's deploy repo
# to set least-privilege permissions appropriately
# for this
data "aws_iam_policy_document" "ec2_ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com", "ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "application_runtime_role" {
  name               = "${var.identifier}-application"
  tags               = "${local.common_tags}"
  assume_role_policy = "${data.aws_iam_policy_document.ec2_ecs_assume_role_policy.json}"
}

# User + role to be assumed by a CI service (e.g. Travis, circle-ci, CodePipeline, etc)
resource "aws_iam_user" "application_ci_user" {
  name = "${var.identifier}-CI"
}

# Policy that grants push/pull/delete permission on any
# ECR repo tagged with this application's identifier.
# The policy is attached to the CI Role, which is then assumed
# by the CI IAM user
data "aws_iam_policy_document" "read_write_delete_on_application_ecr_repos" {
  statement {
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:BatchDeleteImage",
    ]

    effect    = "Allow"
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ecr:ResourceTag/application-identifier"

      values = [
        "${var.identifier}",
      ]
    }
  }

  statement {
    actions = [
      "ecr:GetAuthorizationToken",
    ]

    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "application_ci_policy" {
  name   = "${var.identifier}"
  policy = "${data.aws_iam_policy_document.read_write_delete_on_application_ecr_repos.json}"
}

resource "aws_iam_user_policy_attachment" "ci_can_read_write_app_ecr_repos" {
  policy_arn = "${aws_iam_policy.application_ci_policy.arn}"
  user       = "${aws_iam_user.application_ci_user.name}"
}

output "ecr_repo_arns" {
  value = ["${aws_ecr_repository.ecr_repositories_list.*.arn}"]
}

output "ecr_repo_urls" {
  description = <<HEREDOC
Use these URLs to push/pull container images for your application.
The current user has full control over these repositories. I will 
also grant push/pull/list/describe permission to the C.I. IAM user
HEREDOC

  value = ["${aws_ecr_repository.ecr_repositories_list.*.repository_url}"]
}

output "application_iam_role_arn" {
  description = <<HEREDOC
Your application should run as this IAM role.
I've granted EC2 and ECS permissions to assume this role.
It's up to you to define any other permissions this role will need -
for instance, access to S3 buckets or RDS/DynamoDB/Aurora databases.
HEREDOC

  value = "${aws_iam_role.application_runtime_role.arn}"
}

output "application_iam_role_name" {
  value = "${aws_iam_role.application_runtime_role.name}"
}

output "application_ci_user_name" {
  description = <<HEREDOC
Your C.I. service should use these credentials to push/pull container images
to/from the ECR repositories listed above.
As I cannot output the secret key if I create credentials automatically, I have
left it up to you to create an access key for this user.
You can do this from the AWS console, where you will be given a ONE-TIME-ONLY
chance to view the secret key.
You should copy-and-paste the access key & secret into your CI service.
HEREDOC

  value = "${aws_iam_user.application_ci_user.name}"
}
