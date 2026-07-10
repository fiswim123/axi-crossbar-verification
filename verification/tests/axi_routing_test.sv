//==========================================================================
// T010-T018: Routing
//==========================================================================
class axi_routing_test extends axi_base_test;
    `uvm_component_utils(axi_routing_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // All 4 slaves from master 0
        for (int s = 0; s < 4; s++)
            mst_write(env.mst_drv[0].vif, s * 16'h1000, 32'h00000000 + s, 8'h10);

        // Master 1 → SLV0
        mst_write(env.mst_drv[1].vif, 16'h0000, 32'h00000100, 8'h20);
        // Master 2 → SLV1
        mst_write(env.mst_drv[2].vif, 16'h1000, 32'h00000201, 8'h30);
        // Master 3 → SLV3
        mst_write(env.mst_drv[3].vif, 16'h3000, 32'h00000303, 8'h40);

        #200;
        phase.drop_objection(this);
    endtask
endclass
