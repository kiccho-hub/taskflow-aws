# TaskFlow 学習進捗

> 更新方法：infra-senseiエージェントに「完了しました」と報告すると自動更新されます。
> 手動更新も可。凡例：⬜ 未着手 / 📖 読了 / ★～★★★★★（1〜5）= コンソール/IaC成績

| # | タスク | Knowledge | Console | IaC |
|---|--------|:---------:|:-------:|:---:|
| 1 | VPC・サブネット・ゲートウェイ | 📖 | ★★★★★ | ★★★★★ |
| 2 | セキュリティグループ | ⬜ | ★★★☆☆ | ★★★★☆ |
| 3 | RDS PostgreSQL | ⬜ | ★★★★☆ | ★★★★☆ |
| 4 | ElastiCache Redis | ⬜ | ★★★★☆ | ★★★★★ |
| 5 | ECR コンテナレジストリ | ⬜ | ★★★★☆ | ★★★★☆ |
| 6 | ECS クラスター + Fargate | ⬜ | ★★★★☆ | ★★★☆☆ |
| 7 | ALB パスベースルーティング | ⬜ | ★★★★☆ | ★★★★★ |
| 8 | ECS サービス + タスク定義 | ⬜ | ★★★★☆ | ★★★★☆ |
| 9 | Cognito 認証 | ⬜ | ★★★★☆ | ★★★★☆ |
| 10 | S3 + CloudFront | ⬜ | ★★★★☆ | ★★★★☆ |
| 11 | CI/CD パイプライン | ⬜ | ★★★★☆ | ★★★★☆ |
| 12 | CloudWatch 監視 | ⬜ | ★★★★☆ | ⬜ |

## 凡例

| 記号 | 意味 |
|------|------|
| ⬜ | 未着手 |
| 📖 | 読了（Knowledgeのみ） |
| ★☆☆☆☆ | 1/5 — 再学習が必要 |
| ★★☆☆☆ | 2/5 — 基礎はできているが見直しが必要 |
| ★★★☆☆ | 3/5 — 概ね正しい |
| ★★★★☆ | 4/5 — よくできている |
| ★★★★★ | 5/5 — 完璧 |

## 履歴

<!-- infra-senseiが成績を記録するエリア。自動追記されます。 -->

### 2026-04-14

- **Task 1 IaC** ★★★★★（100点）：VPC・サブネット・ゲートウェイをTerraformで完全に再現。コード品質：terraform fmt対応・タグのベストプラクティス（localsで共通化）・リソース依存関係を正確に表現（depends_on適切・参照参照で自動依存）。セキュリティ：DNS有効化・パブリック/プライベート分離が正確。ベストプラクティス：出力値を整理（VPC ID・サブネットID一覧）。コンソール版の設計を完全に理解した上で、Terraformの宣言的表現に適切に翻訳・実装。小さなタイプミス（ManagedBy: "terrafrom" → "terraform"）も修正。全リソース14個が正確に定義・依存関係が完全。

### 2026-04-04

- **Task 8 Console** ★★★★☆（80点）：ECSタスク定義・サービスの作成を完了。ECRへのイメージ未プッシュに直面し原因を理解、desired countを0に設定して再起動ループを適切に対処。Task 11完了後にRUNNING確認が必要。
- **Task 9 Console** ★★★★☆（85点）：Cognito新UI（2024年11月以降）でユーザープール作成を完了。「アプリケーションを定義」ステップの追加・Hosted UI廃止などのUI変更を自力で発見・対応。SPAクライアントタイプの選択理由（クライアントシークレット不要）を本質的に理解した。

### 2026-04-05

- **Task 10 Console** ★★★★☆（85点）：S3+CloudFrontの構築を完了。フロントエンドをECSではなくS3+CloudFrontで配信する設計理由を本質から理解。Task 11のデバッグ中にバケット名の不一致（末尾 `-an`）を自力発見。
- **Task 11 Console** ★★★★☆（88点）：GitHub Actions + AWS OIDCによるCI/CDパイプラインを構築。3つのエラー（AssumeRoleWithWebIdentity / ServiceNotFoundException / NoSuchBucket）を自力でデバッグして完全解決。OIDCの仕組み（短命トークン・アクセスキー不要）を本質から理解した。

### 2026-04-07

- **Task 7 Console** ★★★★☆（85点）：ALBとCloudFront統合によるパスベースルーティングを実装。4つの本番エラー（NAT Gateway欠落 / イメージタグ不一致 / API HTML返却 / フロントエンド表示不具合）を体系的にデバッグし解決。CloudFrontのビヘイビア優先度・デフォルトルートオブジェクト・キャッシュポリシーを本質から理解。デバッグ方法論を`debug/deployment_debugging_log.md`に記録。
- **Task 12 Console** ★★★★☆（85点）：CloudWatchダッシュボード・アラーム作成を完了。メトリクスデータ不足状態の理由を理解。ウィジェットタイプ（Line chart / Number / Stacked area）の選択基準を習得。SNS統合によるAlert配信を実装。全12タスクのコンソール段階完了。

### 2026-04-14

- **Task 2 IaC** ★★★★☆（85点）：セキュリティグループの Terraform 実装を完了。Frontend / Backend / RDS / ElastiCache の4つの SG を分離設計し、通信パターン（FE→ALB→Backend→RDS）を正確に表現。`source_security_group_id`での SG 間参照・タグの共通化・Task 1 からの継続的な品質向上を実現。検証チェックリストの強化と Egress ルールの細粒度設計が改善ポイント。
- **Task 3 IaC** ★★★★☆（88点）：RDS PostgreSQL の Terraform 実装を完了。DBサブネットグループ・パラメータグループ・RDS インスタンスの3点セットを完全に実装。`publicly_accessible = false`・SG 参照・パスワード変数化（`sensitive = true`）・バックアップ設定が正確。コメントが非常に丁寧で学習姿勢が優秀。改善点：`.tfvars` のパスワード管理意識・`storage_encrypted` の追加検討。
- **Task 4 IaC** ★★★★★（98点）：ElastiCache Valkey 8.x の Terraform 実装を完了。`engine = "valkey"` の正確性・`auth_token` の sensitive 変数化・at-rest / in-transit 暗号化の多層化・Task 2 のセキュリティグループとの正確な連携・`locals.common_tags` の継続的活用。出力値（エンドポイント・ポート・クラスター ID）は Task 8 ECS 統合を見据えた設計。軽微改善：Valkey 採用理由のコード内コメント明示・本番環境での自動フェイルオーバー考慮。
- **Task 5 IaC** ★★★★☆（88点）：ECR リポジトリの Terraform 実装を完了。`aws_ecr_repository` (backend・frontend) と `aws_ecr_lifecycle_policy` の4リソースを正確に定義。`locals` で `ecr_lifecycle_policy` を共通化した DRY 設計が秀逸。`IMMUTABLE + scan_on_push` でセキュリティベストプラクティスを完全に押さえ、`outputs.tf` に ECR URL も追加。改善点：ecr.tf へのコメント追加・`encryption_configuration` の明示。
- **Task 6 IaC** ★★★☆☆（78点）：ECSクラスター + キャパシティプロバイダーのTerraform実装。Container Insights有効化・FARGATE_SPOT先読み登録・クラスター参照が正確。要修正：`name` タグが小文字（Name が正）・`base = 0` は `base = 1` が正しい・IAMロール未実装（Task 8 前に追加要）。繰り返しミス：`Name` タグ大文字確認チェックリストの習慣化が必要。
- **Task 7 IaC** ★★★★★（97点）：ALB・パスベースルーティングの Terraform 実装を完了。`aws_lb_listener`（ポート・デフォルトアクション）と `aws_lb_listener_rule`（パス条件・Priority）の概念を完全に理解し、正確に実装。Priority 値（100 < 65535）の大小関係を完璧に押さえ、Frontend デフォルト・/api/* → Backend の設計が秀逸。ターゲットグループは target_type = "ip"・health_check 設定が充実。出力値（ALB DNS・TG ARN）も Task 8連携を見据えて適切。改善点：alb.tf へのコメント追加・ヘルスチェック matcher の判断ロジック明示。

### 2026-04-17

- **Task 11 IaC** ★★★★☆（88点）：GitHub Actions + AWS OIDC による CI/CD パイプラインを Terraform で実装完了。`data "tls_certificate"` による thumbprint 動的取得・StringLike で main ブランチ限定 Trust Policy・ECR Resource を特定 ARN に絞った最小権限設計・`iam:PassedToService` 条件付き PassRole を全て正確に実装。10個のエラー（OIDC重複・型エラー・PassRole・S3名前ズレ・ECR 403×2・ARM64・ECS名前ズレ・ログ未コミット・STS）を全て自力でデバッグ突破。改善点：`task-definition.json` 修正後のコミット忘れ（ローカル編集≠push済みの意識）・複数サービスまたぐ設定値の名前統一チェックリスト活用。
