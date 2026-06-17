# AWS Final Project Deployment Guide

This document provides a step-by-step guide to deploying the High Availability Web Service using the AWS CLI and Terraform.

## Prerequisites

1.  **AWS CLI**: Ensure the AWS CLI is installed and configured on your system.
2.  **Terraform**: Ensure Terraform is installed.
3.  **AWS Credentials**: You must have valid AWS credentials configured (e.g., via `aws configure` or exported environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`).

## Deployment Steps

### 1. Clone the Repository (or navigate to the directory)

Open your terminal and navigate to the directory containing the Terraform files (`aws_final`).

```bash
cd aws_final
```

### 2. Initialize Terraform

Initialize the working directory. This command downloads the necessary provider plugins (like the AWS provider).

```bash
terraform init
```

### 3. Validate the Configuration

It's a good practice to validate the syntax and arguments of your Terraform configuration files.

```bash
terraform validate
```

### 4. Review the Execution Plan

Generate and review an execution plan. This shows you exactly what resources Terraform will create in your AWS account before it actually does anything.

```bash
terraform plan
```

*Note: Since there are sensitive variables (like the database password), Terraform will prompt you for them if they aren't provided via a `terraform.tfvars` file or environment variables. You can let it prompt you, or create a `terraform.tfvars` file (do not commit this file to version control).*

Example `terraform.tfvars`:
```hcl
db_password = "YourSecurePasswordHere123!"
```

### 5. Apply the Configuration

Apply the changes to create the infrastructure.

```bash
terraform apply
```

Type `yes` when prompted to confirm the execution plan.

Terraform will take several minutes to provision the resources. The RDS database instance typically takes the longest (around 5-10 minutes).

### 6. Access the Application

Once `terraform apply` finishes successfully, it will print out several **Outputs**, including `alb_dns_name`.

```text
Outputs:

alb_dns_name = "aws-final-alb-123456789.us-east-1.elb.amazonaws.com"
rds_endpoint = "aws-final-db.abcdefgh.us-east-1.rds.amazonaws.com:3306"
s3_bucket_name = "aws-final-assets-xyz123"
```

Copy the `alb_dns_name` value and paste it into your web browser.

You should see the "High Availability Web Service" page, which displays:
- The hostname of the EC2 instance that served your request (refreshing the page might show a different hostname due to Load Balancing).
- Your visitor number (hit count fetched from the RDS database).
- The status of the S3 integration (verifying that the EC2 instance successfully uploaded a hit log to the S3 bucket).

### 7. Clean Up (Important)

To avoid incurring unexpected charges on your AWS account, remember to destroy all the resources when you are done testing the project.

```bash
terraform destroy
```

Type `yes` when prompted to confirm the destruction of the resources. This will tear down the VPC, EC2 instances, Load Balancer, RDS database, and S3 bucket.

### 8. Current URL

`aws-final-alb-665331136.us-east-1.elb.amazonaws.com`

note that while AWS lab is stopped the EC2 instances are also stopped in order to save costs, so the website may not work even though the URL is still valid.
