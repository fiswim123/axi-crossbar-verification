///////////////////////////////////////////////////////////////////////////////
//
// AXI Slave Agent - Driver + Monitor
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

class axi_slv_agent #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
);

    // Virtual interface
    virtual axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ).slave_driver vif;

    // Response mailbox
    mailbox #(axi_transaction) rsp_mbx;

    // Memory model
    bit [7:0] mem[];

    // Latency control
    int min_latency;
    int max_latency;

    // Statistics
    int wr_count;
    int rd_count;

    function new(virtual axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ).slave_driver vif, int mem_size = 65536);
        this.vif = vif;
        this.rsp_mbx = new();
        this.mem = new[mem_size];
        this.min_latency = 1;
        this.max_latency = 5;
        this.wr_count = 0;
        this.rd_count = 0;
    endfunction

    //--------------------------------------------------------------------------
    // Reset Task
    //--------------------------------------------------------------------------
    task reset();
        vif.slv_drv_cb.awready <= 1'b0;
        vif.slv_drv_cb.wready  <= 1'b0;
        vif.slv_drv_cb.bvalid  <= 1'b0;
        vif.slv_drv_cb.bid     <= 0;
        vif.slv_drv_cb.bresp   <= 0;
        vif.slv_drv_cb.arready <= 1'b0;
        vif.slv_drv_cb.rvalid  <= 1'b0;
        vif.slv_drv_cb.rid     <= 0;
        vif.slv_drv_cb.rresp   <= 0;
        vif.slv_drv_cb.rdata   <= 0;
        vif.slv_drv_cb.rlast   <= 1'b0;
    endtask

    //--------------------------------------------------------------------------
    // Random Latency
    //--------------------------------------------------------------------------
    task random_latency();
        int latency;
        latency = $urandom_range(max_latency, min_latency);
        repeat(latency) @(posedge vif.aclk);
    endtask

    //--------------------------------------------------------------------------
    // Write Handler
    //--------------------------------------------------------------------------
    task handle_write();
        axi_transaction txn;
        bit [AXI_ID_W-1:0] awid;
        bit [AXI_ADDR_W-1:0] awaddr;
        bit [7:0] awlen;
        int burst_len;

        forever begin
            // Accept write address
            vif.slv_drv_cb.awready <= 1'b1;
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));

            awid    = vif.awid;
            awaddr  = vif.awaddr;
            awlen   = vif.awlen;
            burst_len = awlen + 1;

            vif.slv_drv_cb.awready <= 1'b0;

            // Accept write data
            for (int i = 0; i < burst_len; i++) begin
                vif.slv_drv_cb.wready <= 1'b1;
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));

                // Store to memory
                for (int b = 0; b < AXI_DATA_W/8; b++) begin
                    if (vif.wstrb[b]) begin
                        mem[awaddr + b] = vif.wdata[b*8 +: 8];
                    end
                end

                if (vif.wlast) break;
                awaddr += (1 << vif.awsize);
            end
            vif.slv_drv_cb.wready <= 1'b0;

            // Random latency before response
            random_latency();

            // Send write response
            vif.slv_drv_cb.bid    <= awid;
            vif.slv_drv_cb.bresp  <= 2'b00; // OKAY
            vif.slv_drv_cb.bvalid <= 1'b1;

            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            vif.slv_drv_cb.bvalid <= 1'b0;
            wr_count++;
        end
    endtask

    //--------------------------------------------------------------------------
    // Read Handler
    //--------------------------------------------------------------------------
    task handle_read();
        bit [AXI_ID_W-1:0] arid;
        bit [AXI_ADDR_W-1:0] araddr;
        bit [7:0] arlen;
        bit [2:0] arsize;
        int burst_len;

        forever begin
            // Accept read address
            vif.slv_drv_cb.arready <= 1'b1;
            @(posedge vif.aclk iff (vif.arvalid && vif.arready));

            arid    = vif.arid;
            araddr  = vif.araddr;
            arlen   = vif.arlen;
            arsize  = vif.arsize;
            burst_len = arlen + 1;

            vif.slv_drv_cb.arready <= 1'b0;

            // Random latency before data
            random_latency();

            // Send read data
            for (int i = 0; i < burst_len; i++) begin
                logic [AXI_DATA_W-1:0] rdata;

                // Read from memory
                for (int b = 0; b < AXI_DATA_W/8; b++) begin
                    rdata[b*8 +: 8] = mem[araddr + b];
                end

                vif.slv_drv_cb.rid    <= arid;
                vif.slv_drv_cb.rdata  <= rdata;
                vif.slv_drv_cb.rresp  <= 2'b00; // OKAY
                vif.slv_drv_cb.rlast  <= (i == burst_len - 1) ? 1'b1 : 1'b0;
                vif.slv_drv_cb.rvalid <= 1'b1;

                @(posedge vif.aclk iff (vif.rvalid && vif.rready));
                araddr += (1 << arsize);
            end
            vif.slv_drv_cb.rvalid <= 1'b0;
            vif.slv_drv_cb.rlast  <= 1'b0;
            rd_count++;
        end
    endtask

    //--------------------------------------------------------------------------
    // Main Run Task
    //--------------------------------------------------------------------------
    task run();
        fork
            handle_write();
            handle_read();
        join
    endtask

endclass
