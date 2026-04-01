# Task 6: ECS クラスター構築

## このタスクのゴール

TaskFlow のコンテナを動かす **ECS クラスター** を作る。
完成すると、以下が揃う：

- ECS クラスター（Fargate 対応）
- CloudWatch Container Insights の有効化

---

## 背景知識

### ECS とは？

**Elastic Container Service** — AWSのコンテナオーケストレーションサービス。「どのコンテナを、何個、どこで動かすか」を管理する。

> 例え: コンテナが「料理」なら、ECS は「レストランの厨房マネージャー」。注文（リクエスト）に応じて料理人（コンテナ）を増減させる。

### ECS の登場人物

```
クラスター ← 「レストラン全体」
  └── サービス ← 「メニューの1品目」（常に3個用意しておけ、など）
        └── タスク ← 「実際に作られた1皿」（実行中のコンテナ）
              └── タスク定義 ← 「レシピ」（どのイメージ、CPU、メモリ）
```

| 概念 | 役割 |
|------|------|
| クラスター | コンテナ群をまとめる論理的な箱 |
| タスク定義 | コンテナの設計図（イメージ、CPU、メモリ、環境変数） |
| タスク | タスク定義から起動した実行中のコンテナ |
| サービス | タスクの台数を維持・管理する仕組み |

### Fargate とは？

ECS の実行モード。サーバー（EC2）を自分で管理せず、**コンテナだけ** を指定すればAWSがサーバーを自動で用意してくれる。

| 比較 | EC2モード | Fargateモード |
|------|----------|--------------|
| サーバー管理 | 自分で行う | 不要 |
| スケーリング | EC2 + コンテナ両方 | コンテナだけ |
| コスト | 安い（使い切れば） | やや高い |
| 学習コスト | 高い | 低い |

> 初心者には **Fargate** がおすすめ。サーバーの管理を気にせずコンテナに集中できる。

---

## アーキテクチャ上の位置づけ

```
┌── ECS Cluster ──────────────────────────┐
│                                          │
│  [Service: Backend]   [Service: Frontend]│
│    └── Task ×2          └── Task ×2      │
│                                          │
│  実行環境: Fargate                        │
└──────────────────────────────────────────┘
```

**Task 6 ではクラスター（箱）だけ作る。** 中身のサービス・タスクは Task 8 で作成する。

---

## ハンズオン手順

### Step 1: ECS クラスター作成

```hcl
resource "aws_ecs_cluster" "main" {
  name = "taskflow-cluster"

  # Container Insights を有効化（メトリクス・ログの可視化）
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "taskflow-cluster" }
}
```

**パラメータ解説:**
- `containerInsights`: CPU使用率・メモリ使用率・ネットワークなどをCloudWatchで可視化できる。デバッグ・監視に便利。

### Step 2: クラスターのキャパシティプロバイダー

```hcl
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1       # 通常はFARGATEを使用
    base              = 1       # 最低1タスクはFARGATEで起動
  }
}
```

**Fargate Spot とは？**
AWSの余剰リソースを使う安価（最大70%オフ）なオプション。ただし突然中断される可能性がある。dev環境のコスト削減に使える。

### Step 3: 実行

```bash
terraform plan
terraform apply
```

---

## 確認ポイント

1. **AWSコンソール → ECS** で `taskflow-cluster` が表示されるか
2. キャパシティプロバイダーに `FARGATE` が設定されているか
3. Container Insights が有効か

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `ClusterAlreadyExists` | 同名クラスターが既存 | 名前を変えるか既存を削除 |
| Container Insights のメトリクスが出ない | タスクがまだない | Task 8 でサービスを作った後に確認 |

---

## 理解度チェック

**Q1.** ECS の「クラスター」「サービス」「タスク」「タスク定義」の関係を説明せよ。

<details>
<summary>A1</summary>
タスク定義（レシピ）を基にタスク（コンテナ実体）が起動する。サービスはタスクの台数を監視・維持する管理者。クラスターはこれら全てを束ねる論理的なグループ。
</details>

**Q2.** Fargate を選ぶメリットは何か？EC2モードとの最大の違いは？

<details>
<summary>A2</summary>
EC2インスタンス（サーバー）の管理が不要になる。OS のパッチ適用、キャパシティプランニング、スケーリング設定などを気にせず、コンテナの設定だけに集中できる。最大の違いは「サーバーの存在を意識するかしないか」。
</details>

---

**前のタスク:** [Task 5: ECR構築](05_ecr.md)
**次のタスク:** [Task 7: ALB構築](07_alb.md) → コンテナにリクエストを振り分けるロードバランサーを作る
