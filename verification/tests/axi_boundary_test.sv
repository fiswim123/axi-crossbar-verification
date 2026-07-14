//==========================================================================
// Boundary Test — 边界测试（合并版）
// 测试名称: 边界测试 (axi_boundary_test)
//
// 【测试目的】
// 验证 AXI Crossbar 在各种边界条件下的行为是否正确。
// 本测试合并了以下三个边界测试：
//   1. 边界地址测试：验证地址解码在边界值时的正确性
//   2. 最大突发长度测试：验证最大 burst length 的处理
//   3. 最大 Outstanding 测试：验证最大未完成事务数的处理
//
// 【验证场景】
// - 各 Slave 地址空间的起始/结束地址
// - 地址空间的交界处（跨边界）
// - 最大突发长度（len=15，即 16 拍）
// - 最大 Outstanding 事务数
//
// 【为什么边界测试重要】
// 地址解码通常使用比较器实现，边界值容易暴露设计缺陷。
//==========================================================================

class axi_boundary_test extends axi_base_test;
    `uvm_component_utils(axi_boundary_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        // 声明序列变量
        axi_boundary_seq boundary_seq;
        axi_burst_wr_seq burst_wr_seq;
        axi_burst_rd_seq burst_rd_seq;
        axi_outstanding_read_seq ostd_seq;

        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 测试1: 边界地址测试
        // ============================================================
        `uvm_info("TEST", "=== Boundary Address Test ===", UVM_LOW)
        boundary_seq = axi_boundary_seq::type_id::create("boundary_seq");
        boundary_seq.s_id = 8'h10;
        boundary_seq.start(env.mst_agent[0].sequencer);
        #100;

        // ============================================================
        // 测试2: 最大突发长度测试
        // ============================================================
        `uvm_info("TEST", "=== Max Burst Length Test ===", UVM_LOW)

        // 写测试：len=15（16拍突发）
        burst_wr_seq = axi_burst_wr_seq::type_id::create("burst_wr_seq");
        burst_wr_seq.s_addr = 16'h0100;
        burst_wr_seq.s_id = 8'h10;
        burst_wr_seq.s_len = 4'd15;  // 最大突发长度
        burst_wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 读测试：len=15（16拍突发）
        burst_rd_seq = axi_burst_rd_seq::type_id::create("burst_rd_seq");
        burst_rd_seq.s_addr = 16'h0100;
        burst_rd_seq.s_id = 8'h10;
        burst_rd_seq.s_len = 4'd15;
        burst_rd_seq.start(env.mst_agent[0].sequencer);
        #100;

        // ============================================================
        // 测试3: 最大 Outstanding 测试
        // ============================================================
        `uvm_info("TEST", "=== Max Outstanding Test ===", UVM_LOW)
        ostd_seq = axi_outstanding_read_seq::type_id::create("ostd_seq");
        ostd_seq.s_addr = 16'h1000;
        ostd_seq.s_id = 8'h10;
        ostd_seq.start(env.mst_agent[0].sequencer);  // 默认发送4个连续读请求
        #200;

        phase.drop_objection(this);
    endtask
endclass
