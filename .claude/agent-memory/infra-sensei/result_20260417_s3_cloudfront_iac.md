---
name: 2026/04/17 Task 10 S3+CloudFront IaC A評価
description: Task 10のIaCフェーズ成績記録（S3+CloudFront+ALBパスルーティング）
type: project
---

# Task 10: S3 + CloudFront IaC 成績表

【タスク名】S3 + CloudFront CDN配信基盤の構築
【フェーズ】IaC（Terraform）
【実施日】2026/04/17

## 総合評価：A 87点/100点

## 習熟度評価

- 理解度           ：★★★★★
- 正確性           ：★★★★☆
- ベストプラクティス：★★★★☆
- 問題解決力       ：★★★★★

## 得意だったこと（Keep）

- 課題のS3単体CloudFront配信を完了したうえで、ALBを第2OriginとしてパスベースルーティングまでTerraformに自主的に落とし込んだ
- OAC + SigV4の仕組みを正確に理解・実装（aws_s3_bucket_policy の Condition + SourceArn まで完璧）
- /api/* に Managed-CachingDisabled + AllViewerを選択し、APIキャッシュの罠を回避
- custom_error_response の「Distribution全体に適用される」という落とし穴に気づき、CloudFront Functionsによる解決策まで発想できた
- exec format error（ARM64/x86_64不一致）・ECRイミュータブル・Dockerキャッシュ・terraform output dir間違いなど複数の異なる問題を自力で解決

## 改善ポイント（Try）

- ファイル名タイポ（s3_cloulfront.tf → s3_cloudfront.tf が正しい）
- terraform output 実行前の作業ディレクトリ確認（pwd 徹底）が繰り返しの課題
- ECR MUTABLE変更の理由をコード内コメントに残す習慣

## 今日の学習ポイント

- CloudFront 多Origin設計（S3 + ALB）とパスベースルーティング
- OAC + SigV4 によるS3保護の実装パターン
- custom_error_response のDistribution全体適用という挙動
- CloudFront Functions（viewer-request）によるURL書き換えの発想
- JWT検証（JWKSエンドポイント → 公開鍵 → RS256署名検証）フロー
- Cognitoクライアント種別（SPA = generate_secret=false）
- exec format error = CPUアーキテクチャ不一致デバッグパターン

## 要注意ポイント（苦手分野）

- ファイル名・リソース名のタイポ確認（作成直後の目視確認の習慣化）
- terraform コマンド実行前の作業ディレクトリ確認
- ECR タグ運用（MUTABLE/IMMUTABLEの使い分けと理由の言語化）
