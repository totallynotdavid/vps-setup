provider "aws" {
  region = var.region
}

locals {
  tags = {
    purpose = "vps-setup-e2e"
    run_id  = var.run_id
  }
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/${var.ubuntu_version}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_vpc" "default" {
  default = true
}

resource "random_password" "root" {
  length  = 24
  special = false
}

resource "aws_security_group" "ssh" {
  name        = "vps-setup-e2e-${var.run_id}"
  description = "vps-setup end-to-end run ${var.run_id}: SSH from the operator only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from the operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # A security group has no creation time in the EC2 API, and `aws.sh sweep` needs one.
  tags = merge(local.tags, { created_at = timestamp() })

  lifecycle {
    ignore_changes = [tags["created_at"], tags_all["created_at"]]
  }
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.insecure_value
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.yaml.tftpl", {
    root_password = random_password.root.result
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
  }

  tags        = local.tags
  volume_tags = local.tags
}
