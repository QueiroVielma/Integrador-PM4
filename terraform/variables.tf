variable "aws_region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Ambiente de destino"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Prefixo usado no nome dos recursos"
  type        = string
  default     = "pm04"
}

variable "vpc_cidr" {
  description = "Faixa de IP da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Sub-redes publicas (o ALB exige pelo menos 2 zonas)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  description = "Sub-rede privada onde ficam as VMs"
  type        = string
  default     = "10.0.10.0/24"
}

variable "app_instance_type" {
  description = "Tipo da VM da aplicacao"
  type        = string
  default     = "t3.small"
}

variable "db_instance_type" {
  description = "Tipo da VM do banco de dados"
  type        = string
  default     = "t3.small"
}

variable "app_port" {
  description = "Porta da VM da aplicacao que o load balancer acessa"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Caminho que o load balancer usa para saber se a aplicacao (e o banco) estao no ar"
  type        = string
  default     = "/health"
}

variable "ssh_public_key" {
  description = "Chave publica SSH (vem do GitHub Secret SSH_PUBLIC_KEY)"
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile ja existente (ex: LabInstanceProfile no AWS Academy). Vazio = o Terraform cria um"
  type        = string
  default     = ""
}

variable "habilitar_https" {
  description = "Cria o CloudFront na frente do ALB para ter URL HTTPS (exigencia REQ-05 do escopo)"
  type        = bool
  default     = true
}
