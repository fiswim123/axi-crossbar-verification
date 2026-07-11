###############################################################################
# AXI Crossbar UVM Verification Makefile
###############################################################################

SIM ?= vcs

SRC_DIR = ../src

###############################################################################
# RTL
###############################################################################

SRC_FILES = \
    $(SRC_DIR)/axicb_pipeline.sv \
    $(SRC_DIR)/axicb_round_robin_core.sv \
    $(SRC_DIR)/axicb_round_robin.sv \
    $(SRC_DIR)/axicb_scfifo_ram.sv \
    $(SRC_DIR)/axicb_scfifo_regfile.sv \
    $(SRC_DIR)/axicb_scfifo.sv \
    $(SRC_DIR)/axicb_slv_ooo.sv \
    $(SRC_DIR)/axicb_slv_switch_wr.sv \
    $(SRC_DIR)/axicb_slv_switch_rd.sv \
    $(SRC_DIR)/axicb_slv_switch.sv \
    $(SRC_DIR)/axicb_mst_switch_wr.sv \
    $(SRC_DIR)/axicb_mst_switch_rd.sv \
    $(SRC_DIR)/axicb_mst_switch.sv \
    $(SRC_DIR)/axicb_slv_if.sv \
    $(SRC_DIR)/axicb_mst_if.sv \
    $(SRC_DIR)/axicb_switch_top.sv \
    $(SRC_DIR)/axicb_crossbar_top.sv

###############################################################################
# UVM TB (interface → package → module)
###############################################################################

TB_FILES = \
    env/axi_if.sv \
    env/axi_pkg.sv \
    tb/axi_crossbar_tb.sv

###############################################################################
# Options
###############################################################################

VCS_OPTS     = -sverilog -full64 +incdir+$(SRC_DIR) +incdir+env \
               +incdir+components +incdir+sequences +incdir+tests \
               -ntb_opts uvm-1.2 -timescale=1ns/1ps \
               -cm line+cond+fsm+tgl+branch -cm_dir ./cov_db
XCELIUM_OPTS = -sv -64bit -uvm -access +rwc
COV_OPTS     = -cm line+cond+fsm+tgl+branch+func -cm_dir ./cov_db -cm_name $(UVM_TEST)
SIM_OPTS     = -l sim.log +UVM_VERBOSITY=UVM_MEDIUM

###############################################################################
# Targets
###############################################################################

.PHONY: all compile sim gui cov clean help

all: compile sim

compile:
ifeq ($(SIM),vcs)
	vcs $(VCS_OPTS) $(SRC_FILES) $(TB_FILES) -o simv
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) -elaborate
endif

sim: compile
ifeq ($(SIM),vcs)
	./simv $(SIM_OPTS) +UVM_TESTNAME=$(UVM_TEST) $(COV_OPTS)
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) $(SIM_OPTS) +UVM_TESTNAME=$(UVM_TEST) $(COV_OPTS)
endif

gui:
ifeq ($(SIM),vcs)
	vcs $(VCS_OPTS) $(SRC_FILES) $(TB_FILES) -o simv -gui
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) $(SRC_FILES) $(TB_FILES) -gui
endif

cov:
ifeq ($(SIM),vcs)
	urg -dir cov_db -report coverage_report
else ifeq ($(SIM),xcelium)
	xcov -dir cov_db -report
endif

clean:
	rm -rf simv simv.daidir csrc *.vpd *.vcd *.log
	rm -rf INCA_libs xcelium.d DVEfiles inter.vpd ucli.key
	rm -rf AN.DB *.daidir *.shm cov_db coverage_report
	rm -rf merged_coverage merged_coverage_text

###############################################################################
# Test targets
###############################################################################

.PHONY: test_basic test_routing test_protocol test_burst_size test_outstanding \
        test_outstanding_read test_multi test_same_slave test_interleave \
        test_full_routing \
        test_err_slverr test_err_decerr test_err_recovery \
        test_boundary_addr test_boundary_burst test_boundary_ostd \
        test_bp_wready test_bp_bready test_bp_rready test_bp_all \
        test_reset_wr test_reset_rd test_reset_recovery \
        test_random test_random_concurrent \
        test_perf_latency test_perf_bandwidth regression

# Basic tests
test_basic:            ; $(MAKE) sim UVM_TEST=axi_basic_test SIM=$(SIM)
test_routing:          ; $(MAKE) sim UVM_TEST=axi_routing_test SIM=$(SIM)
test_protocol:         ; $(MAKE) sim UVM_TEST=axi_protocol_test SIM=$(SIM)
test_burst_size:       ; $(MAKE) sim UVM_TEST=axi_burst_size_test SIM=$(SIM)
test_outstanding:      ; $(MAKE) sim UVM_TEST=axi_outstanding_test SIM=$(SIM)
test_outstanding_read: ; $(MAKE) sim UVM_TEST=axi_outstanding_read_test SIM=$(SIM)
test_multi:            ; $(MAKE) sim UVM_TEST=axi_multi_master_test SIM=$(SIM)
test_same_slave:       ; $(MAKE) sim UVM_TEST=axi_same_slave_test SIM=$(SIM)
test_interleave:       ; $(MAKE) sim UVM_TEST=axi_interleave_test SIM=$(SIM)
test_full_routing:     ; $(MAKE) sim UVM_TEST=axi_full_routing_test SIM=$(SIM)

# Error injection tests
test_err_slverr:       ; $(MAKE) sim UVM_TEST=axi_err_slverr_test SIM=$(SIM)
test_err_decerr:       ; $(MAKE) sim UVM_TEST=axi_err_decerr_test SIM=$(SIM)
test_err_recovery:     ; $(MAKE) sim UVM_TEST=axi_err_recovery_test SIM=$(SIM)

# Boundary tests
test_boundary_addr:    ; $(MAKE) sim UVM_TEST=axi_boundary_addr_test SIM=$(SIM)
test_boundary_burst:   ; $(MAKE) sim UVM_TEST=axi_boundary_burst_test SIM=$(SIM)
test_boundary_ostd:    ; $(MAKE) sim UVM_TEST=axi_boundary_ostd_test SIM=$(SIM)

# Backpressure tests
test_bp_wready:        ; $(MAKE) sim UVM_TEST=axi_bp_wready_test SIM=$(SIM)
test_bp_bready:        ; $(MAKE) sim UVM_TEST=axi_bp_bready_test SIM=$(SIM)
test_bp_rready:        ; $(MAKE) sim UVM_TEST=axi_bp_rready_test SIM=$(SIM)
test_bp_all:           ; $(MAKE) sim UVM_TEST=axi_bp_all_test SIM=$(SIM)

# Reset tests
test_reset_wr:         ; $(MAKE) sim UVM_TEST=axi_reset_wr_test SIM=$(SIM)
test_reset_rd:         ; $(MAKE) sim UVM_TEST=axi_reset_rd_test SIM=$(SIM)
test_reset_recovery:   ; $(MAKE) sim UVM_TEST=axi_reset_recovery_test SIM=$(SIM)

# Random tests
test_random:           ; $(MAKE) sim UVM_TEST=axi_random_test SIM=$(SIM)
test_random_concurrent:; $(MAKE) sim UVM_TEST=axi_random_concurrent_test SIM=$(SIM)

# Performance tests
test_perf_latency:     ; $(MAKE) sim UVM_TEST=axi_perf_latency_test SIM=$(SIM)
test_perf_bandwidth:   ; $(MAKE) sim UVM_TEST=axi_perf_bandwidth_test SIM=$(SIM)

regression:
	$(MAKE) test_basic SIM=$(SIM)
	$(MAKE) test_routing SIM=$(SIM)
	$(MAKE) test_protocol SIM=$(SIM)
	$(MAKE) test_burst_size SIM=$(SIM)
	$(MAKE) test_outstanding SIM=$(SIM)
	$(MAKE) test_outstanding_read SIM=$(SIM)
	$(MAKE) test_multi SIM=$(SIM)
	$(MAKE) test_same_slave SIM=$(SIM)
	$(MAKE) test_interleave SIM=$(SIM)
	$(MAKE) test_full_routing SIM=$(SIM)
	$(MAKE) test_err_slverr SIM=$(SIM)
	$(MAKE) test_err_decerr SIM=$(SIM)
	$(MAKE) test_err_recovery SIM=$(SIM)
	$(MAKE) test_boundary_addr SIM=$(SIM)
	$(MAKE) test_boundary_burst SIM=$(SIM)
	$(MAKE) test_boundary_ostd SIM=$(SIM)
	$(MAKE) test_bp_wready SIM=$(SIM)
	$(MAKE) test_bp_bready SIM=$(SIM)
	$(MAKE) test_bp_rready SIM=$(SIM)
	$(MAKE) test_bp_all SIM=$(SIM)
	$(MAKE) test_reset_wr SIM=$(SIM)
	$(MAKE) test_reset_rd SIM=$(SIM)
	$(MAKE) test_reset_recovery SIM=$(SIM)
	$(MAKE) test_random SIM=$(SIM)
	$(MAKE) test_perf_latency SIM=$(SIM)
	$(MAKE) test_perf_bandwidth SIM=$(SIM)
	$(MAKE) cov SIM=$(SIM)

help:
	@echo "Targets: compile sim gui cov regression clean"
	@echo "Basic:   test_basic test_routing test_protocol test_burst_size"
	@echo "         test_outstanding test_outstanding_read test_multi"
	@echo "         test_same_slave test_interleave"
	@echo "Error:   test_err_slverr test_err_decerr test_err_recovery"
	@echo "Bound:   test_boundary_addr test_boundary_burst test_boundary_ostd"
	@echo "BP:      test_bp_wready test_bp_bready test_bp_rready test_bp_all"
	@echo "Reset:   test_reset_wr test_reset_rd test_reset_recovery"
	@echo "Random:  test_random test_random_concurrent"
	@echo "Perf:    test_perf_latency test_perf_bandwidth"
	@echo "Vars:    SIM=vcs|xcelium  UVM_TEST=<testname>"
