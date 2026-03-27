# Thin Makefile for RDI integration.
# All build logic lives in scripts/. This file exists because RDI invokes 'make <target>'.

-include config.conf

CURR_DIR := $(shell pwd)
DESIGN_RUN := $(CURR_DIR)/$(notdir $(DESIGN_FOLDER))

.PHONY: all print_info copy_design_files board_run run

all: print_info

print_info:
	@echo "[INFO] Design folder: $(DESIGN_FOLDER)"
	@echo "[INFO] Design run:    $(DESIGN_RUN)"
	@echo "[INFO] Current dir:   $(CURR_DIR)"

copy_design_files:
	@bash scripts/build.sh copy

run: board_run

board_run: copy_design_files
	@bash scripts/board_run.sh "$(DESIGN_RUN)" "$(CURR_DIR)"
