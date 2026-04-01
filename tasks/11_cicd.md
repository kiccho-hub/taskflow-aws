# Task 11: GitHub Actions CI/CD

## このタスクのゴール

コードを push したら自動でテスト・ビルド・デプロイされる **CI/CD パイプライン** を構築する。
完成すると、以下が揃う：

- CI ワークフロー（テスト・Lint）
- CD ワークフロー（Docker ビルド → ECR push → ECS デプロイ）
- フロントエンドの S3 デプロイ + CloudFront キャッシュ削除

---

## 背景知識

### CI/CD とは？

| 用語 | 正式名称 | 意味 |
|------|---------|------|
| CI | Continuous Integration | コード変更のたびに自動でテスト・ビルド |
| CD | Continuous Delivery/Deployment | テスト通過後に自動でデプロイ |

> 例え: CI = 「工場の品質検査ライン」、CD = 「検査通過品を自動で店舗に配送」

### なぜ CI/CD が必要か？

| 手動デプロイ | CI/CD |
|-------------|-------|
| 手順書を見ながら実行 | 自動 |
| 人為的ミスが起きる | 毎回同じ手順 |
| 時間がかかる | 数分で完了 |
| テスト忘れがある | テスト必須にできる |

### GitHub Actions とは？

GitHub に組み込まれた CI/CD サービス。リポジトリ内の `.github/workflows/` にYAMLファイルを置くだけで動く。

### 基本概念

```
ワークフロー (.yml ファイル)
 └── ジョブ (job) — 実行単位
       └── ステップ (step) — 個々のコマンド
```

| 概念 | 説明 |
|------|------|
| トリガー | いつ実行するか（push, PR, 手動など） |
| ジョブ | 独立した実行環境で動く処理のまとまり |
| ステップ | ジョブ内の1つ1つの作業 |
| アクション | 再利用可能な処理パッケージ（`actions/checkout` など） |
| シークレット | パスワードやAPIキーの安全な保管場所 |

---

## アーキテクチャ上の位置づけ

```
[git push] → [GitHub Actions]
                │
                ├── CI: テスト・Lint
                │
                ├── CD (Backend):
                │     Docker build → ECR push → ECS デプロイ
                │
                └── CD (Frontend):
                      npm build → S3 sync → CloudFront invalidation
```

---

## ハンズオン手順

### Step 1: ディレクトリ構成

```bash
mkdir -p .github/workflows
```

### Step 2: CI ワークフロー（テスト）

`.github/workflows/ci.yml`:

```yaml
name: CI

# トリガー: main へのPR作成・更新時
on:
  pull_request:
    branches: [main]

jobs:
  test-backend:
    runs-on: ubuntu-latest        # 実行環境（Ubuntu）

    steps:
      # リポジトリのコードを取得
      - uses: actions/checkout@v4

      # Node.js のセットアップ
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: backend/package-lock.json

      # 依存関係インストール
      - run: cd backend && npm ci

      # Lint（コード品質チェック）
      - run: cd backend && npm run lint

      # テスト実行
      - run: cd backend && npm test

  test-frontend:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - run: cd frontend && npm ci
      - run: cd frontend && npm run lint
      - run: cd frontend && npm test -- --coverage
```

**ポイント:**
- `npm ci`: `npm install` より高速・再現性が高い（lock ファイル通りにインストール）
- `cache: 'npm'`: node_modules をキャッシュして次回以降高速化
- 2つのジョブは**並列実行**される

### Step 3: CD ワークフロー（Backend デプロイ）

`.github/workflows/deploy-backend.yml`:

```yaml
name: Deploy Backend

on:
  push:
    branches: [main]              # main に push されたら実行
    paths:
      - 'backend/**'              # backend ディレクトリに変更があった場合のみ

# GitHub Actions から AWS にアクセスするための権限
permissions:
  id-token: write                 # OIDC トークン発行
  contents: read

env:
  AWS_REGION: ap-northeast-1
  ECR_REPOSITORY: taskflow-backend
  ECS_CLUSTER: taskflow-cluster
  ECS_SERVICE: taskflow-backend

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      # AWS認証（OIDC — アクセスキー不要で安全）
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      # ECR にログイン
      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr-login

      # Docker イメージをビルド & push
      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}    # コミットハッシュをタグに
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG ./backend
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      # ECS サービスを更新（新しいイメージでデプロイ）
      - name: Deploy to ECS
        env:
          IMAGE_TAG: ${{ github.sha }}
        run: |
          aws ecs update-service \
            --cluster $ECS_CLUSTER \
            --service $ECS_SERVICE \
            --force-new-deployment
```

**重要な概念:**
- **OIDC認証**: アクセスキーをシークレットに保存する代わりに、GitHub と AWS の信頼関係を使う。キーの漏洩リスクがゼロ。
- **`${{ github.sha }}`**: コミットハッシュをイメージタグにすることで、どのコミットがデプロイされているか追跡可能。

### Step 4: CD ワークフロー（Frontend デプロイ）

`.github/workflows/deploy-frontend.yml`:

```yaml
name: Deploy Frontend

on:
  push:
    branches: [main]
    paths:
      - 'frontend/**'

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: ap-northeast-1

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      # ビルド
      - name: Build
        run: |
          cd frontend
          npm ci
          npm run build

      # S3 にアップロード
      - name: Deploy to S3
        run: |
          aws s3 sync frontend/build/ s3://${{ secrets.S3_BUCKET_NAME }}/ \
            --delete    # S3 にあるがビルドにないファイルを削除

      # CloudFront のキャッシュ削除
      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ secrets.CLOUDFRONT_DISTRIBUTION_ID }} \
            --paths "/*"
```

### Step 5: GitHub にシークレットを登録

GitHub リポジトリの **Settings → Secrets and variables → Actions** で以下を登録：

| シークレット名 | 値 |
|---------------|-----|
| `AWS_ROLE_ARN` | OIDC用IAMロールのARN |
| `S3_BUCKET_NAME` | フロントエンド用S3バケット名 |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFrontのID |

### Step 6: OIDC 用 IAM ロール（Terraform）

```hcl
# GitHub OIDC プロバイダー
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# GitHub Actions 用 IAM ロール
resource "aws_iam_role" "github_actions" {
  name = "taskflow-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }]
  })
}

# 必要な権限をアタッチ（ECR, ECS, S3, CloudFront）
resource "aws_iam_role_policy" "github_actions" {
  name = "taskflow-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = aws_cloudfront_distribution.main.arn
      },
    ]
  })
}
```

---

## 確認ポイント

1. PR を作成して CI（テスト）が自動実行されるか
2. main に merge して CD（デプロイ）が自動実行されるか
3. **GitHub → Actions タブ** でワークフローの実行結果が確認できるか
4. デプロイ後にアプリが正常に動作するか

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | OIDC 設定ミス | IAMロールの `Condition` でリポジトリ名を確認 |
| `Error: Process completed with exit code 1` | テストまたはビルド失敗 | ログを読んでエラー箇所を特定 |
| ECR push 後に ECS が更新されない | `force-new-deployment` の欠如 | ワークフローにコマンドがあるか確認 |

---

## 理解度チェック

**Q1.** CI と CD の違いは？それぞれのトリガーは何にしたか？

<details>
<summary>A1</summary>
CI（Continuous Integration）はコード品質の検証（テスト・Lint）で、PRの作成・更新時にトリガーされる。CD（Continuous Deployment）は本番環境へのデプロイで、mainブランチへのpush（merge）時にトリガーされる。CIが通らないとmergeできない → CDが走らない、という関門になっている。
</details>

**Q2.** OIDC 認証がアクセスキーより安全な理由は？

<details>
<summary>A2</summary>
アクセスキーは長期的な認証情報でシークレットに保管するため、漏洩リスクがある。OIDC は GitHub と AWS の信頼関係に基づき、ワークフロー実行時に一時的なトークンを発行するため、永続的な認証情報が存在しない。キーのローテーションも不要。
</details>

**Q3.** `paths: ['backend/**']` の役割は？

<details>
<summary>A3</summary>
backend ディレクトリ内のファイルに変更があった場合のみワークフローを実行する。frontend だけ変更したのに backend のデプロイが走るのは無駄なので、変更箇所に応じて必要なデプロイだけ実行する。
</details>

---

**前のタスク:** [Task 10: S3 + CloudFront](10_s3_cloudfront.md)
**次のタスク:** [Task 12: CloudWatch監視](12_monitoring.md) → アプリの健康状態を監視する
