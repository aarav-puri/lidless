#!/bin/zsh
# Builds Lidless (universal), runs its self-test, and installs the only copy to /Applications.
set -euo pipefail
cd "${0:A:h}"
OUT=.build/Lidless.app
rm -rf .build && mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos13.0 Sources/*.swift -o .build/Lidless-$arch
done
lipo -create .build/Lidless-arm64 .build/Lidless-x86_64 -output "$OUT/Contents/MacOS/Lidless"
cp Info.plist "$OUT/Contents/Info.plist"
xcrun actool Resources/AppIcon.icon --compile "$OUT/Contents/Resources" --platform macosx \
    --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist .build/icon.plist >/dev/null
codesign --force --sign - "$OUT"
"$OUT/Contents/MacOS/Lidless" --self-test
[[ "${1:-}" == "--no-install" ]] && exit 0

if pgrep -x Lidless >/dev/null; then
    osascript -e 'tell application id "app.personal.lidless" to quit' >/dev/null 2>&1 || pkill -x Lidless || true
    sleep 1
fi
rm -rf /Applications/Lidless.app
ditto "$OUT" /Applications/Lidless.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Lidless.app
open /Applications/Lidless.app
print 'Lidless is installed at /Applications/Lidless.app'
