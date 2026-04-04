# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

**TaskFlow** is an AWS infrastructure learning project. The application itself (React + Node.js task manager) is intentionally minimal — it exists as a vehicle to practice real AWS infrastructure patterns. All 12 tasks in `tasks/` are the primary deliverables.

## Architecture

```
[Browser] → [Route 53] → [CloudFront] → [S3: static files]
                              ↓
                           [ALB]
                    /api/*        /*
                      ↓            ↓
          [ECS: Node.js Backend]  [ECS: React Frontend]
                      ↓
          [RDS PostgreSQL 16]
          [ElastiCache Redis 7.x]
```

**Auth:** Amazon Cognito (3 roles: Guest / User / Admin)  
**IaC:** Terraform  
**CI/CD:** GitHub Actions  
**Environments:** `dev` (minimal) and `prod` (Multi-AZ, Auto Scaling)

> **Note:** ElastiCache uses **Valkey** (Redis fork, OSS, ~20% cheaper) — not Redis OSS. Task 04 docs reflect this.

## Learning Task Structure

タスクは「ナレッジ読む → コンソールで手を動かす → IaCで置き換える」のサイクルで進める。

```
tasks/knowledge/  ← 各タスクの前に読む概念・用語・判断基準
tasks/console/    ← AWSコンソールでGUI操作（WHY解説付き）
tasks/iac/        ← Terraformで同じ構成をコード管理
```

### 推奨フロー（タスクごとに繰り返す）

1. `knowledge/0X_xxx.md` で概念を理解する
2. `console/0X_xxx.md` でコンソール操作しながら設定の意味を把握する
3. コンソールで作ったリソースを削除する（または `terraform import` で取り込む）
4. `iac/0X_xxx.md` でTerraformコードに置き換える

| # | Knowledge | Console → IaC | What it builds |
|---|-----------|--------------|----------------|
| 1 | `knowledge/01_networking.md` | `console/01_vpc.md` → `iac/01_vpc.md` | VPC, subnets, gateways |
| 2 | `knowledge/02_security_groups.md` | `console/02_security_groups.md` → `iac/02_security_groups.md` | Security groups |
| 3 | `knowledge/03_rds.md` | `console/03_rds.md` → `iac/03_rds.md` | RDS PostgreSQL 16 |
| 4 | `knowledge/04_cache.md` | `console/04_elasticache.md` → `iac/04_elasticache.md` | ElastiCache **Valkey** 8.x |
| 5 | `knowledge/05_containers.md` | `console/05_ecr.md` → `iac/05_ecr.md` | ECR container registry |
| 6 | `knowledge/06_ecs_fargate.md` | `console/06_ecs_cluster.md` → `iac/06_ecs_cluster.md` | ECS cluster + Fargate |
| 7 | `knowledge/07_load_balancer.md` | `console/07_alb.md` → `iac/07_alb.md` | ALB with path-based routing |
| 8 | `knowledge/08_iam.md` | `console/08_ecs_services.md` → `iac/08_ecs_services.md` | ECS services + task definitions |
| 9 | `knowledge/09_authentication.md` | `console/09_cognito.md` → `iac/09_cognito.md` | Cognito user pool + groups |
| 10 | `knowledge/10_cdn_storage.md` | `console/10_s3_cloudfront.md` → `iac/10_s3_cloudfront.md` | S3 + CloudFront |
| 11 | `knowledge/11_cicd.md` | `console/11_cicd.md` → `iac/11_cicd.md` | GitHub Actions pipelines |
| 12 | `knowledge/12_observability.md` | `console/12_monitoring.md` → `iac/12_monitoring.md` | CloudWatch dashboards + alarms |

## Available Agent & Skills

`infra-sensei` エージェント（`.claude/agents/infra-sensei.md`）がデフォルトの学習サポート担当。以下のスキルを自動適用する：

| スキル | 自動適用タイミング |
|--------|------------------|
| `iac-review` | TerraformなどIaCコードが提示されたとき |
| `console-review` | コンソール操作の確認・指導を求められたとき |
| `debug-guide` | エラーや問題が発生したとき |
| `grade-report` | 「完了した」「できた」などタスク完了を示す発言があったとき |

### 「先生」トリガーフック

`.claude/settings.local.json` に `UserPromptSubmit` フックが設定されており、ユーザーメッセージに「先生」が含まれる場合は **必ず `infra-sensei` サブエージェントを `Agent` ツールで起動**して回答する。直接回答は禁止。このフックは `additionalContext` として `system-reminder` 経由で注入される。

### infra-sensei メモリ

infra-sensei のエージェントメモリは `.claude/agent-memory/infra-sensei/MEMORY.md` に保存される。学習進捗・苦手分野・習熟した概念などが記録されている。タスク完了報告時に参照・更新すること。

## Progress Tracking

`tasks/PROGRESS.md` で全12タスク × 3フェーズ（Knowledge/Console/IaC）の進捗をスターで管理する。
infra-senseiエージェントに完了報告すると自動更新される。手動更新も可。

## Mistake Log

作業開始時に `mistakes/log.md` を確認し、クリティカルなミスや同じミスが繰り返された場合は原因・対処・再発防止策をそのファイルに記録・更新すること。

## Key Design Decisions

- ALB routes `/api/*` → backend ECS service, `/*` → frontend ECS service
- `dev` environment skips CloudFront and Multi-AZ to minimize AWS costs
- Terraform state files (`.tfstate`) and credentials are gitignored — never commit these
- Master spec is in Japanese: `仕様書_TaskFlow.md`

## Standard Resource Tags

All AWS resources must have these 4 tags:

```
Name        = "[resource-name]"   e.g. taskflow-vpc
Environment = "dev"
Project     = "taskflow"
ManagedBy   = "manual"            # console tasks
ManagedBy   = "terraform"         # iac tasks
```

In Terraform, use `locals { common_tags }` + `merge()` to avoid repetition.

## AWS Console UI Drift

AWS frequently updates the console UI. When console task instructions don't match what's on screen:
- Proceed based on the intent of the step, not the exact UI wording
- Update the affected `tasks/console/` file to match the current UI
- Note any significant option changes (e.g. new services like Valkey replacing Redis)

When a user reports a missing step or screen that isn't documented, add it to the relevant `tasks/console/` file immediately. Recent examples: target registration screen in `07_alb.md`, IP pool checkbox in ALB creation.

## Cost Management

`PAUSE_AND_RESUME.md` — **read before stopping a session**. Lists billable resources by task and the exact deletion/restoration order. NAT Gateway (~$33/month) and ALB (~$18/month) accrue charges when idle.
