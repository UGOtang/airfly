# AirFly relay —— x86 云服务器镜像
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY bin ./bin
RUN dart compile exe bin/server.dart -o /airfly-server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /srv/airfly
COPY --from=build /airfly-server ./airfly-server
VOLUME ["/srv/airfly/data"]
ENV HOST=0.0.0.0 PORT=8080 DATA_DIR=/srv/airfly/data
EXPOSE 8080
# 健康检查依赖 /healthz；如需启用可安装 curl 后解开下一行
# HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["./airfly-server"]
