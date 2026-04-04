# --- ビルドステージ ---
FROM node:20-alpine AS builder

WORKDIR /app

# 依存関係を先にコピー（レイヤーキャッシュ最適化）
COPY package.json ./
RUN npm install

# アプリケーションコードをコピーしてビルド
COPY . .
RUN npm run build

# --- 本番ステージ ---
FROM nginx:1.25-alpine

# ビルド成果物をNginxの公開ディレクトリにコピー
COPY --from=builder /app/build /usr/share/nginx/html

# SPAルーティング対応のNginx設定を上書き
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
