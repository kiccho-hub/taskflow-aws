# Task 4: ElastiCache Redis 構築

## このタスクのゴール

TaskFlow のセッション管理・キャッシュ用の **Redis** を構築する。
完成すると、以下が揃う：

- ElastiCache Redis クラスター（プライベートサブネットに配置）
- サブネットグループ
- パラメータグループ

---

## 背景知識

### Redis とは？

**インメモリデータストア** — データをメモリ（RAM）に保存する超高速なデータベース。

> 例え: RDS が「本棚」なら Redis は「デスクの上」。よく使うものを手元に置いておくことで、毎回本棚まで取りに行かなくて済む。

### TaskFlow での使い道

| 用途 | 説明 |
|------|------|
| セッション管理 | ログイン状態の保持 |
| APIキャッシュ | 頻繁にアクセスされるデータの高速化 |

### ElastiCache とは？

AWSが管理してくれるRedis（またはMemcached）サービス。自分でRedisサーバーを立てる必要がない。

### RDS との違い

| 項目 | RDS (PostgreSQL) | ElastiCache (Redis) |
|------|------------------|---------------------|
| データの永続性 | ディスクに保存（永続的） | メモリに保存（揮発性） |
| 速度 | ミリ秒〜 | マイクロ秒〜 |
| 用途 | メインデータ | キャッシュ・セッション |

---

## アーキテクチャ上の位置づけ

```
[ECS: Backend] ──(:6379)──▶ [ElastiCache Redis]
                              │
                        プライベートサブネット
                        (SG: ECSからのみ許可)
```

---

## ハンズオン手順

### Step 1: サブネットグループ

```hcl
resource "aws_elasticache_subnet_group" "main" {
  name = "taskflow-redis-subnet"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id,
  ]

  tags = { Name = "taskflow-redis-subnet" }
}
```

### Step 2: パラメータグループ

```hcl
resource "aws_elasticache_parameter_group" "main" {
  name   = "taskflow-redis7"
  family = "redis7"

  # メモリ上限に達したときの挙動（LRU: 最も古いキーを削除）
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = { Name = "taskflow-redis7" }
}
```

**解説:** `allkeys-lru` = メモリが満杯になったら、最も長く使われていないキーを自動削除。キャッシュ用途に最適。

### Step 3: Redis クラスター

```hcl
resource "aws_elasticache_cluster" "main" {
  cluster_id = "taskflow-redis"

  engine         = "redis"
  engine_version = "7.1"

  # インスタンスサイズ（dev用は最小）
  node_type       = "cache.t4g.micro"   # 2 vCPU, 0.5GB RAM
  num_cache_nodes = 1                   # dev環境は1ノード

  # ネットワーク
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  parameter_group_name = aws_elasticache_parameter_group.main.name

  # メンテナンス
  maintenance_window = "sun:05:00-sun:06:00"

  # ポート
  port = 6379   # Redis のデフォルトポート

  tags = { Name = "taskflow-redis" }
}
```

### Step 4: 実行

```bash
terraform plan
terraform apply
```

> ElastiCache の作成には **5-10分** かかる。

---

## 確認ポイント

1. **AWSコンソール → ElastiCache** で `taskflow-redis` が `Available` か
2. エンドポイントが表示されているか
3. セキュリティグループが `taskflow-redis-sg` であること

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `InsufficientCacheClusterCapacity` | 指定ノードタイプが利用不可 | 別のノードタイプを試す |
| `SubnetGroupNotFound` | サブネットグループ名が間違い | `name` を確認 |
| 作成が遅い | 正常動作 | 5-10分待つ |

---

## 理解度チェック

**Q1.** Redis をデータベース（RDS）の代わりに使わない理由は？

<details>
<summary>A1</summary>
Redis はメモリにデータを保存するため、サーバーが再起動するとデータが消える（揮発性）。タスクのマスターデータのような永続的に保存すべきデータにはRDS（ディスク保存）を使い、Redis はキャッシュやセッションなど「消えても再生成できるデータ」に使う。
</details>

**Q2.** `maxmemory-policy: allkeys-lru` は何をする設定か？

<details>
<summary>A2</summary>
メモリが上限に達したとき、全キーの中から最も長い間アクセスされていないキー(Least Recently Used)を自動削除して空き領域を確保する。キャッシュ用途では「古いキャッシュを捨てて新しいデータを入れる」のが合理的。
</details>

---

**前のタスク:** [Task 3: RDS構築](03_rds.md)
**次のタスク:** [Task 5: ECR構築](05_ecr.md) → コンテナイメージの保管場所を作る
