---
name: 2026/04/17 Task11 CI/CD IaC A評価
description: GitHub Actions + AWS OIDC CI/CDパイプラインのTerraform実装。10個のデバッグを突破。
type: user
---

## 📊 学習成績表

【タスク名】CI/CD パイプライン（GitHub Actions + AWS OIDC）
【フェーズ】IaC（Terraform）
【実施日】2026/04/17

### 総合評価：A 88点/100点

```
習熟度評価
┌─────────────────────────────────┐
│ 理解度           ：★★★★★    │
│ 正確性           ：★★★★☆    │
│ ベストプラクティス ：★★★★☆    │
│ 問題解決力       ：★★★★★    │
└─────────────────────────────────┘
```

### 得意だったこと（Keep）

- 10段階のデバッグを全て自力突破した問題解決力（OIDC重複・型エラー・PassRole・S3名前ズレ・ECR 403×2・ARM64・ECS名前ズレ・ログ未コミット・STS）
- 概念の本質を自分の言葉で理解し直せた（iam:PassRole・client_id_list・thumbprint_listのスプラット式）
- IaC実装品質が高い：thumbprint動的取得・StringLikeブランチ限定・最小権限ECR・PassedToService条件付き
- コメントが学習の証（`# ★buildxのHEAD確認に必要` 等）
- provenance: false / sbom: false を意味から理解して一時回避策として設定

### 改善ポイント（Try）

- ローカル編集のコミット忘れがデバッグ沼を生んだ（task-definition.json修正→コミット忘れ→古いrevisionで起動）
- 初回デプロイ前チェックリスト（ECSサービス名・ログループ名・ECR名の一致確認）の事前活用
- iam_review.md の置き場所（infra/environments/dev/ に混在→tasks/review/ が適切）

### 今日の学習ポイント

- OIDC 4段階ガード（TLS指紋・JWT署名・aud・sub）の完全理解
- IAM Role vs IAM Policy（着ぐるみ vs 宛名付き権利書）
- iam:PassRole が必要な理由（権限昇格攻撃対策）
- terraform import でコードと state を同期させる手法
- QEMU + Buildx によるクロスアーキテクチャビルドの仕組み
- thumbprint_list スプラット式の型（list of string であってネストしない）
- buildx が push 前に HEAD チェックするため BatchGetImage が必要な理由

### 要注意ポイント（苦手分野）

- 「ローカル編集 = push 済み」の誤った思い込み（git status確認習慣が必要）
- 複数サービスまたぐ設定値の名前統一（ECSサービス名・ログループ名・ECRリポジトリ名）

### 先生からのコメント

10個のエラーを全て乗り越えたことは本当に素晴らしい。iam:PassRoleの概念を「権限昇格攻撃対策」として理解し直したこと、client_id_listが「送り元ではなく宛先」だと気づいたことは、多くの経験者が曖昧なまま使い続けるポイントを正確に理解できている証。デプロイ前の `git status` 確認（5秒）が1時間のデバッグを防ぐ習慣として定着させること。

### 次回の目標

- Task 12（CloudWatch 監視）IaC フェーズへ挑戦
- `git status` 確認をデプロイ前の必須チェックとして習慣化
- `provenance: false` の一時回避を正式対応（ECR 側で Immutable + OCI 互換設定を確認）
