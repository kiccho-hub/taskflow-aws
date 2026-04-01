# Knowledge 05: コンテナとECR

Task 5（ECR リポジトリ作成）の前に理解しておくべき概念。

---

## コンテナとは

アプリケーションとその動作に必要なもの（ランタイム・ライブラリ・設定）を1つのパッケージにまとめた実行単位。ホストOSのカーネルを共有しながら、プロセスを隔離して動かす。

**VMとの違い：**
- VM: OSごと仮想化（数GB・起動に数分）
- コンテナ: OSを共有してプロセスだけ隔離（数MB・起動数秒）

**なぜコンテナを使うか：**
- 「開発環境では動くが本番で動かない」問題を解消（環境を丸ごとパッケージ化）
- スケールアウトが早い（コンテナを複製するだけ）
- 同一ホストで複数のアプリを効率よく動かせる

---

## Dockerfile・イメージ・コンテナの関係

```
Dockerfile（レシピ）
    ↓ docker build
Dockerイメージ（設計図・テンプレート）
    ↓ docker run
コンテナ（実際に動いているプロセス）
```

- **Dockerfile**: イメージの作り方を記述したテキストファイル
- **イメージ**: 不変のスナップショット。1つのイメージから何個でもコンテナを起動できる
- **コンテナ**: イメージを基に起動した実行中プロセス。停止すると中の変更は消える

---

## イメージタグとバージョン管理

イメージには**タグ**を付けてバージョンを管理する。

```
taskflow-backend:latest    ← 最新（可変）
taskflow-backend:v1.2.3    ← バージョン固定（不変にすべき）
taskflow-backend:abc1234   ← gitのcommit hashで管理（CI/CDでよく使う）
```

`latest` タグの問題点：
- 「いつ誰がpushしたlatestか」が曖昧になる
- 「本番のlatestと手元のlatestが違う」というトラブルが起きやすい
- 本番ではgit commitハッシュやセマンティックバージョンで固定するのが安全

---

## ECRとは

AWS Elastic Container Registry。Dockerイメージをプライベートに保管するためのAWSサービス。

**DockerHub vs ECR：**

| 項目 | DockerHub | ECR |
|------|----------|-----|
| デフォルトの公開範囲 | パブリック | プライベート |
| AWSとの認証連携 | 手動設定が必要 | IAMで自動（ECSからのpullが楽） |
| 転送速度（ECSから） | インターネット経由 | 同一リージョン内で高速・無料 |
| 脆弱性スキャン | 有料プランで対応 | 組み込み（Inspector連携） |

ECSでコンテナを動かすならECRを使うのが最もシンプル。

---

## scan_on_push（脆弱性スキャン）

ECRに組み込まれた機能。イメージをpushしたタイミングでOSパッケージやライブラリの既知の脆弱性（CVE）をスキャンする。

学習段階では有効にする習慣をつけておくと良い。本番では定期スキャン（日次）の設定も推奨。スキャン結果はECRコンソールやCloudWatchで確認できる。

---

## image_tag_mutability（タグの上書き禁止）

| 設定 | 意味 |
|------|------|
| `MUTABLE`（デフォルト） | 同じタグで上書き可能 |
| `IMMUTABLE` | 一度pushしたタグは変更不可 |

`MUTABLE`の問題：`v1.0`のタグを上書きされると、どのコンテナが「本当のv1.0」か分からなくなる。本番デプロイの安全性のためIMUTABLEを推奨。ただし開発中は`MUTABLE`の方がlatestタグの更新がしやすい場合もある。

---

## ライフサイクルポリシー

デプロイするたびに新しいイメージが蓄積され、放置するとストレージコストが増える。ライフサイクルポリシーで古いイメージを自動削除する。

よくある設定：
- 最新N件だけ保持（`countType: imageCountMoreThan`）
- N日より古いイメージを削除（`countType: sinceImagePushed`）

10〜30件程度保持しておけば、問題発生時のロールバックに十分対応できる。

---

## ECRへのpushフロー

```bash
# 1. AWS認証トークンを取得してDockerにログイン（12時間有効）
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com

# 2. イメージをビルド
docker build -t taskflow-backend .

# 3. ECRのURIでタグ付け
docker tag taskflow-backend:latest \
  <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow-backend:v1

# 4. push
docker push \
  <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow-backend:v1
```

CI/CDではこの手順をワークフローに組み込んで自動化する（Task 11）。
