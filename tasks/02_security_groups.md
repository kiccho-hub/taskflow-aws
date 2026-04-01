# Task 2: セキュリティグループ設定

## このタスクのゴール

Task 1 で作った VPC 内で「誰が誰と通信できるか」を制御する **セキュリティグループ (SG)** を作る。
完成すると、以下の4つのSGが揃う：

- ALB用 SG（外部からHTTP/HTTPSを受け付ける）
- ECS用 SG（ALBからのみ通信を受ける）
- RDS用 SG（ECSからのみ接続を受ける）
- Redis用 SG（ECSからのみ接続を受ける）

---

## 背景知識

### セキュリティグループとは？

AWSリソースに付ける **仮想ファイアウォール**。「どこからの通信を許可するか」をルールで定義する。

> 例え: ビルの各部屋に付ける「入室許可リスト」。受付（ALB）は誰でも入れるが、サーバールーム（RDS）はエンジニア（ECS）しか入れない。

### 重要なルール

| 概念 | 説明 |
|------|------|
| インバウンド | 外から中への通信（受信） |
| アウトバウンド | 中から外への通信（送信） |
| ステートフル | 許可した通信の戻りは自動許可 |
| デフォルト | インバウンド全拒否、アウトバウンド全許可 |

### SG同士の参照

SGのルールでは、IPアドレスの代わりに**別のSGのID**を指定できる。これにより「ALBのSGを持つリソースからのみ許可」のような柔軟な制御ができる。

> IPが変わってもルールを変更する必要がない。

---

## アーキテクチャ上の位置づけ

```
インターネット
    │
    ▼ (:80, :443)
┌─[SG: ALB]──────────┐
│  ALB                │
└─────────────────────┘
    │ (:3000, :8080)
    ▼
┌─[SG: ECS]──────────┐
│  Backend / Frontend │
└─────────────────────┘
    │ (:5432)      │ (:6379)
    ▼              ▼
┌─[SG: RDS]─┐  ┌─[SG: Redis]─┐
│ PostgreSQL │  │ ElastiCache  │
└────────────┘  └──────────────┘
```

**通信は上から下への一方向チェーン。** 各SGは「直前のレイヤーからのみ受信許可」にする。

---

## ハンズオン手順

### Step 1: ALB 用セキュリティグループ

```hcl
resource "aws_security_group" "alb" {
  name        = "taskflow-alb-sg"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  # インバウンド: インターネットからHTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 全世界から許可
  }

  # インバウンド: インターネットからHTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # アウトバウンド: 全て許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"           # -1 = 全プロトコル
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "taskflow-alb-sg" }
}
```

### Step 2: ECS 用セキュリティグループ

```hcl
resource "aws_security_group" "ecs" {
  name        = "taskflow-ecs-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.main.id

  # ALB からのみ受信（SGのIDで参照）
  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # ALBのSGを参照
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "taskflow-ecs-sg" }
}
```

**ポイント:** `cidr_blocks` ではなく `security_groups` でALBのSGを指定。IPが変わっても安全。

### Step 3: RDS 用セキュリティグループ

```hcl
resource "aws_security_group" "rds" {
  name        = "taskflow-rds-sg"
  description = "Allow PostgreSQL from ECS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432           # PostgreSQL のデフォルトポート
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "taskflow-rds-sg" }
}
```

### Step 4: Redis 用セキュリティグループ

```hcl
resource "aws_security_group" "redis" {
  name        = "taskflow-redis-sg"
  description = "Allow Redis from ECS only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from ECS"
    from_port       = 6379           # Redis のデフォルトポート
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "taskflow-redis-sg" }
}
```

### Step 5: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → VPC → セキュリティグループ** で4つのSGが表示されるか
2. 各SGのインバウンドルールが設計どおりか
3. RDS SGのインバウンドに `0.0.0.0/0` が **ない** ことを確認（セキュリティ上重要）

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `Error: cycle detected` | SG同士の循環参照 | 片方を先に作り、後からルール追加 |
| `InvalidGroup.Duplicate` | 同じ名前のSGが既にある | 名前を変えるか既存を削除 |
| 通信できない | SGルールの不足 | インバウンドの `security_groups` が正しいか確認 |

---

## 理解度チェック

**Q1.** セキュリティグループがステートフルであるとはどういう意味か？

<details>
<summary>A1</summary>
インバウンドで許可された通信に対する応答（戻りの通信）は、アウトバウンドルールに関係なく自動的に許可される。逆も同様。つまり、リクエストを許可すればレスポンスは自動で通る。
</details>

**Q2.** RDS のSGで `cidr_blocks = ["0.0.0.0/0"]` を指定するとどうなるか？なぜ危険か？

<details>
<summary>A2</summary>
世界中のどこからでもPostgreSQLに接続できてしまう。データベースが直接攻撃される可能性があり、極めて危険。必ず `security_groups` で特定のSG（ECS）からのみ許可する。
</details>

**Q3.** SGのルールでIPアドレスではなくSGのIDを参照するメリットは？

<details>
<summary>A3</summary>
リソースのIPが変わってもルールを変更する必要がない。ECSタスクはデプロイごとにIPが変わるため、SG参照にしないと運用が破綻する。
</details>

---

**前のタスク:** [Task 1: VPC構築](01_vpc.md)
**次のタスク:** [Task 3: RDS PostgreSQL構築](03_rds.md) → SGを使ってDBを安全に配置する
