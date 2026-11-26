# AMI do Ubuntu 24.04 (ja vem com o agente do SSM instalado)
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Chave SSH usada pelo Ansible (o acesso passa pelo tunel do Session Manager)
resource "aws_key_pair" "pm04" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

# VM 1: aplicacao
resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.app_instance_type
  subnet_id                   = aws_subnet.privada.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.pm04.key_name
  iam_instance_profile        = local.instance_profile
  associate_public_ip_address = false

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-app"
    Role = "app"
  }

  # Nao recriar a VM toda vez que a Canonical publicar uma AMI nova
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_route_table_association.privada]
}

# VM 2: banco de dados
resource "aws_instance" "db" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = var.db_instance_type
  subnet_id                   = aws_subnet.privada.id
  vpc_security_group_ids      = [aws_security_group.db.id]
  key_name                    = aws_key_pair.pm04.key_name
  iam_instance_profile        = local.instance_profile
  associate_public_ip_address = false

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-db"
    Role = "db"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_route_table_association.privada]
}
