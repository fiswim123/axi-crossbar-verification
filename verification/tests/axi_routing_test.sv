//==========================================================================
// T010-T018: Routing (UVM Sequence 版本)
//==========================================================================
class axi_routing_test extends axi_base_test;
    `uvm_component_utils(axi_routing_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T010-T013: Master 0 → All 4 slaves (sequential)
        for (int s = 0; s < 4; s++) begin
            seq = axi_wr_seq::type_id::create($sformatf("m0_s%0d", s));
            seq.s_addr = s * 16'h1000;
            seq.s_data = 32'h00000000 + s;
            seq.s_id   = 8'h10;
            seq.start(env.sqr[0]);
        end

        // T014-T016: Multi-master → different slaves (parallel)
        fork
            begin
                seq = axi_wr_seq::type_id::create("m1_s0");
                seq.s_addr = 16'h0000;
                seq.s_data = 32'h00000100;
                seq.s_id   = 8'h20;
                seq.start(env.sqr[1]);
            end
            begin
                seq = axi_wr_seq::type_id::create("m2_s1");
                seq.s_addr = 16'h1000;
                seq.s_data = 32'h00000201;
                seq.s_id   = 8'h30;
                seq.start(env.sqr[2]);
            end
            begin
                seq = axi_wr_seq::type_id::create("m3_s3");
                seq.s_addr = 16'h3000;
                seq.s_data = 32'h00000303;
                seq.s_id   = 8'h40;
                seq.start(env.sqr[3]);
            end
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
