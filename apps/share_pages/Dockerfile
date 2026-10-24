# Share pages image for Cloud Run. Build from the repo root:
#   docker build -f apps/share_pages/Dockerfile --build-arg TENANT=<id> -t share-pages .
ARG DART_VERSION=3.13.7

FROM dart:${DART_VERSION} AS build
WORKDIR /src
COPY apps/share_pages/docker/pubspec.yaml pubspec.yaml
COPY packages/core packages/core
COPY packages/tokens packages/tokens
COPY apps/share_pages apps/share_pages
RUN dart pub get
RUN mkdir -p /out && dart compile exe apps/share_pages/bin/server.dart -o /out/server

FROM scratch
ARG TENANT
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
COPY tenants/${TENANT}.json /app/tenant.json
ENV TENANT_FILE=/app/tenant.json
EXPOSE 8080
USER 65532
ENTRYPOINT ["/app/server"]
