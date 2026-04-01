# Knowledge 11: CI/CDとGitHub Actions

Task 11（GitHub Actions CI/CD）の前に理解しておくべき概念。

---

## CI/CDとは

| 用語 | 意味 | 具体的な作業 |
|------|------|------------|
| CI（継続的インテグレーション）| コード変更のたびに自動でテスト・ビルド | lintチェック・単体テスト・ビルド確認 |
| CD（継続的デリバリー）| テスト通過後に本番へのデプロイ準備 | デプロイパッケージ作成まで自動 |
| CD（継続的デプロイメント）| テスト通過後に自動でデプロイ完了 | 承認なしで本番まで自動 |

CI/CDがない場合の問題：
- 手動デプロイは手順書を読みながら実行 → ミスが起きる
- テストを忘れてデプロイする
- 誰かが「後でテストする」と言って放置する

---

## GitHub Actionsの基本概念

`.github/workflows/` 配下のYAMLファイルでワークフローを定義する。

```yaml
# 構造の例
name: ワークフロー名

on:               # いつ実行するか（トリガー）
  push:
    branches: [main]

jobs:
  build:          # ジョブ名（複数定義でき、並行実行も可）
    runs-on: ubuntu-latest    # 実行環境

    steps:        # このジョブでやること
      - uses: actions/checkout@v4    # 既存アクションを使う
      - run: npm test               # シェルコマンドを実行
```

**ジョブの並行実行：** デフォルトで複数ジョブは並行実行される。順序依存がある場合は `needs: [前のジョブ名]` で依存関係を設定する。

---

## AWSへの認証方法の比較

GitHub ActionsからAWSを操作する際の認証方法。

### ① IAMアクセスキー（非推奨）
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```
**問題点：** アクセスキーは長期有効な認証情報。GitHubのSecretsに保存するが、漏洩すると永続的に悪用される。またキーのローテーションも自分で管理する必要がある。

### ② OIDC（推奨）
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions-role
    aws-region: ap-northeast-1
```
**仕組み：** GitHub → AWSに「私はこのリポジトリのワークフローです」という署名付きJWTを送る。AWSはそれを検証して一時的な認証情報（STS）を発行する。**アクセスキーが存在しない**ため漏洩リスクがない。

**OIDCの設定が必要なもの：**
1. AWS IAMにGitHub OIDCプロバイダーを登録
2. IAMロールの信頼ポリシーにGitHubリポジトリを指定

---

## OIDCの信頼ポリシー（重要な制限）

IAMロールが「どのリポジトリのどのブランチから」のみ使えるかを制限できる。

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub":
        "repo:yourname/aws-demo:ref:refs/heads/main"
    }
  }
}
```

`StringLike` と `*` を使ってブランチを絞る。`repo:yourname/*` のようにリポジトリを特定しないと、自分の他のリポジトリからもロールを使えてしまうので注意。

---

## Secretsとリポジトリ変数

**Secrets（秘密情報）：**
GitHubのUI上でもマスクされる。一度設定すると値を確認できない。パスワード・APIキー・ARN等を保存する。

**Variables（変数）：**
秘密ではない設定値（リージョン・バケット名等）に使う。ログに出力されても問題ないもの。

環境（Environment）ごとにSecretsを分けることもできる。`development`環境と`production`環境で別のIAMロールARNを設定する、など。

---

## ECSデプロイのフロー

```
git push main
    ↓
GitHub Actions起動
    ↓
① docker build でイメージ作成
    ↓
② aws ecr get-login-password | docker login
    ↓
③ docker push → ECRにイメージ保存
    ↓
④ aws ecs update-service --force-new-deployment
    ↓
ECSがローリングアップデート実行
    ↓
新しいタスクが起動 → ヘルスチェック通過 → 古いタスクを停止
```

`--force-new-deployment` はタスク定義が変わっていなくても新しいタスクを起動させるフラグ。イメージのlatestタグを更新した場合に使う。本番では特定タグのイメージをタスク定義に記録してから更新する方が安全。

---

## フロントエンドデプロイのフロー

```
git push main
    ↓
npm run build（React ビルド）
    ↓
aws s3 sync build/ s3://バケット名/ --delete
    ↓
aws cloudfront create-invalidation --paths "/*"
```

`--delete` フラグ：S3に残っている古いファイル（前のビルドには存在したが今のビルドにはないファイル）を削除する。これを付けないと古いファイルが残り続ける。

---

## ワークフローのベストプラクティス

- **ブランチ保護：** mainへの直接pushを禁止し、PRを必須にする
- **同時実行の制限：** `concurrency` 設定で同じブランチへの複数デプロイが重ならないようにする
- **失敗時の通知：** Slack通知やGitHub Issueへの自動コメントを設定する
- **デプロイの承認：** 本番環境へのデプロイはEnvironment Protectionで手動承認を挟む
