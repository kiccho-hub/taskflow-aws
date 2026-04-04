import React, { useState, useEffect } from 'react';

// バックエンドAPIのベースURL
// 本番ではALB経由（/api/tasks）、ローカルでは環境変数で上書き可能
const API_BASE = import.meta.env.VITE_API_URL || '';

const STATUS_LABEL = {
  completed: { text: '完了', color: '#4CAF50' },
  in_progress: { text: '進行中', color: '#2196F3' },
  todo: { text: '未着手', color: '#9E9E9E' },
};

export default function App() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch(`${API_BASE}/api/tasks`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        setTasks(data.tasks);
        setLoading(false);
      })
      .catch((err) => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>TaskFlow</h1>
        <p style={styles.subtitle}>AWS インフラ学習プロジェクト</p>
      </header>

      <main style={styles.main}>
        {loading && <p style={styles.message}>読み込み中...</p>}
        {error && (
          <div style={styles.errorBox}>
            <p>APIへの接続に失敗しました: {error}</p>
            <p style={{ fontSize: '0.85em', marginTop: 8 }}>
              バックエンドが起動しているか確認してください（GET /api/tasks）
            </p>
          </div>
        )}
        {!loading && !error && (
          <>
            <h2 style={styles.sectionTitle}>タスク一覧</h2>
            <div style={styles.taskList}>
              {tasks.map((task) => {
                const status = STATUS_LABEL[task.status] || { text: task.status, color: '#666' };
                return (
                  <div key={task.id} style={styles.taskCard}>
                    <div style={styles.taskHeader}>
                      <span style={styles.taskId}>#{task.id}</span>
                      <span style={{ ...styles.badge, background: status.color }}>
                        {status.text}
                      </span>
                    </div>
                    <h3 style={styles.taskTitle}>{task.title}</h3>
                    <p style={styles.taskDesc}>{task.description}</p>
                  </div>
                );
              })}
            </div>
          </>
        )}
      </main>

      <footer style={styles.footer}>
        <p>TaskFlow — AWS Infrastructure Learning Project</p>
      </footer>
    </div>
  );
}

const styles = {
  container: {
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
  },
  header: {
    background: '#232F3E',
    color: '#fff',
    padding: '24px 32px',
  },
  title: {
    fontSize: '1.8rem',
    fontWeight: 700,
  },
  subtitle: {
    marginTop: 4,
    fontSize: '0.9rem',
    color: '#FF9900',
  },
  main: {
    flex: 1,
    maxWidth: 800,
    width: '100%',
    margin: '0 auto',
    padding: '32px 16px',
  },
  sectionTitle: {
    fontSize: '1.2rem',
    marginBottom: 16,
    color: '#555',
  },
  taskList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  taskCard: {
    background: '#fff',
    borderRadius: 8,
    padding: '16px 20px',
    boxShadow: '0 1px 4px rgba(0,0,0,0.1)',
  },
  taskHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  taskId: {
    fontSize: '0.85rem',
    color: '#999',
  },
  badge: {
    color: '#fff',
    padding: '2px 10px',
    borderRadius: 12,
    fontSize: '0.8rem',
    fontWeight: 600,
  },
  taskTitle: {
    fontSize: '1rem',
    fontWeight: 600,
    marginBottom: 4,
  },
  taskDesc: {
    fontSize: '0.9rem',
    color: '#666',
  },
  message: {
    textAlign: 'center',
    color: '#999',
    padding: 40,
  },
  errorBox: {
    background: '#fff3cd',
    border: '1px solid #ffc107',
    borderRadius: 8,
    padding: '16px 20px',
    color: '#856404',
  },
  footer: {
    background: '#232F3E',
    color: '#aaa',
    textAlign: 'center',
    padding: '16px',
    fontSize: '0.85rem',
  },
};
