# IAM roles for ECS
resource "aws_iam_role" "ecs_execution" {
  name = "taskflow-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "taskflow-ecs-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "taskflow-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "taskflow-ecs-task-role"
  })
}

# CloudWatch log groups for ECS services
resource "aws_cloudwatch_log_group" "backend" {
  name = "taskflow-backend-logs"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "taskflow-backend-logs"
  })
}

resource "aws_cloudwatch_log_group" "frontend" {
  name = "taskflow-frontend-logs"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "taskflow-frontend-logs"
  })
}

# ECS task definitions
# Task definition for the backend service
resource "aws_ecs_task_definition" "backend" {
  family                   = "taskflow-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions    = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NODE_ENV",   value = "production" },
        { name = "DB_HOST",    value = aws_db_instance.main.address },
        { name = "DB_PORT",    value = "5432" },
        { name = "DB_NAME",    value = "taskflow" },
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.main.primary_endpoint_address },
        { name = "REDIS_PORT", value = "6379" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"        = aws_cloudwatch_log_group.backend.name
          "awslogs-region"       = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

#
resource "aws_ecs_task_definition" "frontend"{
  family                   = "taskflow-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions    = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:latest"

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "REACT_APP_API_URL", value = "http://${aws_lb.main.dns_name}/api" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"        = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"       = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "backend" {
  name = "taskflow-backend-svc"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.id
  desired_count = 1

  launch_type = "FARGATE"

  network_configuration {
    subnets = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups = [aws_security_group.ecs_backend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name = "backend"
    container_port = 3000
  }

  force_new_deployment = true

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "frontend" {
  name            = "taskflow-frontend-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1

  launch_type = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs_frontend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  force_new_deployment = true

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

#================================================================================
# 動作確認（Verification for Task 8: ECS Services & Task Definitions）
#================================================================================
#
# Task 8 のTerraformが正常に完了したことを確認するための手順
#
# 【ステップ1】Terraform計画の確認
# ---------
#   terraform plan
#   期待される結果: 変更なし（Plan: 0 to add, 0 to change, 0 to destroy）
#
# 【ステップ2】ECSクラスター内のサービス一覧確認
# ---------
#   aws ecs list-services \
#     --cluster taskflow-cluster \
#     --region ap-northeast-1
#
#   期待される結果:
#   - arn:aws:ecs:ap-northeast-1:XXXX:service/taskflow-cluster/taskflow-backend-svc
#   - arn:aws:ecs:ap-northeast-1:XXXX:service/taskflow-cluster/taskflow-frontend-svc
#     （2つのサービスが存在）
#
# 【ステップ3】サービスの詳細確認（実行状況）
# ---------
#   aws ecs describe-services \
#     --cluster taskflow-cluster \
#     --services taskflow-backend-svc taskflow-frontend-svc \
#     --region ap-northeast-1 \
#     --query 'services[*].{name:serviceName, running:runningCount, desired:desiredCount, status:status}'
#
#   期待される結果:
#   | name                     | running | desired | status  |
#   |--------------------------|---------|---------|---------|
#   | taskflow-backend-svc     | 1       | 1       | ACTIVE  |
#   | taskflow-frontend-svc    | 1       | 1       | ACTIVE  |
#
# 【ステップ4】タスク定義の確認
# ---------
#   aws ecs list-task-definitions \
#     --region ap-northeast-1 \
#     --query 'taskDefinitionArns' | grep -E 'taskflow-(backend|frontend)'
#
#   期待される結果:
#   - arn:aws:ecs:ap-northeast-1:XXXX:task-definition/taskflow-backend:X
#   - arn:aws:ecs:ap-northeast-1:XXXX:task-definition/taskflow-frontend:X
#
# 【ステップ5】実行中のタスク確認
# ---------
#   # バックエンドタスク
#   aws ecs list-tasks \
#     --cluster taskflow-cluster \
#     --service-name taskflow-backend-svc \
#     --region ap-northeast-1
#
#   # フロントエンドタスク
#   aws ecs list-tasks \
#     --cluster taskflow-cluster \
#     --service-name taskflow-frontend-svc \
#     --region ap-northeast-1
#
#   期待される結果: 各サービスに1つのタスクARNが返される
#
# 【ステップ6】CloudWatch ログを確認
# ---------
#   # バックエンドログを確認
#   aws logs tail taskflow-backend-logs --follow --region ap-northeast-1
#
#   # フロントエンドログを確認
#   aws logs tail taskflow-frontend-logs --follow --region ap-northeast-1
#
#   期待される結果:
#   - エラーが出ていない（または正常なアプリケーションログが出ている）
#   - ログが定期的に更新されている（タスクが稼働中）
#
# 【ステップ7】IAMロール確認
# ---------
#   # 実行ロールの確認
#   aws iam get-role --role-name taskflow-ecs-execution-role --region ap-northeast-1
#
#   # タスクロールの確認
#   aws iam get-role --role-name taskflow-ecs-task-role --region ap-northeast-1
#
#   期待される結果: ロール情報が返される（存在する）
#
# 【ステップ8】ALBでのターゲット登録確認
# ---------
#   # バックエンドターゲットグループ
#   aws elbv2 describe-target-health \
#     --target-group-arn $(aws elbv2 describe-target-groups \
#       --names taskflow-backend-tg --region ap-northeast-1 \
#       --query 'TargetGroups[0].TargetGroupArn' --output text) \
#     --region ap-northeast-1
#
#   期待される結果:
#   - TargetHealth.State: healthy （ターゲット（ECSタスク）がヘルスチェック成功）
#
# 【ステップ9】コンテナイメージ確認
# ---------
#   # バックエンドサービスの詳細（使用イメージ）
#   aws ecs describe-services \
#     --cluster taskflow-cluster \
#     --services taskflow-backend-svc \
#     --region ap-northeast-1 \
#     --query 'services[0].taskDefinition'
#
#   期待される結果:
#   - arn:aws:ecs:ap-northeast-1:XXXX:task-definition/taskflow-backend:X
#     のように、このタスク定義を使用している
#
# 【ステップ10】実機テスト（オプション）
# ---------
#   # ALBのDNS名を取得
#   ALB_DNS=$(aws elbv2 describe-load-balancers \
#     --region ap-northeast-1 \
#     --query 'LoadBalancers[?LoadBalancerName==`taskflow-alb`].DNSName' \
#     --output text)
#
#   # フロントエンド（ブラウザで確認）
#   echo "Frontend: http://$ALB_DNS"
#
#   # バックエンド ヘルスチェック
#   curl "http://$ALB_DNS/api/health"
#
#   期待される結果:
#   - フロントエンド: 404 or React UIが表示される（データがまだない場合もOK）
#   - バックエンド: 200 OK + JSON レスポンス
#
# 【トラブルシューティング】
# ---------
# • サービスがACTIVEだがrunningCount=0
#   → CloudWatch Logs を確認：aws logs tail taskflow-backend-logs --follow
#   → よくある原因：DB接続失敗、環境変数エラー
#
# • ALBターゲットがhealthyにならない
#   → セキュリティグループでポート3000/80が許可されているか確認
#   → アプリケーションが /health エンドポイントに応答しているか確認
#
# • ECRからイメージがpullできない
#   → ECRリポジトリが存在するか確認
#   → :latest タグのイメージがpushされているか確認
#
#================================================================================
