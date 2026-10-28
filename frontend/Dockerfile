ARG FLUTTER_VERSION=3.47.7
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /flutter
ENV PATH=/flutter/bin:$PATH
RUN flutter config --no-analytics && flutter precache --web
WORKDIR /src
COPY packages ./packages
COPY frontend/pubspec.yaml frontend/pubspec.lock ./frontend/
WORKDIR /src/frontend
RUN flutter pub get --enforce-lockfile
COPY frontend .
ARG API_BASE_URL=
RUN flutter build web --release --no-web-resources-cdn \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=BUILD_TIME="$(date -u +%Y-%m-%d\ %H:%M) UTC"
FROM nginx:stable-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/frontend/build/web /usr/share/nginx/html
EXPOSE 80
