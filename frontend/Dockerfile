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
# BUILD_ID: 앱 안에 넣고 app_build.json에도 적어서, 켜 둔 앱이 새 버전이 올라온 걸 알아채게 함
RUN BUILD_ID="$(date -u +%Y%m%d%H%M%S)" \
    && flutter build web --release --no-web-resources-cdn \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=BUILD_TIME="$(date -u +%Y-%m-%d\ %H:%M) UTC" \
    --dart-define=BUILD_ID="${BUILD_ID}" \
    && printf '{"build":"%s"}\n' "${BUILD_ID}" > build/web/app_build.json
FROM nginx:stable-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/frontend/build/web /usr/share/nginx/html
EXPOSE 80
