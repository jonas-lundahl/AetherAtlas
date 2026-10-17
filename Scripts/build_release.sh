#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! "$1" =~ ^[0-9]{8}\.[0-9]{4}$ || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 YYYYMMDD.HHMM BUILD_NUMBER" >&2
  exit 2
fi

version=$1
build_number=$2
project_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_root"

archive="$project_root/build/Release/AetherAtlas-$version.xcarchive"
distribution="$project_root/build/Distribution"
asset_name="AetherAtlas-$version-macOS-universal.zip"
mkdir -p "$distribution"

xcodebuild -quiet -project AetherAtlas.xcodeproj -scheme AetherAtlas \
  -configuration Release -derivedDataPath build/CI \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  archive CODE_SIGN_IDENTITY=- 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

app="$archive/Products/Applications/AetherAtlas.app"
plist="$app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build_number"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" = '26.0'
architectures=$(/usr/bin/lipo -archs "$app/Contents/MacOS/AetherAtlas")
[[ " $architectures " == *' arm64 '* && " $architectures " == *' x86_64 '* ]]
echo "Verified architectures: $architectures"
/usr/bin/codesign --verify --deep --strict "$app"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$distribution/$asset_name"
/usr/bin/unzip -tq "$distribution/$asset_name"
(
  cd "$distribution"
  /usr/bin/shasum -a 256 "$asset_name" > "$asset_name.sha256"
  /usr/bin/shasum -a 256 -c "$asset_name.sha256"
)
echo "Packaged $distribution/$asset_name"
