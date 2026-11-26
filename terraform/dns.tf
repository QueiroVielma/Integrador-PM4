# Dominio com HTTPS (REQ-05).
# A zona do Route 53 foi criada uma unica vez fora do Terraform (igual ao bucket
# do state), para os nameservers cadastrados no Registro.br nunca mudarem,
# mesmo depois de rodar o destroy.
data "aws_route53_zone" "principal" {
  name = var.zona_dns
}

# Certificado gratuito da AWS, validado automaticamente por DNS
resource "aws_acm_certificate" "app" {
  domain_name       = var.dominio_app
  validation_method = "DNS"

  tags = {
    Name = "${var.project_name}-certificado"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validacao" {
  for_each = {
    for opcao in aws_acm_certificate.app.domain_validation_options : opcao.domain_name => opcao
  }

  zone_id         = data.aws_route53_zone.principal.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for registro in aws_route53_record.validacao : registro.fqdn]
}

# todo.martinazzo.dev.br -> load balancer
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.principal.zone_id
  name    = var.dominio_app
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
