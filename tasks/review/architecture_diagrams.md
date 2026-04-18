# TaskFlow アーキテクチャ図解集

> 全 12 タスクで構築した TaskFlow の全体像を 4 枚の Mermaid 図で視覚化。
> 目的：各 Terraform リソースがどこに配置され、どう連動し、IAM がどう作用するかを一望する。

---

## 目次

1. [図 1：全体アーキテクチャ（Terraform リソース粒度）](#図-1全体アーキテクチャterraform-リソース粒度)
2. [図 2：CI/CD フロー（GitHub Actions → AWS）](#図-2cicd-フローgithub-actions--aws)
3. [図 3：IAM 関係図（誰が誰にどう権限を与える）](#図-3iam-関係図誰が誰にどう権限を与える)
4. [図 4：OIDC 認証の 4 段階ガード（ズームイン）](#図-4oidc-認証の-4-段階ガードズームイン)
5. [読み解きのガイド](#読み解きのガイド)
6. [Terraform リソースとのマッピング](#terraform-リソースとのマッピング)

---

## 図 1：全体アーキテクチャ（Terraform リソース粒度）

ユーザーリクエストの通り道と、各 Terraform リソースがどこに配置されるかの全景。

```mermaid
graph TB
    User[👤 User Browser]

    subgraph "Global Services"
        CF[aws_cloudfront_distribution<br/>taskflow-cloudfront<br/>PriceClass_200]
        S3[aws_s3_bucket<br/>taskflow-frontend-840854900854<br/>Private + PublicAccessBlock]
        OAC[aws_cloudfront_origin_access_control<br/>SigV4 / always]
        BP[aws_s3_bucket_policy<br/>Principal: cloudfront.amazonaws.com<br/>Condition: SourceArn=CF]

        ECR_B[aws_ecr_repository<br/>taskflow/backend<br/>MUTABLE]
        ECR_F[aws_ecr_repository<br/>taskflow/frontend<br/>MUTABLE]

        Cognito[aws_cognito_user_pool<br/>taskflow-users<br/>+ User Groups<br/>+ App Client]
    end

    subgraph "VPC 10.0.0.0/16  Region: ap-northeast-1"
        IGW[aws_internet_gateway]

        subgraph "Public Subnets (a/c)"
            NAT[aws_nat_gateway]
            ALB[aws_lb taskflow-alb<br/>internet-facing]
            Listener[aws_lb_listener :80<br/>default → frontend_tg]
            RuleAPI[aws_lb_listener_rule<br/>path /api/* → backend_tg]
            TGB[aws_lb_target_group<br/>taskflow-backend-tg<br/>port 3000 /api/health]
            TGF[aws_lb_target_group<br/>taskflow-frontend-tg<br/>port 80 /]
        end

        subgraph "Private Subnets (a/c)"
            ECS_C[aws_ecs_cluster<br/>taskflow-cluster]
            ECS_BSvc[aws_ecs_service<br/>taskflow-backend-svc<br/>Fargate ARM64]
            ECS_FSvc[aws_ecs_service<br/>taskflow-frontend-svc<br/>Fargate ARM64]
            ECS_BT[aws_ecs_task_definition<br/>taskflow-backend<br/>cpu:256 mem:512]
            ECS_FT[aws_ecs_task_definition<br/>taskflow-frontend<br/>cpu:256 mem:512]

            RDS[aws_db_instance<br/>taskflow-db<br/>PostgreSQL 16<br/>db.t4g.micro]
            Valkey[aws_elasticache_replication_group<br/>taskflow-valkey<br/>Valkey 8.x]
        end

        subgraph "Security Groups"
            SGALB[aws_security_group<br/>alb-sg<br/>ingress :80 from 0.0.0.0/0]
            SGECS[aws_security_group<br/>ecs-sg<br/>ingress :3000/80 from alb-sg]
            SGDB[aws_security_group<br/>rds-sg<br/>ingress :5432 from ecs-sg]
            SGCache[aws_security_group<br/>valkey-sg<br/>ingress :6379 from ecs-sg]
        end
    end

    subgraph "CloudWatch"
        LGB[aws_cloudwatch_log_group<br/>taskflow-backend-logs]
        LGF[aws_cloudwatch_log_group<br/>taskflow-frontend-logs]
    end

    User -->|HTTPS| CF
    CF -->|/*| S3
    CF -->|/api/*| ALB
    S3 -.OAC SigV4.- OAC
    OAC -.- BP
    BP -.- S3

    ALB --> Listener
    Listener --> TGF
    RuleAPI --> TGB
    TGB --> ECS_BSvc
    TGF --> ECS_FSvc

    ECS_BSvc --> ECS_BT
    ECS_FSvc --> ECS_FT
    ECS_BT -->|docker pull| ECR_B
    ECS_FT -->|docker pull| ECR_F

    ECS_BSvc -.logs.-> LGB
    ECS_FSvc -.logs.-> LGF

    ECS_BSvc -->|5432| RDS
    ECS_BSvc -->|6379| Valkey

    SGALB -.protects.- ALB
    SGECS -.protects.- ECS_BSvc
    SGECS -.protects.- ECS_FSvc
    SGDB -.protects.- RDS
    SGCache -.protects.- Valkey

    NAT -->|egress to internet| IGW
    ECS_BSvc -.egress via NAT.-> NAT

    User -.Auth.-> Cognito
    Cognito -.JWT.-> User
    User -->|Bearer JWT| CF

    classDef global fill:#e1f5ff,stroke:#0277bd,color:#000
    classDef public fill:#fff3e0,stroke:#e65100,color:#000
    classDef private fill:#f3e5f5,stroke:#6a1b9a,color:#000
    classDef sg fill:#ffebee,stroke:#c62828,color:#000
    classDef log fill:#e8f5e9,stroke:#2e7d32,color:#000

    class CF,S3,OAC,BP,ECR_B,ECR_F,Cognito global
    class IGW,NAT,ALB,Listener,RuleAPI,TGB,TGF public
    class ECS_C,ECS_BSvc,ECS_FSvc,ECS_BT,ECS_FT,RDS,Valkey private
    class SGALB,SGECS,SGDB,SGCache sg
    class LGB,LGF log
```

### ポイント

- **CloudFront** はグローバルサービスで、`/api/*` を ALB に、`/*` を S3 に振り分ける
- **ECS タスク** は Private Subnet に配置し、ALB 経由でのみ外部到達可能（セキュリティ原則）
- **Security Group** は色分け表示：SG 同士の参照（`from alb-sg` など）が重要
- **NAT Gateway** は Private → 外への出口（ECR pull など）

---

## 図 2：CI/CD フロー（GitHub Actions → AWS）

git push から本番デプロイまでの全ステップ。

```mermaid
sequenceDiagram
    autonumber
    actor Dev as 👤 Developer
    participant GH as GitHub
    participant GA as GitHub Actions<br/>(ubuntu-latest)
    participant OIDC as GitHub OIDC<br/>token.actions...
    participant STS as AWS STS
    participant IAM as IAM<br/>(Trust & Permission)
    participant ECR as ECR<br/>taskflow/backend|frontend
    participant ECS as ECS<br/>taskflow-cluster
    participant S3 as S3<br/>taskflow-frontend
    participant CF as CloudFront

    Dev->>GH: git push origin main
    GH->>GA: workflow trigger (.github/workflows/deploy.yml)

    Note over GA,OIDC: ── OIDC 認証フェーズ ──
    GA->>OIDC: OIDC トークン要求<br/>(aud=sts.amazonaws.com)
    OIDC-->>GA: JWT<br/>{iss, sub=repo:kiccho-hub/...:main, aud}

    GA->>STS: AssumeRoleWithWebIdentity<br/>role-arn + JWT
    STS->>IAM: Role「github-actions-taskflow」の<br/>Trust Policy 検証
    Note over IAM: ①TLS指紋 thumbprint_list<br/>②JWT署名 (JWKS公開鍵)<br/>③aud = sts.amazonaws.com<br/>④sub LIKE repo:...:main
    IAM-->>STS: 検証OK
    STS-->>GA: 一時クレデンシャル<br/>(ASIA... + SessionToken, 1h)

    Note over GA,ECR: ── Backend ビルド & Push ──
    GA->>GA: setup-qemu-action@v3<br/>(ARM64 エミュ準備)
    GA->>GA: setup-buildx-action@v3<br/>(マルチプラットフォーム対応)
    GA->>ECR: ecr:GetAuthorizationToken
    ECR-->>GA: Docker login token
    GA->>GA: docker buildx build<br/>--platform linux/arm64<br/>--provenance=false
    GA->>ECR: ecr:BatchGetImage (HEAD)<br/>ecr:PutImage (PUT)
    Note over GA,ECR: 一時キー使用<br/>ecr:BatchCheckLayerAvailability<br/>ecr:InitiateLayerUpload etc.

    Note over GA,ECS: ── ECS デプロイ ──
    GA->>ECS: ecs:RegisterTaskDefinition<br/>(新revision登録)
    ECS->>IAM: iam:PassRole チェック<br/>(ecsTaskExecutionRoleをECSに渡していい?)
    Note over IAM: ※ Condition:<br/>PassedToService = ecs-tasks
    IAM-->>ECS: OK
    ECS-->>GA: revision 9 登録完了
    GA->>ECS: ecs:UpdateService<br/>taskflow-backend-svc → revision 9
    ECS->>ECR: タスク起動時に docker pull<br/>(ecsTaskExecutionRoleの権限で)
    ECR-->>ECS: ARM64 イメージ
    ECS->>ECS: Fargate タスク起動<br/>(ARM64, env vars注入)
    ECS-->>GA: デプロイ成功

    Note over GA,CF: ── Frontend ビルド & デプロイ ──
    GA->>GA: npm ci && npm run build<br/>→ frontend/build/
    GA->>S3: aws s3 sync build/ s3://bucket/<br/>(s3:PutObject, s3:DeleteObject)
    GA->>CF: cloudfront:CreateInvalidation<br/>(paths: /*)
    CF-->>GA: Invalidation ID

    Note over Dev: 🎉 デプロイ完了
```

### ポイント

- **OIDC フェーズ**：GitHub → JWT → STS → 一時クレデンシャル発行（永続鍵ゼロ）
- **ビルドフェーズ**：QEMU + Buildx で x86_64 ランナーから ARM64 イメージを生成
- **デプロイフェーズ**：タスク定義登録時に `iam:PassRole` がチェックされる
- **並列フェーズ**：Backend と Frontend は独立ジョブとして同時進行

---

## 図 3：IAM 関係図（誰が誰にどう権限を与える）

CI/CD と ECS で動く**全ロール・全ポリシー**の関係を一望。

```mermaid
graph TB
    subgraph "外部ID発行者"
        GH[GitHub OIDC Provider<br/>token.actions.githubusercontent.com]
    end

    subgraph "IAM OIDC Provider (AWS内に登録)"
        OIDCR[aws_iam_openid_connect_provider<br/>github<br/>━━━━━━━━━━━━━<br/>client_id_list: sts.amazonaws.com<br/>thumbprint_list: 動的 TLS 指紋]
    end

    subgraph "IAM Roles (空の着ぐるみ)"
        RoleGH[aws_iam_role<br/>github-actions-taskflow<br/>━━━━━━━━━━━━━<br/>信頼ポリシー:<br/>Principal.Federated = OIDCR<br/>Action: sts:AssumeRoleWithWebIdentity<br/>Condition:<br/>・aud=sts.amazonaws.com<br/>・sub LIKE repo:kiccho-hub/taskflow-aws:<br/>　ref:refs/heads/main]

        RoleExec[ecsTaskExecutionRole<br/>━━━━━━━━━━━━━<br/>信頼ポリシー:<br/>Principal.Service = ecs-tasks.amazonaws.com<br/>Action: sts:AssumeRole]

        RoleTask[ecsTaskRole<br/>(タスク内から使う権限用<br/>現状未使用)]
    end

    subgraph "IAM Policies (権利書)"
        PolGH[aws_iam_role_policy<br/>github-actions-taskflow-policy<br/>━━━━━━━━━━━━━<br/>Statement:<br/>① ecr:GetAuthorizationToken 他<br/>② ecr:BatchGetImage / PutImage 他<br/>③ ecs:UpdateService / Register...<br/>④ s3:PutObject / Delete / ListBucket<br/>⑤ cloudfront:CreateInvalidation<br/>⑥ iam:PassRole to ecs-tasks]

        PolExec[AmazonECSTaskExecutionRolePolicy<br/>(AWSマネージド)<br/>━━━━━━━━━━━━━<br/>ecr:GetAuthorizationToken<br/>ecr:BatchGetImage<br/>ecr:GetDownloadUrlForLayer<br/>logs:CreateLogStream<br/>logs:PutLogEvents]
    end

    subgraph "変身するモノ (Principal)"
        GHA[GitHub Actions Workflow<br/>deploy.yml]
        ECSTask[ECS Fargate Task<br/>taskflow-backend container]
    end

    subgraph "アクセス先リソース"
        ECR2[ECR<br/>taskflow/backend|frontend]
        ECSSvc[ECS Service<br/>taskflow-backend-svc]
        S3Buck[S3<br/>taskflow-frontend bucket]
        CFDist[CloudFront Distribution]
        LG[CloudWatch Log Group<br/>taskflow-backend-logs]
    end

    GH -.発行.- OIDCR
    OIDCR -.信頼登録.- RoleGH

    GHA -->|① OIDC JWT提示| OIDCR
    OIDCR -->|② 認証OK| GHA
    GHA -->|③ AssumeRoleWithWebIdentity<br/>で変身| RoleGH

    RoleGH -.宛名.- PolGH
    PolGH -->|ecr権限で| ECR2
    PolGH -->|ecs権限で| ECSSvc
    PolGH -->|s3権限で| S3Buck
    PolGH -->|cloudfront権限で| CFDist
    PolGH -->|iam:PassRole で ECSに<br/>ecsTaskExecutionRoleを指定| ECSSvc

    ECSSvc -->|タスク起動時<br/>ecsTaskExecutionRole を着せる| ECSTask
    ECSTask -.変身.-> RoleExec
    RoleExec -.宛名.- PolExec
    PolExec -->|ECR pull| ECR2
    PolExec -->|logs書き込み| LG

    classDef external fill:#ffecb3,stroke:#ff6f00,color:#000
    classDef role fill:#c5e1a5,stroke:#33691e,color:#000
    classDef policy fill:#b3e5fc,stroke:#01579b,color:#000
    classDef principal fill:#f8bbd0,stroke:#880e4f,color:#000
    classDef resource fill:#d1c4e9,stroke:#4527a0,color:#000

    class GH,OIDCR external
    class RoleGH,RoleExec,RoleTask role
    class PolGH,PolExec policy
    class GHA,ECSTask principal
    class ECR2,ECSSvc,S3Buck,CFDist,LG resource
```

### この図の読み方（重要 3 原則）

| 関係 | 矢印の意味 | 例 |
|------|-----------|-----|
| **信頼ポリシー** | 点線「信頼登録」「変身」 | GitHub Actions → github-actions-taskflow ロール |
| **権限ポリシー** | 点線「宛名」（ポリシー → ロール） | github-actions-taskflow-policy の宛先は github-actions-taskflow ロール |
| **PassRole** | 実線「指定」 | GitHub Actions がECSに「ecsTaskExecutionRoleを使え」と**指示** |

**ポイント**：
- 変身するのは **人（GitHub Actions, ECS Task）**
- 着る着ぐるみは **ロール**
- ロールに付く権利書が **ポリシー**
- **PassRole は「他人のロールを別サービスに渡す特殊権限」**

---

## 図 4：OIDC 認証の 4 段階ガード（ズームイン）

`AssumeRoleWithWebIdentity` で AWS STS が行う検証の詳細。

```mermaid
flowchart TB
    Start([GitHub Actions が<br/>AssumeRoleWithWebIdentity を呼ぶ<br/>JWT + RoleArn を送信])

    Start --> G1

    subgraph G1 ["① TLS証明書指紋検証 (Network層)"]
        T1[AWS STS が<br/>iss URL に HTTPS 接続]
        T2[サーバー提示の TLS 証明書チェーン取得]
        T3[各証明書の SHA1 指紋を計算]
        T4{thumbprint_list に<br/>一致する指紋ある?}
        T1 --> T2 --> T3 --> T4
    end

    T4 -->|NO| Reject1[🚫 拒否<br/>InvalidIdentityToken]
    T4 -->|YES| G2

    subgraph G2 ["② JWT署名検証 (Crypto層)"]
        J1[JWT Header の<br/>kid から鍵ID取得]
        J2[JWKS URL から<br/>公開鍵リスト取得<br/>/.well-known/jwks.json]
        J3[kid 一致する公開鍵で<br/>Signature を RS256 検証]
        J4{署名検証OK?}
        J1 --> J2 --> J3 --> J4
    end

    J4 -->|NO| Reject2[🚫 拒否<br/>署名不正/改ざん]
    J4 -->|YES| G3

    subgraph G3 ["③ aud 検証 (Application層)"]
        A1[JWT Payload から<br/>aud クレーム取得]
        A2{aud が OIDC Provider の<br/>client_id_list に含まれる?<br/>例: sts.amazonaws.com}
        A1 --> A2
    end

    A2 -->|NO| Reject3[🚫 拒否<br/>AudienceMismatch]
    A2 -->|YES| G4

    subgraph G4 ["④ Condition 検証 (Context層)"]
        C1[Role の Trust Policy の<br/>Condition 読み込み]
        C2{StringEquals<br/>aud = sts.amazonaws.com?}
        C3{StringLike<br/>sub LIKE repo:kiccho-hub/<br/>taskflow-aws:ref:refs/heads/main?}
        C1 --> C2 --> C3
    end

    C2 -->|NO| Reject4a[🚫 拒否]
    C3 -->|NO| Reject4b[🚫 拒否<br/>例: developブランチからは<br/>このロールを名乗れない]
    C3 -->|YES| Issue

    Issue([✅ STS が一時クレデンシャル発行<br/>AccessKeyId: ASIA...<br/>SecretAccessKey<br/>SessionToken ★暗号化された有効期限＆ロール情報<br/>Expiration: +1時間])

    Issue --> Use([GitHub Actions が一時キーを環境変数にセット<br/>以降 aws s3 sync / ecr push などが動く])

    classDef check fill:#fff9c4,stroke:#f57f17,color:#000
    classDef reject fill:#ffcdd2,stroke:#b71c1c,color:#000
    classDef accept fill:#c8e6c9,stroke:#1b5e20,color:#000

    class G1,G2,G3,G4 check
    class Reject1,Reject2,Reject3,Reject4a,Reject4b reject
    class Issue,Use accept
```

### ポイント

- **4 つの独立したガード**が順に評価される（どれか 1 つでもコケたら拒否）
- **①②は TLS/JWT レイヤー、③④は IAM レイヤー**という階層の違いを意識
- **SessionToken には暗号化された有効期限とロール情報が含まれる**（一時キーは3点セット必須の理由）

---

## 読み解きのガイド

### 各図の使い分け

| 図 | 主な用途 | 見るとわかること |
|----|---------|---------------|
| **図1 全体アーキ** | 紙の設計図として | どのリソースがどこに配置され、何と繋がっているか |
| **図2 CI/CD 時系列** | デバッグ・動作確認時 | push から deploy 完了までの全ステップ |
| **図3 IAM 関係** | 権限設計を考えるとき | ロールとポリシーが誰から誰へ、どう付与されているか |
| **図4 OIDC 4段階** | 認証エラー発生時 | どのガードでコケたか特定 |

### 図 3 の「覚えるべき 5 つ」

```
① OIDC Provider = 信頼登録（ARN を生成）
② Role の Trust Policy = 誰が着られるか（Principal + Action + Condition）
③ Role の Permission Policy = 着た人が何できるか（Action + Resource）
④ PassRole = 他人のロールを別サービスに指定する特殊権限
⑤ Service Role (ecsTaskExecutionRole) = ECSが勝手に着るロール
```

---

## Terraform リソースとのマッピング

| Mermaid のノード名 | Terraform リソースタイプ |
|------------------|----------------------|
| `aws_cloudfront_distribution` | `aws_cloudfront_distribution.frontend` |
| `aws_cloudfront_origin_access_control` | `aws_cloudfront_origin_access_control.frontend` |
| `aws_s3_bucket_policy` | `aws_s3_bucket_policy.frontend` |
| `aws_iam_openid_connect_provider` | `aws_iam_openid_connect_provider.github` |
| `aws_iam_role` (github-actions-taskflow) | `aws_iam_role.github_actions` |
| `aws_iam_role_policy` | `aws_iam_role_policy.github_actions` |
| `aws_ecs_cluster` | `aws_ecs_cluster.main` |
| `aws_ecs_service` (backend) | `aws_ecs_service.backend` |
| `aws_ecs_task_definition` (backend) | `aws_ecs_task_definition.backend` |
| `aws_lb` | `aws_lb.main` |
| `aws_lb_listener` | `aws_lb_listener.http` |
| `aws_lb_listener_rule` | `aws_lb_listener_rule.api` |
| `aws_lb_target_group` | `aws_lb_target_group.backend` / `frontend` |
| `aws_security_group` (alb-sg) | `aws_security_group.alb` |
| `aws_db_instance` | `aws_db_instance.main` |
| `aws_elasticache_replication_group` | `aws_elasticache_replication_group.main` |
| `aws_ecr_repository` | `aws_ecr_repository.backend` / `frontend` |
| `aws_cognito_user_pool` | `aws_cognito_user_pool.main` |

---

## 使い方Tips

この 4 枚セットで理解できること：

```
「何がどこに配置されてるか」      → 図1
「コミットからデプロイまでの流れ」  → 図2
「誰が何の権限を持ってるか」       → 図3
「OIDCの認証はどう動くか」         → 図4
```

- **GitHub の Markdown preview** で mermaid が直接レンダリングされる
- **VS Code の Markdown Preview** でも確認可能
- 紙にプリントアウトして壁に貼ると常時参照できる学習ダッシュボードに
- Task 12（監視）の実装時、図 1 を見ながら「どのリソースにアラームを付けるか」を判断できる

---

## 関連ドキュメント

- [IAM 振り返りシート](iam_review.md) — IAM の詳細解説と理解度チェック
- [PROGRESS.md](../PROGRESS.md) — 全 12 タスクの進捗
- [CLAUDE.md](../../CLAUDE.md) — プロジェクト全体ガイド
