#!/bin/bash
set -e

echo "[INFO] Capturing NFS mount info"
grep '\<nfs rw\>' /proc/mounts | tee /mnt/test/mount_path.txt

remount_path() {
    echo "[INFO] Remounting NFS path"
    awk '{ sub(/nfs.*/, ""); print }' /mnt/test/mount_path.txt | \
        xargs -t -n 2 mount -t nfs -o nolock,proto=tcp,port=2049
}

echo "[INFO] Current directory:"
pwd

echo "[INFO] Switching to hw_run directory"
cd /mnt/test/L1_L30/Work/hw_run

echo "[INFO] Current directory after cd:"
pwd

echo "########################################################################"
echo "[INFO] Running MLADF runner"
chmod +x run_mladf_runner.sh
bash ./run_mladf_runner.sh
