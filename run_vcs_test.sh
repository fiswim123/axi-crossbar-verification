#!/bin/bash

###############################################################################
# AXI Crossbar VCS Verification Script
###############################################################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE} AXI Crossbar VCS Verification${NC}"
echo -e "${BLUE}============================================${NC}"

# Clean previous builds
rm -rf build
mkdir -p build
cd build

echo -e "${BLUE}[1/3] Compiling design...${NC}"

# Compile with VCS
vcs -sverilog -full64 -debug_access+all -kdb -lca \
    +incdir+../src \
    ../src/axicb_checker.sv \
    ../src/axicb_pipeline.sv \
    ../src/axicb_round_robin_core.sv \
    ../src/axicb_round_robin.sv \
    ../src/axicb_scfifo_ram.sv \
    ../src/axicb_scfifo_regfile.sv \
    ../src/axicb_scfifo.sv \
    ../src/axicb_slv_ooo.sv \
    ../src/axicb_slv_switch_wr.sv \
    ../src/axicb_slv_switch_rd.sv \
    ../src/axicb_slv_switch.sv \
    ../src/axicb_mst_switch_wr.sv \
    ../src/axicb_mst_switch_rd.sv \
    ../src/axicb_mst_switch.sv \
    ../src/axicb_slv_if.sv \
    ../src/axicb_mst_if.sv \
    ../src/axicb_switch_top.sv \
    ../src/axicb_crossbar_top.sv \
    ../verification/tb/axi_crossbar_vcs_tb.sv \
    -o simv 2>&1 | tail -20

if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"
echo ""

echo -e "${BLUE}[2/3] Running simulation...${NC}"

# Run simulation
./simv -l sim.log 2>&1

echo ""
echo -e "${BLUE}[3/3] Checking results...${NC}"

# Check results
if grep -q "ALL TESTS PASSED" sim.log; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN} VERIFICATION PASSED!${NC}"
    echo -e "${GREEN}============================================${NC}"
    exit 0
elif grep -q "SOME TESTS FAILED" sim.log; then
    echo -e "${RED}============================================${NC}"
    echo -e "${RED} VERIFICATION FAILED!${NC}"
    echo -e "${RED}============================================${NC}"
    exit 1
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED} VERIFICATION INCOMPLETE${NC}"
    echo -e "${RED}============================================${NC}"
    exit 1
fi
