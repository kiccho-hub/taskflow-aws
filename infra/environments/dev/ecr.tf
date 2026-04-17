resource "aws_ecr_repository" "backend" {
  name = "taskflow/backend"

  image_scanning_configuration {
    scan_on_push = true
  }

  # image_tag_mutability = "IMMUTABLE"
  image_tag_mutability = "MUTABLE"

  tags = merge(local.common_tags, {
    Name = "taskflow-backend"
  })
}

resource "aws_ecr_repository" "frontend" {
  name = "taskflow/frontend"

  image_scanning_configuration {
    scan_on_push = true
  }

  # image_tag_mutability = "IMMUTABLE"
  image_tag_mutability = "MUTABLE"

  tags = merge(local.common_tags, {
    Name = "taskflow-frontend"
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = local.ecr_lifecycle_policy
}
