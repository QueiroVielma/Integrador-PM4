# Imagem base com tag fixa (nada de "latest")
FROM node:20.18.1-alpine

WORKDIR /app

# Instala so as dependencias de producao, exatamente como no package-lock
COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
USER node
EXPOSE 5000

# O Docker marca o container como "unhealthy" se a API perder o banco
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:5000/health || exit 1

CMD ["node", "index.js"]
