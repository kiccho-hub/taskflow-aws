---
name: grade-report
description: タスク完了時に習熟度を評価し、成績表をチャットに表示してファイルに保存し、自動コミットするスキル。「完了した」「できた」「終わった」などタスク完了を示す発言があったとき自動適用。
user-invocable: false
allowed-tools: Read, Write, Bash
---

ユーザーがタスク完了を示したとき（「完了しました」「できました」「終わりました」「できた」「終わった」など）に、以下の手順で成績表を発行してください。

## Step 1: チャットに成績表を表示する

会話の内容から習熟度を評価し、以下の形式で成績表を出力してください：

```
📊 ===== 今回の学習成績表 ===== 📊

【タスク名】〇〇の構築
【フェーズ】Knowledge / Console / IaC（該当するものを記載）
【実施日】YYYY/MM/DD

🌟 総合評価：[S/A/B/C/D] 〇〇点/100点

📈 習熟度評価
┌─────────────────────────┐
│ 理解度     ：★★★☆☆    │
│ 正確性     ：★★★★☆    │
│ ベストプラクティス：★★☆☆☆ │
│ 問題解決力 ：★★★☆☆    │
└─────────────────────────┘

✅ 得意だったこと（Keep）
- [具体的に褒める点]
- [もう一つの良い点]

🔧 改善ポイント（Try）
- [改善すべき点と理由]
- [次回気をつけること]

📚 今日の学習ポイント
- [習得できた概念や技術]
- [理解が深まったこと]

⚠️ 要注意ポイント（苦手分野）
- [まだ定着していない点]
- [次回重点的に練習すること]

💬 先生からのコメント
[温かく励ますメッセージ。次のステップへの期待と具体的なアドバイス]

🎯 次回の目標
- [次に挑戦すべきこと]
```

評価基準（スコア→スター変換）：
- S（90-100点）= ★★★★★ — ほぼ完璧、ベストプラクティスも押さえている
- A（80-89点）= ★★★★☆ — よくできており、小さな改善点がある
- B（70-79点）= ★★★☆☆ — 概ね正しいが、重要な改善点がある
- C（60-69点）= ★★☆☆☆ — 基本はできているが、見直しが必要
- D（60点未満）= ★☆☆☆☆ — 再学習を推奨

## Step 2: PROGRESS.md の進捗を更新する

`/Users/yuki-mac/claude-code/aws-demo/tasks/PROGRESS.md` を Read で読み込み、該当タスクの該当フェーズのセルをスターに書き換えてください。

**フェーズの判断**：
- ナレッジ記事を読んだ完了報告 → Knowledge 列を `📖` に更新
- AWSコンソール操作の完了報告 → Console 列をスターに更新
- Terraform/IaCコードの完了報告 → IaC 列をスターに更新

**スター記号の対応**：

| 点数 | Console / IaC 列 |
|------|-----------------|
| 90-100 | ★★★★★ |
| 80-89  | ★★★★☆ |
| 70-79  | ★★★☆☆ |
| 60-69  | ★★☆☆☆ |
| ～59   | ★☆☆☆☆ |

例：タスク1のConsoleフェーズでA評価（85点）なら、該当行の Console 列を `★★★★☆` に書き換える。

更新後、変更した行をチャットに表示して確認させてください：
```
📋 進捗を更新しました：
| 1 | VPC・サブネット・ゲートウェイ | ⬜ | ★★★★☆ | ⬜ |
```

## Step 3: 成績をファイルに保存する

以下の場所にファイルを保存してください：

- **保存先**：`/Users/yuki-mac/claude-code/aws-demo/.claude/agent-memory/infra-sensei/`
- **ファイル名**：`result_YYYYMMDD_<タスク名をスネークケースで>_<phase>.md`
  - 例：`result_20260401_vpc_console.md`
- **内容**：チャットに表示した成績表と同一内容

## Step 4: MEMORY.md に記録を追加する

`/Users/yuki-mac/claude-code/aws-demo/.claude/agent-memory/infra-sensei/MEMORY.md` に1行追記してください：

```
- [YYYY/MM/DD タスク名 フェーズ 評価](result_YYYYMMDD_xxx.md) — 総合評価X/100点、苦手：〇〇
```

## Step 5: タスク完了時に自動コミット実行

タスク完了を確認したら、以下の手順で自動コミットを実行してください。

### 実行条件

- **IaC（Terraform）フェーズの完了時のみ** 自動コミットを実行
- Knowledge フェーズ・Console フェーズはコミット対象外

### コミット手順

1. **変更ファイルの確認**
   ```bash
   git status
   ```
   以下のファイルをコミット対象から除外する（agent-memory のため）：
   - `.claude/agent-memory/` 配下のファイル
   - `.claude/skills/` 配下のファイル

2. **コミットメッセージの自動生成**
   
   完了したタスク情報から自動生成します。形式：
   ```
   feat: IaC Task X完了 - [リソース名1]・[リソース名2]実装
   
   【Task X: リソース名】
   - サブリソース1の説明
   - サブリソース2の説明
   - 設計ポイント
   
   【変更内容】
   - infra/environments/dev/[ファイル名1].tf（新規/更新）
   - infra/environments/dev/[ファイル名2].tf（新規/更新）
   - tasks/PROGRESS.md（進捗更新）
   - tasks/iac/XX_xxx.md（セクション追加）
   
   Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
   ```

3. **実行コマンド例**
   ```bash
   cd /Users/yuki-mac/claude-code/aws-demo
   git add infra/environments/dev/*.tf infra/environments/dev/variables.tf infra/environments/dev/outputs.tf tasks/PROGRESS.md tasks/iac/*.md
   git commit -m "feat: IaC Task X完了 - ..."
   ```

4. **コミット完了確認**
   ```bash
   git log --oneline -1
   ```
   最新コミットが正しく記録されたことを確認する

### 自動コミット実装時の注意

- `.gitignore` に含まれるファイル（`terraform.tfvars`, `.tfstate` など）は追加しない
- agent-memory のファイルは コミット対象外（ローカルメモリなため）
- コミットメッセージは日本語で、前のコミットスタイルと統一する
- エラーが発生した場合は、ユーザーに報告し、手動コミットを案内する
