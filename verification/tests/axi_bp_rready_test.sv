//==========================================================================
// T072: R Channel Backpressure Test
//==========================================================================
class axi_bp_rready_test extends axi_base_test;
    `uvm_component_utils(axi_bp_rready_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write data
        for (int i = 0; i < 4; i++)
            mst_write(env.mst_drv[0].vif, i * 4, 32'hA500_0000 + i, 8'h10);

        #100;

        // R channel backpressure is controlled by master driver
        // Slow rready
        fork
            begin
                for (int i = 0; i < 4; i++) begin
                    bit [31:0] rdata;
                    repeat(3) @(posedge env.mst_drv[0].vif.aclk);
                    mst_read(env.mst_drv[0].vif, i * 4, 8'h10, rdata);
                end
            end
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
