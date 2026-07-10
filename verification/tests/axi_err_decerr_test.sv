//==========================================================================
// T051: DECERR Response Test
//==========================================================================
class axi_err_decerr_test extends axi_base_test;
    `uvm_component_utils(axi_err_decerr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_err_inject_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Configure slave 1 for DECERR injection
        env.slv_cfg[1].err_pct = 100;
        env.slv_cfg[1].err_resp = 2'b11; // DECERR

        seq = axi_err_inject_seq::type_id::create("seq");
        seq.s_addr = 16'h1000; seq.s_id = 8'h10; seq.s_expect_err = 1;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
