//==========================================================================
// T053: Error Recovery Test
//==========================================================================
class axi_err_recovery_test extends axi_base_test;
    `uvm_component_utils(axi_err_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_err_multi_seq err_seq;
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Inject errors on slave 0
        env.slv_cfg[0].err_pct = 50;
        env.slv_cfg[0].err_resp = 2'b10;

        // Send transactions with mixed error expectations
        err_seq = axi_err_multi_seq::type_id::create("err_seq");
        err_seq.s_addr = 16'h0000; err_seq.s_id = 8'h10; err_seq.s_count = 8;
        err_seq.start(env.sqr[0]);

        #100;

        // Disable errors
        env.slv_cfg[0].err_pct = 0;

        // Normal transactions should work
        wr_seq = axi_wr_seq::type_id::create("wr_seq");
        wr_seq.s_addr = 16'h0000; wr_seq.s_id = 8'h10; wr_seq.s_data = 32'hA500_0001;
        wr_seq.start(env.sqr[0]);

        rd_seq = axi_rd_seq::type_id::create("rd_seq");
        rd_seq.s_addr = 16'h0000; rd_seq.s_id = 8'h10;
        rd_seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
