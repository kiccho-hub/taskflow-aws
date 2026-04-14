resource "aws_db_subnet_group" "main" {
  name = "taskflow-db-subnet"

  subnet_ids  = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id,
  ]

  tags = merge(local.common_tags, {
    Name = "taskflow-db-subnet"
  })
}

# パラメータグループ：PostgreSQL の設定を管理するテンプレート
#
# このリソースは RDS インスタンスが起動時に読み込む設定ファイル（postgresql.conf）を定義します。
# RDS では AWS がファイルを管理するため、Terraform でパラメータグループとして定義します。
#
# 【アナロジー】
# - パラメータグループ = PostgreSQL の「設定マニュアル」
# - RDS インスタンス = そのマニュアルに従って動く「データベースエンジン」
#
resource "aws_db_parameter_group" "main" {
  # グループの識別名（AWS コンソールに表示される）
  name   = "taskflow-pg16"

  # PostgreSQL のバージョンを指定
  # "postgres16" = PostgreSQL 16.x に対応したパラメータグループ
  # ※ RDS インスタンスのバージョンと合わせる必要がある
  family = "postgres16"

  # 実際の設定パラメータ（複数ある場合は parameter ブロックを追加）
  parameter {
    # 【client_encoding = UTF8 の役割】
    # クライアント（アプリケーション）から送信されるテキストが
    # 常に UTF-8 エンコーディングであることを DB に伝える
    #
    # 【なぜ必要か？】
    # ✅ 日本語対応：「こんにちは」「新しいタスク」を正しく保存
    # ✅ 絵文字対応：「🎉」「📝」「🚀」などを正しく保存
    # ✅ グローバル対応：中国語、アラビア語など多言語対応
    #
    # 【設定しないと？】
    # ❌ 日本語の入力：文字化けまたはエラー
    # ❌ 絵文字の入力：エラーになる
    # ❌ データベース読み取り時：「?????」になる
    #
    # 【設定例】
    # TaskFlow の Node.js アプリから「新しいタスク📝」を送信
    #   ↓ UTF8 で正しく解釈される ✅
    #   ↓
    # PostgreSQL が正しく保存
    name  = "client_encoding"
    value = "UTF8"
  }

  # AWS リソースのタグ（管理・検索用）
  # local.common_tags で環境・プロジェクト情報を統一
  tags = merge(local.common_tags, {
    Name = "taskflow-db-pg16"
  })
}

resource "aws_db_instance" "main" {
  identifier = "taskflow-db"

  engine             = "postgres"
  engine_version     = "16.6"

  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name               = "taskflow"
  username              = "taskflow_admin"
  password              = var.db_password

  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # パラメータグループをアタッチ
  # 【重要】パラメータグループは定義しただけでは使われない。
  # RDS インスタンスで明示的に参照する必要があります。
  # これにより、起動時に client_encoding = UTF8 などの設定が自動的に適用されます。
  parameter_group_name = aws_db_parameter_group.main.name

  publicly_accessible    = false

  multi_az              = false
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, {
    Name = "taskflow-rds-postgres"
  })
}
