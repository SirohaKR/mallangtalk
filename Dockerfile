# [초보자 노트] 말랑톡을 컨테이너 하나로 묶는 설정이에요. `docker compose up -d --build`로 켜요.
# 1) Flutter로 앱 화면(웹)과 Dart 서버 실행 파일을 빌드 → 2) 둘만 담아서 실행
# Flutter 버전은 개발에 쓴 것과 같게 맞춰요 (pubspec.lock이 이 버전 이상을 요구함)
ARG FLUTTER_VERSION=3.47.7

FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /flutter
ENV PATH=/flutter/bin:$PATH
RUN flutter config --no-analytics && flutter precache --web

WORKDIR /src
# 패키지 목록만 먼저 받아 두면, 코드만 바뀌었을 때 다시 받지 않아 빌드가 빨라요
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
COPY server/pubspec.yaml server/pubspec.lock ./server/
RUN flutter pub get && cd server && dart pub get
COPY . .
RUN flutter build web --release --no-web-resources-cdn
RUN cd server && dart compile exe bin/server.dart -o /out/server

FROM debian:bookworm-slim
# AI 회사 API(https)를 부르려면 인증서 목록이, 유저·캐릭터 DB에는 SQLite가 필요해요
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/server /app/server
COPY --from=build /src/build/web /app/web
ENV WEB_DIR=/app/web PORT=5200 DATA_DIR=/app/data
EXPOSE 5200
CMD ["/app/server"]
