//==========================================================================
// T040: Multi-master concurrent (UVM Sequence 版本)
//==========================================================================
class axi_multi_master_test extends axi_base_test;
    `uvm_component_utils(axi_multi_master_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 4 masters write to 4 different slaves concurrently
        fork
            begin
                seq = axi_wr_seq::type_id::create("m0");
                seq.s_addr = 16'h0000; seq.s_data = 32'hAAAAAAAA; seq.s_id = 8'h10;
                seq.start(env.sqr[0]);
            end
            begin
                seq = axi_wr_seq::type_id::create("m1");
                seq.s_addr = 16'h1000; seq.s_data = 32'hBBBBBBBB; seq.s_id = 8'h20;
                seq.start(env.sqr[1]);
            end
            begin
                seq = axi_wr_seq::type_id::create("m2");
                seq.s_addr = 16'h2000; seq.s_data = 32'hCCCCCCCC; seq.s_id = 8'h30;
                seq.start(env.sqr[2]);
            end
            begin
                seq = axi_wr_seq::type_id::create("m3");
                seq.s_addr = 16'h3000; seq.s_data = 32'hDDDDDDDD; seq.s_id = 8'h40;
                seq.start(env.sqr[3]);
            end
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
