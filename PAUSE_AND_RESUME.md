# PAUSE_AND_RESUME.md - 簡潔版

毎日リソースを削除してコストを削減し、翌日スクラッチから再構築する手順。

---

## 朝：Terraform 削除・再構築

```bash
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
```

```bash
terraform destroy -auto-approve
```

```bash
terraform apply -auto-approve
```

**期待される出力：**
```
Destroy complete! Resources: 18 destroyed.
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
```

> **トラブル:** `Error: error deleting security group` の場合は `terraform apply -auto-approve` → `terraform destroy -auto-approve` を実行

---

## 朝：ECR ログイン

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

```bash
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
```

**期待される出力：**
```
Login Succeeded
```

---

## 朝：バックエンド Docker ビルド・プッシュ

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

```bash
cd /Users/yuki-mac/claude-code/aws-demo/app/backend
```

```bash
docker build -t taskflow-backend:latest .
```

```bash
docker tag taskflow-backend:latest ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/backend:latest
```

```bash
docker push ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/backend:latest
```

---

## 朝：フロントエンド Docker ビルド・プッシュ

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

```bash
cd /Users/yuki-mac/claude-code/aws-demo/app/frontend
```

```bash
docker build -t taskflow-frontend:latest .
```

```bash
docker tag taskflow-frontend:latest ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/frontend:latest
```

```bash
docker push ${ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/frontend:latest
```

---

## 朝：RDS 初期化（オプション）

```bash
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
```

```bash
RDS_ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)
```

```bash
RDS_PASSWORD=$(terraform output -raw rds_password)
```

```bash
PGPASSWORD=$RDS_PASSWORD psql -h $RDS_ENDPOINT -p 5432 -U postgres -f /Users/yuki-mac/claude-code/aws-demo/app/db/schema.sql
```

---

## 朝：動作確認

```bash
cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev
```

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
```

```bash
curl -s http://$ALB_DNS/api/health | jq .
```

```bash
aws ecs describe-services \
  --cluster taskflow-cluster \
  --services taskflow-backend taskflow-frontend \
  --region ap-northeast-1 \
  --query 'services[].[serviceName, desiredCount, runningCount, status]' \
  --output table
```

**期待される出力（API）：**
```json
{
  "status": "ok",
  "timestamp": "2026-04-15T12:34:56Z"
}
```

**期待される出力（ECS）：**
```
| taskflow-backend  | 1 | 1 | ACTIVE |
| taskflow-frontend | 1 | 1 | ACTIVE |
```

ブラウザで `http://$ALB_DNS` にアクセスしてフロントエンド表示確認

---

## 参考：リソース削除確認

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=taskflow-vpc" --region ap-northeast-1 --query 'Vpcs[]' --output text
```

> **出力が空なら削除成功**

---

**所要時間：** 約 15〜20分（Docker ビルド含む）  
**月額コスト削減：** 約 $51（NAT Gateway $33 + ALB $18）
