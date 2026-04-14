# ロードバランサーのセキュリティグループ
resource "aws_security_group" "alb" {
  name        = "taskflow-alb-sg"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-alb-sg"
  })
}

# Frontend ECS セキュリティグループ
resource "aws_security_group" "ecs_frontend" {
  name        = "taskflow-ecs-frontend-sg"
  description = "Allow traffic from ALB to frontend only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Port 80 from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-ecs-frontend-sg"
  })
}

# Backend ECS セキュリティグループ
resource "aws_security_group" "ecs_backend" {
  name        = "taskflow-ecs-backend-sg"
  description = "Allow traffic from ALB to backend, and outbound to RDS/Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Port 3000 from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-ecs-backend-sg"
  })
}

# RDSセキュリティグループ
resource "aws_security_group" "rds" {
  name        = "taskflow-rds-sg"
  description = "Allow traffic from Backend ECS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Backend ECS only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-rds-sg"
  })
}

# Redisセキュリティグループ
resource "aws_security_group" "redis" {
  name        = "taskflow-redis-sg"
  description = "Allow traffic from Backend ECS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from Backend ECS only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_backend.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-redis-sg"
  })
}
