output "app_url" {
  description = "Endereco publico da aplicacao (HTTPS pelo CloudFront)"
  value       = var.habilitar_https ? "https://${aws_cloudfront_distribution.app[0].domain_name}" : "http://${aws_lb.app.dns_name}"
}

output "alb_url" {
  description = "Endereco do load balancer (HTTP, origem do CloudFront)"
  value       = "http://${aws_lb.app.dns_name}"
}

output "app_instance_id" {
  description = "ID da VM da aplicacao (usado no inventario do Ansible)"
  value       = aws_instance.app.id
}

output "db_instance_id" {
  description = "ID da VM do banco (usado no inventario do Ansible)"
  value       = aws_instance.db.id
}

output "app_private_ip" {
  description = "IP privado da VM da aplicacao"
  value       = aws_instance.app.private_ip
}

output "db_private_ip" {
  description = "IP privado do banco (a aplicacao conecta nele)"
  value       = aws_instance.db.private_ip
}
