//==========================================================================
// T073: All Channels Backpressure Test
//==========================================================================
class axi_bp_all_test extends axi_base_test;
    `uvm_component_utils(axi_bp_all_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_backpressure_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Configure all channels backpressure
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].bp_awready_pct = 25;
            env.slv_cfg[i].bp_wready_pct = 25;
            env.slv_cfg[i].bp_arready_pct = 25;
        end

        seq = axi_backpressure_seq::type_id::create("seq");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_count = 6;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
