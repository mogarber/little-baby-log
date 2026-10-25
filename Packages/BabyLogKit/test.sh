#!/bin/sh
# Runs the package tests. With full Xcode, plain `swift test` works. With only the
# Command Line Tools, Swift Testing ships outside the default search paths, so add it.
cd "$(dirname "$0")" || exit 1
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$CLT/Frameworks/Testing.framework" ] && ! xcodebuild -version >/dev/null 2>&1; then
  exec swift test \
    -Xswiftc -F"$CLT/Frameworks" -Xlinker -F"$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test "$@"
