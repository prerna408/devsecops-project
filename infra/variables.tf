# This is where we define settings we might want to change later.

variable "aws_region" {
  description = "The AWS region where we will create everything."
  type        = string
  default     = "eu-north-1"
}

variable "github_owner" {
  description = "prerna408"
  type        = string
}

variable "github_repo" {
  description = "devsecops-project"
  type        = string
}

variable "github_token" {
  description = "devops-token"
  type        = string
  sensitive   = true # This hides the token value in logs.
}