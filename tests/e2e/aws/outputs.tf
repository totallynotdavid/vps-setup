output "public_ip" {
  value = aws_instance.server.public_ip
}

output "instance_id" {
  value = aws_instance.server.id
}

output "run_id" {
  value = var.run_id
}

output "root_password" {
  value     = random_password.root.result
  sensitive = true
}
