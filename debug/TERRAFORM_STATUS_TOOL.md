# Terraform リソース状態確認ツール

このツールは、`terraform apply` で作成された全ての AWS リソースをスキャンし、実際のステータスを確認して統一フォーマットで表示します。

## 設計思想

### 目的
Terraform state ファイルに記録されたリソースと、AWS 側の実際のステータスを同期確認し、乖離やリソースの健全性を把握することが目的です。

### アーキテクチャ

```
[1] terraform state list
    ↓
    全リソースアドレスを列挙
    (aws_vpc.main, aws_subnet.private_1a, ...)
    
[2] リソースタイプ判定
    ↓
    リソースアドレスをパース
    (aws_vpc + main → VPC)
    
[3] terraform state show
    ↓
    Terraform state から以下を抽出
    - Resource ID (vpc-xxxxx など)
    - Name タグ (タグから抽出)
    
[4] AWS CLI リソースタイプ別クエリ
    ↓
    ec2:describe-vpcs
    rds:describe-db-instances
    elbv2:describe-load-balancers
    などを実行してステータス取得
    
[5] ステータス正規化
    ↓
    available → true (isActive)
    creating → false (isActive)
    pending → false (isActive)
    などに統一
    
[6] 統一フォーマット出力
    ↓
    JSON / Table / YAML で表示
```

### 対応リソースタイプ

| AWS リソース | terraform タイプ | ステータス判定 |
|-------------|----------------|-------------|
| VPC | aws_vpc | available/pending |
| Subnet | aws_subnet | available/pending |
| Internet Gateway | aws_internet_gateway | 存在すれば active |
| NAT Gateway | aws_nat_gateway | available/pending/deleting |
| Route Table | aws_route_table | 存在すれば active |
| Security Group | aws_security_group | 存在すれば active |
| RDS (PostgreSQL) | aws_db_instance | available/creating/deleting |
| ElastiCache (Valkey) | aws_elasticache_cluster | available/creating/deleting |
| ALB | aws_lb, aws_alb | active/provisioning |
| ECS Cluster | aws_ecs_cluster | ACTIVE/INACTIVE |
| ECS Service | aws_ecs_service | ACTIVE/INACTIVE |
| IAM Role | aws_iam_role | 存在すれば active |

## 使用方法

### インストール（既設定）

`.zshrc` に以下のエイリアスが設定されています：

```bash
alias tf-status='bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh'
```

### 実行方法

#### 基本的な使用法

```bash
# dev 環境をテーブル形式で表示（デフォルト）
tf-status

# 同上（明示的に指定）
tf-status dev table

# prod 環境をテーブル形式で表示
tf-status prod table
```

#### 出力形式の選択

```bash
# JSON 形式で出力（スクリプト処理に便利）
tf-status dev json

# YAML 形式で出力
tf-status dev yaml

# テーブル形式で出力（見やすい）
tf-status dev table
```

### 出力例

#### テーブル形式

```
ℹ  Scanning terraform state from: /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
ℹ  Environment: dev
ℹ  Output format: table

Name                           Resource Type        Resource ID                    Active     Status
------ ---- ---- ----
taskflow-vpc                   aws_vpc              vpc-0a1b2c3d4e5f6g7h8        true       available
taskflow-subnet-public-1a      aws_subnet           subnet-0f1e2d3c4b5a6g7h8     true       available
taskflow-rds-postgres          aws_db_instance      taskflow-db                   true       available
taskflow-elasticache          aws_elasticache_cluster  taskflow-cache             true       available
taskflow-alb                   aws_lb               arn:aws:elasticloadbalancin  true       active
```

#### JSON 形式

```json
[
  {
    "resource_type": "aws_vpc",
    "name": "taskflow-vpc",
    "resource_id": "vpc-0a1b2c3d4e5f6g7h8",
    "isActive": "true",
    "status": "available"
  },
  {
    "resource_type": "aws_subnet",
    "name": "taskflow-subnet-public-1a",
    "resource_id": "subnet-0f1e2d3c4b5a6g7h8",
    "isActive": "true",
    "status": "available"
  }
]
```

#### YAML 形式

```yaml
resources:
  - name: "taskflow-vpc"
    resource_type: "aws_vpc"
    resource_id: "vpc-0a1b2c3d4e5f6g7h8"
    isActive: true
    status: "available"
  - name: "taskflow-subnet-public-1a"
    resource_type: "aws_subnet"
    resource_id: "subnet-0f1e2d3c4b5a6g7h8"
    isActive: true
    status: "available"
```

## 出力フォーマット仕様

### JSON フォーマット

各リソースは以下の構造を持ちます：

```json
{
  "resource_type": "aws_vpc",           // terraform リソースタイプ
  "name": "taskflow-vpc",                // Name タグ（なければリソース論理名）
  "resource_id": "vpc-xxxxx",            // AWS リソース ID
  "isActive": "true",                    // ステータスをBoolean化（true/false）
  "status": "available"                  // 詳細ステータス（元の値）
}
```

### テーブルフォーマット

```
Name              Resource Type        Resource ID             Active    Status
----              ----                 ----                    ----      ----
(30文字)          (20文字)             (30文字)                (10文字)  (15文字)
```

カラー出力：
- **Name**: 白
- **Active**: `true` なら緑、`false` なら赤
- **その他**: 白

### YAML フォーマット

```yaml
resources:
  - name: "..."
    resource_type: "..."
    resource_id: "..."
    isActive: <boolean>
    status: "..."
```

## 内部処理の説明

### ステップ 1: terraform state から全リソースを列挙

```bash
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/{env}
terraform state list
```

出力例：
```
aws_vpc.main
aws_subnet.public_1a
aws_subnet.private_1a
aws_security_group.backend
aws_db_instance.postgres
```

### ステップ 2: リソースアドレスをパース

`aws_vpc.main` を分解：
- **resource_type**: `aws_vpc`
- **resource_name**: `main`

### ステップ 3: Terraform state から ID とタグを抽出

```bash
terraform state show aws_vpc.main
```

取得内容：
- **id**: `vpc-xxxxx`
- **Name tag**: `"taskflow-vpc"`

### ステップ 4: AWS CLI で実際のステータスを確認

```bash
# VPC の場合
aws ec2 describe-vpcs --vpc-ids vpc-xxxxx \
  --query 'Vpcs[0].[VpcId, State]' --output json

# RDS の場合
aws rds describe-db-instances --db-instance-identifier taskflow-db \
  --query 'DBInstances[0].[DBInstanceIdentifier, DBInstanceStatus]' --output json
```

### ステップ 5: ステータス正規化

AWS のステータス値を `isActive: true/false` に正規化：

```bash
# VPC, Subnet, RDS, ElastiCache
available → true
pending/creating → false

# ALB, ECS
active → true
provisioning/inactive → false

# IAM Role, Security Group
存在 → true
```

## スクリプトのカスタマイズ

### 新しいリソースタイプの追加

`query_*_status()` 関数を追加してから、`get_resource_status()` に以下を追加：

```bash
query_my_resource_status() {
    local resource_id="$1"
    aws myservice describe-resources \
        --resource-ids "$resource_id" \
        --query 'Resources[0].[ResourceId, Status]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

# get_resource_status() の case 文に追加
aws_my_resource)
    query_my_resource_status "$resource_id"
    ;;
```

### 出力形式の変更

`output_*()` 関数を編集して、JSON/YAML/Table の形式をカスタマイズできます。

## トラブルシューティング

### "Terraform directory not found"

**原因**: terraform ディレクトリのパスが誤っている

**解決策**:
```bash
# スクリプト内の TF_DIR を確認
grep "TF_DIR=" /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh
```

### "No resources found in terraform state"

**原因**: 
1. `terraform apply` がまだ実行されていない
2. リソースはあるが state に記録されていない

**解決策**:
```bash
# state 内容を直接確認
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
terraform state list
cat terraform.tfstate | jq '.resources'
```

### AWS CLI エラー

**原因**: AWS 認証情報が無い、または対象リソースが存在しない

**解決策**:
```bash
# AWS 認証状態確認
aws-whoami

# SSO ログイン（必要な場合）
awslogin

# 特定リソースを直接クエリ
aws ec2 describe-vpcs --vpc-ids vpc-xxxxx
```

### リソース ID が取得できない

**原因**: Terraform state の形式が変わった

**解決策**:
```bash
# state を直接確認
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
terraform state show aws_vpc.main | grep "^id"
```

## パフォーマンス

- **実行時間**: 小規模（10〜20リソース）では 10〜30 秒
- **AWS API リクエスト**: リソース数に応じて増加
  - 各リソースタイプ 1 リクエスト
  - 例：VPC, Subnet ×3, RDS, ALB = 6 リクエスト

## セキュリティ

- **認証**: AWS CLI の認証情報を使用
  - `~/.aws/credentials` または `$AWS_PROFILE`
  - SSO: `aws sso login --profile AdministratorAccess-840854900854`

- **リソース アクセス**: リソースの読み取り権限が必要
  - `describe-*` API に対する IAM 権限

- **出力**: ログは stderr、結果は stdout に出力
  - リソース ID はプレーンテキスト（機密情報として扱わない）

## ライセンス

TaskFlow プロジェクトの一部。AWS learning project として使用。
