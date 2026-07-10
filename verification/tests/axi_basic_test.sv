//==========================================================================
// T001-T003: Basic write/read
//==========================================================================
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] rdata;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T001: Write to each slave
        for (int s = 0; s < 4; s++)
            mst_write(env.mst_drv[0].vif, s * 16'h1000, 32'hDEAD0000 + s, 8'h10);

        #200;

        // T002+T003: Read back and verify
        for (int s = 0; s < 4; s++) begin
            mst_read(env.mst_drv[0].vif, s * 16'h1000, 8'h10, rdata);
            if (rdata === 32'hDEAD0000 + s)
                `uvm_info("TEST", $sformatf("SLV%0d PASS: 0x%08h", s, rdata), UVM_LOW)
            else
                `uvm_error("TEST", $sformatf("SLV%0d FAIL: got=0x%08h exp=0x%08h",
                           s, rdata, 32'hDEAD0000 + s))
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
