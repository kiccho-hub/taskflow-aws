# Task 10: S3 + CloudFront 設定

## このタスクのゴール

TaskFlow の React フロントエンドを **CDN経由で高速配信** する。
完成すると、以下が揃う：

- S3 バケット（ビルド済みファイルの保管場所）
- CloudFront ディストリビューション（CDN）
- OAC（S3への安全なアクセス制御）

---

## 背景知識

### なぜ S3 + CloudFront？

React の SPA はビルドすると HTML/CSS/JS の静的ファイルになる。これをサーバー（ECS）で配信する必要はなく、S3 に置いて CloudFront で配信するのが高速・安価・スケーラブル。

| 方式 | 速度 | コスト | スケーリング |
|------|------|--------|-------------|
| ECS で配信 | 普通 | 高い | 設定が必要 |
| S3 + CloudFront | 高速 | 安い | 自動 |

### S3 とは？

**Simple Storage Service** — AWSのオブジェクトストレージ。ファイルを保存する場所。

> 例え: 無限に大きいファイルサーバー。容量を気にせずファイルを置ける。

### CloudFront とは？

**CDN（Content Delivery Network）** — 世界中のエッジロケーション（中継サーバー）にコンテンツをキャッシュし、ユーザーに最も近い場所から配信する。

> 例え: 本店（S3）の人気商品を各支店（エッジ）にも在庫として置いておく。お客さんは最寄りの支店で素早く買える。

### OAC とは？

**Origin Access Control** — CloudFront だけが S3 にアクセスできるようにする仕組み。S3 を直接公開せずに済む。

```
ユーザー → CloudFront → S3（OACで制限）
ユーザー → S3（直接アクセス不可 ✗）
```

---

## アーキテクチャ上の位置づけ

```
[ブラウザ]
    │
    ▼
[CloudFront]
    │
    ├── /* (静的ファイル) → [S3: React ビルドファイル]
    └── /api/*            → [ALB → ECS Backend]
```

> CloudFront がフロントエンド（S3）と API（ALB）の両方の入口になる。

---

## ハンズオン手順

### Step 1: S3 バケット

```hcl
resource "aws_s3_bucket" "frontend" {
  bucket = "taskflow-frontend-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "taskflow-frontend" }
}

# アカウントID取得用
data "aws_caller_identity" "current" {}

# パブリックアクセスをブロック（CloudFront経由のみ許可）
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**ポイント:** S3バケット名はグローバルでユニーク。アカウントIDを付けて重複回避。

### Step 2: OAC

```hcl
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "taskflow-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

### Step 3: CloudFront ディストリビューション

```hcl
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "TaskFlow Frontend"

  # オリジン1: S3（静的ファイル）
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # オリジン2: ALB（API）
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb-backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # デフォルト: S3 から配信
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400      # 1日キャッシュ
    max_ttl     = 31536000   # 最大1年
  }

  # /api/* は ALB に転送（キャッシュしない）
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-backend"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0          # APIはキャッシュしない
    max_ttl     = 0
  }

  # SPA のルーティング対応（404を index.html に）
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true   # まずはデフォルト証明書
  }

  tags = { Name = "taskflow-cdn" }
}
```

**重要ポイント:**
- `custom_error_response`: React Router のクライアントサイドルーティングに対応。`/tasks/123` に直接アクセスしても `index.html` が返る
- `/api/*` は `default_ttl = 0` でキャッシュしない（APIのレスポンスをキャッシュすると古いデータが返る）

### Step 4: S3 バケットポリシー

```hcl
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
```

### Step 5: 実行

```bash
terraform plan
terraform apply
```

### Step 6: ビルドファイルのアップロード（手動確認用）

```bash
# React をビルド
cd frontend && npm run build

# S3 にアップロード
aws s3 sync build/ s3://taskflow-frontend-ACCOUNT_ID/

# CloudFront のキャッシュを削除（変更を即時反映）
aws cloudfront create-invalidation \
  --distribution-id DISTRIBUTION_ID \
  --paths "/*"
```

---

## 確認ポイント

1. **AWSコンソール → CloudFront** でディストリビューションが `Deployed` か
2. CloudFront の URL（`dxxxxxx.cloudfront.net`）にアクセスして画面が表示されるか
3. `/api/health` にアクセスして Backend に転送されるか
4. S3 バケットに直接アクセスして `403 Forbidden` が返るか（OAC が効いている証拠）

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `AccessDenied` | バケットポリシーの設定ミス | OAC の ARN とポリシーの Condition を確認 |
| SPA で画面が真っ白 | `default_root_object` 未設定 | `index.html` を設定 |
| API が 502 | ALB オリジンの設定ミス | `origin_protocol_policy` を確認 |
| デプロイ後も古い画面 | キャッシュ | `create-invalidation` を実行 |

---

## 理解度チェック

**Q1.** S3 を直接公開せず OAC を使う理由は？

<details>
<summary>A1</summary>
S3を直接公開すると、CloudFrontを通さないアクセスが可能になり、キャッシュの恩恵を受けられない上にアクセス制御が困難になる。OACにより「CloudFront経由でのみ」S3にアクセスできるようにし、セキュリティとパフォーマンスを両立する。
</details>

**Q2.** `custom_error_response` で 404 を 200 + `index.html` に変換する理由は？

<details>
<summary>A2</summary>
React SPAはクライアントサイドルーティングを使う。`/tasks/123` のようなURLに直接アクセスすると、S3には該当ファイルが存在しないため404になる。これを `index.html` に転送することで、React Router がURLを解釈して正しい画面を表示する。
</details>

---

**前のタスク:** [Task 9: Cognito認証](09_cognito.md)
**次のタスク:** [Task 11: CI/CD](11_cicd.md) → デプロイを自動化する
