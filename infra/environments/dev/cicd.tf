data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = data.tls_certificate.github.certificates[*].sha1_fingerprint

  tags = merge(local.common_tags, {
    Name = "github-oidc-provider"
  })
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-taskflow"

  tags = merge(local.common_tags, {
    Name = "github-actions-taskflow"
  })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-taskflow-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECSのデプロイに必要な権限
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:RegisterTaskDefinition",
        ]
        Resource = "*" # 本番では特定のクラスター・サービスのARNに絞る
      },
      {
        # ECR: docker login 用（リポジトリ指定不可なのでResource="*"）
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # ECR: pull + push + マニフェスト確認に必要な一式
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",             # ★buildxのHEAD確認に必要
          "ecr:GetDownloadUrlForLayer",    # ★レイヤー差分取得に必要
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
          "ecr:ListImages",
        ]
        Resource = [
          "arn:aws:ecr:ap-northeast-1:${data.aws_caller_identity.current.account_id}:repository/taskflow/backend",
          "arn:aws:ecr:ap-northeast-1:${data.aws_caller_identity.current.account_id}:repository/taskflow/frontend",
        ]
      },
      {
        # S3へのフロントエンドデプロイに必要な権限
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*",
          # ↑ バケット自体のARN（ListBucket用）
          # ↑ バケット内オブジェクトのARN（PutObject/DeleteObject用）
        ]
      },
      {
        # CloudFrontキャッシュ無効化の権限
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = aws_cloudfront_distribution.frontend.arn
      },
      {
        # ★追加：ECSに渡すIAMロールのPassRole権限
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole",
          # 必要ならタスクロールも：
          # "arn:aws:iam::...:role/ecsTaskRole",
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}
