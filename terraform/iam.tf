# Permissao para as VMs se registrarem no Session Manager (SSM).
# E por ele que a pipeline acessa as VMs privadas, sem abrir SSH e sem bastion.
# Se instance_profile_name for informado (AWS Academy), usamos o que ja existe.

locals {
  criar_role       = var.instance_profile_name == ""
  instance_profile = local.criar_role ? aws_iam_instance_profile.ssm[0].name : var.instance_profile_name
}

resource "aws_iam_role" "ssm" {
  count = local.criar_role ? 1 : 0
  name  = "${var.project_name}-role-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = local.criar_role ? 1 : 0
  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = local.criar_role ? 1 : 0
  name  = "${var.project_name}-profile-ssm"
  role  = aws_iam_role.ssm[0].name
}
