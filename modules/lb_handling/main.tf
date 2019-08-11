data "aws_lb" "main" {
  count = var.create ? 1 : 0
  arn   = var.lb_arn
}

locals {
  # Validate the load_balancing_type type by looking up the map with var.allowed_load_balancing_types
  validate_load_balancing_type = var.allowed_load_balancing_types[var.load_balancing_type]

  # Validate the record type by looking up the map with valid record types
  route53_record_type = var.allowed_record_types[var.route53_record_type]

  # We limit the target group name to a length of 32
  tg_name = format("%.32s", format("%v-%v", var.cluster_name, var.name))
}

## Route53 DNS Record
resource "aws_route53_record" "this" {
  count   = var.create && var.route53_record_type != "NONE" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.route53_name
  type    = var.route53_record_type == "ALIAS" ? "A" : "CNAME"
  ttl     = var.route53_record_type == "CNAME" ? "300" : null

  dynamic alias {
    for_each = (var.route53_record_type == "ALIAS" ? [true] : [])
    content {
      name                   = "${data.aws_lb.main.dns_name}"
      zone_id                = "${data.aws_lb.main.zone_id}"
      evaluate_target_health = false
    }
  }

  dynamic weighted_routing_policy {
    for_each = (var.route53_record_type == "ALIAS" ? [true] : [])
    content {
      weight = 0
    }
  }

  records        = var.route53_record_type == "CNAME" ? null : [data.aws_lb.main[0].dns_name]
  set_identifier = var.route53_record_type == "ALIAS" ? var.route53_record_identifier : null
}

# Network service load_balancer_type
resource "aws_lb_target_group" "this" {
  count                = var.create && var.load_balancing_type == "network" ? 1 : 0
  name                 = local.tg_name
  port                 = var.target_group_port
  protocol             = "TCP"
  vpc_id               = var.lb_vpc_id
  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    protocol = "TCP"

    ## health_check.healthy_threshold 3 and health_check.unhealthy_threshold 0 must be the same for target_groups with TCP protocol
    healthy_threshold   = max(var.healthy_threshold, var.unhealthy_threshold)
    unhealthy_threshold = max(var.healthy_threshold, var.unhealthy_threshold)
  }

  tags = local.tags
}

resource "aws_lb_listener" "this" {
  count             = var.create && var.load_balancing_type == "network" ? 1 : 0
  load_balancer_arn = var.lb_arn
  port              = var.nlb_listener_port
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.service_nlb[0].arn
    type             = "forward"
  }
}

##
## aws_lb_target_group inside the ECS Task will be created when the service is not the default forwarding service
## It will not be created when the service is not attached to a load balancer like a worker
resource "aws_lb_target_group" "this" {
  count                = var.create && var.load_balancing_type == "application" ? 1 : 0
  name                 = local.tg_name
  port                 = var.target_group_port
  protocol             = "HTTP"
  vpc_id               = var.lb_vpc_id
  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    matcher             = var.health_matcher
    path                = var.health_uri
    unhealthy_threshold = var.unhealthy_threshold
    healthy_threshold   = var.healthy_threshold
  }
}


##
## An aws_lb_listener_rule will only be created when a service has a load balancer attached
resource "aws_lb_listener_rule" "http" {
  count        = var.create && var.load_balancing_type == "application" && ? ( local.route53_record_type != "NONE" ? 1 : 0 ) + var.custom_listen_hosts_count : 0
  listener_arn = var.lb_listener_arn_http


  dynamic action {
    for_each = (var.redirect_http_to_https ? [true] : [])
    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic action {
    for_each = (! var.redirect_http_to_https ? [true] : [])
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.service[0].arn
    }
  }


  condition {
    field  = "host-header"
    values = [local.listen_hosts[count.index]]
  }
}

locals {
  listen_hosts = compact( 
     concat(
     aws_route53_record.record.*.fqdn,
     var.custom_listen_hosts
  ))
}


resource "aws_lb_listener_rule" "https" {
  count        = var.create && var.load_balancing_type == "application" && var.https_enabled ? ( local.route53_record_type != "NONE" ? 1 : 0 ) + var.custom_listen_hosts_count : 0
  listener_arn = var.lb_listener_arn_https

  dynamic action {
    for_each = (var.cognito_auth_enabled ? [true] : [])
    content {
      type = "authenticate-cognito"

      authenticate_cognito {
        user_pool_arn       = var.cognito_user_pool_arn
        user_pool_client_id = var.cognito_user_pool_client_id
        user_pool_domain    = var.cognito_user_pool_domain
      }
    }
  }

  dynamic action {
    for_each = (! var.redirect_http_to_https ? [true] : [])
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.service[0].arn
    }
  }


  condition {
    field  = "host-header"
    values = [local.listen_hosts[count.index]]
  }
}
