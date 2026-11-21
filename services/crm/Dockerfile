# sim-split crm service (R-9) on Cloud Run. Node 26 runs the TypeScript sources
# directly. config.json is compiled from crm/ by crm_deploy.yml before the build
# (`node src/cli.ts compile`), so each image carries exactly one config commit.
FROM node:26-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY src ./src
COPY config.json ./config.json
USER node
CMD ["node", "src/server.ts"]
