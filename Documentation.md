# Project Documentation — AWS 2-Tier Architecture via Terraform + Jenkins
# 1. Objective
Deploy a highly available 2-tier AWS architecture (Web Tier + Database Tier), fully automated with Infrastructure as Code (Terraform) and a CI/CD pipeline (Jenkins), using remote state management (S3 + DynamoDB) for team-safe, locked Terraform operations.

# 2. Target Architecture
See docs/architecture.svg.

## 1 Custom VPC (10.0.0.0/16)
## 2 Public Subnets (one per AZ) — host the web tier
## 2 Private Subnets (one per AZ) — host the database tier
## Internet Gateway attached to the VPC, routed from the public route table only
## 2 EC2 instances (Apache) in the public subnets, each behind its own security group allowing HTTP (80) and SSH (22)
## 1 RDS MySQL instance (Multi-AZ) in the private subnets, reachable only on port 3306 from the web tier's security group — not from the public internet
##Terraform remote state stored in an S3 bucket (versioned) with a DynamoDB table for state locking, preventing concurrent terraform apply runs from corrupting state
# 3. Target Technology Stack
Component	Choice	Reason
IaC tool	Terraform	Declarative, widely adopted, strong AWS provider support
CI/CD	Jenkins	Free, self-hosted, flexible pipeline-as-code
Compute	EC2 (Amazon Linux 2023)	Free-tier eligible, simple web server hosting
Database	RDS MySQL	Managed database, Multi-AZ for high availability
State backend	S3 + DynamoDB	Standard Terraform remote backend pattern; versioning + locking
VCS	GitHub	Source of truth for both Jenkins and Terraform code
# 4. Part I — Remote State Backend (Implemented via AWS Console)
## S3 Bucket
Name: project2-terraform-state-jithendra01
Region: us-east-1
Versioning: Enabled (protects against state corruption/overwrites)
Public access: fully blocked (default)
## DynamoDB Table
Name: terraform-locks
Partition key: LockID (String) — required exact name for Terraform's S3 backend to use it as a lock table
Billing mode: On-demand
## IAM User
Name: terraform-jenkins-user
Access type: Programmatic (Access Key ID + Secret Access Key)
Policies attached: AmazonEC2FullAccess, AmazonVPCFullAccess, AmazonRDSFullAccess, AmazonS3FullAccess, AmazonDynamoDBFullAccess, IAMReadOnlyAccess
# 5. Part III — 2-Tier Architecture (Implemented via Terraform)
Terraform code lives at the repo root:

provider.tf — AWS provider configuration
backend.tf — S3 + DynamoDB remote state configuration
variables.tf — region, VPC CIDR, DB credentials
vpc.tf — VPC, subnets, IGW, route tables, associations
security_groups.tf — web-sg (80/22 from anywhere) and rds-sg (3306 from web-sg only)
ec2.tf — 2 EC2 instances running Apache via user_data
rds.tf — RDS subnet group + MySQL instance (Multi-AZ)
outputs.tf — exposes web server public IPs and RDS endpoint
Resources created (18 total, per terraform plan): VPC, Internet Gateway, 4 subnets, 2 route tables, 4 route table associations, 2 security groups, 2 EC2 instances, 1 DB subnet group, 1 RDS instance.

# 6. Part II — Jenkins Pipeline
Jenkins Server Setup
EC2 instance (t2.medium, Amazon Linux 2023) in the default VPC
Installed via user_data: Java 17, Jenkins, Terraform 1.9.0, AWS CLI
Security group allows inbound SSH (22) and Jenkins UI (8080) from the administrator's IP
Credentials configured in Jenkins
Credential ID	Type	Purpose
AWS_ACCESS_KEY_ID	Secret text	Authenticates Terraform to AWS
AWS_SECRET_ACCESS_KEY	Secret text	Authenticates Terraform to AWS
db_password	Secret text	Injected as TF_VAR_db_password for the RDS master password
Pipeline Job
Type: Pipeline
Trigger: Poll SCM, schedule H/5 * * * * (checks GitHub every 5 minutes)
Definition: Pipeline script from SCM (Git), reading Jenkinsfile from the repo root, branch main
Pipeline Stages (Jenkinsfile)
Checkout Code — pulls the latest commit from GitHub
Setup Terraform Environment — confirms terraform -version
Terraform Init — connects to the S3/DynamoDB backend, installs providers
Terraform Plan — generates and saves an execution plan (tfplan)
Approval — pipeline pauses (input step) until a human clicks Apply
Terraform Apply — applies the saved plan, provisioning all resources
# 7. Issues Encountered & Fixes
Issue	Root Cause	Fix
terraform init failed with "S3 bucket does not exist"	backend.tf had a typo in the bucket name (tfstate vs terraform-state)	Corrected the bucket name in backend.tf to match the actual S3 bucket exactly, committed and pushed
Jenkins pipeline needed manual confirmation before provisioning	By design — terraform apply should never run unattended in a learning/production environment without review	Added an input step in the Jenkinsfile between Plan and Apply
# 8. Verification
terraform plan showed 18 to add, 0 to change, 0 to destroy before every apply
After apply, confirmed in AWS Console:
VPC with 4 subnets across 2 AZs
2 EC2 instances in running state, in different AZs
RDS instance in available state, Multi-AZ enabled, not publicly accessible
Verified pipeline outputs: web_a_public_ip, web_b_public_ip, rds_endpoint
# 9. Screenshots
Add these to docs/screenshots/ and reference them here:

 S3 bucket with versioning enabled
 DynamoDB table terraform-locks
 Jenkins pipeline — successful run showing all stages green
 Terraform plan output (18 to add)
 AWS Console — VPC resource map
 AWS Console — EC2 instances running
 AWS Console — RDS instance available
# 10. Cleanup
To avoid ongoing AWS charges after the project is reviewed:

terraform destroy
Then manually in the AWS Console:

Terminate the Jenkins EC2 instance
Delete the jenkins-sg security group
Empty and delete the S3 state bucket
Delete the DynamoDB terraform-locks table
Delete the terraform-jenkins-user IAM user (and its access keys)
# 11. Lessons Learned
Terraform's S3 backend requires the bucket name to match exactly — even a small naming inconsistency (e.g. tfstate vs terraform-state) causes terraform init to fail outright.
A manual approval gate (input step) in the Jenkins pipeline is a simple but effective safeguard against accidentally applying infrastructure changes without review.
Keeping the database tier in private subnets with no internet route, and restricting its security group to only accept traffic from the web tier's security group (rather than a CIDR range), is a stronger and more maintainable isolation pattern than IP-based rules.
skip_final_snapshot = true on the RDS instance was a deliberate choice for this learning project to make terraform destroy fast and clean; in production this would be set to false to protect against accidental data loss.