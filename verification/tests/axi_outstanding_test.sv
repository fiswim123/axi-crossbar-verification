//==========================================================================
// T030: Outstanding Write test
//==========================================================================
class axi_outstanding_test extends axi_base_test;
    `uvm_component_utils(axi_outstanding_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        virtual axi_if v;
        phase.raise_objection(this);
        v = env.mst_drv[0].vif;
        @(posedge v.aresetn); repeat(5) @(posedge v.aclk);

        // T030: 4 outstanding writes (pipeline AW+W, collect B later)
        for (int i = 0; i < 4; i++) begin
            @(posedge v.aclk);
            v.awvalid <= 1; v.awaddr <= i * 16'h1000;
            v.awlen <= 0; v.awsize <= 2; v.awburst <= 1;
            v.awid <= 8'h10; v.awlock <= 0; v.awcache <= 0; v.awprot <= 3'b010;
            do @(posedge v.aclk); while (!v.awready);
            v.awvalid <= 0;
            v.wvalid <= 1; v.wdata <= 32'hDEAD0000 + i;
            v.wstrb <= 4'hF; v.wlast <= 1;
            do @(posedge v.aclk); while (!v.wready);
            v.wvalid <= 0; v.wlast <= 0;
        end

        // Collect 4 B responses
        for (int i = 0; i < 4; i++) begin
            v.bready <= 1;
            do @(posedge v.aclk); while (!v.bvalid);
            v.bready <= 0;
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
