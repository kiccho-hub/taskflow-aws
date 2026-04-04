# Task 6: ECS クラスター構築（コンソール）

## 全体構成における位置づけ

> 図: TaskFlow全体アーキテクチャ（オレンジ色が今回構築するコンポーネント）

```mermaid
graph TD
    Browser["🌐 Browser"]
    R53["Route 53"]
    CF["CloudFront (Task10)"]
    S3["S3 (Task10)"]
    ALB["ALB (Task07)"]
    ECSFront["ECS Frontend (Task06/08)"]
    ECSBack["ECS Backend (Task06/08)"]
    ECR["ECR (Task05)"]
    RDS["RDS PostgreSQL (Task03)"]
    Redis["ElastiCache Redis (Task04)"]
    Cognito["Cognito (Task09)"]
    GH["GitHub Actions (Task11)"]
    CW["CloudWatch (Task12)"]

    subgraph VPC["VPC / Subnets (Task01) + SG (Task02)"]
        subgraph PublicSubnet["Public Subnet"]
            ALB
        end
        subgraph PrivateSubnet["Private Subnet"]
            ECSFront
            ECSBack
            RDS
            Redis
        end
    end

    Browser --> R53 --> CF
    CF --> S3
    CF --> ALB
    ALB -->|"/*"| ECSFront
    ALB -->|"/api/*"| ECSBack
    ECSBack --> RDS
    ECSBack --> Redis
    ECR -.->|Pull| ECSFront
    ECR -.->|Pull| ECSBack
    Cognito -.->|Auth| ECSBack
    GH -.->|Deploy| ECR
    CW -.->|Monitor| ALB
    CW -.->|Monitor| ECSBack

    classDef highlight fill:#ff9900,stroke:#cc6600,color:#000,font-weight:bold
    class ECSFront,ECSBack highlight
```

**今回構築する箇所:** ECS Cluster（Task06）- コンテナを動かす基盤（Cluster + IAMロール）

---

> 図: ECS Cluster / Service / Task の階層構造

```mermaid
graph TB
    subgraph Cluster["ECS Cluster: taskflow-cluster\n(Fargate インフラ)"]
        subgraph ServiceFront["Service: taskflow-frontend-service\n(Task08で作成)"]
            TaskFront1["Task (コンテナ)\nNginx:80\n(desired: 1〜)"]
            TaskFront2["Task (コンテナ)\nNginx:80\n(スケールアウト時)"]
        end
        subgraph ServiceBack["Service: taskflow-backend-service\n(Task08で作成)"]
            TaskBack1["Task (コンテナ)\nNode.js:3000\n(desired: 1〜)"]
            TaskBack2["Task (コンテナ)\nNode.js:3000\n(スケールアウト時)"]
        end
    end

    subgraph TaskDef["Task Definition (Task08で作成)"]
        TDFront["taskflow-frontend\nCPU/Memory定義\nコンテナイメージURI\n環境変数\nIAMロール"]
        TDBack["taskflow-backend\nCPU/Memory定義\nコンテナイメージURI\n環境変数 (DB URL等)\nIAMロール"]
    end

    subgraph IAM["IAM Role (今回作成)"]
        ExecRole["ecsTaskExecutionRole\n- ECRからのイメージpull\n- CloudWatch Logsへの書き込み"]
    end

    ECR["ECR\n(taskflow/frontend)\n(taskflow/backend)"]

    TDFront -.->|"インスタンス化"| TaskFront1
    TDBack -.->|"インスタンス化"| TaskBack1
    ExecRole -.->|"権限付与"| TaskFront1
    ExecRole -.->|"権限付与"| TaskBack1
    ECR -->|"イメージpull"| TaskFront1
    ECR -->|"イメージpull"| TaskBack1

    classDef highlight fill:#ff9900,stroke:#cc6600,color:#000,font-weight:bold
    classDef future fill:#f5f5f5,stroke:#999,color:#666,stroke-dasharray: 5 5
    classDef iam fill:#fff3e0,stroke:#ff9900,color:#000
    class Cluster highlight
    class ServiceFront,ServiceBack,TaskFront1,TaskFront2,TaskBack1,TaskBack2 future
    class ExecRole iam
```

---

> 参照ナレッジ: [06_ecs_fargate.md](../knowledge/06_ecs_fargate.md)

## このタスクのゴール

コンテナを動かす基盤（ECSクラスターとIAMロール）を作る。このタスクで作るのはコンテナの「箱」のみ。中身はTask 8で作成する。

---

## ハンズオン手順

### Step 1: ECS タスク実行ロールの作成

コンテナを起動するためにECSが必要とするIAM権限を先に作っておく。

1. AWSコンソール → **「IAM」** → 左メニュー **「ロール」** → **「ロールを作成」**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| 信頼されたエンティティタイプ | AWSのサービス | ECSというAWSサービスに権限を付与する |
| サービス | Elastic Container Service | |
| ユースケース | **Elastic Container Service Task** | 「Task」を選ばないとECSタスクではなくECS全体のロールになってしまう |

2. **「次へ」** → ポリシーを検索して追加：

| ポリシー名 | 理由 |
|-----------|------|
| `AmazonECSTaskExecutionRolePolicy` | ECRからのイメージpull・CloudWatch Logsへの書き込みが含まれる。ECSタスク起動の最小セット |

> **AdministratorAccessを付けてはいけない理由：** 最小権限の原則。コンテナが侵害された場合に被害が最小になるよう、必要な権限だけを付ける。

3. **ロール名**: `ecsTaskExecutionRole`（この名前はAWSの慣習。他の名前でも動くが統一しておく）
4. **「ロールを作成」**

### Step 2: ECS クラスターの作成

1. AWSコンソール → **「ECS」** → 左メニュー **「クラスター」** → **「クラスターを作成」**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| クラスター名 | `taskflow-cluster` | |
| AWS Fargate（サーバーレス） | **チェックを入れる** | サーバー管理なしでコンテナを動かせる。学習・中規模サービスに最適 |
| Amazon EC2インスタンス | チェックしない | EC2管理（OS・パッチ・スケーリング）も必要になり複雑化する。Fargateで十分 |
| 外部インスタンス | チェックしない | オンプレミスのサーバーをECSで管理する場合に使う。今回不要 |

**モニタリング：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| Container Insights を使用 | **有効** | コンテナ単位のCPU・メモリ・ネットワークメトリクスが取れるようになる。問題発生時の調査に不可欠。CloudWatchのコストが若干上がるが有効にする価値がある |

**タグ：**

| キー | 値 |
|------|-----|
| Name | taskflow-cluster |
| Environment | dev |
| Project | taskflow |
| ManagedBy | manual |

2. **「作成」**

---

## 確認ポイント

1. **ECS → クラスター** に `taskflow-cluster` が表示されるか
2. ステータスが **「ACTIVE」** か
3. インフラストラクチャに **「Fargate」** が表示されているか
4. **IAM → ロール** に `ecsTaskExecutionRole` が存在するか
5. `ecsTaskExecutionRole` に `AmazonECSTaskExecutionRolePolicy` がアタッチされているか

---

**このタスクをコンソールで完了したら:** [Task 6: ECSクラスター（IaC版）](../iac/06_ecs_cluster.md)

**次のタスク:** [Task 7: ALB 構築・パスベースルーティング](07_alb.md)

---

## 参考: ECR / ECS / Fargate / CloudFormation の関係図

> 図: ECR・ECS・Fargate・IAM・ネットワーク・監視リソースの全体関係

```mermaid
graph TB
    subgraph Dev["開発者のPC"]
        Code["アプリコード\n(Node.js / React)"]
        Dockerfile["Dockerfile"]
    end

    subgraph CI["CI/CD (GitHub Actions)"]
        GH["GitHub Actions"]
    end

    subgraph Registry["コンテナレジストリ (Task05)"]
        ECR["ECR\nDockerイメージを保管する倉庫"]
    end

    subgraph IaC["IaC"]
        TF["Terraform / CloudFormation\nインフラをコードで定義・管理"]
    end

    subgraph ECSWorld["ECS の世界"]
        subgraph Cluster["ECS Cluster: taskflow-cluster (Task06)"]
            subgraph ServiceFE["ECS Service: Frontend (Task08)\n常にN個動かす監視係"]
                TaskFE["ECS Task\nコンテナ (Nginx)"]
            end
            subgraph ServiceBE["ECS Service: Backend (Task08)\n常にN個動かす監視係"]
                TaskBE["ECS Task\nコンテナ (Node.js)"]
            end
        end
        TD["Task Definition (Task08)\nコンテナの設計図\n・イメージURI\n・CPU/Mem\n・環境変数\n・IAMロール"]
        Fargate["AWS Fargate\nサーバーレス実行基盤\nサーバー管理不要"]
    end

    subgraph IAMRoles["IAM (Task06/08)"]
        ExecRole["ecsTaskExecutionRole\nECRpull / CWLogs書き込み"]
        TaskRole["ECS Task Role\nアプリがS3等を呼ぶ権限"]
        SLRole["AWSServiceRoleForECS\nECSサービス自体の管理権限"]
    end

    subgraph Network["ネットワーク (Task01/02)"]
        VPC["VPC"]
        SG["Security Group\ntaskflow-sg-ecs"]
        PrivSubnet["Private Subnet"]
    end

    subgraph Monitoring["監視 (Task12)"]
        CWLogs["CloudWatch Logs\nコンテナのログ"]
        CWMetrics["CloudWatch Metrics\nCPU・メモリ等"]
    end

    Code --> Dockerfile
    Dockerfile -->|"docker build & push"| GH
    GH -->|"イメージをpush"| ECR
    GH -->|"ECS deploy"| ServiceFE
    GH -->|"ECS deploy"| ServiceBE

    TF -->|"クラスター・サービス・TD を作成"| Cluster
    TF -->|"IAMロールを作成"| IAMRoles

    ECR -->|"イメージpull (ExecRole経由)"| TaskFE
    ECR -->|"イメージpull (ExecRole経由)"| TaskBE

    TD -->|"インスタンス化"| TaskFE
    TD -->|"インスタンス化"| TaskBE

    Fargate -->|"コンテナを起動"| TaskFE
    Fargate -->|"コンテナを起動"| TaskBE

    ExecRole -->|"権限付与"| TaskFE
    ExecRole -->|"権限付与"| TaskBE
    TaskRole -->|"アプリ権限"| TaskBE
    SLRole -->|"サービス管理"| Cluster

    TaskFE --> PrivSubnet
    TaskBE --> PrivSubnet
    PrivSubnet --> VPC
    SG -->|"トラフィック制御"| TaskFE
    SG -->|"トラフィック制御"| TaskBE

    TaskFE -->|"ログ送信"| CWLogs
    TaskBE -->|"ログ送信"| CWLogs
    Fargate -->|"メトリクス送信"| CWMetrics
```
