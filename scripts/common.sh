#!/bin/bash
# Shared configuration and utility functions for Telluride board flow

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_config() {
    local config_file="$FLOW_ROOT/config.conf"
    if [[ ! -f "$config_file" ]]; then
        echo "[ERROR] config.conf not found in $FLOW_ROOT"
        echo "Run './run.sh help' for setup instructions."
        exit 1
    fi
    # Parse Make-compatible config (handles KEY = VALUE and KEY=VALUE)
    eval "$(sed '/^\s*#/d; /^\s*$/d; s/[[:space:]]*=[[:space:]]*/=/' "$config_file")"

    DESIGN_FOLDER="${DESIGN_FOLDER:?DESIGN_FOLDER not set in config.conf}"
    RUN_ID="${RUN_ID:-run_1}"
    XBUILD_PATH="${XBUILD_PATH:-}"
    DESIGN_RUN="$FLOW_ROOT/$(basename "$DESIGN_FOLDER")"
}
