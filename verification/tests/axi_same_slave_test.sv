//==========================================================================
// T041: Same Slave Contention test
//==========================================================================
class axi_same_slave_test extends axi_base_test;
    `uvm_component_utils(axi_same_slave_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_same_slave_seq seq0, seq1;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        seq0 = axi_same_slave_seq::type_id::create("seq0");
        seq0.s_addr = 16'h1000; seq0.s_id = 8'h10;
        seq1 = axi_same_slave_seq::type_id::create("seq1");
        seq1.s_addr = 16'h1000; seq1.s_id = 8'h20;

        fork
            seq0.start(env.sqr[0]);
            seq1.start(env.sqr[1]);
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
