#!/bin/sh
set -eu
cd "$(dirname "$0")"

APP_NAME="Game on Launcher"
EXECUTABLE="GameOnLauncher"
BUNDLE_ID="com.gameonlauncher.app"

# The version lives in a single file so every build agrees on it.
if [ -f VERSION ]; then
  VERSION=$(tr -d '[:space:]' < VERSION)
else
  VERSION="1.0.0"
fi
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP="build/Game on Launcher.app"
STAGE="build/.stage"

# ---------------------------------------------------------------------------
# Sources: every Swift file under Sources/ is compiled together.
# ---------------------------------------------------------------------------
SOURCES=$(find Sources -name '*.swift' | sort)
if [ -z "$SOURCES" ]; then
  echo "Erro: nenhum ficheiro Swift encontrado em Sources/." >&2
  exit 1
fi

MODULE_CACHE="${TMPDIR:-/tmp}/gameon-swift-module-cache"
COMMON_FLAGS="-parse-as-library -module-cache-path $MODULE_CACHE -O"

rm -rf "$APP" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE"

# ---------------------------------------------------------------------------
# Universal binary: x86_64 for Intel Macs, arm64 for Apple silicon.
# ---------------------------------------------------------------------------
BUILD_SLICES=""
for ARCH in x86_64 arm64; do
  SLICE="$STAGE/$ARCH"
  mkdir -p "$SLICE"
  # shellcheck disable=SC2086
  if swiftc $COMMON_FLAGS -target "$ARCH-apple-macos13.0" $SOURCES -o "$SLICE/$EXECUTABLE" 2>"$SLICE/build.log"; then
    BUILD_SLICES="$BUILD_SLICES $ARCH"
    echo "Compilado $ARCH"
  else
    echo "Aviso: não foi possível compilar para $ARCH:" >&2
    sed 's/^/  /' "$SLICE/build.log" >&2
    rm -rf "$SLICE"
  fi
done

if [ -z "$BUILD_SLICES" ]; then
  echo "Erro: nenhuma arquitetura foi compilada." >&2
  exit 1
fi

if [ "$(echo "$BUILD_SLICES" | wc -w)" -gt 1 ]; then
  lipo -create $(for A in $BUILD_SLICES; do echo "$STAGE/$A/$EXECUTABLE"; done) \
    -output "$APP/Contents/MacOS/$EXECUTABLE"
  echo "Binário universal: $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")"
else
  cp "$STAGE/$(echo $BUILD_SLICES | tr -d ' ')/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
  echo "Binário: $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")"
fi
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

# ---------------------------------------------------------------------------
# Info.plist
# ---------------------------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSHumanReadableCopyright</key><string>Game on Launcher · github.com/lUCASFBLAB</string>
<key>NSAppTransportSecurity</key><dict>
  <key>NSAllowsArbitraryLoads</key><false/>
</dict>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

# ---------------------------------------------------------------------------
# App icon (shared with the Electron build)
# ---------------------------------------------------------------------------
if [ -f desktop/build/icon.icns ]; then
  cp desktop/build/icon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "Aviso: icon.icns ausente. Gera-o com 'python3 desktop/tools/make-icons.py'." >&2
fi

# ---------------------------------------------------------------------------
# Signing and notarisation
# ---------------------------------------------------------------------------
# The ad-hoc signature is enough to run locally. A real Developer ID lets the app
# be notarised, which is what stops Gatekeeper from blocking it on other Macs.
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements build/entitlements.plist "$APP" 2>/dev/null \
    || codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
  echo "Assinado com: $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Assinado ad-hoc (sem certificado de programador)."
fi

# Remove the quarantine flag so the bundle runs on this machine straight away.
xattr -cr "$APP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Notarisation (optional, needs APPLE_ID / APP_PASSWORD / TEAM_ID)
# ---------------------------------------------------------------------------
if [ -n "${APPLE_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ] && [ -n "${TEAM_ID:-}" ]; then
  ZIP_FOR_NOTARY="build/notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP_FOR_NOTARY"
  if xcrun notarytool submit "$ZIP_FOR_NOTARY" --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID" --wait 2>&1 | tail -3; then
    xcrun stapler staple "$APP"
    echo "App notarizado."
  else
    echo "Aviso: a notarização falhou. O app continua sem notar." >&2
  fi
  rm -f "$ZIP_FOR_NOTARY"
fi

rm -rf "$STAGE"

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
rm -f build/GameOnLauncher-macOS.zip build/GameOnLauncher-macOS.dmg
ditto -c -k --keepParent "$APP" build/GameOnLauncher-macOS.zip
echo "Criado build/GameOnLauncher-macOS.zip"

if command -v hdiutil >/dev/null 2>&1; then
  # A small staging folder gives the DMG a clean layout and a nicer name.
  DMG_STAGE="build/.dmg"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -R "$APP" "$DMG_STAGE/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGE/Applications" 2>/dev/null || true
  if hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO build/GameOnLauncher-macOS.dmg >/dev/null 2>&1; then
    echo "Criado build/GameOnLauncher-macOS.dmg"
  else
    echo "DMG não foi criado neste ambiente; o ZIP está disponível." >&2
  fi
  rm -rf "$DMG_STAGE"
fi
