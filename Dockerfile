# API only. Build from repository root.
FROM dart:3.13.5-sdk AS build
WORKDIR /src
COPY packages ./packages
COPY server/pubspec.yaml server/pubspec.lock ./server/
WORKDIR /src/server
RUN dart pub get --enforce-lockfile
COPY server .
RUN mkdir -p /out && dart compile exe bin/server.dart -o /out/server && dart compile exe bin/import_sqlite.dart -o /out/import_sqlite
# Match the build stage's C runtime; avoid a glibc mismatch across Debian releases.
FROM dart:3.13.5-sdk
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/ /app/
ENV PORT=5200 DATA_DIR=/app/data
EXPOSE 5200
CMD ["/app/server"]
