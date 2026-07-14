//==========================================================================
// T031: Outstanding Read test (UVM Sequence 版本)
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 的 Outstanding 读事务处理能力：
//   - 先通过写操作预写入数据（Pre-write）
//   - 然后发起 Outstanding 读事务，测试 Crossbar 能否正确处理
//
// 【测试流程】
//   1. 预写阶段：向 4 个连续地址写入已知数据
//   2. 等待写事务完成
//   3. 使用 axi_outstanding_read_seq 发起 Outstanding 读事务
//   4. sequence 内部会连续发起多个读请求，不等待响应
//
// 【为什么需要预写？】
//   读操作需要从 Slave 获取数据，如果 Slave 中没有数据，读回的值不确定
//   因此需要先写入已知数据，再读出来验证
//
// 【UVM 知识点】
//   - 测试的准备阶段（Pre-condition）：通过写操作建立测试环境
//   - 专用 sequence：axi_outstanding_read_seq 内部实现了 outstanding 读逻辑
//
//==========================================================================

// 【类定义】axi_outstanding_read_test 继承自 axi_base_test
class axi_outstanding_read_test extends axi_base_test;

    // 【工厂注册】
    `uvm_component_utils(axi_outstanding_read_test)

    // 【构造函数】
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】
    task run_phase(uvm_phase phase);

        // 【局部变量】
        // wr_seq: 写 sequence，用于预写数据
        // rd_seq: outstanding 读 sequence，用于测试
        axi_wr_seq              wr_seq;
        axi_outstanding_read_seq rd_seq;

        // 【开始测试】
        phase.raise_objection(this);

        // 【等待复位释放 + 稳定】
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 预写阶段：写入已知数据供后续读取
        // ============================================================
        // 向地址 0x0000, 0x0004, 0x0008, 0x000C 写入数据
        // 每个地址间隔 4 字节（32 位数据宽度）
        for (int i = 0; i < 4; i++) begin

            // 【创建写 sequence】实例名如 "prewr_0"、"prewr_1" 等
            wr_seq = axi_wr_seq::type_id::create($sformatf("prewr_%0d", i));

            // 【配置参数】
            // s_addr: 递增 4 字节（i*4），对应 32 位数据宽度
            // s_data: 递增数据 0xBEEF0000 + i，便于验证
            // s_id:   事务 ID
            wr_seq.s_addr = i * 4;
            wr_seq.s_data = 32'hBEEF0000 + i;
            wr_seq.s_id   = 8'h10;

            // 【启动写 sequence】顺序写入，确保数据写入完成
            wr_seq.start(env.mst_agent[0].sequencer);
        end

        // 【等待】确保所有写事务的响应都已返回
        // 写操作需要 B 通道响应，等待响应完成后再读
        #100;

        // ============================================================
        // Outstanding 读测试
        // ============================================================
        // 【创建 outstanding 读 sequence】
        // axi_outstanding_read_seq 内部会连续发起多个读请求
        // 不等待前一个读响应就发送下一个，测试 outstanding 能力
        rd_seq = axi_outstanding_read_seq::type_id::create("rd_seq");

        // 【配置参数】
        // s_addr: 读起始地址
        // s_id:   事务 ID
        rd_seq.s_addr = 16'h0000;
        rd_seq.s_id   = 8'h10;

        // 【启动 outstanding 读 sequence】
        // sequence 内部会自动发起多个 outstanding 读事务
        // start() 是阻塞调用，会等待所有读事务完成
        rd_seq.start(env.mst_agent[0].sequencer);

        // 【等待】确保所有读响应都已处理
        #200;

        // 【结束测试】
        phase.drop_objection(this);
    endtask
endclass
