#!/bin/bash
# Xcode build phase: builds the bundled mediaremote-adapter (BSD 3-Clause, see
# ThirdParty/mediaremote-adapter/LICENSE) and copies it into the app:
#   Contents/Frameworks/MediaRemoteAdapter.framework
#   Contents/Helpers/MediaRemoteAdapterTestClient
#   Contents/Resources/mediaremote-adapter.pl
#   Contents/Resources/Acknowledgements/mediaremote-adapter-LICENSE.txt
#
# Without the submodule or CMake the app still builds; Now Playing then reports itself as
# unavailable in Settings.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

source_dir="$SRCROOT/ThirdParty/mediaremote-adapter"
if [ ! -f "$source_dir/CMakeLists.txt" ]; then
  echo "warning: mediaremote-adapter is missing; run 'git submodule update --init'. Now Playing won't work in this build."
  exit 0
fi
if ! command -v cmake >/dev/null 2>&1; then
  echo "warning: CMake not found; run 'brew install cmake'. Now Playing won't work in this build."
  exit 0
fi

build_dir="$DERIVED_FILE_DIR/mediaremote-adapter"
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" > /dev/null
cmake --build "$build_dir" --config Release > /dev/null

contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$contents/Frameworks" "$contents/Helpers" "$contents/Resources/Acknowledgements"
rm -rf "$contents/Frameworks/MediaRemoteAdapter.framework"
cp -R "$build_dir/MediaRemoteAdapter.framework" "$contents/Frameworks/"
cp "$build_dir/MediaRemoteAdapterTestClient" "$contents/Helpers/"
cp "$source_dir/bin/mediaremote-adapter.pl" "$contents/Resources/"
cp "$source_dir/LICENSE" "$contents/Resources/Acknowledgements/mediaremote-adapter-LICENSE.txt"

# Sign the nested code with the app's identity ("-" = ad hoc) before Xcode signs the app.
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
codesign --force --timestamp=none --sign "$identity" "$contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --timestamp=none --sign "$identity" "$contents/Frameworks/MediaRemoteAdapter.framework"
