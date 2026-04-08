# Terraform リソース状態確認ツール - クイックスタート

## 何ができるのか？

`terraform apply` で AWS に作成した全リソースを自動スキャンし、**実際のステータス** を確認します。

```
Terraform State  →  [スクリプト]  →  AWS CLI Query  →  統一フォーマット表示
  (ローカル)        (自動処理)      (リアルタイム)      (Table/JSON/YAML)
```

---

## インストール（既済み）

`.zshrc` に以下のエイリアスが設定されています：

```bash
alias tf-status='bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh'
```

---

## 実行方法

### 基本

```bash
# dev 環境、テーブル形式（推奨）
tf-status

# または明示的に
tf-status dev table
```

### 環境指定

```bash
# dev 環境
tf-status dev table

# prod 環境
tf-status prod table
```

### 出力形式

```bash
# テーブル形式（見やすい、デフォルト）
tf-status dev table

# JSON 形式（スクリプト処理向け）
tf-status dev json

# YAML 形式（設定ファイル互換）
tf-status dev yaml
```

---

## 出力例

### テーブル形式

```
Name                           Resource Type        Resource ID              Active   Status
taskflow-vpc                   aws_vpc              vpc-0a1b2c3d4e5f6g7h8    true     available
taskflow-subnet-public-1a      aws_subnet           subnet-0f1e2d3c4b5a6g7h true     available
taskflow-rds-postgres          aws_db_instance      taskflow-db              true     available
```

### JSON 形式

```json
[
  {
    "resource_type": "aws_vpc",
    "name": "taskflow-vpc",
    "resource_id": "vpc-0a1b2c3d4e5f6g7h8",
    "isActive": "true",
    "status": "available"
  }
]
```

---

## 対応リソース

| リソース | terraform タイプ | ステータス判定 |
|---------|----------------|-------------|
| VPC | `aws_vpc` | available / pending |
| Subnet | `aws_subnet` | available / pending |
| Security Group | `aws_security_group` | exist |
| Internet Gateway | `aws_internet_gateway` | exist |
| NAT Gateway | `aws_nat_gateway` | available / pending / deleting |
| Route Table | `aws_route_table` | exist |
| RDS PostgreSQL | `aws_db_instance` | available / creating |
| ElastiCache Valkey | `aws_elasticache_cluster` | available / creating |
| ALB | `aws_lb`, `aws_alb` | active / provisioning |
| ECS Cluster | `aws_ecs_cluster` | ACTIVE / INACTIVE |
| ECS Service | `aws_ecs_service` | ACTIVE / INACTIVE |
| IAM Role | `aws_iam_role` | exist |

---

## 実用例

### 全リソース ID を取得

```bash
tf-status dev json | jq -r '.[] | .resource_id'
```

出力：
```
vpc-0a1b2c3d4e5f6g7h8
subnet-0f1e2d3c4b5a6g7h
taskflow-db
```

### 停止中のリソースを検出

```bash
tf-status dev json | jq '.[] | select(.isActive == "false")'
```

### 特定のリソースタイプのみ表示

```bash
tf-status dev json | jq '.[] | select(.resource_type == "aws_db_instance")'
```

### ヘルスチェック（CI/CD 向け）

```bash
#!/bin/bash
INACTIVE=$(tf-status dev json | jq '[.[] | select(.isActive == "false")] | length')
if [ "$INACTIVE" -gt 0 ]; then
    echo "警告: $INACTIVE個の非アクティブリソース"
    exit 1
fi
```

---

## トラブルシューティング

### "terraform directory not found"

terraform ディレクトリが見つからない。以下を確認：

```bash
ls -la /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev/
```

### "No resources found in terraform state"

terraform apply がまだ実行されていない。実行順序：

```bash
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
terraform apply
tf-status dev table
```

### AWS CLI エラー

認証情報が無い。以下で確認・ログイン：

```bash
# AWS 認証状態確認
aws-whoami

# SSO ログイン（必要な場合）
awslogin
```

---

## 詳細ドキュメント

- **[TERRAFORM_STATUS_TOOL.md](./TERRAFORM_STATUS_TOOL.md)** - 設計思想・内部処理・カスタマイズ方法
- **[USAGE_EXAMPLES.sh](./USAGE_EXAMPLES.sh)** - 豊富な実行例

---

## ファイル構成

```
/Users/yuki-mac/claude-code/aws-demo/debug/
├── README.md                        ← 概要
├── QUICKSTART.md                    ← このファイル（使い方）
├── TERRAFORM_STATUS_TOOL.md         ← 詳細設計書
├── USAGE_EXAMPLES.sh                ← 実行例集
└── terraform-resource-status.sh     ← メインスクリプト
```

---

## 次のステップ

1. **AWS リソース作成**
   ```bash
   cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
   terraform apply
   ```

2. **ステータス確認**
   ```bash
   tf-status dev table
   ```

3. **JSON で処理**
   ```bash
   tf-status dev json | jq '.[] | .name'
   ```
