//==========================================================================
// T001-T003: Basic write/read (UVM Sequence 版本)
//==========================================================================
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T001: Write to each slave via sequence
        for (int s = 0; s < 4; s++) begin
            wr_seq = axi_wr_seq::type_id::create($sformatf("wr_seq%0d", s));
            wr_seq.s_addr = s * 16'h1000;
            wr_seq.s_data = 32'hDEAD0000 + s;
            wr_seq.s_id   = 8'h10;
            wr_seq.start(env.sqr[0]);
        end

        #200;

        // T002+T003: Read back and verify via sequence
        for (int s = 0; s < 4; s++) begin
            rd_seq = axi_rd_seq::type_id::create($sformatf("rd_seq%0d", s));
            rd_seq.s_addr = s * 16'h1000;
            rd_seq.s_id   = 8'h10;
            rd_seq.start(env.sqr[0]);
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
