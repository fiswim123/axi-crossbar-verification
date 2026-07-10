//==========================================================================
// T091: Random Concurrent Test
//==========================================================================
class axi_random_concurrent_test extends axi_base_test;
    `uvm_component_utils(axi_random_concurrent_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_random_concurrent_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Run concurrent sequences on all masters sequentially for stability
        for (int i = 0; i < 4; i++) begin
            seq = axi_random_concurrent_seq::type_id::create($sformatf("seq_%0d", i));
            seq.s_count = 5;
            seq.start(env.sqr[i]);
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
