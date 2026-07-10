//==========================================================================
// T063: Max Outstanding Test
//==========================================================================
class axi_boundary_ostd_test extends axi_base_test;
    `uvm_component_utils(axi_boundary_ostd_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_max_ostd_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        seq = axi_max_ostd_seq::type_id::create("seq");
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_ostd_num = 4;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
