#!/bin/bash
# 编译并打包「桌面奶蛙.app」。加参数 install 会顺便装进 ~/Applications。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/桌面奶蛙.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 同时编译 Apple 芯片和 Intel 版本，合成一个通用程序
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/main.swift -o "build/DesktopNaiwa-$arch"
done
lipo -create build/DesktopNaiwa-arm64 build/DesktopNaiwa-x86_64 -output "$APP/Contents/MacOS/DesktopNaiwa"
rm build/DesktopNaiwa-*

cp Resources/Info.plist "$APP/Contents/"
cp Resources/spritesheet.webp Resources/奶蛙素材授权-MIT.txt "$APP/Contents/Resources/"
cp 使用说明.md "$APP/Contents/Resources/"

swift Tools/make_icon.swift Resources/spritesheet.webp build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

codesign --force --deep --sign - "$APP"
echo "打包完成：$APP"

if [ "${1:-}" = "install" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x DesktopNaiwa 2>/dev/null || true
  rm -rf "$HOME/Applications/桌面奶蛙.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "已安装到 ~/Applications/桌面奶蛙.app"
fi
