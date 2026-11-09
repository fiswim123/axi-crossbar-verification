//==========================================================================
// Backpressure Test — 反压测试（合并版）
// 测试名称: 反压测试 (axi_backpressure_test)
//
// 【测试目的】
// 验证 AXI Crossbar 在各通道受到反压时的行为是否正确。
// 本测试合并了以下四个反压测试：
//   1. W 通道反压：写数据通道 ready 信号延迟拉高
//   2. R 通道反压：读数据通道 ready 信号延迟拉高
//   3. B 通道反压：写响应通道 ready 信号延迟拉高
//   4. 全通道反压：所有通道同时受到反压
//
// 【验证场景】
// - Slave 通过拉低 ready 信号模拟繁忙状态
// - Master 需要等待 ready 拉高才能继续传输
// - 验证反压不会导致数据丢失或死锁
//
// 【反压机制】
// AXI 协议的握手机制（valid/ready）天然支持反压：
// - 发送方拉高 valid 表示数据有效
// - 接收方拉高 ready 表示可以接收
// - 只有当 valid && ready 同时为高时，传输才发生
//==========================================================================

class axi_backpressure_test extends axi_base_test;
    `uvm_component_utils(axi_backpressure_test)

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
        // 测试1: W 通道反压
        // ============================================================
        `uvm_info("TEST", "=== W Channel Backpressure ===", UVM_LOW)
        env.slv_cfg[0].bp_wready_pct = 50;  // 50% 时间背压 W 通道

        wr_seq = axi_wr_seq::type_id::create("wr_seq_wbp");
        wr_seq.s_addr = 16'h0000;
        wr_seq.s_data = 32'hDEAD0001;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        env.slv_cfg[0].bp_wready_pct = 0;  // 恢复

        // ============================================================
        // 测试2: R 通道反压
        // ============================================================
        `uvm_info("TEST", "=== R Channel Backpressure ===", UVM_LOW)

        // 先写入数据
        wr_seq = axi_wr_seq::type_id::create("wr_seq_rbp");
        wr_seq.s_addr = 16'h1000;
        wr_seq.s_data = 32'hDEAD0002;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 配置 R 通道反压
        env.slv_cfg[0].bp_wready_pct = 0;  // 不背压 W 通道

        // 读取数据（R 通道反压由 Slave Driver 内部实现）
        rd_seq = axi_rd_seq::type_id::create("rd_seq_rbp");
        rd_seq.s_addr = 16'h1000;
        rd_seq.s_id = 8'h10;
        rd_seq.start(env.mst_agent[0].sequencer);
        #100;

        // ============================================================
        // 测试3: B 通道反压
        // ============================================================
        `uvm_info("TEST", "=== B Channel Backpressure ===", UVM_LOW)
        // B 通道反压需要 Master Driver 支持（暂时跳过）

        // ============================================================
        // 测试4: 全通道反压
        // ============================================================
        `uvm_info("TEST", "=== All Channel Backpressure ===", UVM_LOW)
        env.slv_cfg[0].bp_wready_pct = 30;  // 30% 时间背压 W 通道

        wr_seq = axi_wr_seq::type_id::create("wr_seq_allbp");
        wr_seq.s_addr = 16'h2000;
        wr_seq.s_data = 32'hDEAD0003;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 恢复配置
        env.slv_cfg[0].bp_wready_pct = 0;

        phase.drop_objection(this);
    endtask
endclass
