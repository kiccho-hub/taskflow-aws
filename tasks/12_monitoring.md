# Task 12: CloudWatch 監視設定

## このタスクのゴール

TaskFlow の **監視・アラート** を設定し、問題を早期発見できるようにする。
完成すると、以下が揃う：

- CloudWatch ダッシュボード（一目で状況把握）
- メトリクスアラーム（異常時に通知）
- SNS トピック（通知の送信先）
- ログのメトリクスフィルター（エラーログの検知）

---

## 背景知識

### なぜ監視が必要か？

アプリをデプロイしたら終わりではない。**動いているか、遅くないか、エラーが出ていないか**を常に把握する必要がある。

> 例え: お店を開いたら、売上・来客数・クレーム数を毎日チェックする。見ていないと、お客さんが来なくなっていても気づかない。

### CloudWatch とは？

AWSの**統合監視サービス**。ログ収集・メトリクス監視・アラーム通知を1箇所で管理する。

### 監視の3本柱

| 柱 | 説明 | CloudWatch での実現 |
|----|------|-------------------|
| メトリクス | 数値の時系列データ（CPU使用率、リクエスト数） | CloudWatch Metrics |
| ログ | アプリケーションの出力 | CloudWatch Logs |
| アラート | 異常時の通知 | CloudWatch Alarms + SNS |

### SNS とは？

**Simple Notification Service** — 通知を配信するサービス。メール、SMS、Slack（Lambda経由）などに送れる。

---

## アーキテクチャ上の位置づけ

```
[ECS] ──メトリクス──▶ [CloudWatch Metrics] → [ダッシュボード]
  │                       │
  │                  [アラーム] → [SNS] → メール通知
  │
  └──ログ──▶ [CloudWatch Logs] → [メトリクスフィルター] → [アラーム]
```

---

## ハンズオン手順

### Step 1: SNS トピック（通知先）

```hcl
resource "aws_sns_topic" "alerts" {
  name = "taskflow-alerts"

  tags = { Name = "taskflow-alerts" }
}

# メール通知のサブスクリプション
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email          # 通知先メールアドレス
}
```

> サブスクリプション作成後、確認メールが届く。**メール内のリンクをクリック**して承認する必要がある。

### Step 2: ECS メトリクスアラーム

```hcl
# Backend の CPU 使用率アラーム
resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  alarm_name          = "taskflow-backend-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2                # 2回連続で
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300              # 5分間の平均
  statistic           = "Average"
  threshold           = 80               # 80% を超えたら

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.backend.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]   # アラーム時にSNSに通知
  ok_actions    = [aws_sns_topic.alerts.arn]    # 復旧時にも通知

  alarm_description = "Backend CPU > 80% for 10 minutes"

  tags = { Name = "taskflow-backend-cpu-high" }
}

# Backend のメモリ使用率アラーム
resource "aws_cloudwatch_metric_alarm" "backend_memory_high" {
  alarm_name          = "taskflow-backend-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.backend.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  alarm_description = "Backend Memory > 80% for 10 minutes"

  tags = { Name = "taskflow-backend-memory-high" }
}
```

**パラメータ解説:**
- `evaluation_periods = 2`, `period = 300`: 5分 x 2回 = **10分間連続**で閾値超えたらアラーム。一瞬のスパイクでは鳴らない。
- `ok_actions`: 復旧時にも通知を送ることで「問題が解消した」ことを把握できる。

### Step 3: ALB メトリクスアラーム

```hcl
# 5xx エラー率アラーム（サーバーエラー）
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "taskflow-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10              # 5分間に10回以上の5xxエラー

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  alarm_description = "ALB 5xx errors > 10 in 5 minutes"

  tags = { Name = "taskflow-alb-5xx" }
}

# レスポンスタイムアラーム
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "taskflow-alb-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2.0             # 平均2秒以上

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  alarm_description = "ALB average response time > 2s for 10 minutes"

  tags = { Name = "taskflow-alb-latency" }
}
```

### Step 4: RDS メトリクスアラーム

```hcl
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "taskflow-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  alarm_description = "RDS CPU > 80% for 10 minutes"

  tags = { Name = "taskflow-rds-cpu" }
}

# DB接続数アラーム
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "taskflow-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 50              # db.t4g.micro の上限に近い値

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  alarm_description = "RDS connections > 50 for 10 minutes"

  tags = { Name = "taskflow-rds-connections" }
}
```

### Step 5: ログのメトリクスフィルター（エラー検知）

```hcl
# Backend ログから "ERROR" を検知
resource "aws_cloudwatch_log_metric_filter" "backend_errors" {
  name           = "taskflow-backend-errors"
  pattern        = "ERROR"               # ログに "ERROR" が含まれたら
  log_group_name = aws_cloudwatch_log_group.backend.name

  metric_transformation {
    name      = "BackendErrorCount"
    namespace = "TaskFlow/Backend"
    value     = "1"
  }
}

# エラー数アラーム
resource "aws_cloudwatch_metric_alarm" "backend_error_rate" {
  alarm_name          = "taskflow-backend-errors-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackendErrorCount"
  namespace           = "TaskFlow/Backend"
  period              = 300
  statistic           = "Sum"
  threshold           = 20              # 5分間に20回以上のERROR

  alarm_actions = [aws_sns_topic.alerts.arn]

  alarm_description = "Backend ERROR logs > 20 in 5 minutes"

  tags = { Name = "taskflow-backend-errors" }
}
```

### Step 6: ダッシュボード

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "TaskFlow"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS CPU Utilization"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "taskflow-cluster",
             "ServiceName", "taskflow-backend", { label = "Backend" }],
            ["AWS/ECS", "CPUUtilization", "ClusterName", "taskflow-cluster",
             "ServiceName", "taskflow-frontend", { label = "Frontend" }],
          ]
          period = 300
          stat   = "Average"
          region = "ap-northeast-1"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB Request Count & Latency"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
             "LoadBalancer", aws_lb.main.arn_suffix,
             { stat = "Sum", label = "Requests" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
             "LoadBalancer", aws_lb.main.arn_suffix,
             { stat = "Average", label = "Latency", yAxis = "right" }],
          ]
          period = 300
          region = "ap-northeast-1"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "RDS Metrics"
          metrics = [
            ["AWS/RDS", "CPUUtilization",
             "DBInstanceIdentifier", "taskflow-db",
             { label = "CPU %" }],
            ["AWS/RDS", "DatabaseConnections",
             "DBInstanceIdentifier", "taskflow-db",
             { label = "Connections", yAxis = "right" }],
          ]
          period = 300
          region = "ap-northeast-1"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "5xx Errors"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
             "LoadBalancer", aws_lb.main.arn_suffix,
             { stat = "Sum", label = "5xx Errors" }],
            ["TaskFlow/Backend", "BackendErrorCount",
             { stat = "Sum", label = "Backend Errors" }],
          ]
          period = 300
          region = "ap-northeast-1"
        }
      },
    ]
  })
}
```

### Step 7: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → CloudWatch → ダッシュボード** で `TaskFlow` が表示されるか
2. **アラーム一覧** で全アラームが `OK` 状態か
3. SNS の確認メールが届いて承認したか
4. テストとしてアラームを手動で `ALARM` 状態にしてメールが届くか

```bash
# テスト: アラームを手動でALARM状態にする
aws cloudwatch set-alarm-state \
  --alarm-name "taskflow-backend-cpu-high" \
  --state-value ALARM \
  --state-reason "Testing"
```

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| メール通知が届かない | SNS サブスクリプション未承認 | 確認メールのリンクをクリック |
| アラームが `INSUFFICIENT_DATA` | メトリクスデータがまだない | ECSタスクが動いているか確認 |
| ダッシュボードのグラフが空 | メトリクス名やディメンションの間違い | AWSコンソールでメトリクスを直接検索 |

---

## 理解度チェック

**Q1.** `evaluation_periods = 2`, `period = 300` でアラームが発火する条件は？

<details>
<summary>A1</summary>
5分間（300秒）の平均値が閾値を超えた状態が2回連続（合計10分間）続いた場合にアラームが発火する。一瞬のスパイクでは鳴らず、持続的な異常のみを検知する設計。
</details>

**Q2.** ログのメトリクスフィルターは何のために使うか？

<details>
<summary>A2</summary>
アプリケーションログの中から特定のパターン（例: "ERROR"）を検出し、その出現回数をメトリクスとして記録する。これにより、エラーの発生頻度をグラフ化したり、閾値を超えたらアラームを鳴らしたりできる。ログを人間が目視する代わりに自動監視する仕組み。
</details>

**Q3.** アラームに `ok_actions` を設定する理由は？

<details>
<summary>A3</summary>
問題が解消した（アラーム → OK に戻った）ときにも通知を送る。これにより「障害が発生した」だけでなく「障害が復旧した」ことも把握でき、対応の必要性を正確に判断できる。
</details>

---

**前のタスク:** [Task 11: CI/CD](11_cicd.md)

---

## 全タスク完了！

おめでとうございます！ 12個のタスクを通じて、以下の AWS インフラを構築しました：

```
[Route 53] → [CloudFront] → [S3: React SPA]
                  │
                [ALB]
           /api/*    /*
             │        │
        [ECS Backend] [ECS Frontend]  ← Auto Scaling
             │    │
        [RDS]  [Redis]
             │
        [CloudWatch] → [SNS] → メール通知
             │
        [GitHub Actions] ← CI/CD
             │
        [Cognito] ← 認証
```

全てのリソースが VPC 内のセキュリティグループで保護され、Terraform で管理されています。
