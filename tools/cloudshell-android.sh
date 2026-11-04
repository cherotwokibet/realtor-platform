#!/usr/bin/env bash
# Android SDK for Cloud Shell, which has none: needed for phone builds with
# live Firebase settings and for `tenant release` (docs/android-build.md).
#
#   source tools/cloudshell-android.sh
#
# Installs into /tmp (not the 5 GB home quota), so run it again in each new
# Cloud Shell session; it takes about 5 minutes and skips what is there.
# The platform, build tools and NDK versions are the ones your Flutter uses.

_android_setup() {
  set -euo pipefail
  local sdk=${ANDROID_HOME:-/tmp/android-sdk}
  local flutter_bin flutter_root ext compile_sdk ndk zip tmp
  flutter_bin=$(command -v flutter) || { echo "✗ flutter is not on PATH" >&2; return 1; }
  flutter_root=$(dirname "$(dirname "$(readlink -f "$flutter_bin")")")
  ext="$flutter_root/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
  compile_sdk=$(sed -n 's/.*val compileSdkVersion: Int = \([0-9]*\).*/\1/p' "$ext" | head -1)
  ndk=$(sed -n 's/.*val ndkVersion: String = "\([0-9.]*\)".*/\1/p' "$ext" | head -1)
  [ -n "$compile_sdk" ] && [ -n "$ndk" ] || { echo "✗ could not read the SDK and NDK versions from $ext" >&2; return 1; }

  if [ ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "▶ Android command-line tools → $sdk"
    zip=$(curl -fsS https://dl.google.com/android/repository/repository2-3.xml \
      | grep -o 'commandlinetools-linux-[0-9]*_latest.zip' | sort -uV | tail -1 || true)
    zip=${zip:-commandlinetools-linux-13114758_latest.zip}
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/tools.zip" "https://dl.google.com/android/repository/$zip"
    unzip -q "$tmp/tools.zip" -d "$tmp"
    mkdir -p "$sdk/cmdline-tools"
    rm -rf "$sdk/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$sdk/cmdline-tools/latest"
    rm -rf "$tmp"
  fi

  local sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
  echo "▶ Licences, platform android-$compile_sdk, build tools and NDK $ndk"
  yes | "$sdkmanager" --sdk_root="$sdk" --licenses >/dev/null || true
  "$sdkmanager" --sdk_root="$sdk" "platform-tools" "platforms;android-$compile_sdk" "build-tools;$compile_sdk.0.0" "ndk;$ndk" >/dev/null

  export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
  # Gradle's cache is large: keep it out of the home quota too.
  export GRADLE_USER_HOME=${GRADLE_USER_HOME:-/tmp/gradle}
  flutter config --android-sdk "$sdk" >/dev/null
  echo "✓ Android SDK ready in $sdk (this session only)"
}

# Sourced: run the setup in a subshell (so `set -e` can't close this shell),
# then keep the exports here. `flutter config` is saved for later shells.
if (return 0 2>/dev/null); then
  if ( _android_setup ); then
    export ANDROID_HOME=${ANDROID_HOME:-/tmp/android-sdk}
    export ANDROID_SDK_ROOT=$ANDROID_HOME GRADLE_USER_HOME=${GRADLE_USER_HOME:-/tmp/gradle}
  fi
else
  _android_setup
  echo "Run it with 'source' to keep ANDROID_HOME in this shell."
fi
