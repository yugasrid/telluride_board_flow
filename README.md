# Telluride Board Flow

Automated flow for packaging and running pre-compiled AIE designs on Telluride (VEK385) boards via RDI regression infrastructure.

## Prerequisites

- Design must be **pre-compiled** (the `Work/` folder and `libadf.a` must already exist in your design directory).
- Access to `/proj/xbuilds`, `/proj/aiebuilds`, and `/proj/xtools` network paths.
- `csh` shell available (used internally to source RDI and Ryzen AI environments).
- `DMHA.tql` present in the flow root (ships with the repo).

## Quick Start

```bash
# 1. Edit config.conf with your design path
vi config.conf

# 2. Run the board flow
./run.sh boardrun
```

The script is fully interactive — it will prompt you at each decision point.

## Configuration

Edit **`config.conf`** before running. All settings use `KEY=VALUE` format (no spaces around `=`).

| Key              | Required | Description                                       | Default  |
|------------------|----------|---------------------------------------------------|----------|
| `DESIGN_FOLDER`  | Yes      | Absolute path to your pre-compiled design folder  | —        |
| `RUN_ID`         | No       | Tag for this regression run                       | `run_1`  |
| `XBUILD_PATH`    | No       | Path to a custom Vitis/XBUILD install             | HEAD     |

Example:

```conf
DESIGN_FOLDER=/wrk/xcohdnobkup2/yugasrid/my_design
RUN_ID=my_run_1
XBUILD_PATH=/proj/xbuilds/HEAD_daily_latest/installs/lin64/2026.1/Vitis/
```

## Commands

| Command                | Description                                 |
|------------------------|---------------------------------------------|
| `./run.sh boardrun`   | Full board run flow (see diagram below)     |
| `./run.sh clean`      | Remove all generated artifacts              |
| `./run.sh help`       | Print usage information                     |

## Board Run Flow

```
./run.sh boardrun
    │
    ├── Preclean check
    │     └── Detects stale artifacts from previous runs
    │         Prompts to remove them (avoids OOM on LSF)
    │
    ├── Validate configuration
    │     └── Checks DESIGN_FOLDER, XBUILD_PATH, DMHA.tql
    │
    ├── Check prerequisites
    │     ├── Work/ folder exists
    │     ├── libadf.a exists
    │     └── Binarized data (.bin files in data/)
    │           └── If missing → auto-binarizes using binarize_data.py
    │
    ├── Packaging decision
    │     ├── hw_run/ or design.xclbin missing → packaging required
    │     └── Both present → prompts "Re-run packaging? (yes/no)"
    │           │
    │          yes
    │           │
    │     "Is this a trace-enabled design? (yes/no)"
    │         │                        │
    │        yes                       no
    │         │                        │
    │    copy                     copy → package
    │    trace_package            → mladf
    │    mladf                    → copy_runtime
    │    trace_copy_runtime            │
    │         │                        │
    │         └──────────┬─────────────┘
    │                    │
    │         no (skip packaging)
    │                    │
    └────────────────────┤
                         │
               Launch RDI board run
                 ├── Output logged to rdi_run.log
                 ├── On failure → extracts and prints error lines
                 └── On success → [SUCCESS] Board run completed
```

## What Happens on the Board

Once RDI launches the job on the board, it runs:

1. **FPGA programming** — loads the overlay PDI and device tree.
2. **2-run test** — executes the design, logs output, validates data correctness.
3. **100-run test** — switches `num_runs` to 100 for profiling, logs performance results.
4. **Cleanup** — restores original `config.json`, reports summary.

## Directory Structure

```
telluride_board_flow/
├── run.sh              # Main entry point — start here
├── config.conf         # User configuration (edit this)
├── DMHA.tql            # TQL file for RDI test selection
├── Makefile            # Thin wrapper for RDI (calls scripts/)
├── testinfo.yml        # RDI test metadata
├── scripts/
│   ├── common.sh       # Shared config loader
│   ├── build.sh        # Copy, package, MLADF, runtime steps
│   └── board_run.sh    # On-board wrapper generation + zboard launch
├── utils/
│   ├── aie_runtime     # AIE runtime binary
│   ├── binarize_data.py# Data binarization script
│   ├── config.json     # Default runner config (num_runs, etc.)
│   ├── make_pre.sh     # Pre-make setup
│   ├── run_mladf_runner.sh
│   ├── vaiml_exec.sh   # On-board execution script
│   ├── xrt.ini         # XRT config (standard)
│   └── trace/
│       └── xrt.ini     # XRT config (trace-enabled)
└── README.md
```

## Auto-Binarization

If no `.bin` files are found in `DESIGN_FOLDER/data/`, the flow automatically:

1. Copies `binarize_data.py` from `utils/` to the data folder.
2. Activates the Ryzen AI environment.
3. Runs `python binarize_data.py --data_path .` to generate `.bin` files.
4. Re-checks for `.bin` files — exits with an error if binarization failed.

## Packaging Steps (Detail)

| Step                  | What it does                                                      |
|-----------------------|-------------------------------------------------------------------|
| `copy`                | Copies design files to the local work area                        |
| `package`             | Clones `xclbin_generation`, runs `make all` to produce `design.xclbin` |
| `trace_package`       | Same as `package` + adds `AIE_TRACE_METADATA` and `AIE_METADATA` sections to xclbin |
| `mladf`               | Fetches the latest `aie_runtime` build                            |
| `copy_runtime`        | Copies runtime files, data, configs into `hw_run/`                |
| `trace_copy_runtime`  | Same as `copy_runtime` but uses the trace-enabled `xrt.ini`      |

You can run individual steps directly if needed:

```bash
bash scripts/build.sh copy
bash scripts/build.sh package
bash scripts/build.sh mladf
bash scripts/build.sh copy_runtime
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `config.conf not found` | Create `config.conf` in the flow root — see Configuration above |
| `DESIGN_FOLDER does not exist` | Check the path in `config.conf` — must be absolute |
| `Work folder not found` | Design must be compiled first (this flow only handles packaging + board run) |
| `libadf.a not found` | Compilation artifact missing — recompile the design |
| `Binarization failed` | Check `binarize_data.py` output; ensure data files in `data/` are in the expected format |
| `Board run failed` | Check `rdi_run.log` for full output; error lines are printed automatically |
| OOM on LSF | Run `./run.sh clean` or say "yes" when prompted to remove stale artifacts |
