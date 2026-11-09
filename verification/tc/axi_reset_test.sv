//==========================================================================
// Reset Test — 复位测试（合并版）
// 测试名称: 复位测试 (axi_reset_test)
//
// 【测试目的】
// 验证 AXI Crossbar 在复位条件下的行为是否正确。
// 本测试合并了以下三个复位测试：
//   1. 写通道复位测试：写操作过程中复位
//   2. 读通道复位测试：读操作过程中复位
//   3. 复位恢复测试：复位后能否恢复正常工作
//
// 【验证场景】
// - 写操作过程中触发复位，验证 DUT 能否正确复位
// - 读操作过程中触发复位，验证 DUT 能否正确复位
// - 复位后继续正常操作，验证 DUT 能否恢复正常
//
// 【复位机制】
// AXI 协议使用 aresetn 信号进行复位（低电平有效）：
// - 复位期间，所有 valid 信号必须为低
// - 复位释放后，DUT 应处于初始状态
// - 复位不应导致死锁或数据损坏
//==========================================================================

class axi_reset_test extends axi_base_test;
    `uvm_component_utils(axi_reset_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 测试1: 写通道复位测试
        // ============================================================
        `uvm_info("TEST", "=== Write Channel Reset Test ===", UVM_LOW)

        // 启动一个写操作
        fork
            begin
                wr_seq = axi_wr_seq::type_id::create("wr_seq_reset");
                wr_seq.s_addr = 16'h0000;
                wr_seq.s_data = 32'hDEAD0001;
                wr_seq.s_id = 8'h10;
                wr_seq.start(env.mst_agent[0].sequencer);
            end
        join_none

        // 等待一小段时间后触发复位
        #50;
        env.mst_agent[0].driver.vif.aresetn <= 0;  // 触发复位
        #100;
        env.mst_agent[0].driver.vif.aresetn <= 1;  // 释放复位
        #100;

        // ============================================================
        // 测试2: 读通道复位测试
        // ============================================================
        `uvm_info("TEST", "=== Read Channel Reset Test ===", UVM_LOW)

        // 先写入数据
        wr_seq = axi_wr_seq::type_id::create("wr_seq_for_rd");
        wr_seq.s_addr = 16'h1000;
        wr_seq.s_data = 32'hDEAD0002;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 启动一个读操作
        fork
            begin
                rd_seq = axi_rd_seq::type_id::create("rd_seq_reset");
                rd_seq.s_addr = 16'h1000;
                rd_seq.s_id = 8'h10;
                rd_seq.start(env.mst_agent[0].sequencer);
            end
        join_none

        // 等待一小段时间后触发复位
        #50;
        env.mst_agent[0].driver.vif.aresetn <= 0;  // 触发复位
        #100;
        env.mst_agent[0].driver.vif.aresetn <= 1;  // 释放复位
        #100;

        // ============================================================
        // 测试3: 复位恢复测试
        // ============================================================
        `uvm_info("TEST", "=== Reset Recovery Test ===", UVM_LOW)

        // 复位后继续正常操作
        wr_seq = axi_wr_seq::type_id::create("wr_seq_recovery");
        wr_seq.s_addr = 16'h2000;
        wr_seq.s_data = 32'hCAFEBABE;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 读回验证
        rd_seq = axi_rd_seq::type_id::create("rd_seq_recovery");
        rd_seq.s_addr = 16'h2000;
        rd_seq.s_id = 8'h10;
        rd_seq.start(env.mst_agent[0].sequencer);
        #100;

        phase.drop_objection(this);
    endtask
endclass
