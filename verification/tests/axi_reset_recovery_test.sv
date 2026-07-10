//==========================================================================
// T082: Reset Recovery Test
//==========================================================================
class axi_reset_recovery_test extends axi_base_test;
    `uvm_component_utils(axi_reset_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Multiple reset cycles
        for (int cycle = 0; cycle < 3; cycle++) begin
            // Normal operation
            for (int i = 0; i < 4; i++)
                mst_write(env.mst_drv[0].vif, i * 4, 32'hA500_0000 + cycle * 4 + i, 8'h10);

            #50;

            // Assert reset
            env.mst_drv[0].vif.aresetn <= 0;
            repeat(10) @(posedge env.mst_drv[0].vif.aclk);
            env.mst_drv[0].vif.aresetn <= 1;
            repeat(20) @(posedge env.mst_drv[0].vif.aclk);
        end

        // Final verification
        for (int i = 0; i < 4; i++)
            mst_write(env.mst_drv[0].vif, i * 4, 32'hA500_0010 + i, 8'h10);

        #200;
        phase.drop_objection(this);
    endtask
endclass
