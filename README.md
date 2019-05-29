# Example Application Deploy Code

This repo provides:
* a Terraform module to setup your deployment infrastructure
* an example of how to use it

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
