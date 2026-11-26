# HTTPS publico (REQ-05 do escopo).
# O CloudFront entrega um endereco https://xxxx.cloudfront.net com certificado
# da propria AWS, entao nao precisamos comprar dominio para a feira.
# Ele so repassa as requisicoes para o ALB, sem guardar nada em cache
# (a lista de tarefas muda o tempo todo).

data "aws_cloudfront_cache_policy" "sem_cache" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "repassar_tudo" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "app" {
  count = var.habilitar_https ? 1 : 0

  enabled     = true
  comment     = "${var.project_name} - HTTPS na frente do ALB"
  price_class = "PriceClass_100" # so EUA/Europa: mais barato

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.sem_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.repassar_tudo.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-cdn"
  }
}
