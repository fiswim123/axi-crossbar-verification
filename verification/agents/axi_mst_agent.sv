///////////////////////////////////////////////////////////////////////////////
//
// AXI Master Agent - Driver + Monitor
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

class axi_mst_agent #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
);

    // Virtual interface
    virtual axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ).master_driver vif;

    // Mailbox for transactions
    mailbox #(axi_transaction) aw_mbx;
    mailbox #(axi_transaction) w_mbx;
    mailbox #(axi_transaction) ar_mbx;

    // Outstanding tracking
    int outstanding_wtrans;
    int outstanding_rtrans;
    int max_outstanding;

    // Statistics
    int wr_count;
    int rd_count;

    function new(virtual axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ).master_driver vif, int max_outstanding = 4);
        this.vif = vif;
        this.max_outstanding = max_outstanding;
        this.aw_mbx = new();
        this.w_mbx = new();
        this.ar_mbx = new();
        this.outstanding_wtrans = 0;
        this.outstanding_rtrans = 0;
        this.wr_count = 0;
        this.rd_count = 0;
    endfunction

    //--------------------------------------------------------------------------
    // Reset Task
    //--------------------------------------------------------------------------
    task reset();
        vif.mst_drv_cb.awvalid <= 0;
        vif.mst_drv_cb.awaddr  <= 0;
        vif.mst_drv_cb.awlen   <= 0;
        vif.mst_drv_cb.awsize  <= 0;
        vif.mst_drv_cb.awburst <= 0;
        vif.mst_drv_cb.awlock  <= 0;
        vif.mst_drv_cb.awcache <= 0;
        vif.mst_drv_cb.awprot  <= 0;
        vif.mst_drv_cb.awqos   <= 0;
        vif.mst_drv_cb.awregion<= 0;
        vif.mst_drv_cb.awid    <= 0;
        vif.mst_drv_cb.awuser  <= 0;
        vif.mst_drv_cb.wvalid  <= 0;
        vif.mst_drv_cb.wlast   <= 0;
        vif.mst_drv_cb.wdata   <= 0;
        vif.mst_drv_cb.wstrb   <= 0;
        vif.mst_drv_cb.wuser   <= 0;
        vif.mst_drv_cb.bready  <= 0;
        vif.mst_drv_cb.arvalid <= 0;
        vif.mst_drv_cb.araddr  <= 0;
        vif.mst_drv_cb.arlen   <= 0;
        vif.mst_drv_cb.arsize  <= 0;
        vif.mst_drv_cb.arburst <= 0;
        vif.mst_drv_cb.arlock  <= 0;
        vif.mst_drv_cb.arcache <= 0;
        vif.mst_drv_cb.arprot  <= 0;
        vif.mst_drv_cb.arqos   <= 0;
        vif.mst_drv_cb.arregion<= 0;
        vif.mst_drv_cb.arid    <= 0;
        vif.mst_drv_cb.aruser  <= 0;
        vif.mst_drv_cb.rready  <= 0;
    endtask

    //--------------------------------------------------------------------------
    // Write Address Phase
    //--------------------------------------------------------------------------
    task aw_phase(axi_transaction txn);
        vif.mst_drv_cb.awvalid <= 1'b1;
        vif.mst_drv_cb.awaddr  <= txn.addr;
        vif.mst_drv_cb.awlen   <= txn.len;
        vif.mst_drv_cb.awsize  <= txn.size;
        vif.mst_drv_cb.awburst <= txn.burst;
        vif.mst_drv_cb.awlock  <= txn.lock;
        vif.mst_drv_cb.awcache <= txn.cache;
        vif.mst_drv_cb.awprot  <= txn.prot;
        vif.mst_drv_cb.awqos   <= txn.qos;
        vif.mst_drv_cb.awregion<= txn.region;
        vif.mst_drv_cb.awid    <= txn.id;

        do @(posedge vif.aclk);
        while (!vif.mst_drv_cb.awready);

        vif.mst_drv_cb.awvalid <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Write Data Phase
    //--------------------------------------------------------------------------
    task w_phase(axi_transaction txn);
        for (int i = 0; i <= txn.len; i++) begin
            vif.mst_drv_cb.wvalid <= 1'b1;
            vif.mst_drv_cb.wdata  <= txn.wdata[i];
            vif.mst_drv_cb.wstrb  <= txn.wstrb[i];
            vif.mst_drv_cb.wlast  <= (i == txn.len) ? 1'b1 : 1'b0;

            do @(posedge vif.aclk);
            while (!vif.mst_drv_cb.wready);
        end
        vif.mst_drv_cb.wvalid <= 1'b0;
        vif.mst_drv_cb.wlast  <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Write Response Phase
    //--------------------------------------------------------------------------
    task b_phase(axi_transaction txn);
        vif.mst_drv_cb.bready <= 1'b1;

        do @(posedge vif.aclk);
        while (!vif.bvalid);

        txn.bid   = vif.mst_drv_cb.bid;
        txn.bresp = vif.mst_drv_cb.bresp;
        vif.mst_drv_cb.bready <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Read Address Phase
    //--------------------------------------------------------------------------
    task ar_phase(axi_transaction txn);
        vif.mst_drv_cb.arvalid <= 1'b1;
        vif.mst_drv_cb.araddr  <= txn.addr;
        vif.mst_drv_cb.arlen   <= txn.len;
        vif.mst_drv_cb.arsize  <= txn.size;
        vif.mst_drv_cb.arburst <= txn.burst;
        vif.mst_drv_cb.arlock  <= txn.lock;
        vif.mst_drv_cb.arcache <= txn.cache;
        vif.mst_drv_cb.arprot  <= txn.prot;
        vif.mst_drv_cb.arqos   <= txn.qos;
        vif.mst_drv_cb.arregion<= txn.region;
        vif.mst_drv_cb.arid    <= txn.id;

        do @(posedge vif.aclk);
        while (!vif.mst_drv_cb.arready);

        vif.mst_drv_cb.arvalid <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Read Data Phase
    //--------------------------------------------------------------------------
    task r_phase(axi_transaction txn);
        txn.rdata = new[txn.len + 1];
        vif.mst_drv_cb.rready <= 1'b1;

        for (int i = 0; i <= txn.len; i++) begin
            do @(posedge vif.aclk);
            while (!vif.rvalid);

            txn.rdata[i] = vif.rdata;
            txn.rid      = vif.rid;
            txn.rresp    = vif.rresp;

            if (i == txn.len) begin
                assert(vif.rlast) else
                    $error("RLAST not asserted on last beat");
            end
        end
        vif.mst_drv_cb.rready <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Execute Write Transaction
    //--------------------------------------------------------------------------
    task execute_write(axi_transaction txn);
        fork
            aw_phase(txn);
            w_phase(txn);
        join
        b_phase(txn);
        wr_count++;
    endtask

    //--------------------------------------------------------------------------
    // Execute Read Transaction
    //--------------------------------------------------------------------------
    task execute_read(axi_transaction txn);
        ar_phase(txn);
        r_phase(txn);
        rd_count++;
    endtask

endclass
