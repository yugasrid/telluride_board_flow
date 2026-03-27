#!/bin/bash
# Telluride Board Flow - Main Entry Point
#
# Usage:
#   ./run.sh boardrun   - Board run (handles packaging + trace prompts)
#   ./run.sh help       - Show usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
cd "$SCRIPT_DIR"

# ========================== RDI Environment ==========================

ENVROOT="/proj/xtools/dsv/rdi2/utils"
RDI_DATA="/proj/rdi/xresults/dsv/yugasrid/rdi_data"

# ========================== Core Functions ==========================

validate_config() {
    load_config

    echo "[INFO] Validating configuration..."

    if [[ ! -d "$DESIGN_FOLDER" ]]; then
        echo "[ERROR] DESIGN_FOLDER does not exist: $DESIGN_FOLDER"; exit 1
    fi
    if [[ -n "$XBUILD_PATH" && ! -d "$XBUILD_PATH" ]]; then
        echo "[ERROR] XBUILD_PATH does not exist: $XBUILD_PATH"; exit 1
    fi
    if [[ ! -f "$SCRIPT_DIR/DMHA.tql" ]]; then
        echo "[ERROR] DMHA.tql not found in $SCRIPT_DIR"; exit 1
    fi

    echo "[INFO] Configuration validated."
    echo "----------------------------------------------"
    echo "  DESIGN_FOLDER = $DESIGN_FOLDER"
    echo "  RUN_ID        = $RUN_ID"
    echo "  XBUILD_PATH   = ${XBUILD_PATH:-(not set)}"
    echo "----------------------------------------------"
}

update_tql() {
    echo "[INFO] Updating DMHA.tql with current paths..."
    sed -i "3s|^FROM .*|FROM $SCRIPT_DIR|" "$SCRIPT_DIR/DMHA.tql"
    echo "[INFO] DMHA.tql updated."
}

preclean_check() {
    echo ""
    echo "[INFO] Checking for stale run artifacts..."

    local extras
    extras=$(find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 \
        ! -name 'run.sh' \
        ! -name 'config.conf' \
        ! -name 'DMHA.tql' \
        ! -name 'testinfo.yml' \
        ! -name 'Makefile' \
        ! -name 'scripts' \
        ! -name 'utils' \
        ! -name 'README.md' \
        ! -name '.' \
        ! -name '..' 2>/dev/null || true)

    if [[ -n "$extras" ]]; then
        echo "============================================================"
        echo "[WARNING] Previous run artifacts found (re-running could cause OOM on LSF):"
        echo "$extras"
        echo "============================================================"
        read -p "Remove these files before continuing? (yes/no): " ans
        if [[ "$ans" == "yes" ]]; then
            echo "[INFO] Cleaning previous artifacts..."
            echo "$extras" | xargs rm -rf
            echo "[SUCCESS] Cleanup complete."
        else
            echo "[ERROR] Aborting. Remove artifacts manually or backup existing content."
            exit 1
        fi
    else
        echo "[INFO] No stale artifacts found."
    fi
}

binarize_data() {
    echo "[INFO] Binarizing data in $DESIGN_FOLDER/data..."
    cp "$SCRIPT_DIR/utils/binarize_data.py" "$DESIGN_FOLDER/data/"
    csh -c "cd $DESIGN_FOLDER/data; \
            source /proj/aiebuilds/ryzen-ai/ryzen-ai-TA/release_rai_1_4/ryzenai_release_daily_latest/lnx64/bin/activate.csh; \
            python binarize_data.py --data_path ."
}

check_binarized_data() {
    echo "[INFO] Checking binarized data..."
    if [[ ! -d "$DESIGN_FOLDER/data" ]]; then
        echo "[ERROR] $DESIGN_FOLDER/data not found."; exit 1
    fi
    if ! find "$DESIGN_FOLDER/data" -type f -name "*.bin" | grep -q .; then
        echo "[WARNING] Binarized data not found. Data will be binarized now."
        binarize_data
        if ! find "$DESIGN_FOLDER/data" -type f -name "*.bin" | grep -q .; then
            echo "[ERROR] Binarization failed — no .bin files found after running binarize_data.py. Please handle manually or rename the files in data folder."
            exit 1
        fi
    fi
    echo "[SUCCESS] Binarized files found."
}

# ========================== RDI Command ==========================

build_rdi_cmd() {
    local cmd="rdi regression"
    cmd+=" --run-id '$RUN_ID'"
    cmd+=" --ta '/proj/xbuilds/HEAD_INT_flexml_verified_vitis/installs'"
    cmd+=" --vivado '/proj/xbuilds/HEAD_INT_daily_latest/installs/lin64/HEAD/Vitis'"
    cmd+=" --suite-category 'EDGE,BOARD'"
    cmd+=" --results-path '.'"
    cmd+=" --report-path '.'"
    cmd+=" --level '[1-14]'"
    cmd+=" --terminate-runs-after '23:0'"
    cmd+=" --failure-rate '100'"
    cmd+=" --job-exit-retry '0'"
    cmd+=" --job-fail-retry '0'"
    cmd+=" --job-time-retry '0'"
    cmd+=" --platforms 'lnx64'"
    cmd+=" --root-path 'XTC_ROOT'='/proj/rdi/testcases/xtc/HEAD'"
    cmd+=" --move-output-log-on-retry"
    cmd+=" --local-workarea"
    cmd+=" --keep-workarea"
    cmd+=" --test-dir-append"
    cmd+=" --disable-bqueues-polling"
    cmd+=" --chmod-write-workarea"
    cmd+=" --timestamp-output"
    cmd+=" --dump-env"
    cmd+=" --ignore-env-var 'MYVIVADO'"
    cmd+=" --tql-skip-unknown-paths"
    cmd+=" --tql-write-excluded"
    cmd+=" --tql-metrics"
    cmd+=" --msg-parse-cfg '/proj/testcases/xtc/HEAD/tc/open/flexml/common/utils/vaimlMsgParse.cfg'"
    cmd+=" --msg-parse"
    cmd+=" --env-add-var 'FLEXML_PRINT_VITISTOOLS_OUTPUT'='1'"
    cmd+=" --env-add-var 'DEBUG_LOG_LEVEL'='info'"
    cmd+=" --lsf-queue-level 'aiml:[1-20]'"
    cmd+=" --lsf-priority '960'"
    cmd+=" --lsf-os-override"
    cmd+=" --production-run"
    cmd+=" --test-pre-exec-script '/proj/testcases/xtc/PROD/HEAD/auto/prod_reg/global_scripts/pre_exec_TestXTC_all.csh'"
    cmd+=" --debug-job-max-delay '3600'"
    cmd+=" --tsm-flag"
    cmd+=" --disable-memory-buffer"
    cmd+=" --tql-file './DMHA.tql'"

    if [[ -n "${XBUILD_PATH:-}" ]]; then
        local ta_path
        ta_path=$(echo "$XBUILD_PATH" | sed -E 's|(.*installs)/.*|\1|')
        cmd+=" --ta '$ta_path'"
        cmd+=" --vivado '$XBUILD_PATH'"
    fi

    echo "$cmd"
}

run_rdi() {
    local rdi_cmd
    rdi_cmd=$(build_rdi_cmd)

    echo "[INFO] Verifying RDI..."
    csh -c "setenv RDI_DATA $RDI_DATA; \
            source /proj/xtools/dsv/rdi2/utils/setRDIEnv.csh; \
            echo '[INFO] RDI path:'; \
            which rdi; \
            echo ''"

    echo "[INFO] Launching RDI regression..."
    echo "----------------------------------------------"
    echo "$rdi_cmd"
    echo "----------------------------------------------"

    csh -c "setenv RDI_DATA $RDI_DATA; \
            source /proj/xtools/dsv/rdi2/utils/setRDIEnv.csh; \
            $rdi_cmd"
}

# ========================== Commands ==========================

cmd_help() {
    cat <<'EOF'
==============================================
     Telluride Board Flow Automation
==============================================

Usage:
  ./run.sh boardrun     Run pre-compiled design on board
  ./run.sh clean        Remove generated artifacts
  ./run.sh help         Show this help

The boardrun flow will:
  1. Validate config and check prerequisites
  2. Ask if packaging is needed (or detect automatically)
  3. If packaging: ask if design has trace enabled
     - With trace:    copy → trace_package → build MLADF → copy trace runtime
     - Without trace: copy → package → build MLADF → copy runtime
  4. Launch board run via RDI

Config file format (config.conf):
----------------------------------------------
  DESIGN_FOLDER=/path/to/design       (mandatory)
  RUN_ID=run_1                        (optional)
  XBUILD_PATH=/path/to/vitis          (optional)
----------------------------------------------

EOF
}

cmd_boardrun() {
    preclean_check
    validate_config
    update_tql

    echo ""
    echo "[INFO] Checking prerequisites for board run..."

    if [[ ! -d "$DESIGN_FOLDER/Work" ]]; then
        echo "[ERROR] Work folder not found in $DESIGN_FOLDER. Design must be compiled first."
        exit 1
    fi
    echo "[SUCCESS] Work folder found."

    if [[ ! -f "$DESIGN_FOLDER/libadf.a" ]]; then
        echo "[ERROR] libadf.a not found in $DESIGN_FOLDER"
        exit 1
    fi
    echo "[SUCCESS] libadf.a found."

    check_binarized_data

    # ---- Packaging decision ----
    local need_package="no"
    if [[ ! -d "$DESIGN_FOLDER/Work/hw_run" ]] || [[ ! -f "$DESIGN_FOLDER/Work/hw_run/design.xclbin" ]]; then
        echo "[WARNING] hw_run or design.xclbin not found — packaging is required."
        need_package="yes"
    else
        echo "[SUCCESS] hw_run and design.xclbin found."
        echo ""
        read -p "Design appears already packaged. Re-run packaging? (yes/no): " need_package
    fi

    if [[ "$need_package" == "yes" ]]; then
        # ---- Trace decision (only when packaging) ----
        echo ""
        read -p "Is this a trace-enabled design? (yes/no): " use_trace

        if [[ "$use_trace" == "yes" ]]; then
            echo ""
            echo "[INFO] Running TRACE packaging steps (copy → trace_package → build MLADF → copy trace runtime)..."
            bash "$SCRIPT_DIR/scripts/build.sh" copy
            bash "$SCRIPT_DIR/scripts/build.sh" trace_package
            bash "$SCRIPT_DIR/scripts/build.sh" mladf
            bash "$SCRIPT_DIR/scripts/build.sh" trace_copy_runtime
        else
            echo ""
            echo "[INFO] Running packaging steps (copy → package → build MLADF → copy runtime)..."
            bash "$SCRIPT_DIR/scripts/build.sh" all
        fi
        echo ""
    else
        echo "[INFO] Skipping packaging — proceeding directly to board run."
    fi

    # ---- Launch RDI board run ----

    local rdi_log="$SCRIPT_DIR/rdi_run.log"
    local rdi_rc=0
    run_rdi 2>&1 | tee "$rdi_log" || rdi_rc=$?

    if [[ $rdi_rc -ne 0 ]] || grep -qi 'error\|fail' "$rdi_log"; then
        echo ""
        echo "============================================================"
        echo "[ERROR] Board run failed. Errors from output:"
        echo "============================================================"
        grep -i 'error\|fail' "$rdi_log" || true
        echo "============================================================"
        echo "[INFO] Full log: $rdi_log"
        exit 1
    fi

    echo "[SUCCESS] Board run completed."
}

cmd_clean() {
    echo "[INFO] Cleaning up generated artifacts..."
    find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 \
        ! -name 'run.sh' \
        ! -name 'config.conf' \
        ! -name 'DMHA.tql' \
        ! -name 'testinfo.yml' \
        ! -name 'Makefile' \
        ! -name 'scripts' \
        ! -name 'utils' \
        ! -name 'README.md' \
        -exec rm -rf {} +
    echo "[SUCCESS] Directory cleaned."
}

# ========================== Main Dispatch ==========================

case "${1:-help}" in
    help)      cmd_help ;;
    boardrun)  cmd_boardrun ;;
    clean)     cmd_clean ;;
    *)         echo "[ERROR] Unknown command: $1"; cmd_help; exit 1 ;;
esac
