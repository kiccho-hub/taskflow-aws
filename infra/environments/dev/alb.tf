resource "aws_lb" "main" {
  name               = "taskflow-lb"
  internal           = false
  load_balancer_type = "application"

  security_groups    = [aws_security_group.alb.id]

  subnets            = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id,
  ]

  tags = merge(local.common_tags, {
    Name = "taskflow-lb"
  })
}

resource "aws_lb_target_group" "backend" {
  name = "taskflow-backend-tg"
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/api/health"
    port = "traffic-port"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 3
    matcher = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "taskflow-backend-tg"
  })
}

resource "aws_lb_target_group" "frontend" {
  name = "taskflow-frontend-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/"
    port = "traffic-port"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 3
    matcher = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "taskflow-frontend-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
