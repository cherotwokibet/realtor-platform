# The video transcoder, a Cloud Run job (D15). Build from functions/:
#   docker build -f transcode.Dockerfile -t <repo>/transcode-video:<tag> .
# ffmpeg comes from Debian's signed packages, not a downloaded binary.
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src src
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/package.json package.json
COPY --from=build /app/node_modules node_modules
COPY --from=build /app/lib lib
USER node
CMD ["node", "lib/jobs/transcode-video.js"]
