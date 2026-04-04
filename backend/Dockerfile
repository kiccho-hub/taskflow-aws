FROM node:20-alpine

WORKDIR /app

# 依存関係を先にコピー（レイヤーキャッシュ最適化）
COPY package.json ./
RUN npm install --omit=dev

# アプリケーションコードをコピー
COPY src/ ./src/

EXPOSE 3000

CMD ["node", "src/index.js"]
