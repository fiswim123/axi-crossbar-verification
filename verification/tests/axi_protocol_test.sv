//==========================================================================
// T020-T023: Protocol - Burst lengths (UVM Sequence 版本)
//==========================================================================
class axi_protocol_test extends axi_base_test;
    `uvm_component_utils(axi_protocol_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_burst_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T020: len=0 (single beat)
        seq = axi_burst_wr_seq::type_id::create("len0");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_len = 0;
        seq.start(env.sqr[0]);

        // T021: len=3 (4 beats)
        seq = axi_burst_wr_seq::type_id::create("len3");
        seq.s_addr = 16'h0100; seq.s_id = 8'h10; seq.s_len = 3;
        seq.start(env.sqr[0]);

        // T022: len=7 (8 beats)
        seq = axi_burst_wr_seq::type_id::create("len7");
        seq.s_addr = 16'h0200; seq.s_id = 8'h10; seq.s_len = 7;
        seq.start(env.sqr[0]);

        // T023: len=15 (16 beats)
        seq = axi_burst_wr_seq::type_id::create("len15");
        seq.s_addr = 16'h0300; seq.s_id = 8'h10; seq.s_len = 15;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
