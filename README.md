# Example Application Deploy Code

This repo provides:
* a Terraform module to setup your deployment infrastructure
* an example of how to use it

To use it in your own code, you'll need to reference the Terraform module:

```terraform
module "example_app_with_two_images" {
  source              = "github.com/communitiesuk/exampleapp-deploy/terraform/modules/application_with_ecr"
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

## Tagging Resources

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

# Re-usable Modules
You can use the modules in this repo directly as components of your own infrastructure.

## VPC With Public And Private Subnets

Creates standard Well-Architected VPC setup across a specified number of AZs,
with a shared Internet Gateway that allows the contained infrastructure to get
out to the internet.
Each AZ has a public subnet, a private subnet, a NAT instance (much cheaper
than a NAT Gateway) with an appropriate security group, and routing tables
with appropriate rules.

Example usage:
```terraform
module "vpc_with_public_and_private_subnets" {
  source = "github.com/communitiesuk/exampleapp-deploy/terraform/modules/vpc_with_public_and_private_subnet"
  tags   = local.standard_tags
}
```

### Inputs

*tags*
A map of tags to apply to all infrastructure
Default: {}

*vpc_cidr_block*
A CIDR block describing the IP address range the VPC will use
Default: "10.0.0.0/16"

*az_count*
The number of AZs you want to create subnets in
Default: 2

*private_subnet_size*
The number of bits you want to extend the VPC CIDR block by, for your private subnets
Default: 8

*public_subnet_size*
The number of bits you want to extend the VPC CIDR block by, for your private subnets
Default: 8
