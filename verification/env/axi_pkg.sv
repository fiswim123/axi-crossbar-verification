`timescale 1ns/1ps

package axi_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //==========================================================================
    // Components
    //==========================================================================
    `include "components/axi_slv_cfg.sv"
    `include "components/axi_txn.sv"
    `include "components/axi_mst_drv.sv"
    `include "components/axi_slv_drv.sv"
    `include "components/axi_monitor.sv"
    `include "components/axi_scoreboard.sv"
    `include "components/axi_coverage.sv"
    `include "components/axi_env.sv"

    //==========================================================================
    // Sequences
    //==========================================================================
    `include "sequences/axi_wr_seq.sv"
    `include "sequences/axi_rd_seq.sv"
    `include "sequences/axi_burst_wr_seq.sv"
    `include "sequences/axi_burst_rd_seq.sv"
    `include "sequences/axi_burst_size_seq.sv"
    `include "sequences/axi_outstanding_read_seq.sv"
    `include "sequences/axi_same_slave_seq.sv"
    `include "sequences/axi_interleave_seq.sv"
    `include "sequences/axi_concurrent_seq.sv"
    `include "sequences/axi_err_inject_seq.sv"
    `include "sequences/axi_boundary_seq.sv"
    `include "sequences/axi_backpressure_seq.sv"
    `include "sequences/axi_random_seq.sv"
    `include "sequences/axi_perf_seq.sv"

    //==========================================================================
    // Tests
    //==========================================================================
    `include "tests/axi_base_test.sv"
    `include "tests/axi_basic_test.sv"
    `include "tests/axi_routing_test.sv"
    `include "tests/axi_protocol_test.sv"
    `include "tests/axi_burst_size_test.sv"
    `include "tests/axi_outstanding_test.sv"
    `include "tests/axi_outstanding_read_test.sv"
    `include "tests/axi_multi_master_test.sv"
    `include "tests/axi_same_slave_test.sv"
    `include "tests/axi_interleave_test.sv"
    `include "tests/axi_err_slverr_test.sv"
    `include "tests/axi_err_decerr_test.sv"
    `include "tests/axi_err_recovery_test.sv"
    `include "tests/axi_boundary_addr_test.sv"
    `include "tests/axi_boundary_burst_test.sv"
    `include "tests/axi_boundary_ostd_test.sv"
    `include "tests/axi_bp_wready_test.sv"
    `include "tests/axi_bp_bready_test.sv"
    `include "tests/axi_bp_rready_test.sv"
    `include "tests/axi_bp_all_test.sv"
    `include "tests/axi_random_test.sv"
    `include "tests/axi_random_concurrent_test.sv"
    `include "tests/axi_perf_latency_test.sv"
    `include "tests/axi_perf_bandwidth_test.sv"

endpackage
