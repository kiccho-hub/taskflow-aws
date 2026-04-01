# Task 5: ECR リポジトリ作成

## このタスクのゴール

TaskFlow の Docker イメージを保管する **コンテナレジストリ** を作る。
完成すると、以下が揃う：

- ECR リポジトリ 2つ（Backend 用・Frontend 用）
- ライフサイクルポリシー（古いイメージの自動削除）
- ローカルからイメージを push できる状態

---

## 背景知識

### コンテナとは？

アプリケーションとその動作に必要なものを**1つのパッケージ**にまとめたもの。

> 例え: 引っ越し用の段ボール箱。アプリ本体・設定ファイル・ライブラリを全部入れて、どこに持って行っても同じように動く。

### Docker イメージとは？

コンテナの「設計図」。イメージから実際に動くコンテナが起動する。

```
Dockerfile（レシピ）→ Docker イメージ（料理の写真）→ コンテナ（実際の料理）
```

### ECR とは？

**Elastic Container Registry** — AWSが提供するDockerイメージの保管庫。

> 例え: GitHub がソースコードの保管庫なら、ECR は Docker イメージの保管庫。

### なぜ ECR を使うのか？

| 比較 | Docker Hub | ECR |
|------|-----------|-----|
| AWSとの連携 | 設定が必要 | ネイティブ連携 |
| プライベート | 有料プラン | デフォルトでプライベート |
| ECSからの取得速度 | やや遅い | 同一リージョンで高速 |

---

## アーキテクチャ上の位置づけ

```
[開発者PC] ──docker push──▶ [ECR]
                              │
                        docker pull
                              │
                              ▼
                        [ECS Fargate]
```

ECR は ECS がコンテナを起動するときにイメージを取得する場所。

---

## ハンズオン手順

### Step 1: ECR リポジトリ作成

```hcl
# Backend用
resource "aws_ecr_repository" "backend" {
  name = "taskflow-backend"

  image_scanning_configuration {
    scan_on_push = true    # push時に脆弱性スキャン
  }

  image_tag_mutability = "IMMUTABLE"  # 同じタグで上書き不可（安全）

  tags = { Name = "taskflow-backend" }
}

# Frontend用
resource "aws_ecr_repository" "frontend" {
  name = "taskflow-frontend"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "IMMUTABLE"

  tags = { Name = "taskflow-frontend" }
}
```

**パラメータ解説:**
- `scan_on_push`: イメージの脆弱性を自動チェック
- `IMMUTABLE`: 一度 push したタグは変更不可（`latest` の上書き防止）

### Step 2: ライフサイクルポリシー

古いイメージが溜まるとコストがかかるため、自動削除ルールを設定。

```hcl
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10             # 最新10個だけ保持
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

### Step 3: 実行

```bash
terraform plan
terraform apply
```

### Step 4: Docker イメージを push する（手動確認用）

```bash
# AWSにログイン（リージョンとアカウントIDを置き換え）
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com

# イメージをビルド
docker build -t taskflow-backend ./backend

# タグ付け
docker tag taskflow-backend:latest \
  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow-backend:v1

# push
docker push \
  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow-backend:v1
```

> `123456789012` は自分のAWSアカウントIDに置き換えること。

---

## 確認ポイント

1. **AWSコンソール → ECR** で2つのリポジトリが表示されるか
2. ライフサイクルポリシーが設定されているか
3. （Step 4 を実行した場合）イメージが表示されるか

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `RepositoryAlreadyExistsException` | 同名リポジトリが既存 | 名前を変えるか既存を削除 |
| `docker login` 失敗 | AWS CLI 未設定 | `aws configure` でアクセスキーを設定 |
| `denied: Your authorization token has expired` | ログイントークン期限切れ（12時間） | `get-login-password` を再実行 |

---

## 理解度チェック

**Q1.** `image_tag_mutability = "IMMUTABLE"` にする理由は？

<details>
<summary>A1</summary>
同じタグ（例: v1）で異なるイメージを上書きできないようにする。これにより「本番で動いているv1と、手元のv1が別物」という事故を防ぐ。どのタグがどのイメージかを確実に追跡できる。
</details>

**Q2.** ライフサイクルポリシーはなぜ必要か？

<details>
<summary>A2</summary>
デプロイのたびに新しいイメージが追加され、ストレージコストが増え続ける。ライフサイクルポリシーで古いイメージを自動削除することでコストを抑える。
</details>

---

**前のタスク:** [Task 4: ElastiCache構築](04_elasticache.md)
**次のタスク:** [Task 6: ECSクラスター構築](06_ecs_cluster.md) → コンテナを動かす基盤を作る
