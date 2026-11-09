SIM ?= vcs
UVM_TEST ?= axi_basic_test
SEED ?= 1
COV ?= 0

VERIFICATION_ROOT := $(abspath ..)
BUILD_DIR := $(abspath build)
SIMV := $(BUILD_DIR)/simv
RUN_DIR := $(BUILD_DIR)/runs/$(UVM_TEST)_$(SEED)
RTL_F := $(VERIFICATION_ROOT)/filelist/rtl.f
TB_F := $(VERIFICATION_ROOT)/filelist/tb.f

VCS_OPTS := -sverilog -full64 -ntb_opts uvm-1.2 -timescale=1ns/1ps \
            -debug_access+all +incdir+../../src
XCELIUM_OPTS := -sv -64bit -uvm -access +rwc +incdir+../../src
ifeq ($(COV),1)
VCS_OPTS += -cm line+cond+fsm+tgl+branch
endif

.PHONY: all compile run sim gui cov regression clean help test_basic test_routing
all: sim

compile:
	@mkdir -p $(BUILD_DIR)
ifeq ($(SIM),vcs)
	vcs $(VCS_OPTS) -f $(RTL_F) -f $(TB_F) -Mdir=$(BUILD_DIR)/csrc -o $(SIMV) -l $(BUILD_DIR)/compile.log
else ifeq ($(SIM),xcelium)
	xrun $(XCELIUM_OPTS) -f $(RTL_F) -f $(TB_F) -elaborate -xmlibdirname $(BUILD_DIR)/xcelium.d -l $(BUILD_DIR)/compile.log
else
	$(error Unsupported SIM=$(SIM); use vcs or xcelium)
endif

sim: compile run

run:
	@mkdir -p $(RUN_DIR)
ifeq ($(SIM),vcs)
	@test -x $(SIMV) || { echo 'Compile first: make compile'; exit 1; }
	cd $(RUN_DIR) && $(SIMV) +UVM_TESTNAME=$(UVM_TEST) +ntb_random_seed=$(SEED) \
	    +UVM_VERBOSITY=UVM_MEDIUM $(if $(filter 1,$(COV)),-cm line+cond+fsm+tgl+branch -cm_dir $(RUN_DIR)/cov_db,) \
	    $(PLUS_ARGS) -l $(RUN_DIR)/run.log
else
	cd $(RUN_DIR) && xrun -R -xmlibdirname $(BUILD_DIR)/xcelium.d +UVM_TESTNAME=$(UVM_TEST) \
	    +ntb_random_seed=$(SEED) $(PLUS_ARGS) -l $(RUN_DIR)/run.log
endif
	@awk '/^UVM_ERROR :|^UVM_FATAL :/ { if ($$3 + 0 > 0) failed = 1 } /\[SVA\]/ { failed = 1 } END { exit failed }' $(RUN_DIR)/run.log

gui: compile
	@mkdir -p $(RUN_DIR)

ifeq ($(SIM),vcs)
	cd $(RUN_DIR) && $(SIMV) +UVM_TESTNAME=$(UVM_TEST) -gui
else
	cd $(RUN_DIR) && xrun -R -gui -xmlibdirname $(BUILD_DIR)/xcelium.d +UVM_TESTNAME=$(UVM_TEST)
endif

cov:
	urg -dir $(BUILD_DIR)/simv.vdb $(wildcard $(BUILD_DIR)/runs/*/cov_db.vdb) -report $(BUILD_DIR)/coverage_report -format both

test_basic:
	$(MAKE) sim UVM_TEST=axi_basic_test

test_routing:
	$(MAKE) sim UVM_TEST=axi_routing_test

regression:
	./regress.sh

clean:
	rm -rf $(BUILD_DIR)

help:
	@echo 'make -C verification/sim sim UVM_TEST=axi_basic_test [SEED=1] [COV=1]'
	@echo 'Targets: compile run sim gui cov regression clean test_basic test_routing'
