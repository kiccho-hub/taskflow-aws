# Task 8: ECS サービス・タスク定義（IaC）

> 前提: [コンソール版 Task 8](../console/08_ecs_services.md) を完了済みであること
> 参照ナレッジ: [06_ecs_fargate.md](../knowledge/06_ecs_fargate.md)、[08_iam.md](../knowledge/08_iam.md)

## このタスクのゴール

タスク定義・ECSサービス・IAMロール・Auto ScalingをTerraformで管理する。

---

## 新しいHCL文法：文字列補間と `lifecycle` ブロック

### 文字列補間：`"${...}"`

HCLの文字列の中に変数や参照式を埋め込む構文。

```hcl
image = "${aws_ecr_repository.backend.repository_url}:latest"
#         ↑ ${ } の中に参照式を書く。文字列と連結される
#                                                    ↑ 文字列 ":latest" と結合される
# 結果例: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/backend:latest"
```

文字列全体が参照式の場合は `"${...}"` より `aws_ecr_repository.backend.repository_url` と直接書いた方がシンプル。ただし他の文字列と結合する場合は補間構文が必要。

### `lifecycle` ブロック

リソースのライフサイクル（作成・更新・削除の挙動）を制御する特殊なブロック。全てのリソースで使える。

```hcl
resource "aws_ecs_service" "backend" {
  desired_count = 1

  lifecycle {
    ignore_changes = [desired_count]
    # ↑ ignore_changes: 指定した引数が外部で変更されても Terraform が上書きしない
    # ↑ Auto Scaling が desired_count を変更しても、次の apply でリセットされない
  }
}
```

`ignore_changes` の使いどころ：
- Auto Scalingが管理する `desired_count`
- 外部ツールが変更するタグ
- CI/CDが更新するイメージタグ（`image`）

### `force_new_deployment = true`

```hcl
resource "aws_ecs_service" "backend" {
  force_new_deployment = true
  # ↑ タスク定義のARNが変わらなくても、apply時に強制的に新しいタスクをデプロイする
  # ↑ 例: 同じタスク定義リビジョンでも「latest」イメージが更新された場合に有効
}
```

---

## ハンズオン手順

### IAMロール

```hcl
# タスク実行ロール: ECS基盤（サービス）が使う
# 用途: ECRからイメージをpull、CloudWatch Logsに書き込む
resource "aws_iam_role" "ecs_execution" {
  name = "taskflow-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # ↑ ECSタスクがこのロールを引き受けられる（AssumeRole）ことを許可
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  # ↑ AWSが管理するマネージドポリシーをロールにアタッチ
  # ↑ ECRからのpull、CloudWatch Logsへの書き込みなどに必要な権限が含まれる
}

# タスクロール: コンテナ内のアプリが使う
# 用途: アプリコードがS3・DynamoDB等のAWSサービスを呼ぶ場合に使うロール
resource "aws_iam_role" "ecs_task" {
  name = "taskflow-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# アプリがS3等のAWSサービスを呼ぶ場合はここにポリシーをアタッチする
```

### CloudWatch Logs

```hcl
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/taskflow-backend"    # AWSの規則: /ecs/ プレフィックス推奨
  retention_in_days = 30    # 30日後に自動削除（無制限はコストが増えるため要設定）

  tags = { Name = "taskflow-backend-logs" }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/taskflow-frontend"
  retention_in_days = 30

  tags = { Name = "taskflow-frontend-logs" }
}
```

### タスク定義（Backend）

```hcl
resource "aws_ecs_task_definition" "backend" {
  family                   = "taskflow-backend"    # タスク定義のファミリー名（リビジョン管理の単位）
  requires_compatibilities = ["FARGATE"]           # Fargateのみで実行
  network_mode             = "awsvpc"              # Fargate必須のネットワークモード
  cpu                      = 256                   # 0.25 vCPU（256 = 1/4コア）
  memory                   = 512                   # 512 MB

  execution_role_arn = aws_iam_role.ecs_execution.arn    # タスク実行ロール
  task_role_arn      = aws_iam_role.ecs_task.arn         # タスクロール

  container_definitions = jsonencode([{    # ← JSON配列を jsonencode で書く。[ ] = 配列
    name  = "backend"
    image = "${aws_ecr_repository.backend.repository_url}:latest"
    # ↑ 文字列補間で ECR URL と ":latest" を結合

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      # コンテナに渡す環境変数（配列形式）
      { name = "NODE_ENV",   value = "production" },
      { name = "DB_HOST",    value = aws_db_instance.main.address },
      # ↑ Terraform式をJSON内で使える（jsonencodeの強み）
      { name = "DB_PORT",    value = "5432" },
      { name = "DB_NAME",    value = "taskflow" },
      { name = "REDIS_HOST", value = aws_elasticache_cluster.main.cache_nodes[0].address },
      { name = "REDIS_PORT", value = "6379" },
    ]

    # パスワードはSecrets Managerから取得（本番推奨）
    # secrets = [
    #   { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:ap-northeast-1:xxxx:secret:xxx" }
    # ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = "ap-northeast-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
```

### タスク定義（Frontend）

```hcl
resource "aws_ecs_task_definition" "frontend" {
  family                   = "taskflow-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn = aws_iam_role.ecs_execution.arn
  # task_role_arn は省略（フロントエンドはAWSサービスを直接呼ばないため不要）

  container_definitions = jsonencode([{
    name  = "frontend"
    image = "${aws_ecr_repository.frontend.repository_url}:latest"

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      { name = "REACT_APP_API_URL", value = "http://${aws_lb.main.dns_name}/api" },
      # ↑ 文字列補間を jsonencode の中で使う例
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = "ap-northeast-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
```

### ECSサービス（Backend）

```hcl
resource "aws_ecs_service" "backend" {
  name            = "taskflow-backend-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1    # 起動するタスク数

  launch_type = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false    # プライベートサブネット配置のためfalse
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"    # タスク定義の container name と一致させる
    container_port   = 3000
  }

  force_new_deployment = true
  # ↑ apply のたびに新しいタスクをデプロイする（latestイメージを拾い直す）

  lifecycle {
    ignore_changes = [desired_count]
    # ↑ Auto Scaling が desired_count を変更しても Terraform が上書きしない
  }

  depends_on = [aws_lb_listener.http]
  # ↑ リスナーが存在してからサービスを作成する（ヘルスチェックの競合を避ける）
}
```

### ECSサービス（Frontend）

```hcl
resource "aws_ecs_service" "frontend" {
  name            = "taskflow-frontend-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1

  launch_type = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_c.id]
    security_groups  = [aws_security_group.ecs.id]
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
```

---

## 実行

```bash
terraform apply

# サービスのデプロイ状況を確認
aws ecs describe-services \
  --cluster taskflow-cluster \
  --services taskflow-backend-svc taskflow-frontend-svc \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount}'
```

---

## よくあるエラー

| エラー | 原因 | 対処 |
|--------|------|------|
| タスクが STOPPED | イメージのpull失敗・環境変数エラー等 | CloudWatch Logsでログを確認 |
| `ResourceNotFoundException: task definition not found` | タスク定義の作成前にサービスを作ろうとした | `depends_on` を追加 |
| ALBのヘルスチェックが通らない | アプリが `/api/health` に応答しない | バックエンドコードのエンドポイントを確認 |

---

**次のタスク:** [Task 9: Cognito認証設定（IaC版）](09_cognito.md)
