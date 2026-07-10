#!/bin/bash

###############################################################################
#
# AXI Crossbar Verification - Quick Run Script
#
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  AXI Crossbar Verification                ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check for Icarus Verilog
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}Error: Icarus Verilog not found!${NC}"
    echo "Please install it with: sudo apt-get install iverilog"
    exit 1
fi

echo -e "${GREEN}Found Icarus Verilog${NC}"
echo ""

# Navigate to project directory
cd ${SCRIPT_DIR}

# Create output directory
mkdir -p verification/output

echo -e "${BLUE}Step 1: Compiling design...${NC}"

# Compile all source files
iverilog -g2012 -o verification/output/axi_crossbar_tb.vvp \
    src/axicb_checker.sv \
    src/axicb_pipeline.sv \
    src/axicb_round_robin_core.sv \
    src/axicb_round_robin.sv \
    src/axicb_scfifo_ram.sv \
    src/axicb_scfifo_regfile.sv \
    src/axicb_scfifo.sv \
    src/axicb_slv_ooo.sv \
    src/axicb_slv_switch_wr.sv \
    src/axicb_slv_switch_rd.sv \
    src/axicb_slv_switch.sv \
    src/axicb_mst_switch_wr.sv \
    src/axicb_mst_switch_rd.sv \
    src/axicb_mst_switch.sv \
    src/axicb_slv_if.sv \
    src/axicb_mst_if.sv \
    src/axicb_switch_top.sv \
    src/axicb_crossbar_top.sv \
    verification/tb/axi_crossbar_simple_tb.sv \
    2>&1 | tee verification/output/compile.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"
echo ""

echo -e "${BLUE}Step 2: Running simulation...${NC}"

# Run simulation
cd verification/output
vvp axi_crossbar_tb.vvp 2>&1 | tee sim.log

# Check results
echo ""
if grep -q "ALL TESTS PASSED" sim.log; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  VERIFICATION PASSED!                     ${NC}"
    echo -e "${GREEN}============================================${NC}"
elif grep -q "SOME TESTS FAILED" sim.log; then
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  VERIFICATION FAILED!                     ${NC}"
    echo -e "${RED}============================================${NC}"
    exit 1
else
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  VERIFICATION STATUS UNKNOWN               ${NC}"
    echo -e "${YELLOW}============================================${NC}"
fi

echo ""
echo -e "${BLUE}Output files:${NC}"
echo "  - VCD waveform: verification/output/axi_crossbar_tb.vcd"
echo "  - Simulation log: verification/output/sim.log"
echo "  - Compile log: verification/output/compile.log"
echo ""
echo -e "${BLUE}To view waveform:${NC}"
echo "  gtkwave verification/output/axi_crossbar_tb.vcd &"
echo ""
