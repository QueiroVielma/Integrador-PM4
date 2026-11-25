# Zonas de disponibilidade da regiao
data "aws_availability_zones" "disponiveis" {
  state = "available"
}

# VPC propria do projeto (nao usamos mais a VPC padrao)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway: so as sub-redes publicas usam
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Sub-redes publicas: aqui ficam so o load balancer e o NAT
resource "aws_subnet" "publica" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.disponiveis.names[count.index]

  tags = {
    Name = "${var.project_name}-publica-${count.index + 1}"
  }
}

# Sub-rede privada: VM da aplicacao e VM do banco (sem IP publico)
resource "aws_subnet" "privada" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.disponiveis.names[0]

  tags = {
    Name = "${var.project_name}-privada"
  }
}

# NAT Gateway: deixa as VMs privadas SAIREM para a internet
# (apt, imagens Docker, Session Manager), mas ninguem de fora entra nelas
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.publica[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Tabela de rotas publica: 0.0.0.0/0 -> Internet Gateway
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-rt-publica"
  }
}

resource "aws_route_table_association" "publica" {
  count          = length(aws_subnet.publica)
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# Tabela de rotas privada: 0.0.0.0/0 -> NAT Gateway
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.project_name}-rt-privada"
  }
}

resource "aws_route_table_association" "privada" {
  subnet_id      = aws_subnet.privada.id
  route_table_id = aws_route_table.privada.id
}
