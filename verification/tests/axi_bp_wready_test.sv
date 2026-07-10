//==========================================================================
// T070: W Channel Backpressure Test
//==========================================================================
class axi_bp_wready_test extends axi_base_test;
    `uvm_component_utils(axi_bp_wready_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_backpressure_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Configure W channel backpressure on all slaves
        for (int i = 0; i < 4; i++)
            env.slv_cfg[i].bp_wready_pct = 30; // 30% backpressure

        seq = axi_backpressure_seq::type_id::create("seq");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_count = 4;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
