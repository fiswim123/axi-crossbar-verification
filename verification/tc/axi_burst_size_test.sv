//==========================================================================
// T024: Burst Size test
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 对不同突发大小（Burst Size）的处理能力
//
// 【AXI 突发大小知识】
//   AXSIZE 字段表示每拍数据的字节数：
//   - axsize=0 → 1 字节/拍
//   - axsize=1 → 2 字节/拍
//   - axsize=2 → 4 字节/拍（32位总线常用）
//   - axsize=3 → 8 字节/拍
//   - axsize=4 → 16 字节/拍
//   - axsize=5 → 32 字节/拍
//   - axsize=6 → 64 字节/拍
//   - axsize=7 → 128 字节/拍
//
//   突发大小不能超过数据总线宽度。例如：
//   - 32 位（4 字节）数据总线最大 axsize=2
//   - 64 位（8 字节）数据总线最大 axsize=3
//
// 【UVM 知识点】
//   - axi_burst_size_seq 是专门用于测试不同 burst size 的 sequence
//   - 该 sequence 内部会遍历多种 size 值进行测试
//
//==========================================================================

// 【类定义】axi_burst_size_test 继承自 axi_base_test
class axi_burst_size_test extends axi_base_test;

    // 【工厂注册】
    `uvm_component_utils(axi_burst_size_test)

    // 【构造函数】
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】
    task run_phase(uvm_phase phase);

        // 【局部变量】burst size 测试 sequence 句柄
        // axi_burst_size_seq 会在内部遍历不同的 axsize 值
        axi_burst_size_seq seq;
        axi_burst_wr_seq burst_wr;
        axi_burst_rd_seq burst_rd;

        // 【开始测试】
        phase.raise_objection(this);

        // 【等待复位释放 + 稳定】
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 【创建并配置 burst size sequence】
        seq = axi_burst_size_seq::type_id::create("seq");
        // s_addr: 基地址，sequence 内部可能会在此基础上偏移
        // s_id:   事务 ID
        seq.s_addr = 16'h0000; seq.s_id = 8'h10;

        // 【启动 sequence】
        // sequence 内部会自动遍历不同的 burst size 进行测试
        // 例如：axsize=0, 1, 2 等，每个 size 发起一次或多次写事务
        seq.start(env.mst_agent[0].sequencer);

        // Close the read short/medium length bins with matching write data.
        for (int k = 0; k < 2; k++) begin
            burst_wr = axi_burst_wr_seq::type_id::create($sformatf("len_wr_%0d", k));
            burst_wr.s_addr = 16'h0100 + k * 16'h0040;
            burst_wr.s_id = 8'h10;
            burst_wr.s_len = (k == 0) ? 3 : 7;
            burst_wr.start(env.mst_agent[0].sequencer);

            burst_rd = axi_burst_rd_seq::type_id::create($sformatf("len_rd_%0d", k));
            burst_rd.s_addr = burst_wr.s_addr;
            burst_rd.s_id = 8'h10;
            burst_rd.s_len = burst_wr.s_len;
            burst_rd.start(env.mst_agent[0].sequencer);
        end

        // 【等待】让所有 burst size 测试完成
        #200;

        // 【结束测试】
        phase.drop_objection(this);
    endtask
endclass
