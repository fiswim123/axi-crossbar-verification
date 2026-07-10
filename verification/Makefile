###############################################################################
#
# AXI Crossbar Verification Makefile
#
###############################################################################

# Simulator selection (vcs, xcelium, modelsim)
SIM ?= vcs

# Source directories
SRC_DIR = ../src
TB_DIR = .
AGENT_DIR = agents
TEST_DIR = tests
ENV_DIR = env
COVERAGE_DIR = coverage

# Top module
TOP = axi_crossbar_tb

# Source files
SRC_FILES = \
    $(SRC_DIR)/axicb_crossbar_top.sv \
    $(SRC_DIR)/axicb_switch_top.sv \
    $(SRC_DIR)/axicb_slv_switch.sv \
    $(SRC_DIR)/axicb_slv_switch_wr.sv \
    $(SRC_DIR)/axicb_slv_switch_rd.sv \
    $(SRC_DIR)/axicb_mst_switch.sv \
    $(SRC_DIR)/axicb_mst_switch_wr.sv \
    $(SRC_DIR)/axicb_mst_switch_rd.sv \
    $(SRC_DIR)/axicb_slv_if.sv \
    $(SRC_DIR)/axicb_mst_if.sv \
    $(SRC_DIR)/axicb_round_robin.sv \
    $(SRC_DIR)/axicb_round_robin_core.sv \
    $(SRC_DIR)/axicb_pipeline.sv \
    $(SRC_DIR)/axicb_scfifo.sv \
    $(SRC_DIR)/axicb_scfifo_ram.sv \
    $(SRC_DIR)/axicb_scfifo_regfile.sv \
    $(SRC_DIR)/axicb_slv_ooo.sv \
    $(SRC_DIR)/axicb_checker.sv

TB_FILES = \
    $(AGENT_DIR)/axi_interface.sv \
    $(AGENT_DIR)/axi_transaction.sv \
    $(TB_DIR)/axi_crossbar_tb.sv

# Compilation options
VCS_OPTS = -sverilog -full64 -debug_access+all -kdb -lca
XCELIUM_OPTS = -sv -64bit -access +rwc
MODELSIM_OPTS = -sv

# Coverage options
COV_OPTS = -cm line+cond+fsm+tgl+branch -cm_dir ./cov_db

# Simulation options
SIM_OPTS = -l sim.log +timeout=100000

###############################################################################
# Targets
###############################################################################

.PHONY: all compile sim clean help

# Default target
all: compile sim

# Compile design and testbench
compile:
	@echo "=========================================="
	@echo " Compiling AXI Crossbar Design"
	@echo "=========================================="
ifeq ($(SIM),vcs)
	vcs $(VCS_OPTS) $(SRC_FILES) $(TB_FILES) -o simv
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) -elaborate
else ifeq ($(SIM),modelsim)
	vlib work
	vlog $(MODELSOPTS) $(SRC_FILES) $(TB_FILES)
endif
	@echo "Compilation completed."

# Run simulation
sim: compile
	@echo "=========================================="
	@echo " Running AXI Crossbar Tests"
	@echo "=========================================="
ifeq ($(SIM),vcs)
	./simv $(SIM_OPTS) $(COV_OPTS)
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) $(SIM_OPTS) $(COV_OPTS)
else ifeq ($(SIM),modelsim)
	vsim -c $(TOP) -do "run -all"
endif
	@echo "Simulation completed."

# Run with GUI
gui:
ifeq ($(SIM),vcs)
	vcs $(VCS_OPTS) $(SRC_FILES) $(TB_FILES) -o simv -gui
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) -gui
endif

# Run specific test
test_%:
	@echo "Running test: $@"
ifeq ($(SIM),vcs)
	./simv $(SIM_OPTS) +TESTNAME=$@
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) +TESTNAME=$@
endif

# Generate coverage report
cov:
	@echo "Generating coverage report..."
ifeq ($(SIM),vcs)
	urg -dir cov_db -report coverage_report
else ifeq ($(SIM),xcelium)
	xcov -dir cov_db -report
endif
	@echo "Coverage report generated in coverage_report/"

# Run formal verification
formal:
	@echo "Running formal verification..."
	jg -prove -property axi_crossbar_tb

# Lint check
lint:
	@echo "Running lint checks..."
	spyglass -top $(TOP) -batch -lint

# Clean
clean:
	rm -rf simv simv.daidir csrc *.vpd *.vcd
	rm -rf INCA_libs xcelium.d
	rm -rf work modelsim.ini
	rm -rf *.log *.history
	rm -rf cov_db coverage_report
	rm -rf DVEfiles inter.vpd
	rm -rf *.wlf *.vstf

# Help
help:
	@echo "=========================================="
	@echo " AXI Crossbar Verification Makefile"
	@echo "=========================================="
	@echo ""
	@echo "Targets:"
	@echo "  all      - Compile and run simulation"
	@echo "  compile  - Compile design and testbench"
	@echo "  sim      - Run simulation"
	@echo "  gui      - Run simulation with GUI"
	@echo "  cov      - Generate coverage report"
	@echo "  formal   - Run formal verification"
	@echo "  lint     - Run lint checks"
	@echo "  clean    - Remove generated files"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  SIM      - Simulator (vcs|xcelium|modelsim)"
	@echo ""
	@echo "Examples:"
	@echo "  make all SIM=vcs"
	@echo "  make test_smoke SIM=xcelium"
	@echo "  make cov SIM=vcs"
	@echo ""

###############################################################################
# Individual Test Targets
###############################################################################

.PHONY: test_smoke test_single_master test_multi_master
.PHONY: test_address_routing test_concurrent_access

test_smoke:
	$(MAKE) sim SIM=$(SIM) +TESTNAME=smoke_test

test_single_master:
	$(MAKE) sim SIM=$(SIM) +TESTNAME=single_master_test

test_multi_master:
	$(MAKE) sim SIM=$(SIM) +TESTNAME=multi_master_test

test_address_routing:
	$(MAKE) sim SIM=$(SIM) +TESTNAME=address_routing_test

test_concurrent_access:
	$(MAKE) sim SIM=$(SIM) +TESTNAME=concurrent_access_test

###############################################################################
# Regression
###############################################################################

.PHONY: regression

regression:
	@echo "Running regression suite..."
	$(MAKE) test_smoke
	$(MAKE) test_single_master
	$(MAKE) test_multi_master
	$(MAKE) test_address_routing
	$(MAKE) test_concurrent_access
	$(MAKE) cov
	@echo "Regression completed."
