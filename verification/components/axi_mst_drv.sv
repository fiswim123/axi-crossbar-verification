//==========================================================================
// Master Driver
//==========================================================================
class axi_mst_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_mst_drv)

    virtual axi_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction

    task run_phase(uvm_phase phase);
        vif.awvalid <= 0; vif.wvalid <= 0;
        vif.bready  <= 0; vif.arvalid <= 0; vif.rready <= 0;
        vif.awlock <= 0; vif.awcache <= 0; vif.awprot <= 0;
        vif.awqos  <= 0; vif.awregion <= 0;
        vif.arlock <= 0; vif.arcache <= 0; vif.arprot <= 0;
        vif.arqos  <= 0; vif.arregion <= 0;
        forever begin
            axi_txn txn;
            seq_item_port.get_next_item(txn);
            if (txn.kind == axi_txn::WRITE) drive_wr(txn);
            else                            drive_rd(txn);
            seq_item_port.item_done();
        end
    endtask

    task drive_wr(axi_txn txn);
        @(posedge vif.aclk);
        vif.awvalid <= 1; vif.awaddr <= txn.addr;
        vif.awlen <= txn.len; vif.awsize <= txn.size;
        vif.awburst <= txn.burst; vif.awid <= txn.id;
        vif.awlock <= 0; vif.awcache <= 0; vif.awprot <= 3'b010;
        do @(posedge vif.aclk); while (!vif.awready);
        vif.awvalid <= 0;

        for (int i = 0; i <= txn.len; i++) begin
            vif.wvalid <= 1; vif.wdata <= txn.wdata[i];
            vif.wstrb <= txn.wstrb[i]; vif.wlast <= (i == txn.len);
            do @(posedge vif.aclk); while (!vif.wready);
        end
        vif.wvalid <= 0; vif.wlast <= 0;

        vif.bready <= 1;
        do @(posedge vif.aclk); while (!vif.bvalid);
        txn.bid = vif.bid; txn.bresp = vif.bresp;
        vif.bready <= 0;
    endtask

    task drive_rd(axi_txn txn);
        vif.rready <= 1;
        @(posedge vif.aclk);
        vif.arvalid <= 1; vif.araddr <= txn.addr;
        vif.arlen <= txn.len; vif.arsize <= txn.size;
        vif.arburst <= txn.burst; vif.arid <= txn.id;
        vif.arlock <= 0; vif.arcache <= 0; vif.arprot <= 3'b010;
        do @(posedge vif.aclk); while (!vif.arready);
        vif.arvalid <= 0;

        txn.rdata = new[txn.len + 1];
        for (int i = 0; i <= txn.len; i++) begin
            @(posedge vif.aclk);
            while (!vif.rvalid) @(posedge vif.aclk);
            txn.rdata[i] = vif.rdata;
            txn.rid = vif.rid; txn.rresp = vif.rresp;
        end
        vif.rready <= 0;
    endtask
endclass
