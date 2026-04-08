#!/usr/bin/env bash

###############################################################################
# terraform-resource-status.sh
#
# Purpose: terraform state に記録された全リソースを取得し、
#          AWS CLI で実際のステータスを確認して統一フォーマットで表示
#
# Usage:
#   terraform-resource-status [environment] [output-format]
#
#   environment:    dev | prod (default: dev)
#   output-format:  json | table | yaml (default: table)
#
# Example:
#   terraform-resource-status dev table
#   terraform-resource-status prod json
#
###############################################################################

set -o pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-dev}"
OUTPUT_FORMAT="${2:-table}"

TF_DIR="${PROJECT_ROOT}/infra/environments/${ENVIRONMENT}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC}  $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC}  $1" >&2
}

log_warn() {
    echo -e "${YELLOW}⚠${NC}  $1" >&2
}

log_error() {
    echo -e "${RED}✗${NC}  $1" >&2
}

# Check if terraform directory exists
check_terraform_dir() {
    if [[ ! -d "$TF_DIR" ]]; then
        log_error "Terraform directory not found: $TF_DIR"
        exit 1
    fi
}

# Extract resource type and name from terraform address
# Format: aws_vpc.main -> (aws_vpc, main)
parse_tf_address() {
    local address="$1"
    if [[ $address =~ ^([a-z_]+\.[a-z_]+)\.([a-z0-9_\-]+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    else
        echo "unknown unknown"
    fi
}

# Get resource ID from terraform state
get_resource_id() {
    local resource_type="$1"
    local resource_name="$2"

    cd "$TF_DIR" || return
    terraform state show "${resource_type}.${resource_name}" 2>/dev/null | \
        grep "^id" | awk '{print $3}' | tr -d '"'
}

# Get Name tag from terraform state
get_resource_name_tag() {
    local resource_type="$1"
    local resource_name="$2"

    cd "$TF_DIR" || return
    terraform state show "${resource_type}.${resource_name}" 2>/dev/null | \
        grep 'tags.*"Name"' -A 2 | grep -o '"[^"]*"$' | head -1 | tr -d '"'
}

# ============================================================================
# AWS CLI Query Functions (by resource type)
# ============================================================================

query_vpc_status() {
    local vpc_id="$1"
    aws ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].[VpcId, State]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_subnet_status() {
    local subnet_id="$1"
    aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].[SubnetId, State]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_security_group_status() {
    local sg_id="$1"
    aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --query 'SecurityGroups[0].[GroupId, GroupName]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_nat_gateway_status() {
    local natgw_id="$1"
    aws ec2 describe-nat-gateways \
        --nat-gateway-ids "$natgw_id" \
        --query 'NatGateways[0].[NatGatewayId, State]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_internet_gateway_status() {
    local igw_id="$1"
    aws ec2 describe-internet-gateways \
        --internet-gateway-ids "$igw_id" \
        --query 'InternetGateways[0].[InternetGatewayId, Tags[?Key==`Name`].Value | [0]]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_rds_status() {
    local db_instance_id="$1"
    aws rds describe-db-instances \
        --db-instance-identifier "$db_instance_id" \
        --query 'DBInstances[0].[DBInstanceIdentifier, DBInstanceStatus]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_elasticache_status() {
    local cache_cluster_id="$1"
    aws elasticache describe-cache-clusters \
        --cache-cluster-id "$cache_cluster_id" \
        --query 'CacheClusters[0].[CacheClusterId, CacheClusterStatus]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_alb_status() {
    local alb_arn="$1"
    aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].[LoadBalancerArn, State.Code]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_ecs_cluster_status() {
    local cluster_name="$1"
    aws ecs describe-clusters \
        --clusters "$cluster_name" \
        --query 'clusters[0].[clusterName, status]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_ecs_service_status() {
    local cluster="$1"
    local service="$2"
    aws ecs describe-services \
        --cluster "$cluster" \
        --services "$service" \
        --query 'services[0].[serviceName, status]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

query_iam_role_status() {
    local role_name="$1"
    aws iam get-role \
        --role-name "$role_name" \
        --query 'Role.[RoleName, CreateDate]' \
        --output json 2>/dev/null | jq -r '.[] // empty' | paste -sd '|' -
}

# ============================================================================
# Status Normalization (convert to boolean isActive)
# ============================================================================

normalize_status() {
    local resource_type="$1"
    local status="$2"

    case "$resource_type" in
        aws_vpc)
            [[ "$status" == "available" ]] && echo "true" || echo "false"
            ;;
        aws_subnet)
            [[ "$status" == "available" ]] && echo "true" || echo "false"
            ;;
        aws_security_group)
            echo "true"  # Security groups don't have detailed status
            ;;
        aws_nat_gateway)
            [[ "$status" == "available" ]] && echo "true" || echo "false"
            ;;
        aws_internet_gateway)
            echo "true"  # IGW is always active if it exists
            ;;
        aws_route_table)
            echo "true"  # Route tables are always active
            ;;
        aws_db_instance)
            [[ "$status" == "available" ]] && echo "true" || echo "false"
            ;;
        aws_elasticache_cluster)
            [[ "$status" == "available" ]] && echo "true" || echo "false"
            ;;
        aws_lb|aws_alb)
            [[ "$status" == "active" ]] && echo "true" || echo "false"
            ;;
        aws_ecs_cluster)
            [[ "$status" == "ACTIVE" ]] && echo "true" || echo "false"
            ;;
        aws_ecs_service)
            [[ "$status" == "ACTIVE" ]] && echo "true" || echo "false"
            ;;
        aws_iam_role)
            echo "true"  # IAM roles don't have status
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ============================================================================
# Get status for specific resource types
# ============================================================================

get_resource_status() {
    local resource_type="$1"
    local resource_id="$2"
    local cluster_name="${3:-}"  # For ECS services
    local service_name="${4:-}"

    case "$resource_type" in
        aws_vpc)
            query_vpc_status "$resource_id"
            ;;
        aws_subnet)
            query_subnet_status "$resource_id"
            ;;
        aws_security_group)
            query_security_group_status "$resource_id"
            ;;
        aws_nat_gateway)
            query_nat_gateway_status "$resource_id"
            ;;
        aws_internet_gateway)
            query_internet_gateway_status "$resource_id"
            ;;
        aws_route_table)
            echo "$resource_id|active"
            ;;
        aws_db_instance)
            query_rds_status "$resource_id"
            ;;
        aws_elasticache_cluster)
            query_elasticache_status "$resource_id"
            ;;
        aws_lb|aws_alb)
            query_alb_status "$resource_id"
            ;;
        aws_ecs_cluster)
            query_ecs_cluster_status "$resource_id"
            ;;
        aws_ecs_service)
            query_ecs_service_status "$cluster_name" "$service_name"
            ;;
        aws_iam_role)
            query_iam_role_status "$resource_id"
            ;;
        *)
            echo "unknown|unknown"
            ;;
    esac
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    check_terraform_dir

    log_info "Scanning terraform state from: $TF_DIR"
    log_info "Environment: $ENVIRONMENT"
    log_info "Output format: $OUTPUT_FORMAT"
    echo >&2

    # Array to store results
    declare -a results=()

    cd "$TF_DIR" || exit 1

    # Get all resources from terraform state
    local tf_resources
    tf_resources=$(terraform state list 2>/dev/null)

    if [[ -z "$tf_resources" ]]; then
        log_warn "No resources found in terraform state"
        return 0
    fi

    log_info "Found $(echo "$tf_resources" | wc -l) resource(s) in state"
    echo >&2

    local count=0
    while IFS= read -r tf_address; do
        [[ -z "$tf_address" ]] && continue

        count=$((count + 1))
        echo -ne "\rProcessing resource $count..." >&2

        # Parse resource type and name
        read -r resource_type resource_name <<< "$(parse_tf_address "$tf_address")"

        # Skip unknown resources
        if [[ "$resource_type" == "unknown" ]]; then
            log_warn "Skipping unrecognized resource: $tf_address"
            continue
        fi

        # Get resource ID from state
        local resource_id
        resource_id=$(get_resource_id "$resource_type" "$resource_name")

        if [[ -z "$resource_id" ]]; then
            log_warn "Could not extract ID for: $tf_address"
            continue
        fi

        # Get Name tag
        local name_tag
        name_tag=$(get_resource_name_tag "$resource_type" "$resource_name")
        [[ -z "$name_tag" ]] && name_tag="$resource_name"

        # Query AWS API for status
        local status_line
        status_line=$(get_resource_status "$resource_type" "$resource_id")

        # Extract status and normalize
        local status detailed_status
        if [[ "$status_line" == *"|"* ]]; then
            detailed_status=$(echo "$status_line" | cut -d'|' -f2-)
            status=$(echo "$status_line" | cut -d'|' -f2)
        else
            status="unknown"
            detailed_status="unknown"
        fi

        local is_active
        is_active=$(normalize_status "$resource_type" "$status")

        # Store result
        local result_json
        result_json=$(jq -n \
            --arg resource_type "$resource_type" \
            --arg name "$name_tag" \
            --arg resource_id "$resource_id" \
            --arg is_active "$is_active" \
            --arg status "$detailed_status" \
            '{
                resource_type: $resource_type,
                name: $name,
                resource_id: $resource_id,
                isActive: $is_active,
                status: $status
            }')

        results+=("$result_json")

    done <<< "$tf_resources"

    echo "" >&2
    echo >&2

    # Output results in requested format
    case "$OUTPUT_FORMAT" in
        json)
            output_json "${results[@]}"
            ;;
        table)
            output_table "${results[@]}"
            ;;
        yaml)
            output_yaml "${results[@]}"
            ;;
        *)
            log_error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# ============================================================================
# Output Functions
# ============================================================================

output_json() {
    local -a results=("$@")

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi

    echo "["
    for i in "${!results[@]}"; do
        echo "${results[$i]}"
        if [[ $i -lt $((${#results[@]} - 1)) ]]; then
            echo ","
        fi
    done
    echo "]"
}

output_table() {
    local -a results=("$@")

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "No resources found"
        return
    fi

    # Print header
    printf "${CYAN}%-30s %-20s %-30s %-10s %-15s${NC}\n" \
        "Name" "Resource Type" "Resource ID" "Active" "Status"
    printf "%-30s %-20s %-30s %-10s %-15s\n" \
        "$(printf -- '-%.0s' {1..30})" \
        "$(printf -- '-%.0s' {1..20})" \
        "$(printf -- '-%.0s' {1..30})" \
        "$(printf -- '-%.0s' {1..10})" \
        "$(printf -- '-%.0s' {1..15})"

    # Print rows
    for result in "${results[@]}"; do
        local name resource_type resource_id is_active status

        name=$(echo "$result" | jq -r '.name')
        resource_type=$(echo "$result" | jq -r '.resource_type')
        resource_id=$(echo "$result" | jq -r '.resource_id')
        is_active=$(echo "$result" | jq -r '.isActive')
        status=$(echo "$result" | jq -r '.status')

        # Color code active status
        if [[ "$is_active" == "true" ]]; then
            is_active="${GREEN}true${NC}"
        else
            is_active="${RED}false${NC}"
        fi

        printf "%-30s %-20s %-30s %-10s %-15s\n" \
            "$name" "$resource_type" "$resource_id" "$is_active" "$status"
    done
}

output_yaml() {
    local -a results=("$@")

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "resources: []"
        return
    fi

    echo "resources:"
    for result in "${results[@]}"; do
        local name resource_type resource_id is_active status

        name=$(echo "$result" | jq -r '.name')
        resource_type=$(echo "$result" | jq -r '.resource_type')
        resource_id=$(echo "$result" | jq -r '.resource_id')
        is_active=$(echo "$result" | jq -r '.isActive')
        status=$(echo "$result" | jq -r '.status')

        echo "  - name: \"$name\""
        echo "    resource_type: \"$resource_type\""
        echo "    resource_id: \"$resource_id\""
        echo "    isActive: $is_active"
        echo "    status: \"$status\""
    done
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
