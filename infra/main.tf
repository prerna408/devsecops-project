# This file tells Terraform exactly what to build in AWS.

provider "aws" {
  region = var.aws_region
}

# --- 1. A storage bucket for our pipeline's files ---
resource "aws_s3_bucket" "codepipeline_artifacts" {
  # This combines your base name with the random hex string, ensuring it's unique.
  bucket = "devops-pipeline-bucket-${random_id.bucket_suffix.hex}"
  # ... other settings
}
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# --- 2. IAM Roles (Permissions for AWS Services) ---

# Permission for the EC2 instance to talk to CodeDeploy
resource "aws_iam_role" "ec2_role" {
  name = "CodeDeployEC2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "CodeDeployEC2InstanceProfile"
  role = aws_iam_role.ec2_role.name
}

# Permission for CodeDeploy itself
resource "aws_iam_role" "codedeploy_role" {
  name = "CodeDeployServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "codedeploy.amazonaws.com" }
    }]
  })
}
# --- FINAL CORRECT POLICY FOR CODEDEPLOY ---
resource "aws_iam_role_policy" "codedeploy_s3_access" {
  name = "codedeploy-s3-read-access"
  role = aws_iam_role.codedeploy_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
        ]
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "codedeploy_policy_attachment" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# Permission for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}
# --- FINAL CORRECT POLICY FOR CODEPIPELINE ---
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:*"], Resource = [aws_s3_bucket.codepipeline_artifacts.arn, "${aws_s3_bucket.codepipeline_artifacts.arn}/*"] },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = "*" },
      { Effect = "Allow", Action = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment", "codedeploy:GetDeploymentConfig"], Resource = ["*"] },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.codedeploy_role.arn] },
      {
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}
# Permission for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "CodeBuildPolicy"
  role = aws_iam_role.codebuild_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = ["logs:*", "s3:*"], Effect = "Allow", Resource = ["*"] },
    ]
  })
}

# --- 3. The EC2 Virtual Server ---
data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t3.micro" # Free tier eligible
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  tags = { Name = "MyWebAppServer" }
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y ruby wget python3
              cd /home/ec2-user
              wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto
              yum install -y python3-pip
              pip3 install flask
              EOF
}

# --- 4. The CodeDeploy Application ---
resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name             = "MyWebApp-Application"
}
resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "MyWebApp-DeploymentGroup"
  service_role_arn      = aws_iam_role.codedeploy_role.arn
  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "MyWebAppServer"
  }
}

# --- 5. The CodeBuild Project ---
resource "aws_codebuild_project" "build" {
  name          = "MyWebApp-Build"
  service_role  = aws_iam_role.codebuild_role.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }
  source { type = "CODEPIPELINE" }
}

# --- 6. The CodePipeline Itself ---
resource "aws_codepipeline" "pipeline" {
  name     = "MyWebApp-Pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  # Stage 1: Get Source Code from GitHub
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        Owner      = var.github_owner
        Repo       = var.github_repo
        Branch     = "main"
        OAuthToken = var.github_token
      }
    }
  }

  # Stage 2: Build the Code
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration    = { ProjectName = aws_codebuild_project.build.name }
    }
  }

  # Stage 3: Deploy to EC2 Server
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["BuildOutput"]
      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.dg.deployment_group_name
      }
    }
  }
}