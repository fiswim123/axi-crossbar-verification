//==========================================================================
// T080: Reset During Write Test (UVM Sequence 版本)
//       sequence 负责发起事务，test 负责控制 reset 时序
//==========================================================================
class axi_reset_wr_test extends axi_base_test;
    `uvm_component_utils(axi_reset_wr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T080: 写事务进行中触发 reset
        fork
            begin
                // sequence 发起写事务（会被 reset 打断）
                seq = axi_wr_seq::type_id::create("wr_reset");
                seq.s_addr = 16'h0000;
                seq.s_data = 32'hDEAD_BEEF;
                seq.s_id   = 8'h10;
                seq.start(env.sqr[0]);
            end
            begin
                // test 控制 reset 时序
                repeat(20) @(posedge env.mst_drv[0].vif.aclk);
                env.mst_drv[0].vif.aresetn <= 0;   // 拉低 reset
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
                env.mst_drv[0].vif.aresetn <= 1;   // 释放 reset
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
            end
        join

        // 等待 reset 恢复
        repeat(50) @(posedge env.mst_drv[0].vif.aclk);

        // T080 验证: reset 后应能正常工作
        seq = axi_wr_seq::type_id::create("wr_after_reset");
        seq.s_addr = 16'h0000;
        seq.s_data = 32'hA500_0002;
        seq.s_id   = 8'h10;
        seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
