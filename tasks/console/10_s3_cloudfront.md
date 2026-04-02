# Task 10: S3 + CloudFront 設定（コンソール）

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
    class CF,S3 highlight
```

**今回構築する箇所:** S3 + CloudFront - Task10。ReactビルドファイルをS3に配置し、CloudFront + OACでCDN配信する。

---

> 参照ナレッジ: [10_cdn_storage.md](../knowledge/10_cdn_storage.md)

## このタスクのゴール

React フロントエンドをCDN経由で高速配信できる構成を作る。

---

## ハンズオン手順

### Step 1: S3 バケットの作成

1. AWSコンソール → **「S3」** → **「バケットを作成」**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| バケット名 | `taskflow-frontend-<アカウントID>` | バケット名はAWS全体でグローバルに一意。アカウントIDを含めると重複しにくい |
| リージョン | ap-northeast-1 | CloudFrontは全世界配信なので、バケット自体のリージョンはどこでも良いが、ALBと同リージョンで揃える |
| オブジェクト所有権 | **ACL無効（推奨）** | ACLは古い権限管理方式。バケットポリシーで管理する現在の推奨方式を使う |
| パブリックアクセスのブロック | **すべてブロック** | CloudFront + OACでのみアクセスさせる。S3を直接公開しない |
| バケットのバージョニング | 無効 | 静的ファイルは常に最新をデプロイするため旧バージョン管理は不要。有効にするとストレージコストが増える |
| デフォルトの暗号化 | SSE-S3（デフォルト） | 特別なコンプライアンス要件がなければSSE-S3で十分。SSE-KMSは独自キー管理が必要でコストも高い |

2. **「バケットを作成」**

> **静的ウェブサイトホスティングを有効にしない理由：** 有効にするとS3のウェブサイトエンドポイントが公開される。CloudFront + OACを使う構成ではこのエンドポイントは不要で、OACが使えなくなるためむしろ有効にしてはいけない。

### Step 2: CloudFront ディストリビューションの作成

> 図: CloudFront + S3のOAC設定（エッジロケーション → CloudFront → OAC → S3）

```mermaid
graph LR
    User["🌐 ユーザー\n(東京・NY・ロンドン等)"]

    subgraph EdgeLocations["CloudFront エッジロケーション (世界各地)"]
        Edge1["東京 POP\nキャッシュあり"]
        Edge2["NY POP\nキャッシュあり"]
    end

    subgraph AWS["AWS ap-northeast-1"]
        CF["CloudFront Distribution\nxxxxx.cloudfront.net\nHTTPS終端・キャッシュ制御"]
        OAC["OAC\n(Origin Access Control)\nSigV4署名付きリクエスト"]
        S3["S3 Bucket\ntaskflow-frontend-xxx\nパブリックアクセス: 全ブロック"]
        BucketPolicy["Bucket Policy\nCloudFrontのみ許可\n(DistributionID指定)"]
    end

    User -->|"HTTPS"| Edge1
    User -->|"HTTPS"| Edge2
    Edge1 -->|"キャッシュミス時"| CF
    Edge2 -->|"キャッシュミス時"| CF
    CF --> OAC
    OAC -->|"署名付きリクエスト"| S3
    BucketPolicy -.->|"アクセス制御"| S3

    Note1["❌ S3直接アクセス\n→ 403 Access Denied"]
    User -.->|"ブロック"| Note1
```

1. AWSコンソール → **「CloudFront」** → **「ディストリビューションを作成」**

**オリジン：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| オリジンドメイン | S3バケットを選択（`.s3.amazonaws.com` 形式） | 静的ウェブサイトホスティングのエンドポイントではなくS3 REST APIエンドポイントを使う（OACのため） |
| オリジンアクセス | **Origin access control settings (recommended)** | OACを使ってCloudFrontだけがS3にアクセスできるよう制限する |
| コントロール設定 | **「コントロール設定を作成」** → 名前: `taskflow-oac` → 署名: SigV4 → 作成 | 新しい認証方式（OACはOAIより新しく推奨される方式） |

**デフォルトキャッシュビヘイビア：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| ビューワープロトコルポリシー | **Redirect HTTP to HTTPS** | HTTPアクセスをHTTPSにリダイレクト。ユーザーのブックマークがHTTPでも安全に誘導できる |
| 許可されたHTTPメソッド | GET, HEAD | 静的ファイルは読み取りのみ。POST等を許可する必要はない |
| キャッシュポリシー | **CachingOptimized** | JS/CSS/画像に対して最適なキャッシュ設定（TTL最大1年）。変更時はファイル名が変わるので古いキャッシュが返ることはない |
| オリジンリクエストポリシー | **設定しない（なし）** | S3への転送時に余分なヘッダーを付ける必要はない |

**ファンクションの関連付け：** 設定なし（今回はエッジ処理不要）

**設定：**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| デフォルトルートオブジェクト | `index.html` | ルートURL（`/`）アクセス時に返すファイル |
| 代替ドメイン名 | 設定しない | 独自ドメインを使う場合は設定。今回は `*.cloudfront.net` のドメインを使う |
| カスタムSSL証明書 | 設定しない | 独自ドメインなしなら不要 |
| 標準ログ記録 | **有効（推奨）** | アクセスログをS3に保存。問題調査・セキュリティ監査に使う。ログ用バケットは別途作るか後で追加 |
| IPv6 | 有効 | 追加コストなし。IPv6ユーザーにも対応できる |

2. **「ディストリビューションを作成」**

3. 作成後、ページ上部に **「S3 バケットポリシーをコピー」** という通知が表示されるのでクリック

### Step 3: S3 バケットポリシーの設定

1. S3 バケット → **「アクセス許可」タブ** → **「バケットポリシー」** → **「編集」**
2. Step 2でコピーしたポリシーを貼り付けて **「変更を保存」**

ポリシーの内容（参考）：
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::taskflow-frontend-<アカウントID>/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::<アカウントID>:distribution/<DistributionID>"
      }
    }
  }]
}
```

> **ConditionでDistributionIDを指定する理由：** 「CloudFrontサービス」だけを許可すると、他のAWSアカウントのCloudFrontからもS3にアクセスできてしまう。特定のディストリビューションIDを条件に指定することで自分のCloudFrontからのみに絞る。

### Step 4: SPAルーティングのエラーページ設定

1. CloudFront ディストリビューション → **「エラーページ」タブ** → **「カスタムエラーレスポンスを作成」**

| 項目 | 値 | 判断理由 |
|------|----|---------|
| HTTPエラーコード | 403 | S3はオブジェクトが存在しない場合403を返す（パブリックアクセスブロック有効時） |
| エラーキャッシュの最小 TTL | 0 | エラーをキャッシュしないようにする |
| レスポンスページのパス | `/index.html` | SPAのルーター（React Router等）に処理させる |
| HTTPレスポンスコード | 200 | ブラウザには200として返す（404ではなく） |

同様に **HTTPエラーコード: 404** も同じ設定で追加する。

> **なぜ403と404の両方を設定するか：** S3は「オブジェクトが存在しない」場合に404を返すが、パブリックアクセスブロックが有効な場合は403を返すこともある。両方設定しておくことでどちらのケースも対応できる。

### Step 5: フロントエンドのビルドとアップロード

ローカルでReactアプリをビルドしてS3にアップロードする：

```bash
# ビルド
npm run build

# S3にアップロード（--deleteで古いファイルを削除）
aws s3 sync build/ s3://taskflow-frontend-<アカウントID>/ --delete
```

---

## 確認ポイント

1. CloudFront のステータスが **「Deployed」** になっているか（最大15分かかる）
2. **ディストリビューションドメイン名** (`xxxxx.cloudfront.net`) をブラウザで開いてサイトが表示されるか
3. S3バケットのURL（`https://taskflow-frontend-xxx.s3.ap-northeast-1.amazonaws.com/index.html`）を直接開いて **「Access Denied」** になるか（OACが正しく設定されている証拠）
4. `/tasks/any-path` のような深いURLを直接開いても404にならずアプリが表示されるか（エラーページ設定の確認）

---

**このタスクをコンソールで完了したら:** [Task 10: S3 + CloudFront（IaC版）](../iac/10_s3_cloudfront.md)

**次のタスク:** [Task 11: GitHub Actions CI/CD](11_cicd.md)
