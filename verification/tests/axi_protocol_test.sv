//==========================================================================
// T020-T026: Protocol (burst lengths and sizes)
//==========================================================================
class axi_protocol_test extends axi_base_test;
    `uvm_component_utils(axi_protocol_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T020: len=0 (single)
        mst_burst_write(env.mst_drv[0].vif, 16'h0000, 8'h10, 0);
        // T021: len=3 (4 beats)
        mst_burst_write(env.mst_drv[0].vif, 16'h0100, 8'h10, 3);
        // T022: len=7 (8 beats)
        mst_burst_write(env.mst_drv[0].vif, 16'h0200, 8'h10, 7);
        // T023: len=15 (16 beats)
        mst_burst_write(env.mst_drv[0].vif, 16'h0300, 8'h10, 15);

        #200;
        phase.drop_objection(this);
    endtask
endclass
