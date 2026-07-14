//==========================================================================
// Error Test — 错误测试（合并版）
// 测试名称: 错误测试 (axi_error_test)
//
// 【测试目的】
// 验证 AXI Crossbar 在各种错误条件下的行为是否正确。
// 本测试合并了以下三个错误测试：
//   1. SLVERR 测试：从机返回 Slave Error 响应
//   2. DECERR 测试：解码错误（地址无效）
//   3. 错误恢复测试：错误发生后能否恢复正常工作
//
// 【验证场景】
// - Slave 返回 SLVERR（2'b10）：表示从机内部错误
// - Slave 返回 DECERR（2'b11）：表示地址解码失败
// - 错误发生后，Crossbar 能否继续处理后续事务
//
// 【AXI 响应码】
// - 2'b00 = OKAY：正常完成
// - 2'b01 = EXOKAY：独占访问成功
// - 2'b10 = SLVERR：从机错误
// - 2'b11 = DECERR：解码错误
//==========================================================================

class axi_error_test extends axi_base_test;
    `uvm_component_utils(axi_error_test)

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
        // 测试1: SLVERR 测试
        // ============================================================
        `uvm_info("TEST", "=== SLVERR Test ===", UVM_LOW)
        env.slv_cfg[0].err_pct = 100;      // 100% 错误率
        env.slv_cfg[0].err_resp = 2'b10;   // SLVERR

        wr_seq = axi_wr_seq::type_id::create("wr_seq_slverr");
        wr_seq.s_addr = 16'h0000;
        wr_seq.s_data = 32'hDEAD0001;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 恢复配置
        env.slv_cfg[0].err_pct = 0;

        // ============================================================
        // 测试2: DECERR 测试
        // ============================================================
        `uvm_info("TEST", "=== DECERR Test ===", UVM_LOW)
        env.slv_cfg[0].err_pct = 100;      // 100% 错误率
        env.slv_cfg[0].err_resp = 2'b11;   // DECERR

        wr_seq = axi_wr_seq::type_id::create("wr_seq_decerr");
        wr_seq.s_addr = 16'h1000;
        wr_seq.s_data = 32'hDEAD0002;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 恢复配置
        env.slv_cfg[0].err_pct = 0;

        // ============================================================
        // 测试3: 错误恢复测试
        // ============================================================
        `uvm_info("TEST", "=== Error Recovery Test ===", UVM_LOW)

        // 先注入错误
        env.slv_cfg[0].err_pct = 50;  // 50% 错误率
        wr_seq = axi_wr_seq::type_id::create("wr_seq_err");
        wr_seq.s_addr = 16'h2000;
        wr_seq.s_data = 32'hDEAD0003;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 恢复配置
        env.slv_cfg[0].err_pct = 0;

        // 验证能正常工作
        wr_seq = axi_wr_seq::type_id::create("wr_seq_ok");
        wr_seq.s_addr = 16'h2000;
        wr_seq.s_data = 32'hCAFEBABE;
        wr_seq.s_id = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);
        #100;

        // 读回验证
        rd_seq = axi_rd_seq::type_id::create("rd_seq_ok");
        rd_seq.s_addr = 16'h2000;
        rd_seq.s_id = 8'h10;
        rd_seq.start(env.mst_agent[0].sequencer);
        #100;

        phase.drop_objection(this);
    endtask
endclass
