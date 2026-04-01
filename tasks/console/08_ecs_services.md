# Task 8: ECS サービス・タスク定義（コンソール）

> 参照ナレッジ: [06_ecs_fargate.md](../knowledge/06_ecs_fargate.md)、[08_iam.md](../knowledge/08_iam.md)

## このタスクのゴール

TaskFlow の Backend / Frontend コンテナを実際に起動する。

---

## ハンズオン手順

### Step 1: Backend タスク定義の作成

1. AWSコンソール → **「ECS」** → 左メニュー **「タスク定義」** → **「新しいタスク定義を作成」**

**タスク定義の設定：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| タスク定義ファミリー | `taskflow-backend` | ファミリー名はリビジョン管理の単位。変更のたびに新リビジョンが作られる |
| 起動タイプ | **AWS Fargate** | |
| オペレーティングシステム | Linux/X86_64 | ARMを選ぶとコストを抑えられるが、Dockerイメージがarm64対応している必要がある |
| CPU | 0.5 vCPU（512） | 最小は0.25 vCPU。バックエンドの負荷に応じて調整。最初は小さく始めてCloudWatchを見て増やす |
| メモリ | 1 GB（1024） | CPUとメモリには有効な組み合わせがある。512MBでもよいが余裕を持たせる |
| タスクロール | なし | アプリがS3等のAWSサービスを呼ばない限り不要 |
| タスク実行ロール | `ecsTaskExecutionRole` | Task 6で作成。ECRからイメージpullとCloudWatch Logsへの書き込みに必要。これがないとタスクが起動しない |

**コンテナを追加：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| 名前 | `backend` | タスク定義内でのコンテナの識別子 |
| イメージURI | `<アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/backend:latest` | Task 5で作成したECRリポジトリのURI。latestは学習用。本番ではgitハッシュを使う |
| コンテナポート | 3000 / TCP | Node.jsバックエンドのポート |

**環境変数（「環境変数」セクションで追加）：**

| キー | 値 | 判断理由 |
|------|----|---------|
| `DATABASE_URL` | `postgresql://taskflow_admin:<パスワード>@<RDSエンドポイント>:5432/taskflow` | RDSのエンドポイントはTask 3でメモした値 |
| `REDIS_URL` | `redis://<Redisエンドポイント>:6379` | Task 4でメモした値 |
| `NODE_ENV` | `production` | productionモードで依存解決・最適化が変わる |

> **パスワードを環境変数に平文で入れることについて：** コンソール上は見えてしまう。学習環境では許容するが、本番では「シークレット」セクションでAWS Secrets Managerの値を参照させる。Secrets Managerに格納したパスワードがコンテナに安全に注入される。

**ログ収集：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| ログドライバー | awslogs | CloudWatch Logsにコンテナのstdout/stderrを送る。他にFirelens(fluentbit)もあるが学習用にはawslogsで十分 |
| ロググループ | `/ecs/taskflow-backend` | 自動作成される。CloudWatchでこのグループ名でログを検索できる |
| ストリームプレフィックス | `ecs` | ログストリームが `ecs/backend/<タスクID>` という形式になる |

2. **「作成」**

### Step 2: Frontend タスク定義の作成

同様に作成。異なる点のみ記載：

| 項目 | 値 |
|------|----|
| タスク定義ファミリー | `taskflow-frontend` |
| CPU / メモリ | 0.25 vCPU / 512 MB（フロントエンドは軽量） |
| イメージURI | `<アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/taskflow/frontend:latest` |
| コンテナポート | 80 |
| 環境変数 | `REACT_APP_API_URL` = `http://<ALBのDNS名>/api` |
| ロググループ | `/ecs/taskflow-frontend` |

### Step 3: Backend ECS サービスの作成

1. **「ECS」** → **「クラスター」** → `taskflow-cluster` → **「サービス」タブ** → **「作成」**

**環境：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| コンピューティングオプション | 起動タイプ | キャパシティプロバイダーはFargate Spotの割合調整ができるが、まずはシンプルな起動タイプで |
| 起動タイプ | FARGATE | |
| プラットフォームバージョン | LATEST | 特定バージョンにロックする理由がなければLATEST |

**デプロイ設定：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| アプリケーションタイプ | サービス | 「タスク」は1回実行して終わるバッチ処理用。Webサービスは常時稼働の「サービス」 |
| タスク定義 | `taskflow-backend`（最新リビジョン） | |
| サービス名 | `taskflow-backend-svc` | |
| 必要なタスク | 1 | 学習環境では1で十分。本番では2以上（ALBが1台が死んでも継続できるよう） |

**デプロイの失敗検出：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| デプロイの失敗検出 | 有効（推奨） | ヘルスチェックが連続失敗したらデプロイを自動ロールバックする。本番では必須 |

**ネットワーキング：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| VPC | `taskflow-vpc` | |
| サブネット | `taskflow-private-a`、`taskflow-private-c` | コンテナはプライベートサブネットに配置。直接インターネットに公開しない |
| セキュリティグループ | `taskflow-sg-ecs`（defaultを外す） | Task 2で作成 |
| パブリック IP | **オフ** | プライベートサブネットにパブリックIPは不要。NATを経由してアウトバウンドする |

**ロードバランシング：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| ロードバランサーの種類 | Application Load Balancer | |
| ロードバランサー | `taskflow-alb` | Task 7で作成 |
| コンテナ | `backend 3000:3000` | タスク定義で定義したコンテナのポートと一致させる |
| リスナー | 既存を使用 → HTTP:80 | Task 7で作成済み |
| ターゲットグループ | 既存を使用 → `taskflow-tg-backend` | |

**サービスの自動スケーリング：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| サービスの自動スケーリング | 設定しない | 学習環境では不要。本番ではCPU使用率ベースのターゲット追跡を設定 |

2. **「作成」**

### Step 4: Frontend ECS サービスの作成

同様に作成。異なる点のみ：

| 項目 | 値 |
|------|----|
| タスク定義 | `taskflow-frontend` |
| サービス名 | `taskflow-frontend-svc` |
| ターゲットグループ | `taskflow-tg-frontend` |

---

## 確認ポイント

1. 各サービスの「最後のステータス」が **「RUNNING」** になっているか（数分待つ）
2. タスクのステータスが `RUNNING` か `STOPPED`（STOPPEDの場合はログを確認）
3. ALBのDNS名をブラウザで開いてフロントエンドが表示されるか
4. `<ALBのDNS>/api/health` にアクセスして `{"status":"ok"}` が返るか

**タスクが起動しない場合の調査：**

ECS → クラスター → サービス → タスク → 停止したタスクをクリック → **「ログ」タブ** でエラー内容を確認する。

よくある原因：
- ECRのイメージがpushされていない（imageが存在しないためpull失敗）
- `ecsTaskExecutionRole` が設定されていない
- セキュリティグループがECSからRDS/Redisへの通信を許可していない
- 環境変数（DATABASE_URL等）のエンドポイントが間違っている

---

**このタスクをコンソールで完了したら:** [Task 8: ECSサービス（IaC版）](../iac/08_ecs_services.md)

**次のタスク:** [Task 9: Cognito 認証設定](09_cognito.md)
