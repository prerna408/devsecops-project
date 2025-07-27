# --- THIS IS THE COMPLETE, HARDENED, AND FINAL main.tf FILE ---

# 1. PROVIDER CONFIGURATION
provider "aws" {
  region = var.aws_region
}

# 2. DATA SOURCES
data "aws_caller_identity" "current" {}

data "aws_ami" "latest_ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "local_file" "public_ssh_key" {
  filename = pathexpand("~/.ssh/id_rsa.pub")
}

# 3. S3 BUCKET (HARDENED)
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "devops-pipeline-bucket-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "codepipeline_artifacts_pab" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts_sse" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts_versioning" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "codepipeline_artifacts_ownership" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 4. DEDICATED KMS KEY (HARDENED)
resource "aws_kms_key" "codepipeline_key" {
  description             = "KMS key for CodePipeline artifacts"
  deletion_window_in_days = 7
  enable_key_rotation     = true
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
      type = "AWS"
      identifiers = [
        aws_iam_role.codepipeline_role.arn,
        aws_iam_role.codebuild_role.arn,
        aws_iam_role.codedeploy_role.arn,
        aws_iam_role.ec2_role.arn # Add EC2 role to key policy
      ]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
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

resource "aws_iam_role_policy" "codedeploy_s3_kms_access" {
  name   = "FinalCodeDeployS3KMSAccess"
  role   = aws_iam_role.codedeploy_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.codepipeline_artifacts.arn}/*" },
      { Effect = "Allow", Action = "kms:Decrypt", Resource = aws_kms_key.codepipeline_key.arn }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service_attachment" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role" "ec2_role" {
  name               = "FinalEC2Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "ec2_kms_access" {
  name = "FinalEC2KMSAccess"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = "kms:Decrypt", Resource = aws_kms_key.codepipeline_key.arn }
    ]
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

# 6. EC2 AND NETWORKING (HARDENED)
resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key"
  public_key = data.local_file.public_ssh_key.content
}

resource "aws_security_group" "instance_sg" {
  name        = "webapp-instance-sg"
  description = "Allow SSH and HTTP traffic"

  ingress {
    description = "Allow SSH from anywhere (for learning purposes)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP traffic from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.latest_ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  tags                   = { Name = "MyFinalAppServer-Ubuntu" }

  root_block_device {
    encrypted = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y ruby-full wget python3-pip
              cd /home/ubuntu
              wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto
              systemctl start codedeploy-agent
              systemctl enable codedeploy-agent
              pip3 install flask
              EOF
}

# 7. CODEDEPLOY, CODEBUILD, AND CODEPIPELINE
resource "aws_codebuild_project" "build" {
  name         = "Final-WebApp-Build-Ubuntu"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }
  source {
    type = "CODEPIPELINE"
  }
}

resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name             = "Final-WebApp-Application-Ubuntu"
}

resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "Final-WebApp-DeploymentGroup-Ubuntu"
  service_role_arn      = aws_iam_role.codedeploy_role.arn
  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = "MyFinalAppServer-Ubuntu"
  }
}

resource "aws_codepipeline" "pipeline" {
  name     = "Final-WebApp-Pipeline-Ubuntu"
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
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
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