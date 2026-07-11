//==========================================================================
// T030: Outstanding Write test (UVM Sequence 版本)
//       发起多个写事务，不等 B 响应就继续发下一个
//       通过 fork/join_none 实现流水线效果
//==========================================================================
class axi_outstanding_test extends axi_base_test;
    `uvm_component_utils(axi_outstanding_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T030: 4 outstanding writes — 流水线发出，不等前一个完成
        for (int i = 0; i < 4; i++) begin
            seq = axi_wr_seq::type_id::create($sformatf("ostd_%0d", i));
            seq.s_addr = i * 16'h1000;
            seq.s_data = 32'hDEAD0000 + i;
            seq.s_id   = 8'h10;
            fork
                automatic axi_wr_seq s = seq;
                s.start(env.sqr[0]);
            join_none
        end
        // 等所有 outstanding 完成
        wait fork;

        #200;
        phase.drop_objection(this);
    endtask
endclass
