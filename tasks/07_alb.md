# Task 7: ALB 構築・パスベースルーティング

## このタスクのゴール

リクエストを Backend / Frontend に振り分ける **ロードバランサー** を作る。
完成すると、以下が揃う：

- Application Load Balancer (ALB)
- ターゲットグループ 2つ（Backend 用・Frontend 用）
- リスナールール（パスベースルーティング）

---

## 背景知識

### ロードバランサーとは？

外部からのリクエストを複数のサーバーに**分散**する仕組み。

> 例え: レストランの受付。お客さん（リクエスト）を空いているテーブル（サーバー）に案内する。1つのテーブルに集中しないようにする。

### ALB とは？

**Application Load Balancer** — HTTP/HTTPS レベルで動作するロードバランサー。URLのパスやヘッダーを見て、振り分け先を決められる。

### パスベースルーティング

URLのパスによって転送先を変える機能。TaskFlow では：

| パス | 転送先 |
|------|--------|
| `/api/*` | Backend（ECS） |
| `/*` （それ以外） | Frontend（ECS） |

> 1つのドメイン（`taskflow.example.com`）で Backend と Frontend を両方提供できる。

### ALB の登場人物

```
ALB（受付）
 └── リスナー（どのポートで待つか: 80, 443）
       └── リスナールール（どの条件でどこに転送するか）
             └── ターゲットグループ（転送先のコンテナ群）
```

---

## アーキテクチャ上の位置づけ

```
インターネット
    │
    ▼
┌── ALB ──────────────────────────┐
│  リスナー :80                    │
│    ├── /api/* → TG: Backend     │
│    └── /*     → TG: Frontend    │
└──────────────────────────────────┘
    │                    │
    ▼                    ▼
[ECS: Backend]    [ECS: Frontend]
```

---

## ハンズオン手順

### Step 1: ALB 本体

```hcl
resource "aws_lb" "main" {
  name               = "taskflow-alb"
  internal           = false              # インターネット向け（外部公開）
  load_balancer_type = "application"      # ALB を指定
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_a.id,               # パブリックサブネットに配置
    aws_subnet.public_c.id,
  ]

  tags = { Name = "taskflow-alb" }
}
```

**パラメータ解説:**
- `internal = false`: インターネットからアクセス可能。`true` にすると VPC 内部のみ
- `load_balancer_type`: `application`（HTTP/HTTPS）, `network`（TCP/UDP）, `gateway` の3種類

### Step 2: ターゲットグループ

```hcl
# Backend用
resource "aws_lb_target_group" "backend" {
  name        = "taskflow-backend-tg"
  port        = 3000                      # Backend アプリのポート
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"                      # Fargate では ip を指定

  health_check {
    path                = "/api/health"   # ヘルスチェック用エンドポイント
    port                = "traffic-port"
    healthy_threshold   = 2               # 2回連続成功で healthy
    unhealthy_threshold = 3               # 3回連続失敗で unhealthy
    interval            = 30              # 30秒間隔でチェック
    timeout             = 5
    matcher             = "200"           # HTTP 200 で成功判定
  }

  tags = { Name = "taskflow-backend-tg" }
}

# Frontend用
resource "aws_lb_target_group" "frontend" {
  name        = "taskflow-frontend-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "taskflow-frontend-tg" }
}
```

**ヘルスチェックとは？** ALB がターゲット（コンテナ）に定期的にリクエストを送り、正常に応答するか確認する仕組み。異常なコンテナにはリクエストを送らない。

### Step 3: リスナーとルーティングルール

```hcl
# HTTP リスナー（ポート80）
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # デフォルトアクション: Frontend に転送
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# /api/* は Backend に転送
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100                      # 小さい数字が優先

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]                 # /api/ で始まるパス
    }
  }
}
```

**ルーティングの流れ:**
1. リクエストが ALB に到着
2. パスが `/api/*` に一致 → Backend TG へ（priority 100）
3. 一致しない → デフォルトの Frontend TG へ

### Step 4: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → EC2 → ロードバランサー** で `taskflow-alb` が `Active` か
2. DNS名（`taskflow-alb-xxxx.ap-northeast-1.elb.amazonaws.com`）が発行されているか
3. リスナールールで `/api/*` → Backend、`/*` → Frontend の設定があるか
4. ターゲットグループのヘルスチェックパスが正しいか

> この時点ではターゲット（ECSタスク）がまだないため、ヘルスチェックは unhealthy になる。Task 8 完了後に healthy になる。

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `At least two subnets in two different AZs` | サブネットが1AZしかない | 2つのAZのパブリックサブネットを指定 |
| ターゲットが unhealthy | ECSサービスがまだない | Task 8 完了後に確認 |
| `DuplicateListener` | 同じポートのリスナーが既存 | 既存を削除するか別ポートを使用 |

---

## 理解度チェック

**Q1.** ALB のターゲットグループで `target_type = "ip"` を指定する理由は？

<details>
<summary>A1</summary>
Fargate ではコンテナに動的にIPが割り当てられ、EC2インスタンスIDを持たない。そのため、target_type を "ip" にして、IPアドレスベースでターゲットを登録する。EC2モードでは "instance" を使う。
</details>

**Q2.** ヘルスチェックが unhealthy になるとどうなるか？

<details>
<summary>A2</summary>
ALB はそのターゲット（コンテナ）にリクエストを転送しなくなる。healthy なターゲットにのみリクエストが振り分けられる。全ターゲットが unhealthy だと 503 エラーが返る。
</details>

**Q3.** リスナールールの priority の役割は？

<details>
<summary>A3</summary>
ルールの評価順序を決める。数字が小さいほど優先的に評価される。最初にマッチしたルールが適用され、どのルールにもマッチしなければデフォルトアクションが実行される。
</details>

---

**前のタスク:** [Task 6: ECSクラスター](06_ecs_cluster.md)
**次のタスク:** [Task 8: ECSサービス・タスク定義](08_ecs_services.md) → ALBの先にコンテナを配置する
