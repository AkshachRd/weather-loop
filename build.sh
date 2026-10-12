#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/.build"
app_dir="$script_dir/WeatherLoop.app"

mkdir -p "$build_dir" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

compile() {
  local output="$1"
  shift

  swiftc "$@" "$script_dir/WeatherLoop.swift" \
    -parse-as-library \
    -o "$output" \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreLocation
}

if [[ "${WEATHERLOOP_UNIVERSAL:-0}" == "1" ]]; then
  compile "$build_dir/WeatherLoop-arm64" -target arm64-apple-macos14.0
  compile "$build_dir/WeatherLoop-x86_64" -target x86_64-apple-macos14.0
  lipo -create \
    "$build_dir/WeatherLoop-arm64" \
    "$build_dir/WeatherLoop-x86_64" \
    -output "$build_dir/WeatherLoop"
else
  compile "$build_dir/WeatherLoop"
fi

cp "$build_dir/WeatherLoop" "$app_dir/Contents/MacOS/WeatherLoop"
cp "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"

if [[ -n "${WEATHERLOOP_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${WEATHERLOOP_VERSION}" \
    "$app_dir/Contents/Info.plist"
fi

if [[ -n "${WEATHERLOOP_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion ${WEATHERLOOP_BUILD}" \
    "$app_dir/Contents/Info.plist"
fi

echo "Готово: $app_dir"
