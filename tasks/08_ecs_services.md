# Task 8: ECS サービス・タスク定義

## このタスクのゴール

TaskFlow の Backend / Frontend コンテナを **実際に起動** する。
完成すると、以下が揃う：

- タスク定義 2つ（Backend / Frontend）
- ECS サービス 2つ
- IAM ロール（タスク実行用）
- Auto Scaling 設定

---

## 背景知識

### タスク定義とは？

コンテナの「設計図」。どのイメージを使い、CPU・メモリをどれだけ割り当て、どの環境変数を渡すかを定義する。

> 例え: 料理のレシピ。材料（イメージ）、分量（CPU/メモリ）、手順（コマンド）が書いてある。

### ECS サービスとは？

タスク定義をもとにタスクを起動し、**常に指定した台数を維持** する仕組み。1つ落ちたら自動で新しいのを起動する。

### IAM ロール（2種類）

| ロール | 用途 |
|--------|------|
| タスク実行ロール | ECS がイメージ取得・ログ出力するための権限 |
| タスクロール | コンテナ内のアプリがAWSサービスを呼ぶための権限 |

> タスク実行ロール = 「厨房に入るための入館証」、タスクロール = 「料理人が使える道具の許可証」

### Auto Scaling とは？

負荷に応じてタスク数を自動増減する仕組み。CPU使用率が高くなったらタスクを増やし、下がったら減らす。

---

## アーキテクチャ上の位置づけ

```
ALB
 ├── /api/* → [ECS Service: Backend]
 │              ├── Task 1 (Fargate)
 │              └── Task 2 (Fargate)
 │                    │
 │              [RDS] [Redis]
 │
 └── /*     → [ECS Service: Frontend]
                ├── Task 1 (Fargate)
                └── Task 2 (Fargate)
```

---

## ハンズオン手順

### Step 1: IAM ロール

```hcl
# タスク実行ロール（ECS自体が使う権限）
resource "aws_iam_role" "ecs_execution" {
  name = "taskflow-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# AWS管理ポリシーをアタッチ（ECR取得 + CloudWatch Logs出力）
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# タスクロール（アプリが使う権限）
resource "aws_iam_role" "ecs_task" {
  name = "taskflow-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}
```

### Step 2: CloudWatch Logs グループ

```hcl
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/taskflow-backend"
  retention_in_days = 30     # 30日間保持

  tags = { Name = "taskflow-backend-logs" }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/taskflow-frontend"
  retention_in_days = 30

  tags = { Name = "taskflow-frontend-logs" }
}
```

### Step 3: タスク定義（Backend）

```hcl
resource "aws_ecs_task_definition" "backend" {
  family                   = "taskflow-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"        # Fargate は awsvpc 必須
  cpu                      = 256             # 0.25 vCPU
  memory                   = 512             # 512 MB

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${aws_ecr_repository.backend.repository_url}:latest"

      portMappings = [{
        containerPort = 3000
        protocol      = "tcp"
      }]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "taskflow" },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.main.cache_nodes[0].address },
        { name = "REDIS_PORT", value = "6379" },
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "arn:aws:ssm:ap-northeast-1:ACCOUNT_ID:parameter/taskflow/db-password"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  tags = { Name = "taskflow-backend" }
}
```

**パラメータ解説:**
- `cpu = 256`: Fargate の CPU 単位（256 = 0.25 vCPU）
- `network_mode = "awsvpc"`: 各タスクに専用のENI（ネットワークインタフェース）を付与
- `secrets`: パスワードなどをSSM Parameter Store から安全に取得
- `logConfiguration`: コンテナのログを CloudWatch Logs に出力

### Step 4: タスク定義（Frontend）

```hcl
resource "aws_ecs_task_definition" "frontend" {
  family                   = "taskflow-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "frontend"
      image = "${aws_ecr_repository.frontend.repository_url}:latest"

      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
      }]

      environment = [
        { name = "REACT_APP_API_URL", value = "/api" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = { Name = "taskflow-frontend" }
}
```

### Step 5: ECS サービス

```hcl
resource "aws_ecs_service" "backend" {
  name            = "taskflow-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 2                     # 常に2タスク維持
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false              # プライベートサブネットなので不要
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 3000
  }

  tags = { Name = "taskflow-backend" }
}

resource "aws_ecs_service" "frontend" {
  name            = "taskflow-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 8080
  }

  tags = { Name = "taskflow-frontend" }
}
```

### Step 6: Auto Scaling

```hcl
# Backend の Auto Scaling ターゲット
resource "aws_appautoscaling_target" "backend" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU使用率 70% でスケールアウト
resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "taskflow-backend-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0   # CPU 70% を維持するように自動調整
  }
}
```

### Step 7: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → ECS → クラスター** でサービスが `ACTIVE`、タスクが `RUNNING` か
2. ALB のターゲットグループで各ターゲットが `healthy` か
3. **CloudWatch Logs** にコンテナのログが出力されているか
4. ALB の DNS名にブラウザでアクセスして画面が表示されるか

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| タスクが `STOPPED` → `PENDING` を繰り返す | イメージ取得失敗 or アプリエラー | CloudWatch Logs でエラーを確認 |
| `CannotPullContainerError` | ECR のイメージが見つからない | リポジトリURLとタグを確認、ECRにイメージがあるか確認 |
| ターゲットが unhealthy | ヘルスチェックパスが間違い | アプリの `/api/health` が200を返すか確認 |
| `ResourceInitializationError` | ENI作成失敗 | サブネットのIP枯渇、またはSGの設定を確認 |

---

## 理解度チェック

**Q1.** タスク実行ロールとタスクロールの違いは？

<details>
<summary>A1</summary>
タスク実行ロールは「ECSエージェント」が使う権限（ECRからイメージ取得、CloudWatch Logsへのログ出力など）。タスクロールは「コンテナ内のアプリケーション」が使う権限（S3アクセス、DynamoDB操作など）。主語が違う。
</details>

**Q2.** `desired_count = 2` にする理由は？

<details>
<summary>A2</summary>
高可用性のため。1タスクだとそのタスクが停止した瞬間にサービスが止まる。2タスクあれば、1つが停止しても残り1つでリクエストを処理でき、ECSが自動的に新しいタスクを起動して2台に戻す。
</details>

**Q3.** Auto Scaling の `target_value = 70.0` はどういう意味か？

<details>
<summary>A3</summary>
全タスクの平均CPU使用率が70%を維持するようにタスク数を自動調整する。70%を超えるとタスクを増やし、大きく下回るとタスクを減らす。70%は「余裕を持ちつつ効率的」なバランスポイント。
</details>

---

**前のタスク:** [Task 7: ALB構築](07_alb.md)
**次のタスク:** [Task 9: Cognito認証](09_cognito.md) → ユーザー認証機能を追加する
