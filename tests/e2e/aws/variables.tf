variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ubuntu_version" {
  description = "Ubuntu release to test, as it appears in Canonical's SSM parameter path."
  type        = string
  default     = "26.04"

  validation {
    condition     = can(regex("^[0-9]{2}\\.[0-9]{2}$", var.ubuntu_version))
    error_message = "ubuntu_version must look like 26.04."
  }
}

variable "ssh_source_cidr" {
  description = "The only source allowed to reach tcp/22, normally the operator's public IP as a /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_source_cidr, 0)) && var.ssh_source_cidr != "0.0.0.0/0"
    error_message = "ssh_source_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0."
  }
}

variable "run_id" {
  description = "Identifies one run; it is tagged on every resource and forms the Tailscale node name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.run_id))
    error_message = "run_id must be lowercase letters, digits and hyphens, 1-40 characters, starting and ending with a letter or digit."
  }
}
