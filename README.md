# Example Application Deploy Code

This repo provides:
* a Terraform module to setup your deployment infrastructure
* an example of how to use it

To use it in your own code, you'll need to reference the Terraform module:

```terraform
module "example_app_with_two_images" {
  source              = "https://github.com/communitiesuk/exampleapp-deploy/modules/application_with_ecr"
  # You can define as many ECR repositories as your application will need.
  # An ECR repository will be created for each entry in this list
  ecr_repo_names      = ["frontend", "backend"]

  # The rest of these parameters are used to tag the created infrastructure
  # for cost-allocation. It's important that you provide meaningful values.
  name                = "Name of your application"
  # The identifier should be a UNIQUE, short reference (usually an abbreviation)
  # for this application. It might correspond to a prefix in JIRA, for example.
  identifier          = "EXAPP2ECR"
  business_unit       = "Digital Delivery"
  budget_holder_email = "your.budget.holder@communities.gov.uk"
  tech_contact_email  = "probably.your.team.email@communities.gov.uk"
  stage               = "dev|staging|production"
}
```

This will create ECR repositories, IAM users & policies for your application and
CI to use.

It's up to you to create the actual infrastructure & backing services
that your application will run on.

PLEASE NOTE you should use the same cost-allocation tags for all of your infrastructure. For instance, tag all EC2 instances like this:

```terraform
resource "aws_instance" "my-test-instance" {
  ami             = "(some AMI id)"
  instance_type   = "t2.micro"

  tags {
    application-name        = "Name of your application"
    application-identifier  = "EXAPP2ECR"
    business-unit           = "Digital Delivery"
    budget-holder-email     = "your.budget.holder@communities.gov.uk"
    tech-contact-email      = "probably.your.team.email@communities.gov.uk"
    stage                   = "dev|staging|production"
  }
}
```

To save duplication, you can define your standard tags as a `local` map, like this:
```terraform

locals {
  standard_tags = {
    application-name        = "Name of your application"
    application-identifier  = "EXAPP2ECR"
    business-unit           = "Digital Delivery"
    budget-holder-email     = "your.budget.holder@communities.gov.uk"
    tech-contact-email      = "probably.your.team.email@communities.gov.uk"
    stage                   = "dev|staging|production"
  }
}
```
and then _most_ (not all, sadly) AWS resources allow you to pass them as a single map:
```terraform
resource "aws_instance" "my-test-instance" {
  ami             = "(some AMI id)"
  instance_type   = "t2.micro"

  tags = "${local.standard_tags}"
}
```

## Deployment Model

Each application will have:
* one or more Elastic Container Repository (ECR) repositories to store container images
* an IAM role for the application to run as (e.g. to be assumed by EC2 instances)
* an IAM user for a Continuous Integration service to use, with permission ONLY to push/pull/delete to/from the application's ECR repositories - this user be given short-lived credentials for the ECR repo using the `aws get login` command (see below)


## Interacting with ECR repositories

AWS's ECR command line tool can generate a `docker login` command with short-lived credentials like so:
```
aws ecr get-login --region eu-west-2 --no-include-email
```
NOTE: this command will use whatever credentials are present in its environment, so you can either set them explicitly with AWS_ACCESS_KEY_ID & AWS_SECRET_ACCESS_KEY, or (better) write them to the ~/.aws/credentials file as a named profile, and then pass AWS_PROFILE=(profile name) to the command.

Your CI service can therefore generate & execute a docker login like this:
```
$(AWS_PROFILE=(profile name) aws ecr get-login --region eu-west-2 --no-include-email)
```
...and then `docker push` as normal.
