//==========================================================================
// Slave Driver (Memory Model with Error Injection & Backpressure)
//==========================================================================
class axi_slv_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_slv_drv)

    virtual axi_if vif;
    bit [7:0] mem[bit [31:0]];
    axi_slv_cfg cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
        // Get config or use default
        if (!uvm_config_db#(axi_slv_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = axi_slv_cfg::type_id::create("cfg");
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.awready <= 0; vif.wready <= 0;
        vif.bvalid <= 0; vif.bid <= 0; vif.bresp <= 0;
        vif.arready <= 0; vif.rvalid <= 0;
        vif.rid <= 0; vif.rresp <= 0; vif.rdata <= 0; vif.rlast <= 0;
        fork
            wr_handler();
            rd_handler();
        join
    endtask

    task wr_handler();
        bit [7:0]  awid;
        bit [31:0] awaddr, wr_addr;
        bit [7:0]  awlen;
        bit        inject_err;
        forever begin
            // AW channel with backpressure
            vif.awready <= 0;
            @(posedge vif.aclk);
            while (!(vif.awvalid && vif.awready)) begin
                vif.awready <= !cfg.should_bp(0);
                @(posedge vif.aclk);
            end
            awid = vif.awid; awaddr = vif.awaddr; awlen = vif.awlen;
            wr_addr = awaddr;
            inject_err = cfg.should_error();
            vif.awready <= 0;

            // W channel with backpressure
            for (int i = 0; i < awlen + 1; i++) begin
                vif.wready <= !cfg.should_bp(1);
                @(posedge vif.aclk);
                while (!(vif.wvalid && vif.wready)) begin
                    vif.wready <= !cfg.should_bp(1);
                    @(posedge vif.aclk);
                end
                if (!inject_err) begin
                    mem[wr_addr]     = vif.wdata[7:0];
                    mem[wr_addr + 1] = vif.wdata[15:8];
                    mem[wr_addr + 2] = vif.wdata[23:16];
                    mem[wr_addr + 3] = vif.wdata[31:24];
                end
                wr_addr += 4;
            end
            vif.wready <= 0;

            // Optional delay
            repeat(cfg.get_delay()) @(posedge vif.aclk);

            // B response (with error injection)
            vif.bid <= awid;
            vif.bresp <= inject_err ? cfg.err_resp : 2'b00;
            vif.bvalid <= 1;
            @(posedge vif.aclk);
            while (!vif.bready) @(posedge vif.aclk);
            vif.bvalid <= 0;
        end
    endtask

    task rd_handler();
        bit [7:0]  arid;
        bit [31:0] araddr;
        int        blen;
        bit        inject_err;
        forever begin
            // AR channel with backpressure
            vif.arready <= 0;
            @(posedge vif.aclk);
            while (!(vif.arvalid && vif.arready)) begin
                vif.arready <= !cfg.should_bp(2);
                @(posedge vif.aclk);
            end
            arid = vif.arid; araddr = vif.araddr; blen = vif.arlen + 1;
            inject_err = cfg.should_error();
            vif.arready <= 0;

            // Optional delay
            repeat(cfg.get_delay()) @(posedge vif.aclk);

            // R response
            for (int i = 0; i < blen; i++) begin
                vif.rid <= arid;
                vif.rdata <= inject_err ? 32'hDEAD_BEEF :
                             {mem[araddr+3], mem[araddr+2],
                              mem[araddr+1], mem[araddr]};
                vif.rresp <= inject_err ? cfg.err_resp : 2'b00;
                vif.rlast <= (i == blen - 1);
                vif.rvalid <= 1;
                @(posedge vif.aclk);
                while (!vif.rready) @(posedge vif.aclk);
                araddr += 4;
            end
            vif.rvalid <= 0; vif.rlast <= 0;
        end
    endtask
endclass
