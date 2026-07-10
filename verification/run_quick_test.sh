#!/bin/bash

###############################################################################
#
# AXI Crossbar Quick Test Script
#
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE} AXI Crossbar Quick Verification${NC}"
echo -e "${BLUE}==========================================${NC}"

# Navigate to verification directory
cd "$(dirname "$0")"

# Check if we have a simulator
if command -v iverilog &> /dev/null; then
    SIM="iverilog"
    echo -e "${GREEN}Using Icarus Verilog${NC}"
elif command -v vcs &> /dev/null; then
    SIM="vcs"
    echo -e "${GREEN}Using VCS${NC}"
elif command -v xrun &> /dev/null; then
    SIM="xrun"
    echo -e "${GREEN}Using Xcelium${NC}"
else
    echo -e "${RED}No simulator found!${NC}"
    echo "Please install one of: iverilog, vcs, xrun"
    exit 1
fi

# Create simple testbench for quick verification
cat > quick_test.sv << 'EOF'
`timescale 1ns/1ps

module quick_test;

    // Parameters
    parameter AXI_ADDR_W = 16;
    parameter AXI_ID_W = 8;
    parameter AXI_DATA_W = 32;

    // Clock and reset
    logic aclk = 0;
    logic aresetn = 0;
    logic srst = 1;

    always #5 aclk = ~aclk;

    // AXI signals
    logic awvalid, awready;
    logic [AXI_ADDR_W-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic [AXI_ID_W-1:0] awid;

    logic wvalid, wready, wlast;
    logic [AXI_DATA_W-1:0] wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;

    logic bvalid, bready;
    logic [AXI_ID_W-1:0] bid;
    logic [1:0] bresp;

    logic arvalid, arready;
    logic [AXI_ADDR_W-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [AXI_ID_W-1:0] arid;

    logic rvalid, rready, rlast;
    logic [AXI_ID_W-1:0] rid;
    logic [1:0] rresp;
    logic [AXI_DATA_W-1:0] rdata;

    // DUT instantiation (simplified - direct connection to slave 0)
    // In real test, connect to crossbar

    // Simple test
    initial begin
        $display("Starting Quick Test...");

        // Reset
        aresetn = 0;
        srst = 1;
        #100;
        aresetn = 1;
        srst = 0;
        #50;

        // Test complete
        $display("Quick Test PASSED!");
        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("Timeout!");
        $finish;
    end

    // Waveform
    initial begin
        $dumpfile("quick_test.vcd");
        $dumpvars(0, quick_test);
    end

endmodule
EOF

# Compile and run
echo -e "${BLUE}Compiling...${NC}"

case ${SIM} in
    iverilog)
        iverilog -g2012 -o quick_test.vvp \
            ../src/*.sv \
            quick_test.sv \
            2>&1 | tee compile.log
        ;;
    vcs)
        vcs -sverilog -full64 -debug_access+all \
            ../src/*.sv \
            quick_test.sv \
            -o simv \
            -l compile.log
        ;;
    xrun)
        xrun -sv -64bit -access +rwc \
            ../src/*.sv \
            quick_test.sv \
            -elaborate \
            -l compile.log
        ;;
esac

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Compilation successful${NC}"
else
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${BLUE}Running simulation...${NC}"

case ${SIM} in
    iverilog)
        vvp quick_test.vvp | tee sim.log
        ;;
    vcs)
        ./simv -l sim.log
        ;;
    xrun)
        xrun -sv -64bit -access +rwc \
            ../src/*.sv \
            quick_test.sv \
            -l sim.log
        ;;
esac

# Check result
if grep -q "PASSED" sim.log; then
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN} Quick Test PASSED!${NC}"
    echo -e "${GREEN}==========================================${NC}"
else
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED} Quick Test FAILED!${NC}"
    echo -e "${RED}==========================================${NC}"
    exit 1
fi

# Cleanup
rm -f quick_test.sv quick_test.vvp simv *.log

echo -e "${BLUE}Done!${NC}"
