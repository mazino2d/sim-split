# sim-split telemetry endpoint (R-4) on Cloud Run. Node 24 runs the TypeScript
# sources directly (type stripping), so there is no build step.
FROM node:26-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY src ./src
USER node
CMD ["node", "src/server.ts"]
