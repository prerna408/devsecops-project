# --- THIS IS THE COMPLETE AND FINAL main.tf FILE ---

# 1. PROVIDER CONFIGURATION
provider "aws" {
  region = var.aws_region
}

# 2. DATA SOURCES
data "aws_caller_identity" "current" {}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# 3. S3 BUCKET FOR ARTIFACTS
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "devops-pipeline-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "codepipeline_artifacts_ownership" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 4. DEDICATED KMS KEY FOR ARTIFACT ENCRYPTION
resource "aws_kms_key" "codepipeline_key" {
  description             = "KMS key for CodePipeline artifacts"
  deletion_window_in_days = 7
}

data "aws_iam_policy_document" "codepipeline_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow Service Roles to use the key"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        aws_iam_role.codepipeline_role.arn,
        aws_iam_role.codebuild_role.arn,
        aws_iam_role.codedeploy_role.arn
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key_policy" "codepipeline_key_policy_attachment" {
  key_id = aws_kms_key.codepipeline_key.id
  policy = data.aws_iam_policy_document.codepipeline_key_policy.json
}

# 5. IAM ROLES AND POLICIES
resource "aws_iam_role" "codepipeline_role" {
  name               = "FinalCodePipelineRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "FinalCodePipelinePolicy"
  role = aws_iam_role.codepipeline_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:*"], Resource = ["${aws_s3_bucket.codepipeline_artifacts.arn}", "${aws_s3_bucket.codepipeline_artifacts.arn}/*"] },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = "*" },
      { Effect = "Allow", Action = ["codedeploy:*"], Resource = "*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.codedeploy_role.arn] }
    ]
  })
}

resource "aws_iam_role" "codebuild_role" {
  name               = "FinalCodeBuildRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "FinalCodeBuildPolicy"
  role = aws_iam_role.codebuild_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["logs:*"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:*"], Resource = ["${aws_s3_bucket.codepipeline_artifacts.arn}", "${aws_s3_bucket.codepipeline_artifacts.arn}/*"] }
    ]
  })
}

resource "aws_iam_role" "codedeploy_role" {
  name               = "FinalCodeDeployRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "codedeploy.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service_attachment" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# --- THE FINAL, MISSING PIECE ---
# This policy gives the CodeDeploy role the explicit permission it needs to
# read the artifact from S3 and decrypt it with the KMS key.
resource "aws_iam_role_policy" "codedeploy_s3_kms_access" {
  name = "FinalCodeDeployS3KMSAccess"
  role = aws_iam_role.codedeploy_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ],
        Resource = "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = "kms:Decrypt",
        Resource = aws_kms_key.codepipeline_key.arn
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name               = "FinalEC2Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_service_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "FinalEC2InstanceProfile"
  role = aws_iam_role.ec2_role.name
}

# 6. AWS RESOURCES
resource "aws_instance" "app_server" {
  ami                  = data.aws_ami.latest_amazon_linux.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  tags                 = { Name = "MyFinalAppServer" }
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

resource "aws_codebuild_project" "build" {
  name         = "Final-WebApp-Build"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }
  source { type = "CODEPIPELINE" }
}

resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name             = "Final-WebApp-Application"
}

resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "Final-WebApp-DeploymentGroup"
  service_role_arn      = aws_iam_role.codedeploy_role.arn
  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "MyFinalAppServer"
  }
}

# 7. THE PIPELINE
resource "aws_codepipeline" "pipeline" {
  name     = "Final-WebApp-Pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
    encryption_key {
      id   = aws_kms_key.codepipeline_key.arn
      type = "KMS"
    }
  }

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

  depends_on = [
    aws_s3_bucket_ownership_controls.codepipeline_artifacts_ownership,
    aws_kms_key_policy.codepipeline_key_policy_attachment
  ]
}