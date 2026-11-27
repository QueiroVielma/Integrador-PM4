output "app_url" {
  description = "Endereco publico da aplicacao (HTTPS com dominio proprio)"
  value       = "https://${local.dominio_app}"
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
