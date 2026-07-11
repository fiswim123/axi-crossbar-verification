//==========================================================================
// T081: Reset During Read Test (UVM Sequence 版本)
//       sequence 负责发起事务，test 负责控制 reset 时序
//==========================================================================
class axi_reset_rd_test extends axi_base_test;
    `uvm_component_utils(axi_reset_rd_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write: 先写入数据
        wr_seq = axi_wr_seq::type_id::create("pre_wr");
        wr_seq.s_addr = 16'h0000;
        wr_seq.s_data = 32'hA500_0003;
        wr_seq.s_id   = 8'h10;
        wr_seq.start(env.sqr[0]);

        #50;

        // T081: 读事务进行中触发 reset
        fork
            begin
                // sequence 发起读事务（会被 reset 打断）
                rd_seq = axi_rd_seq::type_id::create("rd_reset");
                rd_seq.s_addr = 16'h0000;
                rd_seq.s_id   = 8'h10;
                rd_seq.start(env.sqr[0]);
            end
            begin
                // test 控制 reset 时序
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
                env.mst_drv[0].vif.aresetn <= 0;
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
                env.mst_drv[0].vif.aresetn <= 1;
                repeat(10) @(posedge env.mst_drv[0].vif.aclk);
            end
        join

        // 等待 reset 恢复
        repeat(50) @(posedge env.mst_drv[0].vif.aclk);

        // T081 验证: reset 后应能正常读写
        wr_seq = axi_wr_seq::type_id::create("wr_after_reset");
        wr_seq.s_addr = 16'h0000;
        wr_seq.s_data = 32'hA500_0004;
        wr_seq.s_id   = 8'h10;
        wr_seq.start(env.sqr[0]);

        rd_seq = axi_rd_seq::type_id::create("rd_after_reset");
        rd_seq.s_addr = 16'h0000;
        rd_seq.s_id   = 8'h10;
        rd_seq.start(env.sqr[0]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
