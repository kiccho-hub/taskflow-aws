# TaskFlow — タスク管理アプリケーション 仕様書

**バージョン**: 1.1
**作成日**: 2026-04-01
**作成者**: 田中裕貴

---

## 本ドキュメントの位置づけ

このプロジェクトの主目的は **AWSインフラの実践的な学習** である。
アプリケーションは、AWSリソースを動かすための**最小限の土台**として位置づける。

---

## プロダクト概要

**TaskFlow** - タスクを作成・閲覧・削除できるシンプルなWebアプリ

### 学習対象のAWS要素

| AWS要素 | 対応するアプリ上の動作 |
|---------|----------------------|
| ALBのパスベースルーティング | `/api/*` → Backend、`/*` → Frontend |
| ECS Fargate | コンテナの起動・Auto Scaling |
| VPC・サブネット・SG | サービス間通信の制御 |
| RDS PostgreSQL | タスクのCRUD操作 |
| Amazon Cognito | ログイン・ロール判定 |
| CloudFront + S3 | フロントエンド静的配信 |

### ロール定義

| ロール | 説明 |
|--------|------|
| ゲスト | 未認証。公開タスク閲覧のみ |
| ユーザー | ログイン済み。自分のタスクCRUD |
| アドミン | 全ユーザー・全タスク管理 |

---

## アーキテクチャ概要

```
[ブラウザ] → [Route 53] → [CloudFront] → [S3: 静的ファイル]
                              ↓
                           [ALB]
                    /api/*     /*
                      ↓         ↓
              [ECS: Backend] [ECS: Frontend]
                      ↓
              [RDS PostgreSQL]
              [ElastiCache Redis]
```

---

## 詳細タスクファイル

各ステップの詳細は以下のタスクファイルを参照：

| タスク | ファイル | 概要 |
|--------|----------|------|
| Task 1 | [tasks/01_vpc.md](tasks/01_vpc.md) | VPC・サブネット・ゲートウェイ構築 |
| Task 2 | [tasks/02_security_groups.md](tasks/02_security_groups.md) | セキュリティグループ設定 |
| Task 3 | [tasks/03_rds.md](tasks/03_rds.md) | RDS PostgreSQL構築 |
| Task 4 | [tasks/04_elasticache.md](tasks/04_elasticache.md) | ElastiCache Redis構築 |
| Task 5 | [tasks/05_ecr.md](tasks/05_ecr.md) | ECRリポジトリ作成 |
| Task 6 | [tasks/06_ecs_cluster.md](tasks/06_ecs_cluster.md) | ECSクラスター構築 |
| Task 7 | [tasks/07_alb.md](tasks/07_alb.md) | ALB構築・パスベースルーティング |
| Task 8 | [tasks/08_ecs_services.md](tasks/08_ecs_services.md) | ECSサービス・タスク定義 |
| Task 9 | [tasks/09_cognito.md](tasks/09_cognito.md) | Cognito認証設定 |
| Task 10 | [tasks/10_s3_cloudfront.md](tasks/10_s3_cloudfront.md) | S3 + CloudFront設定 |
| Task 11 | [tasks/11_cicd.md](tasks/11_cicd.md) | GitHub Actions CI/CD |
| Task 12 | [tasks/12_monitoring.md](tasks/12_monitoring.md) | CloudWatch監視設定 |

---

## 環境構成

| 環境 | 用途 | 主な違い |
|------|------|----------|
| dev | 開発・動作確認 | 最小リソース、CloudFrontなし |
| prod | 本番 | Multi-AZ、Auto Scaling有効 |

---

## 技術スタック

| カテゴリ | 技術 |
|----------|------|
| フロントエンド | React SPA |
| バックエンド | Node.js (Express) |
| データベース | PostgreSQL 16 |
| キャッシュ | Redis 7.x |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

*詳細は各タスクファイルを参照*
