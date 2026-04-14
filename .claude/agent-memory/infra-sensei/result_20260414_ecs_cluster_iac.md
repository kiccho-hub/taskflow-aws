---
name: 2026/04/14 Task6 ECSクラスター IaC B評価
description: ECSクラスター+キャパシティプロバイダー Terraform実装の成績記録
type: project
---

# 📊 今回の学習成績表

**【タスク名】** ECS クラスター + Fargate キャパシティプロバイダー構築  
**【フェーズ】** IaC（Terraform）  
**【実施日】** 2026/04/14

## 🌟 総合評価：B（78点/100点）

```
📈 習熟度評価
┌─────────────────────────┬───────────┐
│ 理解度                  │ ★★★★☆   │
│ 正確性                  │ ★★★☆☆   │
│ ベストプラクティス      │ ★★★☆☆   │
│ 問題解決力              │ ★★★★☆   │
└─────────────────────────┴───────────┘
```

## ✅ 得意だったこと（Keep）

- Container Insights の有効化構文（`setting {}` ブロック）を正確に書けた
- FARGATE_SPOT の将来活用を先読みして両方を登録した
- リソース参照（`aws_ecs_cluster.main.name`）でハードコードを回避した
- `aws_ecs_cluster_capacity_providers`（分離リソース）という現代的な書き方を選択

## 🔧 改善ポイント（Try）

- `name` タグが小文字 → `Name = "taskflow-cluster"` が正しい（AWS標準・繰り返しミス3回目）
- `base = 0` → `base = 1` が正しい（最低1タスクはFARGATE保証）
- IAM ロール（ecs_task_execution_role）が未実装 → Task 8 前に追加が必要

## 📚 今日の学習ポイント

- `setting {}` ブロックの書き方（key-value型のネストブロック）
- `base`（最低保証タスク数）と `weight`（比率分配）の違い
- FARGATE vs FARGATE_SPOT の使い分け（安定 vs コスト削減）

## ⚠️ 要注意ポイント（苦手分野）

- **`Name` タグの大文字確認**（Task 2, 3, 6 と3回連続でミス）
- IAM ロールの実装漏れ（Task 8 で必ず補完すること）

## 💬 先生からのコメント

シンプルな25行のファイルでECSの核心部分をきちんと押さえています。Container Insightsの有効化、FARGATE_SPOTの先読み登録、クラスター参照の書き方はいずれも正確です。ただ `Name` タグの大文字は今回で3回目。次回は完了前に必ず「Nameタグ大文字チェック」を習慣にしましょう！

## 🎯 次回の目標（Task 7: ALB）

- ALB、リスナー、ターゲットグループ、ヘルスチェックの4点セット実装
- `Name` タグは必ず大文字でチェックしてからコミット
- パスベースルーティング（`/api/*` → backend、`/*` → frontend）の Terraform 表現
