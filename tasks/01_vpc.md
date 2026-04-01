# Task 1: VPC・サブネット・ゲートウェイ構築

## このタスクのゴール

TaskFlowアプリの全リソースを配置する **ネットワーク基盤** を作る。
完成すると、以下が揃う：

- VPC（仮想ネットワーク）1つ
- パブリックサブネット 2つ（ALBを置く場所）
- プライベートサブネット 2つ（ECS・RDS を置く場所）
- インターネットゲートウェイ（外部との出入口）
- NAT Gateway（プライベートサブネットから外に出るための中継）
- ルートテーブル（通信経路の設定）

---

## 背景知識

### VPC とは？

**Virtual Private Cloud** — AWS上に作る「自分専用のネットワーク」。

> 例え: VPC は「自社ビル」。外の道路（インターネット）とは壁で仕切られていて、出入口（ゲートウェイ）を自分で設計する。

### サブネットとは？

VPC の中をさらに区切った小部屋。**パブリック**（外部アクセス可）と**プライベート**（外部アクセス不可）に分ける。

| 種類 | 用途 | 外からアクセス |
|------|------|---------------|
| パブリック | ALB, NAT Gateway | できる |
| プライベート | ECS, RDS, Redis | できない（セキュア） |

### なぜ 2つずつ？

AWSのベストプラクティスで、異なる**アベイラビリティゾーン（AZ）**に配置することで、1つのデータセンターが障害を起こしても別のAZで動き続ける（**高可用性**）。

### インターネットゲートウェイ (IGW) とは？

VPC とインターネットを繋ぐ出入口。パブリックサブネットに紐づける。

### NAT Gateway とは？

プライベートサブネットのリソースが「外に出る」ための中継地点。外からプライベートに入ることはできない（一方通行）。

> 例え: 社内のPCからインターネットは見れるけど、外から社内PCに直接アクセスはできない仕組み。

### ルートテーブルとは？

「この宛先の通信はここを通れ」という経路表。サブネットごとに設定する。

---

## アーキテクチャ上の位置づけ

```
┌─────────────────── VPC (10.0.0.0/16) ───────────────────┐
│                                                          │
│  ┌── Public Subnet (AZ-a) ──┐  ┌── Public Subnet (AZ-c) ──┐
│  │  ALB, NAT Gateway        │  │  ALB                      │
│  └──────────────────────────┘  └────────────────────────────┘
│                                                          │
│  ┌── Private Subnet (AZ-a) ─┐  ┌── Private Subnet (AZ-c) ─┐
│  │  ECS, RDS, Redis         │  │  ECS, RDS (standby)       │
│  └──────────────────────────┘  └────────────────────────────┘
│                                                          │
└──────────────────────────────────────────────────────────┘
         │
    [Internet Gateway] ── インターネット
```

**Task 1 で作るのはこの「箱」全体。** 中身のリソースは Task 2 以降で配置する。

---

## ハンズオン手順

### Step 1: Terraform プロジェクト初期化

```bash
mkdir -p infra/environments/dev
cd infra/environments/dev
```

`main.tf` を作成：

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"  # 東京リージョン
}
```

### Step 2: VPC の作成

```hcl
# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"    # IPアドレスの範囲（65,536個）
  enable_dns_support   = true              # VPC内でDNS解決を有効化
  enable_dns_hostnames = true              # リソースにDNSホスト名を付与

  tags = {
    Name = "taskflow-vpc"
  }
}
```

**パラメータ解説:**
- `cidr_block`: VPC内で使えるIPの範囲。`/16` は約65,000個のIP
- `enable_dns_support`: VPC内でドメイン名→IPアドレスの解決を有効にする
- `enable_dns_hostnames`: EC2等にDNS名を自動付与（RDS接続などに必要）

### Step 3: サブネットの作成

```hcl
# --- パブリックサブネット ---
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"     # 256個のIP
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true               # 起動時にパブリックIP付与

  tags = { Name = "taskflow-public-a" }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = { Name = "taskflow-public-c" }
}

# --- プライベートサブネット ---
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"

  tags = { Name = "taskflow-private-a" }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-northeast-1c"

  tags = { Name = "taskflow-private-c" }
}
```

**ポイント:** パブリックは `10.0.1-2.x`、プライベートは `10.0.10-11.x` と分かりやすく分ける。

### Step 4: インターネットゲートウェイ

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "taskflow-igw" }
}
```

### Step 5: NAT Gateway

```hcl
# NAT Gateway には Elastic IP（固定IP）が必要
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "taskflow-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id  # パブリックサブネットに配置

  tags = { Name = "taskflow-nat" }
}
```

**注意:** NAT Gateway は有料リソース。開発中は使わないときに削除してコスト節約を。

### Step 6: ルートテーブル

```hcl
# --- パブリック用ルートテーブル ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"              # 全ての宛先
    gateway_id = aws_internet_gateway.main.id  # → IGW経由でインターネットへ
  }

  tags = { Name = "taskflow-public-rt" }
}

# パブリックサブネットに紐づけ
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# --- プライベート用ルートテーブル ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id  # → NAT経由で外へ
  }

  tags = { Name = "taskflow-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}
```

### Step 7: 実行

```bash
terraform init    # プロバイダーのダウンロード
terraform plan    # 変更内容のプレビュー
terraform apply   # 実際に作成（yes と入力）
```

---

## 確認ポイント

1. **AWSコンソール → VPC** で `taskflow-vpc` が表示されるか
2. **サブネット一覧** でパブリック2つ・プライベート2つが存在するか
3. **ルートテーブル** でパブリック→IGW、プライベート→NATの経路があるか
4. `terraform output` でVPC IDが出力されるか（output を定義している場合）

---

## よくあるエラーと対処法

| エラー | 原因 | 対処 |
|--------|------|------|
| `Error: CIDR block conflicts` | サブネットのCIDRが重複 | CIDR範囲が被らないように修正 |
| `Error: limit exceeded` | リージョンのVPC上限（デフォルト5） | AWSサポートに上限緩和申請 |
| NAT Gateway作成が遅い | 正常（2-3分かかる） | 待つだけでOK |

---

## 理解度チェック

**Q1.** パブリックサブネットとプライベートサブネットの違いは何か？ルートテーブルの観点で説明せよ。

<details>
<summary>A1</summary>
パブリックサブネットのルートテーブルにはインターネットゲートウェイ(IGW)への経路があり、外部と直接通信できる。プライベートサブネットにはIGWへの経路がなく、外に出るにはNAT Gatewayを経由する（外からの直接アクセスは不可）。
</details>

**Q2.** サブネットを2つのAZに分散させる理由は？

<details>
<summary>A2</summary>
高可用性（High Availability）のため。1つのAZ（データセンター群）に障害が発生しても、別のAZでサービスを継続できる。
</details>

**Q3.** NAT Gateway はなぜパブリックサブネットに配置するのか？

<details>
<summary>A3</summary>
NAT Gateway自体がインターネットと通信する必要があるため、IGWへの経路を持つパブリックサブネットに配置する。プライベートサブネットのリソースは、NAT Gatewayを経由して間接的にインターネットにアクセスする。
</details>

---

**次のタスク:** [Task 2: セキュリティグループ設定](02_security_groups.md) → この VPC 内の通信ルールを設定する
