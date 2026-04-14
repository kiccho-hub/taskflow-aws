variable "db_password" {
  type        = string
  description = "Password for the database"
  sensitive   = true
}

# =============================================================================
# ElastiCache (Valkey) 関連変数
# =============================================================================
#
# 【Task 3 (RDS) との設計上の共通点】
#   RDS はパスワードのような機密情報を variable で外出しにする。
#   Valkey は認証トークンが不要な構成（内部 VPC のみアクセス可能なため）なので、
#   機密情報の変数は不要。代わりにリソース名・エンジン設定を変数化する。
#
# 【なぜ変数化するか？】
#   dev / prod で異なる値（ノードタイプやクラスター数）を
#   terraform.tfvars だけ変えることで切り替えられる。
#   コード本体（elasticache.tf）を変更せずに済むため、安全で再利用しやすい。
#
variable "elasticache_cluster_id" {
  type        = string
  description = "ElastiCache レプリケーショングループの識別子（AWS コンソールに表示される名前）"
  default     = "taskflow-valkey"
}

variable "elasticache_node_type" {
  type        = string
  description = "ElastiCache ノードタイプ（dev: cache.t4g.micro / prod: cache.r7g.large など）"
  default     = "cache.t4g.micro"
}

variable "elasticache_engine_version" {
  type        = string
  description = "Valkey エンジンバージョン（family = valkey8 と合わせること）"
  default     = "8.0"
}

variable "elasticache_num_cache_clusters" {
  type        = number
  description = "キャッシュクラスター数（1 = プライマリのみ / 2以上 = レプリカあり）"
  default     = 1
}

variable "elasticache_subnet_group_name" {
  type        = string
  description = "ElastiCache サブネットグループ名"
  default     = "taskflow-valkey-subnet"
}

variable "elasticache_parameter_group_name" {
  type        = string
  description = "ElastiCache パラメータグループ名（ファミリー valkey8 対応）"
  default     = "taskflow-valkey8"
}
