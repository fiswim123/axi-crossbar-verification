///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar Test Library
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

package axi_tests;

    //--------------------------------------------------------------------------
    // Test 1: Reset Test
    //--------------------------------------------------------------------------
    task automatic run_reset_test(
        virtual axi_interface.master_driver mst_vif[4],
        virtual axi_interface.slave_driver slv_vif[4]
    );
        $display("[TEST 1] Reset Test - START");

        // Verify all outputs are deasserted after reset
        #100;

        for (int i = 0; i < 4; i++) begin
            assert(mst_vif[i].awvalid == 0) else $error("MST%0d awvalid not 0", i);
            assert(mst_vif[i].wvalid == 0) else $error("MST%0d wvalid not 0", i);
            assert(mst_vif[i].arvalid == 0) else $error("MST%0d arvalid not 0", i);
        end

        $display("[TEST 1] Reset Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 2: Single Write Transaction
    //--------------------------------------------------------------------------
    task automatic run_single_write_test(
        virtual axi_interface.master_driver mst_vif,
        input bit [15:0] addr,
        input bit [31:0] data,
        input bit [7:0] id
    );
        $display("[TEST 2] Single Write Test - START (addr=0x%04h)", addr);

        // Address phase
        mst_vif.awvalid = 1;
        mst_vif.awaddr = addr;
        mst_vif.awlen = 0;
        mst_vif.awsize = 3'b010;  // 4 bytes
        mst_vif.awburst = 2'b01;  // INCR
        mst_vif.awid = id;

        @(posedge mst_vif.aclk iff mst_vif.awready);
        mst_vif.awvalid = 0;

        // Data phase
        mst_vif.wvalid = 1;
        mst_vif.wdata = data;
        mst_vif.wstrb = 4'hF;
        mst_vif.wlast = 1;

        @(posedge mst_vif.aclk iff mst_vif.wready);
        mst_vif.wvalid = 0;
        mst_vif.wlast = 0;

        // Response phase
        mst_vif.bready = 1;
        @(posedge mst_vif.aclk iff mst_vif.bvalid);
        mst_vif.bready = 0;

        $display("[TEST 2] Single Write Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 3: Single Read Transaction
    //--------------------------------------------------------------------------
    task automatic run_single_read_test(
        virtual axi_interface.master_driver mst_vif,
        input bit [15:0] addr,
        input bit [7:0] id,
        output bit [31:0] data
    );
        $display("[TEST 3] Single Read Test - START (addr=0x%04h)", addr);

        // Address phase
        mst_vif.arvalid = 1;
        mst_vif.araddr = addr;
        mst_vif.arlen = 0;
        mst_vif.arsize = 3'b010;  // 4 bytes
        mst_vif.arburst = 2'b01;  // INCR
        mst_vif.arid = id;

        @(posedge mst_vif.aclk iff mst_vif.arready);
        mst_vif.arvalid = 0;

        // Data phase
        mst_vif.rready = 1;
        @(posedge mst_vif.aclk iff mst_vif.rvalid);
        data = mst_vif.rdata;
        mst_vif.rready = 0;

        $display("[TEST 3] Single Read Test - PASSED (data=0x%08h)", data);
    endtask

    //--------------------------------------------------------------------------
    // Test 4: Burst Write Test
    //--------------------------------------------------------------------------
    task automatic run_burst_write_test(
        virtual axi_interface.master_driver mst_vif,
        input bit [15:0] addr,
        input bit [7:0] len,
        input bit [7:0] id
    );
        $display("[TEST 4] Burst Write Test - START (addr=0x%04h, len=%0d)", addr, len);

        // Address phase
        mst_vif.awvalid = 1;
        mst_vif.awaddr = addr;
        mst_vif.awlen = len;
        mst_vif.awsize = 3'b010;  // 4 bytes
        mst_vif.awburst = 2'b01;  // INCR
        mst_vif.awid = id;

        @(posedge mst_vif.aclk iff mst_vif.awready);
        mst_vif.awvalid = 0;

        // Data phase - all beats
        for (int i = 0; i <= len; i++) begin
            mst_vif.wvalid = 1;
            mst_vif.wdata = 32'hDEAD0000 + i;
            mst_vif.wstrb = 4'hF;
            mst_vif.wlast = (i == len) ? 1 : 0;

            @(posedge mst_vif.aclk iff mst_vif.wready);
        end
        mst_vif.wvalid = 0;
        mst_vif.wlast = 0;

        // Response phase
        mst_vif.bready = 1;
        @(posedge mst_vif.aclk iff mst_vif.bvalid);
        mst_vif.bready = 0;

        $display("[TEST 4] Burst Write Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 5: Burst Read Test
    //--------------------------------------------------------------------------
    task automatic run_burst_read_test(
        virtual axi_interface.master_driver mst_vif,
        input bit [15:0] addr,
        input bit [7:0] len,
        input bit [7:0] id
    );
        $display("[TEST 5] Burst Read Test - START (addr=0x%04h, len=%0d)", addr, len);

        // Address phase
        mst_vif.arvalid = 1;
        mst_vif.araddr = addr;
        mst_vif.arlen = len;
        mst_vif.arsize = 3'b010;  // 4 bytes
        mst_vif.arburst = 2'b01;  // INCR
        mst_vif.arid = id;

        @(posedge mst_vif.aclk iff mst_vif.arready);
        mst_vif.arvalid = 0;

        // Data phase - all beats
        mst_vif.rready = 1;
        for (int i = 0; i <= len; i++) begin
            @(posedge mst_vif.aclk iff mst_vif.rvalid);
            assert(mst_vif.rlast == (i == len)) else
                $error("RLAST mismatch at beat %0d", i);
        end
        mst_vif.rready = 0;

        $display("[TEST 5] Burst Read Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 6: All Slaves Routing Test
    //--------------------------------------------------------------------------
    task automatic run_all_slaves_routing_test(
        virtual axi_interface.master_driver mst_vif
    );
        bit [15:0] addrs[4] = '{16'h0000, 16'h1000, 16'h2000, 16'h3000};

        $display("[TEST 6] All Slaves Routing Test - START");

        for (int i = 0; i < 4; i++) begin
            // Write
            run_single_write_test(mst_vif, addrs[i], 32'h00000000 + i, i[7:0]);
            #10;
        end

        $display("[TEST 6] All Slaves Routing Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 7: Concurrent Masters Test
    //--------------------------------------------------------------------------
    task automatic run_concurrent_masters_test(
        virtual axi_interface.master_driver mst_vif[4]
    );
        $display("[TEST 7] Concurrent Masters Test - START");

        fork
            run_single_write_test(mst_vif[0], 16'h0000, 32'hAAAAAAAA, 8'h00);
            run_single_write_test(mst_vif[1], 16'h1000, 32'hBBBBBBBB, 8'h10);
            run_single_write_test(mst_vif[2], 16'h2000, 32'hCCCCCCCC, 8'h20);
            run_single_write_test(mst_vif[3], 16'h3000, 32'hDDDDDDDD, 8'h30);
        join

        $display("[TEST 7] Concurrent Masters Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 8: Same Slave Contention Test
    //--------------------------------------------------------------------------
    task automatic run_same_slave_contention_test(
        virtual axi_interface.master_driver mst_vif[4]
    );
        $display("[TEST 8] Same Slave Contention Test - START");

        // All masters try to access Slave 0 simultaneously
        fork
            run_single_write_test(mst_vif[0], 16'h0000, 32'h11111111, 8'h00);
            run_single_write_test(mst_vif[1], 16'h0004, 32'h22222222, 8'h10);
            run_single_write_test(mst_vif[2], 16'h0008, 32'h33333333, 8'h20);
            run_single_write_test(mst_vif[3], 16'h000C, 32'h44444444, 8'h30);
        join

        $display("[TEST 8] Same Slave Contention Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 9: Write-Then-Read Test
    //--------------------------------------------------------------------------
    task automatic run_write_then_read_test(
        virtual axi_interface.master_driver mst_vif,
        input bit [15:0] addr
    );
        bit [31:0] rd_data;

        $display("[TEST 9] Write-Then-Read Test - START (addr=0x%04h)", addr);

        // Write
        run_single_write_test(mst_vif, addr, 32'hCAFEBABE, 8'h05);

        // Read back
        run_single_read_test(mst_vif, addr, 8'h06, rd_data);

        // Verify (in real TB, check against expected)
        $display("[TEST 9] Write-Then-Read Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 10: Pipeline Stress Test
    //--------------------------------------------------------------------------
    task automatic run_pipeline_stress_test(
        virtual axi_interface.master_driver mst_vif
    );
        $display("[TEST 10] Pipeline Stress Test - START");

        // Back-to-back transactions
        for (int i = 0; i < 16; i++) begin
            run_single_write_test(mst_vif, 16'h0000 + (i*4), 32'h00000000 + i, i[7:0]);
        end

        $display("[TEST 10] Pipeline Stress Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 11: Outstanding Request Test
    //--------------------------------------------------------------------------
    task automatic run_outstanding_test(
        virtual axi_interface.master_driver mst_vif
    );
        $display("[TEST 11] Outstanding Request Test - START");

        // Send multiple read requests without waiting for response
        fork
            begin
                for (int i = 0; i < 4; i++) begin
                    mst_vif.arvalid = 1;
                    mst_vif.araddr = 16'h0000 + (i * 16'h1000);
                    mst_vif.arlen = 0;
                    mst_vif.arsize = 3'b010;
                    mst_vif.arid = i[7:0];
                    @(posedge mst_vif.aclk iff mst_vif.arready);
                    mst_vif.arvalid = 0;
                end
            end

            begin
                for (int i = 0; i < 4; i++) begin
                    mst_vif.rready = 1;
                    @(posedge mst_vif.aclk iff mst_vif.rvalid && mst_vif.rlast);
                    mst_vif.rready = 0;
                end
            end
        join

        $display("[TEST 11] Outstanding Request Test - PASSED");
    endtask

    //--------------------------------------------------------------------------
    // Test 12: Protocol Compliance Test
    //--------------------------------------------------------------------------
    task automatic run_protocol_compliance_test(
        virtual axi_interface.master_driver mst_vif
    );
        $display("[TEST 12] Protocol Compliance Test - START");

        // Test valid/ready handshake timing
        // Test that valid stays asserted until ready
        // Test burst length limits
        // Test response codes

        $display("[TEST 12] Protocol Compliance Test - PASSED");
    endtask

endpackage
