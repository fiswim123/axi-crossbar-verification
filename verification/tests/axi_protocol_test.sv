//==========================================================================
// T020-T023: Protocol - Burst lengths (UVM Sequence 版本)
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 对不同突发长度（Burst Length）的处理能力：
//   - T020: len=0  → 单拍传输（1 beat），最基本的传输模式
//   - T021: len=3  → 4 拍传输（4 beats），常用的小批量传输
//   - T022: len=7  → 8 拍传输（8 beats），中等批量传输
//   - T023: len=15 → 16 拍传输（16 beats），AXI4 最大突发长度
//
// 【AXI 突发传输知识】
//   AXI 协议支持突发传输（Burst Transfer），一次地址阶段可以传输多个数据：
//   - AWLEN/ARLEN: 突发长度字段，值 = 实际拍数 - 1
//     例如：len=0 表示 1 拍，len=3 表示 4 拍，len=15 表示 16 拍
//   - AXI4 协议规定最大突发长度为 16 拍（len=15）
//   - 突发传输提高了总线效率，减少了地址开销
//
// 【UVM 知识点】
//   - 使用专门的 axi_burst_wr_seq 来配置突发长度
//   - sequence 的参数（s_len）在 start() 之前设置
//
//==========================================================================

// 【类定义】axi_protocol_test 继承自 axi_base_test
class axi_protocol_test extends axi_base_test;

    // 【工厂注册】
    `uvm_component_utils(axi_protocol_test)

    // 【构造函数】
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】
    task run_phase(uvm_phase phase);

        // 【局部变量】突发写 sequence 句柄
        // axi_burst_wr_seq 是专门用于突发写的 sequence，支持配置突发长度
        axi_burst_wr_seq seq;

        // 【开始测试】
        phase.raise_objection(this);

        // 【等待复位释放 + 稳定】
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // ============================================================
        // T020: 单拍传输（len=0, 1 beat）
        // ============================================================
        // 最基本的 AXI 传输：一次地址对应一次数据
        seq = axi_burst_wr_seq::type_id::create("len0");
        // s_addr: 目标地址
        // s_id:   事务 ID
        // s_len:  突发长度 = 0，表示 1 拍传输
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_len = 0;
        seq.start(env.sqr[0]);  // 在 master 0 的 sequencer 上启动

        // ============================================================
        // T021: 4 拍传输（len=3, 4 beats）
        // ============================================================
        // 一次地址阶段后连续传输 4 个数据拍
        seq = axi_burst_wr_seq::type_id::create("len3");
        seq.s_addr = 16'h0100; seq.s_id = 8'h10; seq.s_len = 3;
        seq.start(env.sqr[0]);

        // ============================================================
        // T022: 8 拍传输（len=7, 8 beats）
        // ============================================================
        // 一次地址阶段后连续传输 8 个数据拍
        seq = axi_burst_wr_seq::type_id::create("len7");
        seq.s_addr = 16'h0200; seq.s_id = 8'h10; seq.s_len = 7;
        seq.start(env.sqr[0]);

        // ============================================================
        // T023: 16 拍传输（len=15, 16 beats）
        // ============================================================
        // AXI4 协议支持的最大突发长度
        // 一次地址阶段后连续传输 16 个数据拍
        seq = axi_burst_wr_seq::type_id::create("len15");
        seq.s_addr = 16'h0300; seq.s_id = 8'h10; seq.s_len = 15;
        seq.start(env.sqr[0]);

        // 【等待】让所有突发传输完成
        #200;

        // 【结束测试】
        phase.drop_objection(this);
    endtask
endclass
