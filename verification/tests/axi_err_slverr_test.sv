//==========================================================================
// T050: SLVERR Response Test
//==========================================================================
class axi_err_slverr_test extends axi_base_test;
    `uvm_component_utils(axi_err_slverr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_err_inject_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Configure slave 0 for SLVERR injection
        env.slv_cfg[0].err_pct = 100; // 100% error
        env.slv_cfg[0].err_resp = 2'b10; // SLVERR

        seq = axi_err_inject_seq::type_id::create("seq");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_expect_err = 1;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
