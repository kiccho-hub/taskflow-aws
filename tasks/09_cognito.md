# Task 9: Cognito 認証設定

## このタスクのゴール

TaskFlow に **ユーザー認証（ログイン機能）** を追加する。
完成すると、以下が揃う：

- Cognito ユーザープール（ユーザーDB）
- アプリクライアント（フロントエンドからの認証窓口）
- ユーザーグループ（ロール制御: user / admin）

---

## 背景知識

### Cognito とは？

AWSが提供する **認証サービス**。ユーザー登録・ログイン・トークン発行を全部やってくれる。

> 例え: ビルの「受付＋入館証発行所」。身分証を見せて（ログイン）、入館証（トークン）をもらう。各フロア（API）は入館証を見て通してくれる。

### なぜ自前で認証を作らないのか？

| 項目 | 自前実装 | Cognito |
|------|---------|---------|
| パスワード管理 | ハッシュ化、ソルト… | 自動 |
| MFA | 一から実装 | 設定だけ |
| トークン管理 | JWT発行・検証を実装 | 自動 |
| セキュリティ対策 | ブルートフォース対策等 | 組み込み済み |

> 認証はセキュリティの最重要部分。実績のあるマネージドサービスに任せるのがベスト。

### Cognito の登場人物

```
ユーザープール（ユーザーのDB）
 ├── ユーザー（田中さん、鈴木さん...）
 ├── グループ（admin, user）
 └── アプリクライアント（React アプリからの接続設定）
```

### 認証フロー

```
1. [React] → Cognito にログインリクエスト
2. [Cognito] → ID トークン + アクセストークンを返す
3. [React] → API リクエストに トークンを付けて送信
4. [Backend] → トークンを検証 → ユーザー情報・ロールを取得
```

---

## アーキテクチャ上の位置づけ

```
[ブラウザ] ──ログイン──▶ [Cognito]
    │                       │
    │◀──トークン発行────────┘
    │
    │ Authorization: Bearer <token>
    ▼
  [ALB] → [ECS Backend] → トークン検証
```

---

## ハンズオン手順

### Step 1: ユーザープール

```hcl
resource "aws_cognito_user_pool" "main" {
  name = "taskflow-users"

  # ログイン方法: メールアドレス
  username_attributes = ["email"]

  # パスワードポリシー
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # メール検証（サインアップ時に確認メール送信）
  auto_verified_attributes = ["email"]

  # ユーザーの属性
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = { Name = "taskflow-users" }
}
```

**パラメータ解説:**
- `username_attributes = ["email"]`: メールアドレスをユーザー名として使用
- `auto_verified_attributes`: サインアップ時に自動で検証コードを送る属性

### Step 2: アプリクライアント

```hcl
resource "aws_cognito_user_pool_client" "web" {
  name         = "taskflow-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # トークン設定
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",          # セキュアなパスワード認証
    "ALLOW_REFRESH_TOKEN_AUTH",     # トークンの更新
  ]

  # トークンの有効期限
  access_token_validity  = 1       # 1時間
  id_token_validity      = 1       # 1時間
  refresh_token_validity = 30      # 30日

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # クライアントシークレットは生成しない（SPAでは不要）
  generate_secret = false

  # コールバックURL（ログイン後のリダイレクト先）
  callback_urls = ["http://localhost:3000/callback"]
  logout_urls   = ["http://localhost:3000"]

  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]
}
```

**ポイント:**
- `generate_secret = false`: SPA（React）はクライアントサイドで動くため、シークレットを安全に保持できない。そのため生成しない。

### Step 3: ユーザーグループ（ロール制御）

```hcl
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administrator group"
  precedence   = 1              # 優先度（小さいほど高い）
}

resource "aws_cognito_user_group" "user" {
  name         = "user"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Regular user group"
  precedence   = 10
}
```

### Step 4: ドメイン（Hosted UI 用）

```hcl
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "taskflow-auth"            # ユニークな名前
  user_pool_id = aws_cognito_user_pool.main.id
}
```

> これで `https://taskflow-auth.auth.ap-northeast-1.amazoncognito.com` にログイン画面が生成される。

### Step 5: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → Cognito** でユーザープールが表示されるか
2. アプリクライアントが作成されているか
3. admin / user グループが存在するか
4. Hosted UI の URL にアクセスしてログイン画面が表示されるか

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `UsernameExistsException` | 同じメールアドレスで登録済み | 別のメールで試す |
| `InvalidParameterException` | スキーマ定義が不正 | required属性を確認 |
| ドメイン作成失敗 | ドメイン名が既に使われている | 別のユニークな名前に変更 |

---

## 理解度チェック

**Q1.** ID トークンとアクセストークンの違いは？

<details>
<summary>A1</summary>
IDトークンは「ユーザーが誰か」の情報（名前、メール、所属グループなど）を含む。アクセストークンは「何ができるか」の権限情報を含む。Backend は用途に応じて使い分ける（ユーザー情報が欲しいならIDトークン、権限チェックならアクセストークン）。
</details>

**Q2.** SPA で `generate_secret = false` にする理由は？

<details>
<summary>A2</summary>
SPAはブラウザ上で動くため、ソースコード（JavaScript）がユーザーに丸見え。クライアントシークレットをコードに含めると漏洩するため、シークレットなしの認証フロー（PKCE付き Authorization Code Flow）を使う。
</details>

**Q3.** ユーザーグループの `precedence` は何のために使うか？

<details>
<summary>A3</summary>
ユーザーが複数グループに所属する場合、IDトークンの `cognito:groups` に含まれるグループの優先順位を決める。precedence が最も小さいグループの権限が優先的に適用される。
</details>

---

**前のタスク:** [Task 8: ECSサービス](08_ecs_services.md)
**次のタスク:** [Task 10: S3 + CloudFront](10_s3_cloudfront.md) → フロントエンドの静的配信を設定する
