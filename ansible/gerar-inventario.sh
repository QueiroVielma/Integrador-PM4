#!/bin/sh
# Gera o inventory.ini com as saidas do Terraform.
# Uso (dentro da pasta ansible): ./gerar-inventario.sh <id_vm_app> <id_vm_db> <ip_privado_db>
# Os hosts sao IDs de instancia porque o SSH passa pelo Session Manager (sem IP publico).
set -eu
cat > inventory.ini <<FIM
[app]
$1

[db]
$2

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/pm04
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
db_host=$3
FIM
cat inventory.ini
