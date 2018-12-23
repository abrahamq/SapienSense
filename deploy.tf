variable "config" {
  default = {
    bucket = "sapiensenseconsulting"
  }
}

locals {
  bucket = "sapiensenseconsulting"
  aliases = ["sapiensenseconsulting.com", "www.sapiensenseconsulting.com"]
}

locals {
  # unique id for caching
  s3_origin_id = "SapienSense"
}

locals {
  route_53_zone_id = "Z2Z05YJ9PZXYMA"
  route_53_domain_name = "sapiensenseconsulting.com"
}

locals {
  acm_certificate_arn = "arn:aws:acm:us-east-1:756582436461:certificate/a0edf067-73c2-4f17-99f3-c9223951384a"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Cloudfront access for ${var.config["bucket"]} s3"
}

resource "aws_s3_bucket" "b" {
  bucket = "${local.bucket}"
  region = "us-east-1"
  acl    = "private"

  tags {
    Name = "${local.bucket}"
  }

  policy = <<POLICY
{
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "Cloudfront access",
              "Effect": "Allow",
              "Principal": { "CanonicalUser":
			"${aws_cloudfront_origin_access_identity.origin_access_identity.s3_canonical_user_id}"
                          },
              "Action": "s3:GetObject",
              "Resource": "arn:aws:s3:::${local.bucket}/*"
          }
      ]
  }POLICY
}



resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  aliases = "${local.aliases}"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers = ["Origin"]
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags {
    Environment = "production"
  }

  viewer_certificate {
    acm_certificate_arn = "${local.acm_certificate_arn}"
    ssl_support_method = "sni-only"
  }
}

resource "aws_route53_record" "www" {
  zone_id = "${local.route_53_zone_id}"
  name    = "${local.route_53_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.s3_distribution.hosted_zone_id}"
    evaluate_target_health = true
  }
}
