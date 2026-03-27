#!/bin/bash
# Build steps for Telluride board flow
# Replaces aie_tell.mk build targets with shell functions.
# Design is assumed to be pre-compiled; only copy/package/runtime steps remain.
#
# Usage:
#   ./scripts/build.sh all|copy|package|trace_package|mladf|copy_runtime|trace_copy_runtime

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

AIE_RUNTIME="$FLOW_ROOT/utils/aie_runtime"

# ========================== Build Functions ==========================

copy_design_files() {
    echo "[INFO] Copying design files..."
    mkdir -p "$DESIGN_RUN"

    if [[ -d "$DESIGN_FOLDER" ]]; then
        cp -rf "$DESIGN_FOLDER"/* "$DESIGN_RUN"/
    else
        echo "[ERROR] Design directory does not exist: $DESIGN_FOLDER"
        exit 1
    fi

    if [[ -d "$DESIGN_FOLDER/../../kernels" ]]; then
        cp -rf "$DESIGN_FOLDER/../../kernels" "$DESIGN_RUN/../../"
    else
        echo "[WARN] kernels directory not found (skipping)"
    fi

    echo "[SUCCESS] Design files copied to $DESIGN_RUN"
}

package_design() {
    echo "[INFO] Packaging design..."

    if [[ ! -d "$DESIGN_RUN/Work" ]]; then
        echo "[ERROR] Work directory not found in $DESIGN_RUN. Ensure design is pre-compiled."
        exit 1
    fi

    cd "$DESIGN_RUN"
    rm -rf xclbin_generation
    git clone https://gitenterprise.xilinx.com/aiecompiler/xclbin_generation.git \
        || { echo "[ERROR] Failed to clone xclbin_generation."; exit 1; }

    cd xclbin_generation
    make all WORK_HW_DIR="../../Work" DEVICE=KRK \
        || { echo "[ERROR] Packaging failed."; exit 1; }

    echo "[SUCCESS] Design packaged."
}

trace_package_design() {
    package_design

    echo "[INFO] Adding AIE_TRACE and AIE_METADATA sections..."
    cd "$DESIGN_RUN/Work/hw_run"

    xclbinutil --add-section AIE_TRACE_METADATA:JSON:../../Work/ps/c_rts/aie_trace_config.json \
        -i ./design.xclbin -o tmp.xclbin --force
    xclbinutil --add-section AIE_METADATA:JSON:../../Work/ps/c_rts/aie_control_config.json \
        -i ./tmp.xclbin -o tmp1.xclbin --force

    rm -f design.xclbin tmp.xclbin
    mv tmp1.xclbin design.xclbin

    echo "[SUCCESS] Trace sections added to design.xclbin"
}

build_mladf_runner() {
    echo "[INFO] Fetching latest aie_runtime..."
    bash "$SCRIPT_DIR/fetch_aie_runtime.sh"
}

copy_runtime_files() {
    local use_trace="${1:-false}"

    echo "[INFO] Copying runtime files to hw_run..."

    if [[ ! -d "$DESIGN_RUN/Work/hw_run" ]]; then
        echo "[ERROR] hw_run directory not found. Package design first."
        exit 1
    fi

    cd "$DESIGN_RUN/Work/hw_run"
    cp -rf ../../data .
    cp ../ps/c_rts/external_buffer_id.json .
    cp -rf "$AIE_RUNTIME" .
    cp -rf "$FLOW_ROOT/utils/config.json" .
    cp -rf "$FLOW_ROOT/utils/run_mladf_runner.sh" .

    if [[ "$use_trace" == "true" ]]; then
        cp -rf "$FLOW_ROOT/utils/trace/xrt.ini" .
    else
        cp -rf "$FLOW_ROOT/utils/xrt.ini" .
    fi

    echo "[SUCCESS] Runtime files copied."
}

# ========================== Dispatch ==========================

case "${1:-all}" in
    all)                copy_design_files; package_design; build_mladf_runner; copy_runtime_files ;;
    copy)               copy_design_files ;;
    package)            package_design ;;
    trace_package)      trace_package_design ;;
    mladf)              build_mladf_runner ;;
    copy_runtime)       copy_runtime_files ;;
    trace_copy_runtime) copy_runtime_files true ;;
    *)
        echo "Usage: $0 {all|copy|package|trace_package|mladf|copy_runtime|trace_copy_runtime}"
        exit 1
        ;;
esac
