output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id,
  ]
}

output "private_subnet_ids" {
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id,
  ]
}

output "db_endpoint" {
  value = aws_db_instance.main.endpoint
  sensitive = false
}

# ElastiCache (Valkey) のプライマリエンドポイント
#
# 【Task 3 との違い】
#   RDS:    aws_db_instance.main.endpoint（ホスト:ポートの形式）
#   Valkey: aws_elasticache_replication_group.main.primary_endpoint_address
#           ※ replication_group では primary_endpoint_address 属性を使う
#              （aws_elasticache_cluster の cache_nodes[0].address とは異なる点に注意）
#
output "valkey_primary_endpoint" {
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  description = "Valkey クラスターのプライマリエンドポイント（読み書き用）"
}
