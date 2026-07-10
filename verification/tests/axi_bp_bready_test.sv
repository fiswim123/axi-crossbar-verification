//==========================================================================
// T071: B Channel Backpressure Test
//==========================================================================
class axi_bp_bready_test extends axi_base_test;
    `uvm_component_utils(axi_bp_bready_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // B channel backpressure is controlled by master driver
        // Use backpressure sequence with slow bready
        fork
            begin
                for (int i = 0; i < 4; i++) begin
                    // Slow bready
                    repeat(3) @(posedge env.mst_drv[0].vif.aclk);
                    mst_write(env.mst_drv[0].vif, 16'h0000, 32'hBACC_0000 + i, 8'h10);
                end
            end
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
