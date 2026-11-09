`timescale 1ns/1ps

package axi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Shared transaction/configuration and the common bus monitor.
    `include "common/axi_slv_cfg.sv"
    `include "common/axi_txn.sv"
    `include "common/axi_monitor.sv"

    // The two agent types retain the original driver/monitor behavior.
    `include "agent/mst/axi_mst_monitor.sv"
    `include "agent/mst/axi_mst_drv.sv"
    `include "agent/mst/axi_mst_agent.sv"
    `include "agent/slv/axi_slv_monitor.sv"
    `include "agent/slv/axi_slv_drv.sv"
    `include "agent/slv/axi_slv_agent.sv"

    `include "env/axi_scoreboard.sv"
    `include "env/axi_coverage.sv"
    `include "env/axi_env.sv"

    // The sequence and test order is maintained in one place.
    `include "tc/tc.f"
endpackage : axi_pkg
