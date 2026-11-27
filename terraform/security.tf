# Load balancer: unico recurso aberto para a internet
resource "aws_security_group" "alb" {
  name        = "${local.prefixo}-sg-alb"
  description = "HTTP e HTTPS publicos no load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP da internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS da internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefixo}-sg-alb"
  }
}

# VM da aplicacao: so recebe trafego vindo do load balancer
# Obs: nao tem porta 22 aberta, o acesso do Ansible e pelo Session Manager
resource "aws_security_group" "app" {
  name        = "${local.prefixo}-sg-app"
  description = "Aplicacao acessivel somente pelo ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Trafego do load balancer"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefixo}-sg-app"
  }
}

# VM do banco: so a VM da aplicacao acessa o MongoDB (nunca a internet)
resource "aws_security_group" "db" {
  name        = "${local.prefixo}-sg-db"
  description = "MongoDB acessivel somente pela aplicacao"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB vindo da aplicacao"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefixo}-sg-db"
  }
}
