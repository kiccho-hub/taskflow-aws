# TaskFlow デプロイメント デバッグログ

## 概要

2026-04-04 〜 2026-04-07 における CI/CD・ECS デプロイの一連のデバッグプロセスを記録。
4つの主要な問題に直面し、各々を段階的に解決した。

---

## Issue 1: ECR からのイメージプル失敗（リソース初期化エラー）

### 症状
```
ResourceInitializationError: unable to pull secrets or registry auth
The task cannot pull registry auth from Amazon ECR
There is a connection issue between the task and Amazon ECR
operation error ECR: GetAuthorizationToken, exceeded maximum number of attempts
```

### 根本原因
**NAT Gateway が存在しない** → プライベートサブネット内の ECS タスクがインターネットに接続できない

### なぜこれが問題か
- ECS タスク（プライベートサブネット内）は、ECR からコンテナイメージをダウンロードするために **インターネットアクセスが必須**
- インターネットアクセスは NAT Gateway 経由で提供される
- 学習用に PAUSE_AND_RESUME.md に従ってリソース削除したが、再開時に NAT Gateway を再作成しなかった

### 対処方法
1. VPC コンソール → NAT ゲートウェイ → 「NAT ゲートウェイを作成」
2. 設定：
   - 名前：`taskflow-nat`
   - サブネット：`taskflow-public-a`（ap-northeast-1a）
   - 接続タイプ：パブリック
   - Elastic IP：新規割り当て
3. ステータスが「Available」になるまで待つ（1-2分）
4. プライベートルートテーブルを更新：
   - VPC → ルートテーブル → `taskflow-private-rt`
   - ルートを編集：`0.0.0.0/0` → 新しい NAT Gateway ID に変更

### 学習ポイント
- **ネットワークの疎通性は第一に確認すべき** — タスク起動前に通信経路を検証
- NAT Gateway が削除されると、プライベートサブネットは完全にオフラインになる
- 学習用リソース削除時は「何が削除されたか」を記録しておくことが重要

---

## Issue 2: イメージタグの不一致（CannotPullContainerError）

### 症状
```
CannotPullContainerError: pull image manifest has been retried 7 times
failed to resolve ref 840854900854.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/backend:latest
not found
```

### 根本原因
**タグの不一致** — ECS タスク定義では `:latest` を指定しているが、ECR には コミットハッシュタグ（`c6a25e13...`）しか存在しない

### デバッグプロセス
1. ECR リポジトリを確認 → イメージ存在確認、タグを確認
2. GitHub Actions ワークフローログを確認 → docker push は成功していた
3. GitHub Actions が `${{ github.sha }}`（コミットハッシュ）をタグとしていることを発見
4. ECS タスク定義は固定の `:latest` を参照していることを発見
5. **結論**：自動化されていない手作業のズレが原因

### なぜこれが問題か
- 手作業で ECS タスク定義を修正していた（毎回コンソールで `:latest` タグを指定）
- コミットハッシュが変わるたびに、手作業でタスク定義を更新する必要があった（再現不可能）
- CI/CD の自動化が不完全

### 対処方法：Infrastructure as Code（IaC）化

**Step 1：task-definition.json テンプレートを作成**
```
.github/workflows/task-definition.json
```
- `PLACEHOLDER_IMAGE` を使用
- `executionRoleArn` をトップレベルに配置（コンテナ定義ではなく）

**Step 2：GitHub Actions ワークフローを改善**
```yaml
- name: Update ECS task definition with new image
  id: task-def
  uses: aws-actions/amazon-ecs-render-task-definition@v1
  with:
    task-definition: .github/workflows/task-definition.json
    container-name: backend
    image: ${{ secrets.ECR_REGISTRY }}/taskflow/backend:${{ github.sha }}

- name: Deploy to ECS
  uses: aws-actions/amazon-ecs-deploy-task-definition@v1
  with:
    task-definition: ${{ steps.task-def.outputs.task-definition }}
    service: taskflow-backend-service-8zr92cb4
    cluster: taskflow-cluster
    wait-for-service-stability: true
```

### 学習ポイント
- **手作業（マニュアルプロセス）は再現性がない** → 自動化が不可欠
- **タグ戦略が重要** — `latest` は不安定、コミットハッシュが本質的で再現可能
- ECS では task-definition リビジョンが自動的に作成されるため、毎回新しいリビジョンを登録できる
- GitHub Actions の公式アクション（amazon-ecs-render-task-definition、amazon-ecs-deploy-task-definition）は非常に便利

---

## Issue 3: バックエンド API が応答しない（HTML が返される）

### 症状
ブラウザで `https://d38u58isnyyzc2.cloudfront.net/api/tasks` にアクセス
```
APIへの接続に失敗しました: Unexpected token '<', "<!DOCTYPE "... is not valid JSON
```

HTML（React の `index.html`）が返されている

### デバッグプロセス
1. ALB DNS に直接アクセス → JSON が正常に返される（バックエンドは正常）✅
2. CloudFront 経由だと HTML が返される → CloudFront の設定に問題あり
3. CloudFront のビヘイビアを確認 → **`/api/*` パス用のビヘイビアが存在しない**
4. デフォルトビヘイビア（`*` → S3）が `/api/*` リクエストをキャッチしていた

### なぜこれが問題か
CloudFront は複数のオリジン（S3、ALB など）を持つことができるが、**どのパスをどのオリジンに転送するか**を定義するのが「ビヘイビア」

現在の設定：
```
パスパターン: * (デフォルト)
オリジン: S3
```

すべてのリクエストが S3 に行き、S3 は `/api/tasks` という「ファイル」を探して見つけられず、デフォルトの `index.html` を返していた

### 対処方法

**Step 1：CloudFront に ALB オリジンを追加**
```
CloudFront → ディストリビューション → taskflow-cloudfront
  → オリジンタブ → 「オリジンを作成」
```

設定値：
- オリジン名：`taskflow-alb`
- オリジンドメイン：`taskflow-alb-1165620692.ap-northeast-1.elb.amazonaws.com`
- プロトコル：HTTP
- ポート：80

**Step 2：`/api/*` 用のビヘイビアを作成**
```
CloudFront → ビヘイビアタブ → 「ビヘイビアを作成」
```

設定値：
- パスパターン：`/api/*`
- 優先度：`0`（デフォルト（*）より優先）
- オリジン：`taskflow-alb`
- ビューワープロトコルポリシー：HTTPS にリダイレクト
- キャッシュポリシー：`CachingDisabled`（API はキャッシュしない）
- オリジンリクエストポリシー：`AllViewer`（ブラウザリクエスト情報をそのまま転送）

**Step 3：HTTP メソッド許可**
```
許可された HTTP メソッド：GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE
```
（API が POST・DELETE を使用する場合は必須）

### CloudFront ビヘイビアの評価順序
CloudFront は優先度が小さいビヘイビアから順に評価：
```
優先度 0: /api/* → ALB ← この条件に合致したら、ここで転送
優先度 1（デフォルト）: * → S3 ← 合致しなかった場合ここ
```

### 学習ポイント
- **CloudFront は「リバースプロキシ」の役割を果たす** — 複数のオリジンを管理し、パスに応じて転送先を決定
- ビヘイビアの優先度が重要 — デフォルト（`*`）よりも具体的なパターンを優先度を上げて定義
- API とキャッシュは相性が悪い → `CachingDisabled` が正解
- `/api/*` と `/*` の分離は、SPA + API バックエンド構成の基本パターン

---

## Issue 4: フロントエンドが表示されない（背景が黒い）

### 症状
`https://d38u58isnyyzc2.cloudfront.net/` にアクセス → 背景が黒い JSON だけが表示される

正常：React UI + CSS スタイル
実際：JSON データが `<pre>` タグで表示されている

### デバッグプロセス
1. Network タブ確認 → CSS リクエストは成功している（`/assets/...`）
2. Elements タブ確認 → HTML が JSON のみ（スタイル定義なし）
3. ALB に直接アクセス → JSON が返される
4. **CloudFront で `/` にアクセスしても JSON が返される**
5. **原因**：CloudFront が `index.html` ではなく、S3 の何か別のファイル（API レスポンス？）を返している

### なぜこれが問題か
CloudFront の「デフォルトルートオブジェクト」が設定されていなかった

```
GET https://cloudfront.net/
  → CloudFront に「このパスで何を返すか」という指示がない
  → S3 に「/」というパスへのリクエストが転送される
  → S3 は「根ディレクトリ」を返そうとして、何か別のものを返す
```

### なぜ CLI で正常に動いたのか
```bash
curl http://taskflow-alb-xxxxxx.ap-northeast-1.elb.amazonaws.com/api/tasks
# → JSON ✅

curl https://cloudfront.net/
# → JSON ❌（ブラウザでも同じ）
```

CloudFront を経由するとデフォルトルートオブジェクトが必要

### 対処方法

**CloudFront の設定を更新**
```
CloudFront → ディストリビューション → taskflow-cloudfront
  → 一般タブ
  → 「デフォルトルートオブジェクト」フィールドを探す
  → 値：index.html に変更
```

### デプロイ完了を待つ
CloudFront の更新には 1-2 分必要。ステータスが「デプロイ完了」になるまで待機。

### 学習ポイント
- **CloudFront は「Webサーバー」の機能を部分的に提供する** — デフォルトルートオブジェクト設定は必須
- `/` へのリクエストをキャッチするビヘイビアとデフォルトルートオブジェクトは別
  - ビヘイビア：パスに応じたオリジン選択
  - デフォルトルートオブジェクト：ルートパスで返すファイル名
- SPA をホストする場合、この設定忘れは頻出のバグ

---

## デバッグの全体的な流れと学習

### 構造化デバッグの手法

**1. 症状の正確な把握**
- エラーメッセージを完全に読む
- Network タブ・Console タブで実際のリクエスト・レスポンスを確認
- ALB など「1つ前の層」で直接テストして、該当層の問題か判定

**2. 層ごとのテスト**
```
CloudFront → ALB → ECS → ECR
```
各層を個別にテストすることで、問題がどこにあるか特定。

**3. 設定と実装のズレを疑う**
- タグの問題（Issue 2）
- オリジン設定の問題（Issue 3）
- デフォルト設定の問題（Issue 4）

### 今後のデバッグ時チェックリスト

#### ネットワーク層
- [ ] NAT Gateway は存在するか？
- [ ] プライベートルートテーブルは正しく設定されているか？
- [ ] セキュリティグループは通信を許可しているか？

#### コンテナ/イメージ層
- [ ] ECR にイメージは存在するか？
- [ ] タグは正しいか？
- [ ] IAM 権限（ecsTaskExecutionRole）は正しいか？

#### ロードバランサー/ルーティング層
- [ ] ALB のリスナールールは正しいか？
- [ ] ターゲットグループのヘルスチェックは成功しているか？
- [ ] 直接 ALB DNS でテストして動作確認したか？

#### CDN 層（CloudFront）
- [ ] オリジンは正しく登録されているか？
- [ ] ビヘイビアの優先度は正しいか？
- [ ] デフォルトルートオブジェクトが設定されているか？
- [ ] キャッシュポリシーは適切か（API は `CachingDisabled`）？

### 重要な原則
1. **自動化を優先** — 手作業は再現性がない（Issue 2）
2. **具体的にテストする** — 「動かない」ではなく「この層の動作を確認」
3. **公式ドキュメント・公式ツールを使う** — CloudFront の公式アクション、AWS 公式エージェント
4. **ログを読む** — エラーメッセージは情報の宝庫

---

## タイムライン

| 日時 | Issue | 原因特定 | 対処 | 状態 |
|------|-------|--------|------|------|
| 2026-04-07 00:00 | NAT Gateway なし | ネットワーク疎通テスト | 再作成 | 解決 ✅ |
| 2026-04-07 06:00 | イメージ不在 | GitHub Actions ログ確認 | IaC 化（task-definition.json） | 解決 ✅ |
| 2026-04-07 12:00 | API が HTML を返す | CloudFront ビヘイビア確認 | `/api/*` ビヘイビア追加 | 解決 ✅ |
| 2026-04-07 13:30 | フロントエンド表示されない | Elements タブ確認 | デフォルトルートオブジェクト設定 | 解決 ✅ |

---

## 最終結果

✅ CloudFront → ALB（API）→ ECS Backend → ECR（イメージ）の全経路が疎通  
✅ React フロントエンド UI が正常に表示  
✅ API がタスク一覧を正常に返す  
✅ CI/CD パイプラインが自動化されている
