# Task 3: RDS PostgreSQL 構築

## このタスクのゴール

TaskFlow のタスクデータを保存する **データベース** を構築する。
完成すると、以下が揃う：

- RDS PostgreSQL インスタンス（プライベートサブネットに配置）
- DB サブネットグループ（どのサブネットに配置するかの定義）
- パラメータグループ（DB設定のカスタマイズ）

---

## 背景知識

### RDS とは？

**Relational Database Service** — AWSが管理してくれるデータベースサービス。

> 例え: 自分でDBサーバーを買って設定する代わりに、AWSが「サーバーの管理・バックアップ・パッチ適用」を全部やってくれるレンタルDB。

### なぜ RDS を使うのか？（自前のDBとの違い）

| 項目 | 自前（EC2にDB） | RDS |
|------|-----------------|-----|
| バックアップ | 自分で設定 | 自動（毎日） |
| パッチ適用 | 自分で実行 | 自動 |
| フェイルオーバー | 自分で構築 | Multi-AZ で自動 |
| スケーリング | 手作業 | ボタン1つ |

### Multi-AZ とは？

プライマリDBと同じデータを別AZの**スタンバイDB**に自動複製。プライマリが障害を起こすと、スタンバイに自動切り替え（フェイルオーバー）する。

> 例え: メインの金庫室が壊れても、別の建物にある複製金庫がすぐ使える。

### サブネットグループとは？

「このDBはこれらのサブネットに配置してよい」という許可リスト。Multi-AZ には最低2つのAZのサブネットが必要。

---

## アーキテクチャ上の位置づけ

```
[ECS: Backend] ──(:5432)──▶ [RDS PostgreSQL]
                              │
                        プライベートサブネット
                        (SG: ECSからのみ許可)
```

---

## ハンズオン手順

### Step 1: DB サブネットグループ

```hcl
resource "aws_db_subnet_group" "main" {
  name = "taskflow-db-subnet"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id,
  ]

  tags = { Name = "taskflow-db-subnet" }
}
```

### Step 2: パラメータグループ

```hcl
resource "aws_db_parameter_group" "main" {
  name   = "taskflow-pg16"
  family = "postgres16"

  # 日本語対応のエンコーディング
  parameter {
    name  = "client_encoding"
    value = "UTF8"
  }

  tags = { Name = "taskflow-pg16" }
}
```

### Step 3: RDS インスタンス

```hcl
resource "aws_db_instance" "main" {
  identifier = "taskflow-db"

  # エンジン設定
  engine         = "postgres"
  engine_version = "16.4"

  # インスタンスサイズ（dev用は最小）
  instance_class = "db.t4g.micro"   # 2 vCPU, 1GB RAM（無料枠対象）

  # ストレージ
  allocated_storage     = 20        # 20GB
  max_allocated_storage = 100       # オートスケーリング上限
  storage_type          = "gp3"     # 汎用SSD

  # 認証情報
  db_name  = "taskflow"
  username = "taskflow_admin"
  password = var.db_password        # 変数で管理（ハードコード厳禁！）

  # ネットワーク
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false    # 外部からアクセス不可（重要）

  # 可用性
  multi_az = false                  # dev環境ではコスト節約のためオフ

  # バックアップ
  backup_retention_period = 7       # 7日間保持
  backup_window           = "03:00-04:00"  # UTC（日本時間12:00-13:00）

  # メンテナンス
  maintenance_window = "sun:04:00-sun:05:00"

  # 削除保護
  deletion_protection = false       # dev環境ではオフ（本番はtrue）
  skip_final_snapshot = true        # dev環境ではスナップショット不要

  parameter_group_name = aws_db_parameter_group.main.name

  tags = { Name = "taskflow-db" }
}
```

### Step 4: パスワード変数の定義

`variables.tf`:

```hcl
variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true   # terraform outputやログに表示されない
}
```

`terraform.tfvars`（**Gitにコミットしない！**）:

```hcl
db_password = "YourSecurePassword123!"
```

`.gitignore` に追加:

```
*.tfvars
```

### Step 5: 実行

```bash
terraform plan
terraform apply
```

> RDS の作成には **10-15分** かかる。気長に待とう。

---

## 確認ポイント

1. **AWSコンソール → RDS** で `taskflow-db` が `Available` 状態か
2. エンドポイント（接続先URL）が表示されているか
3. `publicly_accessible` が `false` であること
4. セキュリティグループが `taskflow-rds-sg` であること

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `DBSubnetGroupDoesNotCoverEnoughAZs` | サブネットグループのAZが1つだけ | 2つ以上のAZのサブネットを含める |
| `InvalidParameterValue: password` | パスワードが要件を満たさない | 8文字以上、`/`, `"`, `@` を避ける |
| 作成が非常に遅い | 正常動作 | 10-15分待つ |

---

## 理解度チェック

**Q1.** `publicly_accessible = false` にする理由は？

<details>
<summary>A1</summary>
データベースをインターネットから直接アクセスできないようにするため。プライベートサブネットに配置し、ECS（アプリケーション）経由でのみアクセスさせることでセキュリティを確保する。
</details>

**Q2.** DB のパスワードを `terraform.tfvars` に書いて `.gitignore` する理由は？

<details>
<summary>A2</summary>
パスワードをソースコードにハードコードすると、Gitリポジトリを通じて漏洩するリスクがある。`.tfvars` に分離し `.gitignore` で除外することで、コードと秘密情報を分離する。本番ではAWS Secrets Managerの利用がベスト。
</details>

**Q3.** Multi-AZ を有効にすると何が変わるか？

<details>
<summary>A3</summary>
別のAZにスタンバイDBが自動作成され、データがリアルタイムで同期される。プライマリDBが障害を起こすと、自動的にスタンバイに切り替わる（フェイルオーバー）。ダウンタイムは通常1-2分。ただしコストは約2倍になる。
</details>

---

**前のタスク:** [Task 2: セキュリティグループ](02_security_groups.md)
**次のタスク:** [Task 4: ElastiCache Redis構築](04_elasticache.md) → キャッシュ層を追加する
