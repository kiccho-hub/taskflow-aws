# Task 12: CloudWatch 監視設定（IaC）

## 全体構成における位置づけ

> 図: TaskFlow全体アーキテクチャ（オレンジ色が今回構築するコンポーネント）

```mermaid
graph TD
    Browser["🌐 Browser"]
    R53["Route 53"]
    CF["CloudFront (Task10)"]
    S3["S3 (Task10)"]
    ALB["ALB (Task07)"]
    ECSFront["ECS Frontend (Task06/08)"]
    ECSBack["ECS Backend (Task06/08)"]
    ECR["ECR (Task05)"]
    RDS["RDS PostgreSQL (Task03)"]
    Redis["ElastiCache Redis (Task04)"]
    Cognito["Cognito (Task09)"]
    GH["GitHub Actions (Task11)"]
    CW["CloudWatch (Task12)"]

    subgraph VPC["VPC / Subnets (Task01) + SG (Task02)"]
        subgraph PublicSubnet["Public Subnet"]
            ALB
        end
        subgraph PrivateSubnet["Private Subnet"]
            ECSFront
            ECSBack
            RDS
            Redis
        end
    end

    Browser --> R53 --> CF
    CF --> S3
    CF --> ALB
    ALB -->|"/*"| ECSFront
    ALB -->|"/api/*"| ECSBack
    ECSBack --> RDS
    ECSBack --> Redis
    ECR -.->|Pull| ECSFront
    ECR -.->|Pull| ECSBack
    Cognito -.->|Auth| ECSBack
    GH -.->|Deploy| ECR
    CW -.->|Monitor| ALB
    CW -.->|Monitor| ECSBack

    classDef highlight fill:#ff9900,stroke:#cc6600,color:#000,font-weight:bold
    class CW highlight
```

**今回構築する箇所:** CloudWatch Dashboards + Alarms + SNS - インフラ全体の監視・アラート通知をTerraformで管理する

---

> 前提: [コンソール版 Task 12](../console/12_monitoring.md) を完了済みであること
> 参照ナレッジ: [12_observability.md](../knowledge/12_observability.md)

## このタスクのゴール

CloudWatchアラーム・SNSトピック・ダッシュボードをTerraformで管理する。コード化することで監視設定がレビュー可能・再現可能になる。

---

## 新しいHCL文法：`arn_suffix` と複雑な `jsonencode()`

### `arn_suffix` について

CloudWatchのディメンション（メトリクスのフィルター条件）では、ARN全体ではなく **ARNのサフィックス部分** を指定する必要がある。

```hcl
# NG: ARN全体を渡すとエラーになる
LoadBalancer = aws_lb.main.arn
# → "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/taskflow-alb/xxx"

# OK: arn_suffix でサフィックス部分だけ取得
LoadBalancer = aws_lb.main.arn_suffix
# → "app/taskflow-alb/xxx"  （CloudWatchが期待する形式）
```

`arn_suffix` は `aws_lb`（ALB）リソースが持つ特別な属性。

### `jsonencode()` で大きなJSONを書く

CloudWatchダッシュボードの設定は複雑なJSON。`jsonencode()` を使えばHCLとして書けてTerraformの参照式も使える。

```hcl
dashboard_body = jsonencode({
  widgets = [
    {                          # ← リストの要素（1つのウィジェット）
      type = "metric"
      x = 0; y = 0            # ← セミコロンで同一行に複数引数を書ける（HCLの機能）
      properties = {           # ← ネストされたマップ
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name],
          # ↑ jsonencode 内でも Terraform 参照式が使える（重要）
        ]
      }
    },
    { ... },                   # ← 複数のウィジェット
  ]
})
```

---

## Terraformリソース依存グラフ

> 図: Task12 で作成するTerraformリソースの依存関係

```mermaid
graph LR
    SNS["aws_sns_topic<br/>.alerts"]
    Sub["aws_sns_topic_subscription<br/>.email"]
    AlarmCPU["aws_cloudwatch_metric_alarm<br/>.backend_cpu_high"]
    AlarmStorage["aws_cloudwatch_metric_alarm<br/>.rds_storage_low"]
    AlarmALB["aws_cloudwatch_metric_alarm<br/>.alb_5xx_high"]
    Dashboard["aws_cloudwatch_dashboard<br/>.main"]

    SNS --> Sub
    SNS --> AlarmCPU
    SNS --> AlarmStorage
    SNS --> AlarmALB

    classDef tf fill:#7b42bc,stroke:#5a2e8a,color:#fff
    class SNS,Sub,AlarmCPU,AlarmStorage,AlarmALB,Dashboard tf
```

---

## ハンズオン手順

### variables.tf

```hcl
# File: infra/environments/dev/variables.tf
variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
  # アラート通知を受け取るメールアドレスを変数化
}
```

### SNSトピック

```hcl
# File: infra/environments/dev/monitoring.tf
resource "aws_sns_topic" "alerts" {
  name = "taskflow-alerts"

  tags = merge(local.common_tags, {
    Name = "taskflow-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email    # 通知先メールアドレス
}
```

**注意：** `aws_sns_topic_subscription` でメールを登録した後、確認メールが届く。**Terraformでは確認操作を自動化できない**ため、手動でメール内のリンクをクリックする必要がある。確認前はアラームが発火してもメールが届かない。

### ECS CPUアラーム

```hcl
# File: infra/environments/dev/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  alarm_name          = "taskflow-backend-cpu-high"
  comparison_operator = "GreaterThanThreshold"    # threshold より大きい場合にALARM
  evaluation_periods  = 3        # 3データポイント連続でALARMになる
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300      # 1データポイント = 5分
  statistic           = "Average"
  threshold           = 80       # 80% を超えたらアラーム

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name      # どのクラスターのメトリクスか
    ServiceName = aws_ecs_service.backend.name   # どのサービスのメトリクスか
  }

  alarm_description = "Backend ECS service CPU utilization is too high"
  alarm_actions     = [aws_sns_topic.alerts.arn]    # アラーム時にSNSに通知
  ok_actions        = [aws_sns_topic.alerts.arn]    # 復旧時にも通知

  treat_missing_data = "notBreaching"
  # ↑ データが来ない期間（タスク停止中など）をOKと見なす
  # ↑ "breaching" にすると、起動直後にデータがない期間も全部アラームになる
}
```

**`treat_missing_data` の選択：**
- `notBreaching`: データなし = 正常（ECSタスクが0の場合など）
- `breaching`: データなし = 異常（監視がきちんと動いているか確認したい場合）
- `missing`: データ不足のままアラーム状態にしない

### RDS ストレージアラーム

```hcl
# File: infra/environments/dev/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "taskflow-rds-storage-low"
  comparison_operator = "LessThanThreshold"    # threshold より小さい場合にALARM
  evaluation_periods  = 1        # 1回でも下回ったらアラーム（ストレージ不足は即対応が必要）
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 5000000000    # 5GB（バイト単位。5 * 1000 * 1000 * 1000）

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier    # どのDBインスタンスか
  }

  alarm_description = "RDS free storage space is running low"
  alarm_actions     = [aws_sns_topic.alerts.arn]

  treat_missing_data = "notBreaching"
}
```

### ALB 5xxアラーム

```hcl
# File: infra/environments/dev/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  alarm_name          = "taskflow-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10    # 5分間で10件以上の5xxエラー

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    # ↑ .arn ではなく .arn_suffix を使う（CloudWatchの仕様）
    # ↑ "app/taskflow-alb/xxxx" 形式の文字列
  }

  alarm_description = "ALB 5xx error rate is too high"
  alarm_actions     = [aws_sns_topic.alerts.arn]

  treat_missing_data = "notBreaching"
}
```

### CloudWatch ダッシュボード

```hcl
# File: infra/environments/dev/monitoring.tf
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "TaskFlow-Overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        # ↑ セミコロンで同一行に複数引数を書ける（見やすくなる）
        properties = {
          title   = "ECS Backend - CPU & Memory"
          metrics = [
            # CloudWatchのメトリクス配列形式: [名前空間, メトリクス名, ディメンション1キー, 値, ...]
            ["AWS/ECS", "CPUUtilization",    "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.backend.name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.backend.name],
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"    # 時系列グラフ
        }
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title   = "ALB - Traffic Overview"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",              "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 6; width = 12; height = 6
        properties = {
          title   = "RDS - Database Status"
          metrics = [
            ["AWS/RDS", "CPUUtilization",      "DBInstanceIdentifier", aws_db_instance.main.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier],
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
    ]
  })
}
```

---

## 実行

```bash
terraform apply
# メールのサブスクリプション確認を忘れずに実施
```

---

## ✅ 動作確認（Verification）

このセクションで、Task 12が正常に完了したことを確認します。

### 確認方法

#### 1. Terraform計画の確認

```bash
terraform plan
```

**期待される結果：** `Plan: 0 to add, 0 to change, 0 to destroy.`

---

#### 2. SNS トピック確認

```bash
aws sns list-topics \
  --region ap-northeast-1 \
  --query 'Topics[?contains(TopicArn, `taskflow-alerts`)]' \
  --output table
```

**期待される結果：** `taskflow-alerts` トピックが表示される

```
| TopicArn                                              |
|-------------------------------------------------------|
| arn:aws:sns:ap-northeast-1:123456789012:taskflow-alerts |
```

---

#### 3. SNS サブスクリプション確認

```bash
TOPIC_ARN=$(aws sns list-topics \
  --region ap-northeast-1 \
  --query 'Topics[?contains(TopicArn, `taskflow-alerts`)].TopicArn' \
  --output text)

aws sns list-subscriptions-by-topic \
  --topic-arn $TOPIC_ARN \
  --region ap-northeast-1 \
  --query 'Subscriptions[*].[Protocol, Endpoint, SubscriptionArn]' \
  --output table
```

**期待される結果：** メール登録状況（未確認または確認済み）

```
| Protocol | Endpoint              | SubscriptionArn                          | SubscriptionStatus |
|----------|----------------------|------------------------------------------|-------------------|
| email    | your.email@example.com | arn:aws:sns:ap-northeast-1:...:taskflow-alerts:... | PendingConfirmation |
```

**重要：** `PendingConfirmation` の場合は、メール内の Confirm リンクをクリックして、ステータスを `Confirmed` に変更してください。

---

#### 4. CloudWatch アラーム一覧確認

```bash
aws cloudwatch describe-alarms \
  --region ap-northeast-1 \
  --query 'MetricAlarms[*].[AlarmName, StateValue, AlarmActions]' \
  --output table
```

**期待される結果：** 3つのアラーム（CPU、RDS ストレージ、ALB 5xx）が表示される

```
| AlarmName                    | StateValue | AlarmActions                          |
|------------------------------|------------|---------------------------------------|
| taskflow-backend-cpu-high    | OK         | arn:aws:sns:...:taskflow-alerts       |
| taskflow-rds-storage-low     | OK         | arn:aws:sns:...:taskflow-alerts       |
| taskflow-alb-5xx-high        | OK         | arn:aws:sns:...:taskflow-alerts       |
```

---

#### 5. ECS CPU アラーム詳細確認

```bash
aws cloudwatch describe-alarms \
  --alarm-names taskflow-backend-cpu-high \
  --region ap-northeast-1 \
  --query 'MetricAlarms[0].{AlarmName:AlarmName, Statistic:Statistic, Period:Period, Threshold:Threshold, EvaluationPeriods:EvaluationPeriods, Dimensions:Dimensions}' \
  --output table
```

**期待される結果：** CPU アラーム設定が表示される

```
| AlarmName                 | Statistic | Period | Threshold | EvaluationPeriods | Dimensions                     |
|---------------------------|-----------|--------|-----------|-------------------|---------------------------------|
| taskflow-backend-cpu-high | Average   | 300    | 80        | 3                 | ClusterName, ServiceName        |
```

- `Statistic: Average` - 平均値で判定
- `Period: 300` - 5分間隔
- `Threshold: 80` - 80% を超えたらアラーム
- `EvaluationPeriods: 3` - 3回連続でアラーム条件を満たしたら発火

---

#### 6. RDS ストレージアラーム詳細確認

```bash
aws cloudwatch describe-alarms \
  --alarm-names taskflow-rds-storage-low \
  --region ap-northeast-1 \
  --query 'MetricAlarms[0].{AlarmName:AlarmName, ComparisonOperator:ComparisonOperator, Statistic:Statistic, Threshold:Threshold, Dimensions:Dimensions}' \
  --output table
```

**期待される結果：** RDS ストレージアラーム設定が表示される

```
| AlarmName              | ComparisonOperator | Statistic | Threshold  | Dimensions          |
|------------------------|-------------------|-----------|------------|----------------------|
| taskflow-rds-storage-low | LessThanThreshold | Minimum  | 5000000000 | DBInstanceIdentifier |
```

- `ComparisonOperator: LessThanThreshold` - 5GB以下でアラーム
- `Statistic: Minimum` - 最小値で判定

---

#### 7. ALB 5xx アラーム詳細確認

```bash
aws cloudwatch describe-alarms \
  --alarm-names taskflow-alb-5xx-high \
  --region ap-northeast-1 \
  --query 'MetricAlarms[0].{AlarmName:AlarmName, Statistic:Statistic, Threshold:Threshold, Dimensions:Dimensions}' \
  --output table
```

**期待される結果：** ALB アラーム設定が表示される

```
| AlarmName            | Statistic | Threshold | Dimensions |
|----------------------|-----------|-----------|------------|
| taskflow-alb-5xx-high | Sum       | 10        | LoadBalancer |
```

- `Statistic: Sum` - 合計で判定
- `Threshold: 10` - 5分間で10件以上の5xxエラーでアラーム

---

#### 8. CloudWatch ダッシュボード確認

```bash
aws cloudwatch list-dashboards \
  --region ap-northeast-1 \
  --query 'DashboardEntries[?contains(DashboardName, `TaskFlow`)]' \
  --output table
```

**期待される結果：** `TaskFlow-Overview` ダッシュボードが表示される

```
| DashboardName    | DashboardArn                                           | LastModified         |
|------------------|--------------------------------------------------------|----------------------|
| TaskFlow-Overview | arn:aws:cloudwatch::123456789012:dashboard/TaskFlow-Overview | 2024-04-15T12:00:00Z |
```

---

#### 9. ダッシュボード詳細確認

```bash
aws cloudwatch get-dashboard \
  --dashboard-name TaskFlow-Overview \
  --region ap-northeast-1 \
  --query 'DashboardBody' \
  --output text | jq . | head -50
```

**期待される結果：** ダッシュボード JSON が表示される（ウィジェット数など）

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "title": "ECS Backend - CPU & Memory",
        "metrics": [
          ["AWS/ECS", "CPUUtilization", ...]
        ]
      }
    },
    ...
  ]
}
```

---

#### 10. CloudWatch ダッシュボードをブラウザで確認

```bash
# AWS マネジメントコンソール → CloudWatch → Dashboards
# "TaskFlow-Overview" をクリック

# 期待される画面:
# 1. ECS Backend - CPU & Memory グラフ
# 2. ALB - Traffic Overview グラフ
# 3. RDS - Database Status グラフ
```

**期待される結果：** グラフが表示される（データがなくても OK、ダッシュボード生成が成功していることが重要）

---

#### 11. CloudWatch ログ確認

```bash
# ECS バックエンド ログ
aws logs describe-log-groups \
  --region ap-northeast-1 \
  --query 'logGroups[?contains(logGroupName, `taskflow`)]' \
  --output table
```

**期待される結果：** ログが取得されている

```
| logGroupName         | retentionInDays | creationTime           | storedBytes |
|----------------------|-----------------|------------------------|-------------|
| taskflow-backend-logs | 30              | 2024-04-15T12:00:00Z   | 5000        |
| taskflow-frontend-logs | 30             | 2024-04-15T12:00:00Z   | 3000        |
```

---

#### 12. CloudWatch メトリクス確認

```bash
# ECS メトリクス
aws cloudwatch list-metrics \
  --namespace AWS/ECS \
  --dimensions Name=ClusterName,Value=taskflow-cluster \
  --region ap-northeast-1 \
  --query 'Metrics[*].[MetricName, Dimensions]' \
  --output table
```

**期待される結果：** CPU と Memory メトリクスが表示される

```
| MetricName        | Dimensions                                         |
|-------------------|--------------------------------------------------|
| CPUUtilization    | [{'Name': 'ClusterName', 'Value': 'taskflow-cluster'}, ...] |
| MemoryUtilization | [{'Name': 'ClusterName', 'Value': 'taskflow-cluster'}, ...] |
```

---

#### 13. アラーム テストトリガー（オプション）

```bash
# ※警告：実際にアラームメールが送信されます※
# テスト目的でアラームを発火させる場合:

aws cloudwatch set-alarm-state \
  --alarm-name taskflow-backend-cpu-high \
  --state-value ALARM \
  --state-reason "Testing alarm notification" \
  --region ap-northeast-1
```

**期待される結果：** 登録したメールアドレスにアラーム通知が届く

```
Subject: AWS Notification - taskflow-backend-cpu-high

Alarm Details:
- AlarmName: taskflow-backend-cpu-high
- State: ALARM
- Reason: Testing alarm notification
```

**テスト後は状態を戻す:**

```bash
aws cloudwatch set-alarm-state \
  --alarm-name taskflow-backend-cpu-high \
  --state-value OK \
  --state-reason "Test completed" \
  --region ap-northeast-1
```

---

#### 14. メール確認リンク実施（重要）

```bash
# 初回設定時、SNS サブスクリプション確認メールが届く場合:
# 1. メール内の Confirm subscription リンクをクリック
# 2. 確認後、以下で確認
```

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $TOPIC_ARN \
  --region ap-northeast-1 \
  --query 'Subscriptions[?Protocol==`email`].[Endpoint, SubscriptionArn]' \
  --output table
```

**期待される結果：** `SubscriptionArn` がない場合は「未確認」、ある場合は「確認済み」

```
| Endpoint          | SubscriptionArn                                   |
|-------------------|--------------------------------------------------|
| user@example.com  | arn:aws:sns:ap-northeast-1:...:...:abc123def... |
```

---

### トラブルシューティング

| 問題 | 原因 | 対処 |
|------|------|------|
| SNS サブスクリプションが `PendingConfirmation` のまま | メール確認リンク未実施 | メール内の Confirm リンクをクリック |
| アラーム通知が来ない | SNS が未確認状態 | 上記のメール確認を実施 |
| ダッシュボードにデータが表示されない | メトリクスのデータ不足 | 数分〜数時間待機（CloudWatch はデータ蓄積に時間がかかる） |
| `Invalid dimension value` エラー | ALB の `arn_suffix` が間違っている | `.arn_suffix` を使用しているか確認 |
| ログが表示されない | ログが出力されていない | アプリケーションが正常に動作しているか確認 |

---

## よくあるエラー

| エラー | 原因 | 対処 |
|--------|------|------|
| `Invalid dimension value` | ALBのarn_suffixが間違っている | `.arn_suffix` を使っているか確認 |
| アラーム通知が来ない | SNSサブスクリプションが未確認 | メールのConfirmリンクをクリック |
| `InvalidParameterValue: Namespace` | メトリクスのNamespaceが間違っている | `AWS/ECS`・`AWS/RDS`・`AWS/ApplicationELB` のスペルを確認 |

---

**全IaCタスク完了！** これでTaskFlowの全インフラがTerraformコードで管理される状態になった。

次のステップ：
- `terraform.tfstate` をS3 + DynamoDBでリモート管理に移行（チーム開発の前提）
- dev環境とprod環境の設定をモジュール化して再利用する
