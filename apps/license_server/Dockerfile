# Build from the REPOSITORY ROOT (the server depends on packages/engines/license):
#   docker build -f apps/license_server/Dockerfile -t idsnap-license .
FROM dart:stable AS build
WORKDIR /src
# Only what the server needs: its own package and engine_license, resolved
# as a small standalone project (the full monorepo workspace needs Flutter).
COPY packages/engines/license /src/packages/engines/license
COPY apps/license_server /src/apps/license_server
RUN sed -i '/^resolution: workspace/d' /src/packages/engines/license/pubspec.yaml \
 && sed -i '/^resolution: workspace/d' /src/apps/license_server/pubspec.yaml \
 && rm -f /src/apps/license_server/analysis_options.yaml /src/packages/engines/license/analysis_options.yaml
WORKDIR /src/apps/license_server
# `dart build cli` runs package:sqlite3's build hook, which bundles a
# checksum-verified SQLite next to the executable (bundle/lib).
RUN dart pub get && dart test && dart build cli -t bin/server.dart -o /out

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /data licence \
 && mkdir -p /data && chown licence /data
COPY --from=build /out/bundle /app
USER licence
ENV PORT=8080 DATABASE_PATH=/data/license.db
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]
