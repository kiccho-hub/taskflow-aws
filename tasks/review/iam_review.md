# IAM 振り返りシート

> Task 11（CI/CD）の学習を通じて扱った IAM 関連概念の体系的なまとめ。
> 目的：GitHub Actions OIDC 連携を中心に、IAM の基礎から応用までを整理する。

---

## 目次

1. [IAM の基本構造](#1-iam-の基本構造)
2. [ロール と ポリシー の関係](#2-ロール-と-ポリシー-の関係)
3. [Principal の 4 種類](#3-principal-の-4-種類)
4. [OIDC 連携とは](#4-oidc-連携とは)
5. [STS と一時クレデンシャル](#5-sts-と一時クレデンシャル)
6. [AssumeRole / AssumeRoleWithWebIdentity](#6-assumerole--assumerolewithwebidentity)
7. [OIDC 認証の 4 段階ガード](#7-oidc-認証の-4-段階ガード)
8. [Terraform 実装パターン（GitHub Actions OIDC）](#8-terraform-実装パターンgithub-actions-oidc)
9. [用語集](#9-用語集)
10. [理解度チェック](#10-理解度チェック)
11. [よくある誤解と修正](#11-よくある誤解と修正)

---

## 1. IAM の基本構造

### IAM = Identity and Access Management

AWS における「誰が」「何を」「どう」できるかを定義する仕組み。

### 主要コンポーネント

| 要素 | 役割 | 例え |
|------|------|------|
| **IAM User** | 永続アカウント（人が使う） | 正社員の社員証 |
| **IAM Role** | 一時的にまとう役・権限セット | 着ぐるみ／役職 |
| **IAM Policy** | 何ができるかのルール書 | 権利書／ビザ |
| **IAM Group** | ユーザーをまとめる単位 | 部署 |
| **Identity Provider** | 外部の認証機関登録 | 提携大使館 |

### クレデンシャルの種類

| 種類 | プレフィックス | 期限 | 発行元 |
|------|--------------|------|--------|
| 永続アクセスキー | `AKIA...` | 無期限（手動ローテーションまで） | IAMユーザー作成時 |
| 一時アクセスキー | `ASIA...` | 15分〜12時間 | STS |

**一時キーは必ず SessionToken とセットで使う。**

---

## 2. ロール と ポリシー の関係

### 概念

```
ロール   = 人・役・キャラ本体（空の器）
ポリシー = 宛名付きの権利書
```

### 階層関係

```
[IAM Role: "github-actions-taskflow"]    ← 人（空の着ぐるみ）
     ↑
     │ 宛名として参照される
     │
┌────┴─────────────────────────┐
│                              │
[Policy A]  [Policy B]  [Policy C]     ← 個別に発行される権利書
 ECS権限     S3権限       ECR権限         各々が「宛先ロール」を知っている
```

### 重要な視点

- **ロール自身は「自分に何のポリシーが付いているか」を知らない**
- **ポリシーが「自分の宛先ロール」を知っている**
- これはデータベースの「外部キー（Foreign Key）」パターンと同じ

### 2 種類のポリシー（役割別）

1 つのロールには **2 種類のポリシー**が付く：

| ポリシー種別 | Terraform リソース | 役割 |
|------------|------------------|------|
| **信頼ポリシー（Trust Policy）** | `aws_iam_role.assume_role_policy` | **誰がこのロールに変身できるか** |
| **権限ポリシー（Permission Policy）** | `aws_iam_role_policy` | **変身した人が何をできるか** |

### 例え話：仮装舞踏会

```
ロール「仮装衣装」    = 着ぐるみ
信頼ポリシー           = 「この衣装を着られるのは誰か」の招待状規定
権限ポリシー           = 「この衣装を着たら何ができるか」の能力リスト
```

---

## 3. Principal の 4 種類

信頼ポリシーの `Principal` = 「誰がこのロールに変身できるか」の指定。

| 種類 | 書き方 | ユースケース |
|------|-------|------------|
| **AWS** | `{ AWS = "arn:aws:iam::123:user/alice" }` | IAMユーザー/ロール同士の権限委譲 |
| **Service** | `{ Service = "ec2.amazonaws.com" }` | EC2/Lambda/ECSなどAWSサービスがロールを使う |
| **Federated** | `{ Federated = "arn:...:oidc-provider/..." }` | **外部IdP経由**（GitHub/Google/Okta/Cognito） |
| **`"*"`** | `Principal = "*"` | 誰でも（基本的に禁止・危険） |

### 今回の GitHub Actions OIDC は `Federated`

- AWS 社員証（IAMユーザー）ではない
- AWS サービスでもない
- 外部 IdP（GitHub）から来た人なので **`Federated`**

---

## 4. OIDC 連携とは

### 目的：パスワードレスな外部連携

従来の方法（悪い）：
- GitHub Secrets に永続アクセスキーを保存
- 漏洩リスク・ローテーション負担が大きい

OIDC 連携（良い）：
- GitHub が JWT トークンを動的発行
- AWS は JWT を検証 → 一時クレデンシャル発行（最大 1 時間）
- **永続鍵ゼロ**

### 例え話

- 旧来：マスターキー配布（落としたら終わり）
- OIDC：ワンタイムパスワード入館（1 時間で自動失効）

### 登場する AWS リソース（3 つ）

1. **IAM OIDC Provider** — GitHub を「信頼できるID発行者」として AWS に登録
2. **IAM Role** — GitHub Actions が変身する役
3. **IAM Role Policy** — 変身後の権限（ECS/ECR/S3/CloudFront 操作）

---

## 5. STS と一時クレデンシャル

### STS = Security Token Service

AWS における「一時クレデンシャル発行の専用窓口」。エンドポイント：`sts.amazonaws.com`。

### STS の主要 API

| API | 用途 |
|-----|------|
| `AssumeRole` | IAM ユーザー/ロールが別ロールに変身 |
| **`AssumeRoleWithWebIdentity`** | **OIDC トークンでロール変身（今回）** |
| `AssumeRoleWithSAML` | SAML でロール変身 |
| `GetSessionToken` | MFA 付き一時セッション取得 |
| `GetCallerIdentity` | 「今の自分」を確認 |

### 一時クレデンシャルの構成

```
AccessKeyId       : ASIA... （ASIA で始まる）
SecretAccessKey   : xxxxx...
SessionToken      : FwoGZXIvYXdzE... （必ずセット必要）
Expiration        : 2026-04-17T17:30:00Z
```

**SessionToken がないと ASIA キーは使えない。** 3 点セット必須。

---

## 6. AssumeRole / AssumeRoleWithWebIdentity

### 共通：「ロールに変身する」API

`Assume` = 「（役や姿を）まとう・変身する」。「引き受ける」という訳は誤解を招きやすい。

### 違い：事前の身分証

| 観点 | `AssumeRole` | `AssumeRoleWithWebIdentity` |
|------|-------------|----------------------------|
| 呼ぶ人 | AWS内のIAMユーザー/別ロール | 外部（GitHub/Google/Cognito等） |
| 提示する身分証 | 永続クレデンシャル（AKIA...） | JWT（OIDCトークン） |
| 認証方法 | AWSがキーを直接確認 | JWT署名+TLS指紋で検証 |
| `Principal` | `AWS = "..."` | `Federated = "..."` |

### 変身の結果（両方共通）

一時クレデンシャル（`ASIA...` + SessionToken）が発行される。呼び出し側はこれを使って AWS API を叩く。

---

## 7. OIDC 認証の 4 段階ガード

GitHub Actions の OIDC 認証で、AWS STS は **4 つの独立した検証**を通す。

| # | 検証項目 | 対象 | 目的 |
|---|---------|------|------|
| ① | **TLS 証明書指紋** | iss URL の TLS 証明書 | 発行者エンドポイントが本物か |
| ② | **JWT 署名検証** | JWT の Signature 部 | トークンが改ざんされてないか |
| ③ | **aud 検証** | JWT の `aud` クレーム | AWS 向けトークンか |
| ④ | **Condition 検証** | JWT の `sub` 等 | どのリポジトリ・ブランチか |

### ①②は「TLS/JWTレイヤー」、③④は「IAMレイヤー」

```
 ①    ②                    ③          ④
TLS  JWT署名              aud検証      sub検証
 ↑    ↑                   ↑           ↑
 ネットワーク接続先の真正性   中身・宛先・実行コンテキスト
```

### 比喩：大使館のビザ申請

| チェック | 大使館員が見るもの |
|---------|----------------|
| ① TLS 指紋 | 発行所の建物が本物か |
| ② JWT 署名 | パスポートの印刷が本物か |
| ③ aud | 対象国が自国か |
| ④ Condition | 入国目的・ビザ種別・有効期間 |

全部通って初めて入国許可（一時クレデンシャル発行）。

---

## 8. Terraform 実装パターン（GitHub Actions OIDC）

### 完成形 4 リソース

```hcl
# ① TLS証明書取得（TLSプロバイダー）
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# ② OIDC Provider 登録
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.github.certificates[*].sha1_fingerprint
}

# ③ ロール（空の着ぐるみ + 信頼ポリシー）
resource "aws_iam_role" "github_actions" {
  name = "github-actions-taskflow"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:kiccho-hub/taskflow-aws:ref:refs/heads/main"
        }
      }
    }]
  })
}

# ④ 権限ポリシー（ロール宛の権利書）
resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-taskflow-policy"
  role = aws_iam_role.github_actions.id   # 宛名：どのロールに発行するか

  policy = jsonencode({
    Statement = [
      { Effect = "Allow", Action = ["ecr:*"],            Resource = "*" },
      { Effect = "Allow", Action = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:RegisterTaskDefinition"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"], Resource = [aws_s3_bucket.frontend.arn, "${aws_s3_bucket.frontend.arn}/*"] },
      { Effect = "Allow", Action = ["cloudfront:CreateInvalidation"], Resource = aws_cloudfront_distribution.frontend.arn },
    ]
  })
}
```

### 各フィールドの意味（日本語訳）

#### `client_id_list`
- **「受け入れるトークンの `aud` 値」のホワイトリスト**
- GitHub Actions の公式アクションは `aud = "sts.amazonaws.com"` をデフォルトで使うのでこれを書く

#### `thumbprint_list`
- **「信頼する TLS 証明書の SHA1 指紋リスト」**
- `data.tls_certificate` で動的取得することで、GitHub の証明書ローテーションに自動追従
- スプラット式 `[*]` で証明書チェーン全体の指紋を抽出

#### `Principal.Federated`
- **「②で登録した OIDC Provider 経由で来た人を受け入れる」という指定**
- ARN は `aws_iam_openid_connect_provider.github.arn` で参照

#### `Action = "sts:AssumeRoleWithWebIdentity"`
- **「OIDC トークンでロール変身するAPI」を許可**

#### `Condition.StringEquals` / `StringLike`
- JWT クレームとの比較
- `aud` = 完全一致 / `sub` = ワイルドカード許容

#### `sub` の形式
```
repo:<owner>/<repo>:ref:refs/heads/<branch>
repo:<owner>/<repo>:pull_request
repo:<owner>/<repo>:environment:<env>
repo:<owner>/<repo>:ref:refs/tags/<tag>
```

---

## 9. 用語集

| 用語 | 読み方 | 意味 |
|------|-------|------|
| **IAM** | アイアム | Identity and Access Management。AWS の権限管理サービス |
| **STS** | エス・ティ・エス | Security Token Service。一時クレデンシャル発行サービス |
| **IdP** | アイ・ディ・ピー | Identity Provider。ID発行者 |
| **OIDC** | オー・アイ・ディ・シー | OpenID Connect。OAuth 2.0 ベースの認証プロトコル |
| **JWT** | ジョット / ジェイ・ダブリュー・ティー | JSON Web Token。署名付きの認証トークン |
| **JWKS** | ジェイ・ダブリュー・ケー・エス | JSON Web Key Set。公開鍵のリスト公開エンドポイント |
| **aud** | オード | Audience。JWT の「宛先」クレーム |
| **sub** | サブ | Subject。JWT の「主体」クレーム（誰が/どこから） |
| **iss** | イス | Issuer。JWT の発行者URL |
| **Principal** | プリンシパル | 信頼ポリシーにおける「誰が」 |
| **Federation** | フェデレーション | 外部IdPとの連携 |
| **Trust Policy** | トラストポリシー | 信頼ポリシー。誰がロールを引き受けられるか |
| **Permission Policy** | パーミッションポリシー | 権限ポリシー。何ができるか |
| **Assume** | アシューム | まとう・変身する（≠引き受け） |
| **Thumbprint** | サムプリント | 証明書の SHA1 指紋 |
| **SigV4** | シグ・ブイ・フォー | AWS Signature Version 4。AWSの署名規格 |

---

## 10. 理解度チェック

設問に対して自分の言葉で答えてみましょう。答えはこのドキュメント内にあります。

### レベル1（基礎）

1. IAM Role と IAM Policy の違いを 1 行で説明してください。
2. `AKIA` と `ASIA` のアクセスキーの違いは？
3. STS は何をするサービス？
4. IAM Role における 2 種類のポリシーの役割の違いは？

### レベル2（中級）

5. `AssumeRole` と `AssumeRoleWithWebIdentity` の違いは？
6. `Principal.Federated` を使う条件は？
7. OIDC Provider で `client_id_list` に書く値は何に対応する？
8. `thumbprint_list` に `data.tls_certificate` を使う利点は？

### レベル3（応用）

9. GitHub Actions が AWS にアクセスする際、AWS STS が行う 4 つの検証を挙げよ。
10. `Condition.StringLike` で `sub` を検査する目的を説明せよ。
11. `aws_iam_role_policy` の `role = aws_iam_role.github_actions.id` はなぜこの方向（ポリシー → ロール）で参照する？
12. 一時クレデンシャル（`ASIA...` キー）単独では AWS API を叩けない理由を述べよ。

### レベル4（実装）

13. もし develop ブランチからも同じロールを使わせたい場合、Terraform をどう書き換える？
14. 複数のリポジトリから同じロールを使わせる書き方は？
15. 権限ポリシーで `Resource = "*"` を使うリスクとその緩和方法は？

---

## 11. よくある誤解と修正

### ❌ 誤解 1：JWT の中に TLS 証明書が入っている
**✅ 修正**：JWT には claims（iss/sub/aud/exp）しか入っていない。TLS証明書検証は JWT の中身ではなく、**iss URL への HTTPS 接続時に相手が提示する証明書**に対して行う。

### ❌ 誤解 2：「ロールを引き受ける」= 誰かから権限を譲り受ける
**✅ 修正**：`Assume` は「まとう・変身する」。自分が一時的に別のキャラになるだけ。誰かから奪うわけではない。

### ❌ 誤解 3：ロールがポリシーのリストを保持している
**✅ 修正**：ポリシーが「自分の宛先ロール」を知っている（DBの外部キーパターン）。ロール自身は自分に付いたポリシー一覧を持たない。

### ❌ 誤解 4：`client_id_list` は OAuth 2.0 のクライアント ID
**✅ 修正**：名前は歴史的経緯で `client_id` だが、実体は **JWT の `aud` クレームとの照合リスト**。

### ❌ 誤解 5：IAM ユーザーを作らないと AWS にアクセスできない
**✅ 修正**：STS + OIDC/SAML で永続ユーザーなしでもアクセス可能。むしろ CI/CD やマシン間通信ではこちらが推奨。

---

## まとめカード

```
【GitHub Actions → AWS デプロイを支える 5 層】

レイヤー1  TLS（HTTPS）
          → 通信相手の真正性（thumbprint_list）

レイヤー2  JWT（OIDC トークン）
          → 発行者が正規（JWKS署名検証）

レイヤー3  aud / sub 等のクレーム
          → トークンの文脈（OIDC Provider の client_id_list、Role の Condition）

レイヤー4  IAM Role（信頼ポリシー）
          → 「誰が変身できるか」（Principal.Federated + Condition）

レイヤー5  IAM Policy（権限ポリシー）
          → 「変身後に何ができるか」（Action + Resource）

すべてが揃って初めて
「GitHub Actions が AWS に安全にアクセスできる」が成立する。
```

---

## 関連リソース

- [AWS 公式: Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS 公式: IAM Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [AWS 公式: AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [jwt.io](https://jwt.io/) — JWT デコーダー（学習用）
