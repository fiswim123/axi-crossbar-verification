//==========================================================================
// T040: Multi-master concurrent
//==========================================================================
class axi_multi_master_test extends axi_base_test;
    `uvm_component_utils(axi_multi_master_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        fork
            mst_write(env.mst_drv[0].vif, 16'h0000, 32'hAAAAAAAA, 8'h10);
            mst_write(env.mst_drv[1].vif, 16'h1000, 32'hBBBBBBBB, 8'h20);
            mst_write(env.mst_drv[2].vif, 16'h2000, 32'hCCCCCCCC, 8'h30);
            mst_write(env.mst_drv[3].vif, 16'h3000, 32'hDDDDDDDD, 8'h40);
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
