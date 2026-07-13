//==========================================================================
// T042: Read/Write Interleave test
//
// 测试名称: 读写交织测试 (axi_interleave_test)
// 测试编号: T042
// 测试目的: 验证AXI Crossbar是否正确支持读写事务的交织(interleaving)。
//          AXI协议允许读和写通道独立工作，读写操作可以交替进行，
//          从而提高总线利用率。这个测试验证Crossbar不破坏这一特性。
//
// 测试原理:
//   - 使用单个Master发起交替的读和写操作
//   - 写操作: 通过AW通道(地址)和W通道(数据)发送
//   - 读操作: 通过AR通道(地址)发送，从R通道(数据)接收
//   - AXI协议中，读通道(AR/R)和写通道(AW/W/B)是独立的
//   - 因此读和写可以同时进行，也可以交替进行
//
// 验证要点:
//   1. Crossbar是否允许读写事务交织进行
//   2. 读写交织时数据是否保持正确
//   3. 写响应(BRESP)和读响应(RRESP)是否正确返回
//   4. Crossbar内部是否存在读写通道的死锁风险
//   5. 交织操作后数据一致性是否得到保证
//
// AXI交织背景知识:
//   AXI5个通道: AW(写地址), W(写数据), B(写响应), AR(读地址), R(读数据)
//   写操作路径: AW -> W -> B
//   读操作路径: AR -> R
//   两组通道独立，允许同时传输，这就是交织的基础
//==========================================================================

class axi_interleave_test extends axi_base_test;

    // 注册到UVM工厂
    `uvm_component_utils(axi_interleave_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义读写交织的测试激励
    task run_phase(uvm_phase phase);

        // seq: AXI交织序列对象
        // axi_interleave_seq是专门设计的sequence，内部会交替发起
        // 读和写操作，模拟真实的交织场景
        axi_interleave_seq seq;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放(检测复位信号上升沿)
        @(posedge env.mst_drv[0].vif.aresetn);

        // 等待5个时钟周期，系统稳定
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 创建交织sequence实例
        seq = axi_interleave_seq::type_id::create("seq");

        // 配置sequence参数:
        // s_addr: 基地址0x0000，sequence内部可能会递增地址
        // s_id: 事务ID为0x10
        seq.s_addr = 16'h0000;
        seq.s_id   = 8'h10;

        // 在Master 0的sequencer上启动交织sequence
        // sequence内部会自动交替发送读写事务
        seq.start(env.sqr[0]);

        // 等待200ns，让所有读写事务完成
        #200;

        // 释放objection
        phase.drop_objection(this);
    endtask
endclass
