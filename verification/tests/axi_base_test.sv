//==========================================================================
// Helper tasks (module-level callable)
//==========================================================================

task automatic mst_write(
    virtual axi_if vif,
    input bit [15:0] addr,
    input bit [31:0] data,
    input bit [7:0]  id
);
    @(posedge vif.aclk);
    vif.awvalid <= 1; vif.awaddr <= addr;
    vif.awlen <= 0; vif.awsize <= 2; vif.awburst <= 1;
    vif.awid <= id; vif.awlock <= 0; vif.awcache <= 0; vif.awprot <= 3'b010;
    do @(posedge vif.aclk); while (!vif.awready);
    vif.awvalid <= 0;

    vif.wvalid <= 1; vif.wdata <= data;
    vif.wstrb <= 4'hF; vif.wlast <= 1;
    do @(posedge vif.aclk); while (!vif.wready);
    vif.wvalid <= 0; vif.wlast <= 0;

    vif.bready <= 1;
    do @(posedge vif.aclk); while (!vif.bvalid);
    vif.bready <= 0;
endtask

task automatic mst_read(
    virtual axi_if  vif,
    input  bit [15:0] addr,
    input  bit [7:0]  id,
    output bit [31:0] data
);
    vif.rready <= 1;
    @(posedge vif.aclk);
    vif.arvalid <= 1; vif.araddr <= addr;
    vif.arlen <= 0; vif.arsize <= 2; vif.arburst <= 1;
    vif.arid <= id; vif.arlock <= 0; vif.arcache <= 0; vif.arprot <= 3'b010;
    do @(posedge vif.aclk); while (!vif.arready);
    vif.arvalid <= 0;

    @(posedge vif.aclk);
    while (!vif.rvalid) @(posedge vif.aclk);
    data = vif.rdata;
    vif.rready <= 0;
endtask

task automatic mst_burst_write(
    virtual axi_if vif,
    input bit [15:0] addr,
    input bit [7:0]  id,
    input bit [7:0]  len
);
    @(posedge vif.aclk);
    vif.awvalid <= 1; vif.awaddr <= addr;
    vif.awlen <= len; vif.awsize <= 2; vif.awburst <= 1;
    vif.awid <= id; vif.awlock <= 0; vif.awcache <= 0; vif.awprot <= 3'b010;
    do @(posedge vif.aclk); while (!vif.awready);
    vif.awvalid <= 0;

    for (int i = 0; i <= len; i++) begin
        vif.wvalid <= 1; vif.wdata <= 32'hA500_0000 + i;
        vif.wstrb <= 4'hF; vif.wlast <= (i == len);
        do @(posedge vif.aclk); while (!vif.wready);
    end
    vif.wvalid <= 0; vif.wlast <= 0;

    vif.bready <= 1;
    do @(posedge vif.aclk); while (!vif.bvalid);
    vif.bready <= 0;
endtask

//==========================================================================
// Base Test
//==========================================================================
class axi_base_test extends uvm_test;
    `uvm_component_utils(axi_base_test)
    axi_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction
endclass
