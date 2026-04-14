# =============================================================================
# Task 4: ElastiCache (Valkey) - キャッシュ・セッション管理
# =============================================================================
#
# 【Task 3 (RDS) との共通点】
#   - サブネットグループ：Task 1 のプライベートサブネットを使用（構成が同じ）
#   - パラメータグループ：エンジン設定を外部化する仕組み（構成が同じ）
#   - セキュリティグループ参照：Task 2 で作成した SG を vpc_security_group_ids に指定
#   - タグ：local.common_tags + merge() パターンが同じ
#   - dev 環境最適化：マルチ AZ / フェイルオーバー無効でコスト削減
#
# 【Task 3 (RDS) との相違点】
#   - リソースの種類：RDS は永続的なディスク DB、Valkey はインメモリ DB
#     → データの永続性が異なる（再起動でデータ消える）
#   - バックアップ：RDS は backup_retention_period = 7 だが、
#     Valkey のキャッシュはセッション・キャッシュなので snapshot_retention_limit = 0
#   - リソース型：aws_db_instance → aws_elasticache_replication_group
#     ※ aws_elasticache_cluster ではなく replication_group を使用する理由：
#       ・Valkey 8.x / Redis 7.x 以降は replication_group が推奨
#       ・将来的なレプリカ追加が容易
#       ・encryption_at_rest / in_transit を replication_group で一元管理できる
#   - ポート番号：RDS は 5432 (PostgreSQL)、Valkey は 6379 (Redis互換)
#   - エンジン名：engine = "valkey"（Redis OSS ではなく Valkey を明示）
#
# 【Valkey とは？】
#   Redis の OSS フォーク。AWS が 2024 年に採用したオープンソース実装。
#   Redis OSS と API 互換があり、既存コードの変更なしで利用可能。
#   Redis OSS より約 20% 安価（dev 環境では誤差だが、prod では効いてくる）。
#
# =============================================================================

# -----------------------------------------------------------------------------
# サブネットグループ
# -----------------------------------------------------------------------------
# 【役割】
#   Valkey クラスターをどのサブネットに配置するかを定義するグループ。
#   複数の AZ のサブネットを登録しておくと、将来的なマルチ AZ 配置に備えられる。
#
# 【Task 3 (RDS) との共通点】
#   aws_db_subnet_group と全く同じ構成パターン。
#   どちらも「プライベートサブネットに DB 系リソースを閉じ込める」設計。
#
# 【なぜプライベートサブネット？】
#   Valkey はセッション情報やキャッシュを保持する。
#   インターネットから直接アクセスできないよう、必ずプライベートに配置する。
#   （鍵のかかった金庫室に大切なデータを保管するイメージ）
#
resource "aws_elasticache_subnet_group" "main" {
  name        = var.elasticache_subnet_group_name
  description = "Subnet group for TaskFlow Valkey cluster"

  # Task 1 で作成したプライベートサブネットを両 AZ 分登録
  subnet_ids = [
    aws_subnet.private_a.id, # ap-northeast-1a
    aws_subnet.private_c.id, # ap-northeast-1c
  ]

  tags = merge(local.common_tags, {
    Name = var.elasticache_subnet_group_name
  })
}

# -----------------------------------------------------------------------------
# パラメータグループ
# -----------------------------------------------------------------------------
# 【役割】
#   Valkey の動作設定を管理する「設定テンプレート」。
#   AWS マネージドサービスでは設定ファイルを直接編集できないため、
#   パラメータグループ経由で設定値を注入する。
#
# 【Task 3 との比較】
#   RDS:    family = "postgres16"  → PostgreSQL 16.x
#   Valkey: family = "valkey8"     → Valkey 8.x
#   どちらも「family = エンジン名 + メジャーバージョン」という命名規則。
#
# 【maxmemory-policy = allkeys-lru とは？】
#   Valkey のメモリが満杯になったとき、どのキーを削除するかのルール。
#   allkeys-lru = 「全キーの中から、最も長く使われていないものを削除」
#
#   【料理の例え】
#   冷蔵庫（メモリ）が満杯になったとき、
#   一番古い（最近使っていない）食材（キャッシュデータ）を先に捨てる戦略。
#   いつも使う食材は残し、使わなかったものを処分するので合理的。
#
resource "aws_elasticache_parameter_group" "main" {
  name        = var.elasticache_parameter_group_name
  description = "Parameter group for TaskFlow Valkey 8.x"

  # Valkey 8.x 対応のファミリー名
  # ※ engine_version と必ず合わせること（不一致でエラーになる）
  family = "valkey8"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = merge(local.common_tags, {
    Name = var.elasticache_parameter_group_name
  })
}

# -----------------------------------------------------------------------------
# レプリケーショングループ（Valkey クラスター本体）
# -----------------------------------------------------------------------------
# 【なぜ aws_elasticache_cluster ではなく aws_elasticache_replication_group？】
#   Valkey 8.x および Redis 7.x 以降は replication_group が推奨リソース。
#   理由：
#     1. 暗号化設定（at_rest / transit）を replication_group で一元管理できる
#     2. フェイルオーバー・レプリカ設定が可能（prod 環境への拡張が容易）
#     3. Valkey エンジンの正式サポートが replication_group に付いている
#
# 【dev 環境の設計方針】
#   - num_cache_clusters = 1：プライマリのみ、レプリカなし（コスト削減）
#   - automatic_failover_enabled = false：レプリカがないため不要
#   ↑ prod では num_cache_clusters = 2 以上にして failover を有効化する
#
# 【Task 3 (RDS) との比較】
#   RDS:    multi_az = false, backup_retention_period = 7
#   Valkey: automatic_failover_enabled = false, snapshot_retention_limit = 0
#   どちらも「dev はシングル構成でコスト最適化」という設計思想は同じ。
#   ただし Valkey はキャッシュ特性上、スナップショット不要（0 = 無効化）。
#
resource "aws_elasticache_replication_group" "main" {
  # レプリケーショングループの識別子（AWS コンソールに表示される名前）
  replication_group_id = var.elasticache_cluster_id

  # コンソール上での説明文
  description = "TaskFlow Valkey cache cluster for dev environment"

  # エンジン設定
  # ※ "valkey" を明示することで Redis OSS との混在を防ぐ
  engine         = "valkey"
  engine_version = var.elasticache_engine_version # "8.0"

  # ノードタイプ
  # cache.t4g.micro = ARM ベースの Graviton2 採用。dev 環境で最もコストが低い。
  # 【Task 3 との共通点】db.t4g.micro と同じ Graviton2 系で統一
  node_type = var.elasticache_node_type # "cache.t4g.micro"

  # ノード数（プライマリ + レプリカの合計）
  # 1 = プライマリのみ（dev 環境）
  # prod では 2 以上にして可用性を高める
  num_cache_clusters = var.elasticache_num_cache_clusters # 1

  # ネットワーク設定
  # Task 1 で作成したサブネットグループを使用（どの VPC・サブネットに配置するか）
  subnet_group_name = aws_elasticache_subnet_group.main.name

  # Task 2 で作成した redis セキュリティグループを適用
  # ポート 6379 を Backend ECS からのみ許可する SG
  security_group_ids = [aws_security_group.redis.id]

  # パラメータグループ（上で定義した maxmemory-policy 等の設定を適用）
  parameter_group_name = aws_elasticache_parameter_group.main.name

  # Valkey/Redis 互換ポート
  port = 6379

  # フェイルオーバー設定
  # dev では num_cache_clusters = 1 のため必ず false にする
  # ※ true にするには num_cache_clusters >= 2 が必要（変更するとエラー）
  automatic_failover_enabled = false

  # 暗号化設定
  # 【Task 3 との共通点】RDS も storage_encrypted = true（デフォルト）で暗号化
  #
  # at_rest_encryption_enabled: ディスクに書き込まれるデータを暗号化
  # transit_encryption_enabled: クライアント ↔ Valkey 間の通信を TLS で暗号化
  #   ※ transit 有効時は接続先のポートが TLS 対応している必要がある
  #   ※ アプリ側も TLS 接続設定が必要（Node.js の ioredis など）
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # スナップショット設定
  # 0 = スナップショット無効（バックアップなし）
  #
  # 【なぜ RDS と異なるか？】
  # RDS: backup_retention_period = 7（7 日分バックアップ）
  #      → タスクデータは失うと困るため、バックアップ必須
  # Valkey: snapshot_retention_limit = 0（バックアップ不要）
  #      → セッション・キャッシュは再生成可能なデータなので、バックアップ不要
  #         （失ってもユーザーが再ログイン・再リクエストすれば復元できる）
  #         スナップショットを有効にすると追加コストが発生するため 0 が推奨
  snapshot_retention_limit = 0

  tags = merge(local.common_tags, {
    Name = var.elasticache_cluster_id
  })
}
