#!/bin/bash
# Board run: copies overlay files, generates the on-board wrapper script,
# and launches zboard for a combined 2-run + 100-run test session.
#
# Usage:
#   ./scripts/board_run.sh <DESIGN_RUN> [CURR_DIR]

set -euo pipefail

DESIGN_RUN="${1:?Usage: $0 <DESIGN_RUN> [CURR_DIR]}"
CURR_DIR="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

DESIGN_NAME="$(basename "$DESIGN_RUN")"
HW_RUN="$DESIGN_RUN/Work/hw_run"
BOARD_PATH="/mnt/test/$DESIGN_NAME/Work/hw_run"

# Boot images and overlay paths
OVERLAY_PDI="/proj/aiebuilds/Vitis-AI-Telluride/vaiml_revA/vai_main_daily_latest/amd/boot_images/overlay/vpl_gen_fixed_pld.pdi"
OVERLAY_DTBO="/proj/aiebuilds/Vitis-AI-Telluride/vaiml_revA/vai_main_daily_latest/amd/boot_images/overlay/pl_aiarm.dtbo"
ROOTFS="/proj/aiebuilds/Vitis-AI-Telluride/vaiml_revA/vai_main_daily_latest/amd/boot_images/rootfs.wic.xz"
OSPI_BIN="/proj/aiebuilds/Vitis-AI-Telluride/vaiml_revA/vai_main_daily_latest/amd/boot_images/edf-ospi-versal2-vek385-sdt-full.bin"
VAIML_PATHS="/proj/rdi/aiml_regr/ghe_repos/AIModelTesting/main/common/,/proj/ai_models/ai_datasets/vision"
ZBOARD="/proj/sdxbf/emhw_telluride/bin/zboard"
RELEASE="2025.1.1"

echo "###############################################"
echo "  Running AIE Design on Board"
echo "###############################################"

which python || true
deactivate 2>/dev/null || true

# ---- Copy overlay and exec files ----

echo "[INFO] Copying vaiml_exec.sh and overlay files..."
cp -f "$CURR_DIR/utils/vaiml_exec.sh" "$HW_RUN/"
cp -f "$OVERLAY_PDI" "$HW_RUN/"
cp -f "$OVERLAY_DTBO" "$HW_RUN/"

echo "[INFO] Updating vaiml_exec.sh with design path..."
sed -i "s|cd /mnt/test/.*/Work/hw_run|cd $BOARD_PATH|g" "$HW_RUN/vaiml_exec.sh"

# ---- Generate on-board wrapper script ----
# This heredoc replaces 40+ printf lines from the old Makefile.

echo "[INFO] Generating board wrapper script..."
cat > "$HW_RUN/vaiml_wrapper.sh" <<WRAPPER_EOF
#!/bin/bash
echo "============================================="
echo " Running design on board: $DESIGN_NAME"
echo "============================================="

echo "[INFO] Programming FPGA..."
fpgautil -b $BOARD_PATH/vpl_gen_fixed_pld.pdi -o $BOARD_PATH/pl_aiarm.dtbo

# ---- 2-run test ----
echo "[INFO] Starting 2-run test..."
bash $BOARD_PATH/vaiml_exec.sh | tee $BOARD_PATH/run2.log
sleep 2

cd $BOARD_PATH
binfile=\$(ls -t *.bin 2>/dev/null | head -n 1)
if [ -n "\$binfile" ]; then
    mv "\$binfile" "\${binfile%.bin}_2runs.bin"
    echo "[INFO] Renamed \$binfile -> \${binfile%.bin}_2runs.bin"
else
    echo "[WARNING] No .bin file found after 2-run."
fi

echo "---------------------------------------------"
echo "[INFO] 2-run validation summary:"
grep -A5 "DATA VALIDATION" run2.log || echo "[WARN] No DATA VALIDATION section found"

# ---- Switch to 100-run ----
echo "[INFO] Updating config.json for 100-run test..."
if [ -f config.json ]; then
    cp config.json config_2runs_backup.json
    sed -i 's/"num_runs":[[:space:]]*[0-9]\+/"num_runs": 100/' config.json
else
    echo "[WARNING] config.json not found"
fi

echo "[INFO] Starting 100-run test..."
bash $BOARD_PATH/vaiml_exec.sh | tee $BOARD_PATH/run100.log
sleep 2

binfile=\$(ls -t *.bin 2>/dev/null | head -n 1)
if [ -n "\$binfile" ]; then
    mv "\$binfile" "\${binfile%.bin}_100runs.bin"
    echo "[INFO] Renamed \$binfile -> \${binfile%.bin}_100runs.bin"
else
    echo "[WARNING] No .bin file found after 100-run."
fi

echo "---------------------------------------------"
echo "[INFO] 100-run profile summary:"
grep -A10 "PROFILE RESULTS" run100.log || echo "[WARN] No PROFILE RESULTS section found"

# ---- Restore config ----
if [ -f config_2runs_backup.json ]; then
    mv config_2runs_backup.json config.json
    echo "[INFO] Restored original config.json"
fi

echo "============================================="
echo " Completed both 2-run and 100-run tests."
echo "============================================="
WRAPPER_EOF

chmod +x "$HW_RUN/vaiml_wrapper.sh"

# ---- Launch zboard ----

echo "[INFO] Launching board session..."
"$ZBOARD" -d /dev/ttyUSB1 run-test \
    -e "$DESIGN_NAME/Work/hw_run/vaiml_wrapper.sh" \
    -i "$ROOTFS" \
    -m ospi_sd \
    --ospi_path "$OSPI_BIN" \
    --vaiml "$VAIML_PATHS" \
    --release "$RELEASE"

echo "###############################################"
echo "  Board Tests Completed"
echo "###############################################"
