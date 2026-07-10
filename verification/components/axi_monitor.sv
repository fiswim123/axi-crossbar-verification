//==========================================================================
// Monitor
//==========================================================================
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_txn) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction

    task run_phase(uvm_phase phase);
        fork
            mon_wr();
            mon_rd();
        join
    endtask

    task mon_wr();
        forever begin
            axi_txn txn;
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));
            txn = axi_txn::type_id::create("wr_txn");
            txn.kind = axi_txn::WRITE;
            txn.addr = vif.awaddr; txn.id = vif.awid;
            txn.len = vif.awlen; txn.size = vif.awsize;
            txn.wdata = new[txn.len + 1]; txn.wstrb = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));
                txn.wdata[i] = vif.wdata; txn.wstrb[i] = vif.wstrb;
            end
            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            txn.bid = vif.bid; txn.bresp = vif.bresp;
            ap.write(txn);
        end
    endtask

    task mon_rd();
        forever begin
            axi_txn txn;
            @(posedge vif.aclk iff (vif.arvalid && vif.arready));
            txn = axi_txn::type_id::create("rd_txn");
            txn.kind = axi_txn::READ;
            txn.addr = vif.araddr; txn.id = vif.arid;
            txn.len = vif.arlen; txn.size = vif.arsize;
            txn.rdata = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.rvalid && vif.rready));
                txn.rdata[i] = vif.rdata;
                txn.rid = vif.rid; txn.rresp = vif.rresp;
            end
            ap.write(txn);
        end
    endtask
endclass
