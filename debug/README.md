# Debug ツール群

TaskFlow インフラの構築と調査を支援するユーティリティスクリプト。

## terraform-resource-status.sh

terraform apply で作成された全リソースのステータスをスキャン・表示します。

### クイックスタート

```bash
# インストール（既設定）
alias tf-status='bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh'

# デフォルト実行（dev, テーブル形式）
tf-status

# prod 環境、JSON 形式
tf-status prod json
```

### 出力例

```
Name                           Resource Type        Resource ID              Active   Status
taskflow-vpc                   aws_vpc              vpc-0a1b2c3d4e5f6g7h8    true     available
taskflow-subnet-public-1a      aws_subnet           subnet-0f1e2d3c4b5a6g7h true     available
taskflow-rds-postgres          aws_db_instance      taskflow-db              true     available
```

### 対応リソース

- **ネットワーク**: VPC, Subnet, Internet Gateway, NAT Gateway, Route Table
- **セキュリティ**: Security Group
- **データベース**: RDS (PostgreSQL)
- **キャッシュ**: ElastiCache (Valkey)
- **ロードバランシング**: ALB
- **コンテナ**: ECS Cluster, ECS Service
- **IAM**: IAM Role

### フォーマット

- **table** (デフォルト): 見やすいテーブル形式
- **json**: スクリプト処理向け
- **yaml**: 設定ファイル互換

詳細は [TERRAFORM_STATUS_TOOL.md](./TERRAFORM_STATUS_TOOL.md) を参照。

---

### ファイル構成

```
debug/
├── README.md                        ← このファイル
├── terraform-resource-status.sh     ← メインスクリプト
├── TERRAFORM_STATUS_TOOL.md         ← 詳細ドキュメント
└── USAGE_EXAMPLES.sh                ← 実行例集
```
