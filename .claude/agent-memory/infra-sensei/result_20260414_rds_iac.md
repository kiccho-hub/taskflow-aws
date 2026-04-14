---
name: 2026/04/14 Task3 RDS IaC 成績記録
description: Task 3 RDS PostgreSQL Terraform実装の成績表（A評価 88点）
type: project
---

## 学習成績表

**タスク名**：RDS PostgreSQL の Terraform 実装
**フェーズ**：IaC
**実施日**：2026/04/14

**総合評価：A 88点/100点**

### 習熟度評価

| 項目 | 評価 |
|------|------|
| 理解度 | ★★★★☆ |
| 正確性 | ★★★★★ |
| ベストプラクティス | ★★★★☆ |
| 問題解決力 | ★★★★☆ |

### 得意だったこと（Keep）

- DB サブネットグループ・パラメータグループ・RDS インスタンスの3点セットを完全に実装
- セキュリティ設定（`publicly_accessible = false`、SG 参照、パスワード変数化）が全部正確
- パラメータグループのコメントが非常に丁寧（client_encoding = UTF8 の理由・影響まで記述）
- バックアップ・メンテナンスウィンドウの重複なし設定
- `sensitive = true` で変数保護パターンを正しく適用

### 改善ポイント（Try）

- `terraform.tfvars` のパスワードが平文（学習環境では許容範囲だが、.gitignore 確認が必要）
- `skip_final_snapshot = true` などのコメントをさらに意識する
- `storage_encrypted = true` を本番想定で追加しておくと尚良し

### 今日の学習ポイント

- RDS の3リソース構成（サブネットグループ・パラメータグループ・インスタンス）を完全習得
- `sensitive = true` による変数保護パターンを習得
- ストレージ自動拡張（`max_allocated_storage`）の設計意図を理解

### 要注意ポイント（苦手分野）

- `.tfvars` ファイルの取り扱い（本番では secrets manager 等を使う）
- デフォルト値を意識した追加設定（`storage_encrypted` など）

### 先生からのコメント

Task 1（VPC）・Task 2（SG）からの学習の積み重ねが、このコードにしっかり表れています！特に「パラメータグループを定義するだけでなく、RDS インスタンスで明示的に参照する必要がある」ことをコメントで解説している点が印象的でした。次の Task 4（ElastiCache Valkey）も同じような3点セット構成で書けるはずです。自信を持って進みましょう！

### 次回の目標

- Task 4（ElastiCache Valkey 8.x）の IaC 実装
- `storage_encrypted` などのセキュリティ設定を意識的に確認する習慣をつける
