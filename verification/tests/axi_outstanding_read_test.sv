//==========================================================================
// T031: Outstanding Read test (UVM Sequence 版本)
//==========================================================================
class axi_outstanding_read_test extends axi_base_test;
    `uvm_component_utils(axi_outstanding_read_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq              wr_seq;
        axi_outstanding_read_seq rd_seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write: 通过 sequence 写入数据供后续读取
        for (int i = 0; i < 4; i++) begin
            wr_seq = axi_wr_seq::type_id::create($sformatf("prewr_%0d", i));
            wr_seq.s_addr = i * 4;
            wr_seq.s_data = 32'hBEEF0000 + i;
            wr_seq.s_id   = 8'h10;
            wr_seq.start(env.sqr[0]);
        end

        #100;

        // Outstanding read
        rd_seq = axi_outstanding_read_seq::type_id::create("rd_seq");
        rd_seq.s_addr = 16'h0000;
        rd_seq.s_id   = 8'h10;
        rd_seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
