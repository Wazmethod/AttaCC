FROM node:22-alpine AS frontend
WORKDIR /src
COPY frontend/package.json ./
RUN npm install
COPY frontend ./
RUN npm run build

FROM node:22-alpine AS backend
RUN apk add --no-cache git ca-certificates
WORKDIR /app
COPY backend/package.json ./
RUN npm install --omit=dev
COPY backend/server.js ./server.js
COPY --from=frontend /src/dist ./public
RUN mkdir -p /data
ENV PUBLIC_DIR=/app/public
EXPOSE 8080
CMD ["node", "server.js"]
