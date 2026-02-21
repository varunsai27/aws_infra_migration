# ─────────────────────────────────────────────────────────────────────────────
# MODULE: alb
# Provisions: Application Load Balancer, target group, HTTP listener
# Note: For production, replace HTTP listener with HTTPS + ACM certificate
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false # Set true in production

  tags = { Name = "${var.name_prefix}-alb" }
}

# ── Target Group ──────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.name_prefix}-api-tg" }
}

# ── HTTP Listener ─────────────────────────────────────────────────────────────
# For production: use aws_lb_listener with HTTPS and an ACM certificate
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
