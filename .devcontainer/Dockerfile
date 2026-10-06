# Dev container for GitHub Codespaces (and VS Code "Reopen in Container").
# Covers what CI runs on every PR plus the web app: Flutter, the Dart tools,
# and (via features in devcontainer.json) Java + Node for the Firestore
# rules tests. No Android SDK or Xcode: build mobile apps on a local machine.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Keep in step with flutter-version in .github/actions/flutter-setup/action.yml.
ARG FLUTTER_VERSION=3.47.6

# Packages Flutter needs on Linux (git, unzip, xz) and for web builds (curl).
RUN apt-get update \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get install -y --no-install-recommends curl git unzip xz-utils zip \
  && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
  && chown -R vscode:vscode "${FLUTTER_HOME}"

USER vscode
RUN flutter config --no-analytics --enable-web \
  && dart --disable-analytics \
  && flutter precache --web --no-android --no-ios
