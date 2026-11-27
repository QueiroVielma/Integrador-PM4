aws_region   = "us-east-2"
environment  = "prod"
project_name = "pm04"

app_instance_type = "t3.small"
db_instance_type  = "t3.small"

app_port          = 80
health_check_path = "/health" # a API so responde 200 se estiver conectada no MongoDB

# Dominio comprado no Registro.br, com DNS apontado para o Route 53
zona_dns   = "martinazzo.dev.br"
subdominio = "todo" # prod: todo.martinazzo.dev.br | dev: todo-dev.martinazzo.dev.br

# Se estiver usando AWS Academy (Learner Lab), descomente a linha abaixo,
# porque o laboratorio nao deixa criar roles IAM
# instance_profile_name = "LabInstanceProfile"

# ssh_public_key NAO fica aqui: vem do GitHub Secret SSH_PUBLIC_KEY
