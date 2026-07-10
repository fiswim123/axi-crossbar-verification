//==========================================================================
// T031: Outstanding Read test
//==========================================================================
class axi_outstanding_read_test extends axi_base_test;
    `uvm_component_utils(axi_outstanding_read_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_outstanding_read_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write data
        for (int i = 0; i < 4; i++)
            mst_write(env.mst_drv[0].vif, i * 4, 32'hBEEF0000 + i, 8'h10);

        #100;

        seq = axi_outstanding_read_seq::type_id::create("seq");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
