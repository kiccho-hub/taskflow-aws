#!/usr/bin/env bash

###############################################################################
# USAGE_EXAMPLES.sh
#
# terraform-resource-status.sh の実行例集
# 各例はコメントとして記載され、実際の出力サンプルも掲載
#
###############################################################################

# ============================================================================
# 例 1: デフォルト（dev 環境、テーブル形式）
# ============================================================================
echo "# 例 1: デフォルト実行（dev 環境、テーブル形式）"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh"
echo ""
echo "ℹ  Scanning terraform state from: /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev"
echo "ℹ  Environment: dev"
echo "ℹ  Output format: table"
echo ""
echo "Name                           Resource Type        Resource ID                    Active     Status"
echo "------------ ------------ -------------- -------- -------"
echo "taskflow-vpc                   aws_vpc              vpc-0a1b2c3d4e5f6g7h8        true       available"
echo "taskflow-subnet-public-1a      aws_subnet           subnet-0f1e2d3c4b5a6g7h8     true       available"
echo "taskflow-subnet-public-1c      aws_subnet           subnet-1a2b3c4d5e6f7g8h9     true       available"
echo "taskflow-subnet-private-1a     aws_subnet           subnet-2b3c4d5e6f7g8h9i0     true       available"
echo "taskflow-subnet-private-1c     aws_subnet           subnet-3c4d5e6f7g8h9i0j1     true       available"
echo ""
echo ""

# ============================================================================
# 例 2: prod 環境、テーブル形式
# ============================================================================
echo "# 例 2: prod 環境をテーブル形式で表示"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh prod table"
echo ""
echo "ℹ  Scanning terraform state from: /Users/yuki-mac/claude-code/aws-demo/infra/environments/prod"
echo "ℹ  Environment: prod"
echo "ℹ  Output format: table"
echo ""
echo "Name                           Resource Type        Resource ID                    Active     Status"
echo "------------ ------------ -------------- -------- -------"
echo "taskflow-vpc-prod              aws_vpc              vpc-0x1y2z3a4b5c6d7e8f9    true       available"
echo "taskflow-nat-gw-1a             aws_nat_gateway      nat-0p1q2r3s4t5u6v7w8x      true       available"
echo "taskflow-nat-gw-1c             aws_nat_gateway      nat-1a2b3c4d5e6f7g8h9i      true       available"
echo "taskflow-alb                   aws_lb               arn:aws:elasticloadbalancin true       active"
echo "taskflow-rds-postgres          aws_db_instance      taskflow-db                 true       available"
echo "taskflow-elasticache           aws_elasticache_cluster  taskflow-cache           true       available"
echo ""
echo ""

# ============================================================================
# 例 3: JSON 形式で出力
# ============================================================================
echo "# 例 3: JSON 形式で出力（スクリプト処理に便利）"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev json"
echo ""
echo "["
echo "  {"
echo '    "resource_type": "aws_vpc",'
echo '    "name": "taskflow-vpc",'
echo '    "resource_id": "vpc-0a1b2c3d4e5f6g7h8",'
echo '    "isActive": "true",'
echo '    "status": "available"'
echo "  },"
echo "  {"
echo '    "resource_type": "aws_subnet",'
echo '    "name": "taskflow-subnet-public-1a",'
echo '    "resource_id": "subnet-0f1e2d3c4b5a6g7h8",'
echo '    "isActive": "true",'
echo '    "status": "available"'
echo "  },"
echo "  {"
echo '    "resource_type": "aws_db_instance",'
echo '    "name": "taskflow-rds-postgres",'
echo '    "resource_id": "taskflow-db",'
echo '    "isActive": "true",'
echo '    "status": "available"'
echo "  }"
echo "]"
echo ""
echo ""

# ============================================================================
# 例 4: YAML 形式で出力
# ============================================================================
echo "# 例 4: YAML 形式で出力"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev yaml"
echo ""
echo "resources:"
echo '  - name: "taskflow-vpc"'
echo '    resource_type: "aws_vpc"'
echo '    resource_id: "vpc-0a1b2c3d4e5f6g7h8"'
echo '    isActive: true'
echo '    status: "available"'
echo '  - name: "taskflow-subnet-public-1a"'
echo '    resource_type: "aws_subnet"'
echo '    resource_id: "subnet-0f1e2d3c4b5a6g7h8"'
echo '    isActive: true'
echo '    status: "available"'
echo '  - name: "taskflow-rds-postgres"'
echo '    resource_type: "aws_db_instance"'
echo '    resource_id: "taskflow-db"'
echo '    isActive: true'
echo '    status: "available"'
echo ""
echo ""

# ============================================================================
# 例 5: zshrc エイリアスで実行
# ============================================================================
echo "# 例 5: .zshrc エイリアスで実行（最も簡単）"
echo "$ tf-status dev table"
echo "$ tf-status prod json"
echo "$ tf-status dev yaml"
echo ""
echo ""

# ============================================================================
# 例 6: JSON 結果をパイプで処理
# ============================================================================
echo "# 例 6: JSON 結果を jq で処理（高度な活用）"
echo ""
echo "# 全リソース ID の一覧を取得"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev json | jq -r '.[] | .resource_id'"
echo ""
echo "vpc-0a1b2c3d4e5f6g7h8"
echo "subnet-0f1e2d3c4b5a6g7h8"
echo "subnet-1a2b3c4d5e6f7g8h9"
echo "taskflow-db"
echo "taskflow-cache"
echo ""
echo ""

# ============================================================================
# 例 7: isActive がfalseのリソースを検出
# ============================================================================
echo "# 例 7: 停止中（isActive=false）のリソースを検出"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev json | jq '.[] | select(.isActive == \"false\")'  "
echo ""
echo "{"
echo '  "resource_type": "aws_db_instance",'
echo '  "name": "taskflow-rds-backup",'
echo '  "resource_id": "taskflow-db-backup",'
echo '  "isActive": "false",'
echo '  "status": "creating"'
echo "}"
echo ""
echo ""

# ============================================================================
# 例 8: 特定のリソースタイプのみを抽出
# ============================================================================
echo "# 例 8: 特定のリソースタイプのみを抽出"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev json | jq '.[] | select(.resource_type == \"aws_db_instance\")'  "
echo ""
echo "{"
echo '  "resource_type": "aws_db_instance",'
echo '  "name": "taskflow-rds-postgres",'
echo '  "resource_id": "taskflow-db",'
echo '  "isActive": "true",'
echo '  "status": "available"'
echo "}"
echo ""
echo ""

# ============================================================================
# 例 9: リソースの状態チェック（CI/CD スクリプト用）
# ============================================================================
echo "# 例 9: リソースの健全性チェック（自動化スクリプト用）"
echo ""
cat << 'BASH_SCRIPT'
#!/bin/bash
# すべてのリソースが active であることを確認
INACTIVE_COUNT=$(bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh dev json | \
    jq '[.[] | select(.isActive == "false")] | length')

if [ "$INACTIVE_COUNT" -gt 0 ]; then
    echo "警告: $INACTIVE_COUNT個の非アクティブリソースが見つかりました"
    exit 1
else
    echo "OK: すべてのリソースが正常な状態です"
    exit 0
fi
BASH_SCRIPT
echo ""
echo ""

# ============================================================================
# 例 10: ALB だけの状態を取得
# ============================================================================
echo "# 例 10: ALB（ロードバランサー）のみを取得"
echo "$ bash /Users/yuki-mac/claude-code/aws-demo/debug/terraform-resource-status.sh prod json | jq '.[] | select(.resource_type == \"aws_lb\")'  "
echo ""
echo "{"
echo '  "resource_type": "aws_lb",'
echo '  "name": "taskflow-alb",'
echo '  "resource_id": "arn:aws:elasticloadbalancing:ap-northeast-1:840854900854:loadbalancer/app/taskflow-alb/1234567890abcdef",'
echo '  "isActive": "true",'
echo '  "status": "active"'
echo "}"
echo ""
echo ""

echo "============================================================================"
echo "上記の例は terraform apply 後の想定出力です。"
echo "現在 terraform state には リソースがまだ作成されていません。"
echo ""
echo "実際に AWS リソースを作成した後、コマンドを実行してください："
echo ""
echo "  cd /Users/yuki-mac/claude-code/aws-demo/infra/environments/dev"
echo "  terraform apply"
echo "  tf-status dev table"
echo "============================================================================"
