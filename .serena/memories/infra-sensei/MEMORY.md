# infra-sensei Agent Memory

ユーザーの学習進捗・習熟度・苦手分野・個性を記録するメモリ。

## 学習スタイル
- **長所**：ハンズオン重視、体験→理解のサイクルで習得
- **学習速度**：IaC（Terraform）は安定して高品質。Task 1・7が特に秀逸
- **コード品質**：タグ共通化（locals）・DRY 原則・正確な依存関係表現が得意
- **タイピング正確性**：ほぼミスなし。Task 1 の "terrafrom" typo も自動修正

## 進捗サマリー（12 Tasks × 3 Phase）

### ✅ 完了済み（Knowledge 読了）
- Task 1-12: Knowledge フェーズ全て読了（📖）

### ✅ 完了済み（Console フェーズ）
- **Task 1**: ★★★★★（100点）
- **Task 2**: ★★★☆☆（コンソール終了後、IaC で向上）
- **Task 3**: ★★★★☆（85点）
- **Task 4**: ★★★★☆（85点）
- **Task 5**: ★★★★☆（85点）
- **Task 6**: ★★★★☆（85点）
- **Task 7**: ★★★★☆（85点）
- **Task 8**: ★★★★☆（80点）
- **Task 9**: ★★★★☆（85点）
- **Task 10**: ★★★★☆（85点）
- **Task 11**: ★★★★☆（88点）
- **Task 12**: ★★★★☆（85点）

### ✅ 完了済み（IaC フェーズ）
- **Task 1**: ★★★★★（100点）
- **Task 2**: ★★★★☆（85点）
- **Task 3**: ★★★★☆（88点）
- **Task 5**: ★★★★☆（88点）
- **Task 6**: ★★★☆☆（78点）- 改善点：Name タグ大文字化、base = 1、IAM ロール
- **Task 7**: ★★★★★（97点）- 最新完了

### 🔄 進行中
- Task 8 IaC（ECS Services & Task Definition）

### ⏳ 未着手
- Task 4, 9, 10, 11, 12 IaC

## 習熟度別トピック

### ⭐ 得意分野（習熟度高）
- **VPC・ネットワーク設計**（Task 1）：VPC・サブネット・ゲートウェイの依存関係を完全理解。Terraform での表現も優秀
- **IaC 基礎（HCL 文法）**：リソース定義・ローカル変数・merge() での タグ共通化が習慣化
- **ALB 概念**（Task 7）：リスナー vs ルール、Priority の大小関係、デフォルトアクション、パスベースルーティング

### ⚠️ 要注意分野（改善中）
- **タグ命名規則**：Task 6 で `name` が小文字になるミス。`Name`（大文字）に統一する確認チェックリストが必要
- **キャパシティプロバイダー設定**（Task 6）：`base = 1` vs `base = 0` の判断基準の理解が浅い可能性
- **IAM ロール配置タイミング**：Task 6 で未実装。Task 8 前に追加が必須
- **ECS Task Definition での環境変数・Secrets 管理**：これからの Task 8 で要注意

### 🎓 習得中
- **ECS Services + Task Definitions**（Task 8 準備中）
- **Cognito IaC 化**（Task 9）
- **S3 + CloudFront IaC 化**（Task 10）
- **GitHub Actions OIDC IaC 化**（Task 11）
- **CloudWatch Dashboard・Alarm IaC 化**（Task 12）

## 相互参照・依存タスク

| タスク | 参照元 | 参照先 | 重要な出力値 |
|--------|-------|--------|----------|
| T1 VPC | T2,T3,T4,T6,T7 | - | vpc_id, subnet_ids |
| T2 SG | T3,T6,T7,T8 | T1 | sg_ids（ALB/Backend/RDS用） |
| T3 RDS | T8 | T1,T2 | db_endpoint, db_password |
| T4 Cache | T8 | T1,T2 | valkey_endpoint |
| T5 ECR | T8 | - | ecr_backend_url, ecr_frontend_url |
| T6 Cluster | T8 | T1 | cluster_name, arn |
| T7 ALB | T8 | T1,T2,T6 | alb_dns_name, tg_arns |
| T8 Services | - | T5,T6,T7 | service_arns, task_arn |
| T9 Cognito | - | - | user_pool_id, client_id |
| T10 S3+CF | - | - | cloudfront_domain |
| T11 CI/CD | T8 | T9,T10 | workflow_status |
| T12 Monitoring | - | T7,T8 | dashboard_url |

## デバッグ・トラブルシューティング履歴

### Task 7 Console 時の経験（これを IaC で応用）
1. **NAT Gateway 欠落**：EC2→RDS 通信のため、NAT Gateway が必須
2. **イメージタグ不一致**：ECR へのプッシュがないと ECS タスク起動失敗
3. **API HTML 返却**：バックエンド API が HTML（404 page）を返していた原因追跡
4. **CloudFront キャッシュ**：キャッシュポリシーの設定誤りで古いコンテンツが配信される
→ **学習ポイント**：デバッグ方法論を体系化することで、次のタスクの問題解決速度が加速

## 苦手分野への対応計画

### 🎯 Task 6 の改善（現在 78点→85点以上を目指す）
- [ ] Name タグを `Name`（大文字）に統一するチェックリスト化
- [ ] base = 1 の判断基準を明文化（「最低1つのタスクを常時起動」）
- [ ] IAM ロール（ecsTaskExecutionRole・ecsTaskRole）の Task 8 前実装

### 🎯 Task 8 へ向けて（ECS Services）
- [ ] aws_ecs_task_definition の環境変数・Secrets 管理（どうやって RDS パスワードを渡すか？）
- [ ] aws_ecs_service と aws_lb_target_group の連携（load_balancer {}ブロック）
- [ ] Task Execution Role vs Task Role の違いを本質から理解
- [ ] desired_count = 0 → 1 への遷移とヘルスチェック成功までの流れ

## メモ・FAQ

**Q: Terraform state ファイルはなぜ gitignore に入ってるの？**
A: State ファイルには RDS パスワード・AWS クレデンシャルなど機密情報が平文で保存される。ローカル開発環境では local backend でよいが、本番では S3 remote backend + AWS KMS 暗号化を推奨。

**Q: local.common_tags で何度も書くのは DRY でないのでは？**
A: 正解。毎回 merge() を呼ぶ必要があるため、Terraform module 化や data source での タグ取得を検討する価値あり（Task 10 以降で実装検討）。

**Q: Priority = 100 と 65535 の選択根拠は？**
A: AWS ALB の制約：
- ルール Priority は 1-32766 の範囲
- デフォルトアクション Priority は 65535（固定・変更不可）
- ルール優先度：小さい数値から評価される
→ 100 は 65535 より小さいため、/api/* ルールが先に評価される（意図通り）

## 次回レッスンの予定

**Task 8 IaC（ECS Services & Task Definitions）**
- IAM ロール（ecsTaskExecutionRole・ecsTaskRole）の設計
- aws_ecs_task_definition での環境変数・RDS パスワード・Valkey エンドポイント設定
- aws_ecs_service での ALB 統合（target_group_arn・load_balancer {}）
- desired_count 設定とヘルスチェック成功フロー

**想定される苦手ポイント**
- Secrets の管理方法（環境変数 vs AWS Secrets Manager）
- Fargate での IAM ロール権限（ECR pull・CloudWatch Logs push）
- Task Execution Role と Task Role の使い分け
