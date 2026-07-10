//==========================================================================
// T060: Boundary Address Test
//==========================================================================
class axi_boundary_addr_test extends axi_base_test;
    `uvm_component_utils(axi_boundary_addr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_boundary_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        seq = axi_boundary_seq::type_id::create("seq");
        seq.s_id = 8'h10;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
