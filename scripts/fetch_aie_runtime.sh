#!/bin/bash
# Downloads the latest aie_runtime binary from Artifactory.
# Falls back to an existing copy in utils/ if the download fails.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_URL="https://xcoartifactory.xilinx.com/ui/native/acas-devops-build-artifacts/aiecompiler/mladf_unified_runner/main-latest/linux/arm/telluride/"
FILE_NAME="aie_runtime"
DEST_DIR="$SCRIPT_DIR/utils"
TMP_DIR="$SCRIPT_DIR/tmp_download"

DEST_FILE="$DEST_DIR/$FILE_NAME"
TMP_FILE="$TMP_DIR/$FILE_NAME"

echo "[INFO] Checking utils directory..."
if [ ! -d "$DEST_DIR" ]; then
    echo "[ERROR] utils directory not found at $DEST_DIR"
    exit 1
fi

mkdir -p "$TMP_DIR"

echo "[INFO] Downloading latest $FILE_NAME from Artifactory..."
if curl -L --fail -o "$TMP_FILE" "${BASE_URL}${FILE_NAME}"; then
    echo "[SUCCESS] Download successful."
    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$DEST_FILE"
    echo "[SUCCESS] Updated $FILE_NAME in utils/."
else
    echo "[WARNING] Download failed."
    if [ -f "$DEST_FILE" ]; then
        echo "[INFO] Using existing aie_runtime in utils/."
    else
        echo "[ERROR] No existing aie_runtime found in utils/. Cannot proceed."
        rm -rf "$TMP_DIR"
        exit 1
    fi
fi

rm -rf "$TMP_DIR"
