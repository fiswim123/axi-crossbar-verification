///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar Coverage Collector
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

class axi_coverage #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32,
    parameter MST_NB = 4,
    parameter SLV_NB = 4
);

    // Transaction for sampling
    axi_transaction txn;

    // Covergroup for AXI transactions
    covergroup axi_txn_cg;

        // Transaction type
        cp_txn_type: coverpoint txn.txn_type {
            bins read  = {axi_transaction::READ};
            bins write = {axi_transaction::WRITE};
        }

        // Address ranges for each slave
        cp_addr_range: coverpoint txn.addr[15:12] {
            bins slv0 = {[0:0]};      // 0x0000-0x0FFF
            bins slv1 = {[1:1]};      // 0x1000-0x1FFF
            bins slv2 = {[2:2]};      // 0x2000-0x2FFF
            bins slv3 = {[3:3]};      // 0x3000-0x3FFF
        }

        // Burst length
        cp_burst_len: coverpoint txn.len {
            bins single = {0};
            bins short  = {[1:3]};
            bins medium = {[4:7]};
            bins long   = {[8:15]};
            bins max    = {[16:255]};
        }

        // Burst size
        cp_burst_size: coverpoint txn.size {
            bins byte1 = {0};  // 1 byte
            bins byte2 = {1};  // 2 bytes
            bins byte4 = {2};  // 4 bytes
        }

        // Burst type
        cp_burst_type: coverpoint txn.burst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }

        // ID range
        cp_id: coverpoint txn.id {
            bins slv0_id = {[8'h00:8'h0F]};
            bins slv1_id = {[8'h10:8'h1F]};
            bins slv2_id = {[8'h20:8'h2F]};
            bins slv3_id = {[8'h30:8'h3F]};
        }

        // Response
        cp_response: coverpoint (txn.txn_type == axi_transaction::WRITE) ?
                     txn.bresp : txn.rresp {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }

        // Cross coverage
        cx_type_addr: cross cp_txn_type, cp_addr_range;
        cx_type_len: cross cp_txn_type, cp_burst_len;
        cx_type_size: cross cp_txn_type, cp_burst_size;
        cx_addr_len: cross cp_addr_range, cp_burst_len;

    endgroup

    // Covergroup for crossbar-specific coverage
    covergroup crossbar_cg;

        // Master to slave routing
        cp_mst_idx: coverpoint txn.id[7:4] {
            bins mst0 = {4'h0};
            bins mst1 = {4'h1};
            bins mst2 = {4'h2};
            bins mst3 = {4'h3};
        }

        cp_slv_idx: coverpoint txn.addr[15:12] {
            bins slv0 = {4'h0};
            bins slv1 = {4'h1};
            bins slv2 = {4'h2};
            bins slv3 = {4'h3};
        }

        // All master-slave combinations
        cx_routing: cross cp_mst_idx, cp_slv_idx;

    endgroup

    // Covergroup for arbitration coverage
    covergroup arbitration_cg;

        // Priority levels used
        cp_priority: coverpoint txn.id[3:0] {
            bins pri0 = {0};
            bins pri1 = {1};
            bins pri2 = {2};
            bins pri3 = {3};
        }

        // Concurrent request scenarios (indirect)
        cp_outstanding: coverpoint txn.len {
            bins low  = {[0:3]};
            bins high = {[4:255]};
        }

    endgroup

    // Constructor
    function new();
        axi_txn_cg = new();
        crossbar_cg = new();
        arbitration_cg = new();
    endfunction

    // Sample transaction
    function void sample(axi_transaction txn);
        this.txn = txn;
        axi_txn_cg.sample();
        crossbar_cg.sample();
        arbitration_cg.sample();
    endfunction

    // Report coverage
    function void report();
        $display("\n=== Coverage Report ===");
        $display("AXI Transaction Coverage: %.2f%%", axi_txn_cg.get_coverage());
        $display("Crossbar Routing Coverage: %.2f%%", crossbar_cg.get_coverage());
        $display("Arbitration Coverage: %.2f%%", arbitration_cg.get_coverage());
        $display("Overall Functional Coverage: %.2f%%",
                 (axi_txn_cg.get_coverage() +
                  crossbar_cg.get_coverage() +
                  arbitration_cg.get_coverage()) / 3.0);
        $display("========================\n");
    endfunction

endclass
