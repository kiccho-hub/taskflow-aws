const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// ALBヘルスチェック用エンドポイント
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

// モックタスク一覧
const mockTasks = [
  {
    id: 1,
    title: 'VPCを構築する',
    description: 'サブネット・IGW・NATGWを含むVPCを作成する',
    status: 'completed',
    createdAt: '2026-04-01T09:00:00Z',
  },
  {
    id: 2,
    title: 'セキュリティグループを設定する',
    description: 'ALB・ECS・RDS・ElastiCache用のSGを作成する',
    status: 'completed',
    createdAt: '2026-04-01T10:00:00Z',
  },
  {
    id: 3,
    title: 'RDSを構築する',
    description: 'PostgreSQL 16のDBインスタンスを作成する',
    status: 'completed',
    createdAt: '2026-04-01T11:00:00Z',
  },
  {
    id: 4,
    title: 'ElastiCacheを構築する',
    description: 'Valkey 8.xのキャッシュクラスターを作成する',
    status: 'in_progress',
    createdAt: '2026-04-02T09:00:00Z',
  },
  {
    id: 5,
    title: 'S3+CloudFrontを設定する',
    description: 'OACを使ったCDN配信構成を構築する',
    status: 'todo',
    createdAt: '2026-04-02T10:00:00Z',
  },
];

// タスク一覧取得
app.get('/api/tasks', (req, res) => {
  res.json({ tasks: mockTasks });
});

// タスク詳細取得
app.get('/api/tasks/:id', (req, res) => {
  const task = mockTasks.find((t) => t.id === parseInt(req.params.id));
  if (!task) {
    return res.status(404).json({ error: 'Task not found' });
  }
  res.json({ task });
});

app.listen(PORT, () => {
  console.log(`TaskFlow backend running on port ${PORT}`);
});
