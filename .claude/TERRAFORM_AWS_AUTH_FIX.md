# Terraform AWS 認証エラー修正ガイド

## 問題の概要

**エラー：** `terraform plan` で「No valid credential sources found」または「failed to refresh cached credentials」

**原因：** Terraform の AWS provider で、SSO プロファイルが明示的に指定されていなかった。

---

## 修正内容

### 1. プロバイダー設定に `profile` パラメータを追加

**修正ファイル：** `infra/environments/dev/main.tf`

**変更前：**
```hcl
provider "aws" {
  region = "ap-northeast-1"
}
```

**変更後：**
```hcl
provider "aws" {
  region  = "ap-northeast-1"
  profile = "AdministratorAccess-840854900854"  # SSO プロファイル名を追加
}
```

**重要：** プロファイル名は `aws configure sso` で設定した値と完全に一致する必要があります。

---

## 技術背景（初心者向け）

### AWS 認証の仕組み

ローカルマシンで AWS を操作するとき、Terraform（や AWS CLI）は以下の順序で認証情報を探します：

1. **環境変数**（`AWS_ACCESS_KEY_ID`など） → アクセスキーベース
2. **~/.aws/credentials** → アクセスキーファイル
3. **~/.aws/config** + SSO プロファイル → **← 現在のセットアップ**
4. **EC2 インスタンスメタデータ** → EC2 上でのみ有効
5. **ECS タスクロール** → ECS 上でのみ有効

### なぜ `profile` が必要か？

SSO（Single Sign-On）を使う場合、`~/.aws/config` に以下のようにプロファイルが定義されます：

```
[profile AdministratorAccess-840854900854]
sso_start_url = https://...
sso_region = ...
sso_account_id = 840854900854
sso_role_name = AdministratorAccess
```

Terraform に「**どのプロファイルを使うか**」を指示しないと、AWS SDK は困って EC2 メタデータを探し始めます。EC2 ではないローカルマシンなので失敗します。

### こうしていなかった理由

初期テンプレートでは `profile` を指定していませんでした。本番環境では環境変数でプロファイルを設定するケースもあるため、明示的な指定を避けていた可能性があります。

---

## 診断・確認コマンド

### 1. SSO プロファイルが正しく設定されているか確認

```bash
aws sts get-caller-identity --profile AdministratorAccess-840854900854
```

**期待結果：**
```json
{
  "UserId": "...",
  "Account": "840854900854",
  "Arn": "arn:aws:iam::840854900854:user/..."
}
```

### 2. Terraform が使用するプロファイルを確認

```bash
cd infra/environments/dev
terraform plan
```

**成功：** リソース計画が表示される

### 3. デバッグ情報を見たい場合

```bash
TF_LOG=DEBUG terraform plan
```

ログに「Using AWS profile 'AdministratorAccess-840854900854'」のような文字が出れば正しく読み込めています。

---

## 本番環境（prod）への対応

もし `infra/environments/prod/main.tf` が存在する場合、同じ修正を加えます：

```hcl
provider "aws" {
  region  = "ap-northeast-1"
  profile = "AdministratorAccess-840854900854"
}
```

---

## ベストプラクティス

### 異なるプロファイルを環境で使い分けたい場合

Terraform 変数で動的に設定することもできます：

```hcl
variable "aws_profile" {
  description = "AWS SSO profile name"
  type        = string
  default     = "AdministratorAccess-840854900854"
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = var.aws_profile
}
```

実行時：
```bash
terraform apply -var="aws_profile=AdministratorAccess-840854900854"
```

### 環境変数での上書き（CI/CD向け）

GitHub Actions などで `AWS_PROFILE` 環境変数を使用する場合、provider 設定を以下のように記述：

```hcl
provider "aws" {
  region = "ap-northeast-1"
}
```

実行前に環境変数を設定：
```bash
export AWS_PROFILE=AdministratorAccess-840854900854
terraform plan
```

---

## よくある間違い

| 状況 | 原因 | 解決策 |
|------|------|--------|
| `profile` を指定しているのに「credentials not found」 | プロファイル名が誤っている | `aws configure sso` で確認した名前と一致させる |
| `aws sts get-caller-identity` は成功するが `terraform plan` は失敗 | SSO トークンが期限切れ | `aws sso login --profile AdministratorAccess-840854900854` を実行 |
| 複数のプロファイルがあって混乱 | デフォルトプロファイルが古い | `~/.aws/config` を確認して `default` プロファイルを更新 |

---

## 次のステップ

1. ✅ `infra/environments/dev/main.tf` に `profile` を追加
2. 次のコマンドで動作確認：
   ```bash
   cd infra/environments/dev
   terraform plan
   ```
3. 本番環境の設定も同じプロファイルを使う場合は `prod/main.tf` にも追加

---

**最終確認日：** 2026-04-08  
**作成者：** Claude Code (Haiku 4.5)
