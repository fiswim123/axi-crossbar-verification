//==========================================================================
// T081: Reset During Read Test
//==========================================================================
class axi_reset_rd_test extends axi_base_test;
    `uvm_component_utils(axi_reset_rd_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] rdata;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write data
        mst_write(env.mst_drv[0].vif, 16'h0000, 32'hA500_0003, 8'h10);
        #50;

        // Start read, then reset during transfer
        fork
            begin
                mst_read(env.mst_drv[0].vif, 16'h0000, 8'h10, rdata);
            end
            begin
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
                // Assert reset
                env.mst_drv[0].vif.aresetn <= 0;
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
                // Release reset
                env.mst_drv[0].vif.aresetn <= 1;
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
            end
        join

        // Wait for reset recovery
        repeat(50) @(posedge env.mst_drv[0].vif.aclk);

        // Should work after reset
        mst_write(env.mst_drv[0].vif, 16'h0000, 32'hA500_0004, 8'h10);
        mst_read(env.mst_drv[0].vif, 16'h0000, 8'h10, rdata);

        #200;
        phase.drop_objection(this);
    endtask
endclass
