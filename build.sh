#!/bin/zsh
set -eu
cd "$(dirname "$0")"
TEST_PURPOSE=""
if (( $# > 0 )); then
 if [[ $# != 2 || "$1" != "--test" || -z "${2//[[:space:]]/}" || ${#2} -gt 40 ]]; then
  print -u2 'Usage: ./build.sh [--test "short test purpose (1–40 characters)"]'
  exit 2
 fi
 TEST_PURPOSE="$2"
fi
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
# The current SwiftBuild backend incorrectly stamps the deployment target as the SDK.
# Build architectures independently with SwiftPM's native backend, then validate both.
for ARCH in arm64 x86_64; do
 swift build -c release --build-system native --sdk "$SDK_PATH" --arch "$ARCH"
done
STAGE=$(mktemp -d .build/package.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/实况工坊.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns/LivePhotoFinder.appex/Contents/MacOS"
ARM_BIN=$(swift build -c release --build-system native --sdk "$SDK_PATH" --arch arm64 --show-bin-path)
INTEL_BIN=$(swift build -c release --build-system native --sdk "$SDK_PATH" --arch x86_64 --show-bin-path)
lipo -create "$ARM_BIN/LivePhotoStudio" "$INTEL_BIN/LivePhotoStudio" -output "$APP/Contents/MacOS/LivePhotoStudio"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Licenses/*.txt "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LivePhotoStudio-MIT.txt"
for ARCH in arm64 x86_64; do
 swiftc FinderExtension/FinderExtension.swift -sdk "$SDK_PATH" -target "$ARCH-apple-macos14.0" -o ".build/LivePhotoFinder-$ARCH" -module-name LivePhotoFinder -framework Cocoa -framework FinderSync -Xlinker -e -Xlinker _NSExtensionMain -parse-as-library
done
lipo -create .build/LivePhotoFinder-arm64 .build/LivePhotoFinder-x86_64 -output "$APP/Contents/PlugIns/LivePhotoFinder.appex/Contents/MacOS/LivePhotoFinder"
# Swift's linker adds a toolchain fallback path even when all libraries are system-provided.
# Remove development-machine search paths before signing the portable bundle.
python3 - "$APP" <<'PY_RPATH'
from pathlib import Path
import re, subprocess, sys
for binary in Path(sys.argv[1]).glob('Contents/**/MacOS/*'):
    commands=subprocess.check_output(['otool','-l',str(binary)],text=True)
    paths=set(re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',commands))
    for path in sorted(paths):
        if path.startswith('/') and path != '/usr/lib/swift':
            subprocess.run(['install_name_tool','-delete_rpath',path,str(binary)],check=True)
PY_RPATH
if [[ -n "$TEST_PURPOSE" ]]; then
 python3 package.py "$APP/Contents" --test "$TEST_PURPOSE"
else
 python3 package.py "$APP/Contents"
fi
codesign --force --sign - --entitlements FinderExtension/entitlements.plist "$APP/Contents/PlugIns/LivePhotoFinder.appex"
codesign --force --sign - "$APP"
python3 validate_package.py "$APP" "$SDK_VERSION" > .build/package-audit.json
# Publish only a complete, signed, validated bundle; never keep stale bundle resources.
python3 - "$APP" "$TEST_PURPOSE" <<'PY'
from pathlib import Path
import shutil, sys
source=Path(sys.argv[1])
target=Path('../测试版本.noindex/实况工坊-测试版.app') if sys.argv[2] else Path('../实况工坊.app')
target.parent.mkdir(parents=True,exist_ok=True)
if target.exists(): shutil.rmtree(target)
shutil.move(str(source),str(target))
PY
cat .build/package-audit.json
