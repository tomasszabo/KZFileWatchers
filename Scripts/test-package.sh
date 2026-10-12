#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATION="$ROOT/.build/PackageValidation"
mkdir -p "$VALIDATION"

for item in Package.swift Sources ObjcWrappers Tests; do
    if [ ! -L "$VALIDATION/$item" ]; then
        ln -s "$ROOT/$item" "$VALIDATION/$item"
    fi
done

cd "$VALIDATION"
xcodebuild -scheme KZFileWatchers-Package \
    -destination "${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$ROOT/.build/PackageDerivedData" \
    CODE_SIGNING_ALLOWED=NO "$@"
