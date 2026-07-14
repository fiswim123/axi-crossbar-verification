//==========================================================================
// T030: Outstanding Write test (UVM Sequence 版本)
//       发起多个写事务，不等 B 响应就继续发下一个
//       通过 fork/join_none 实现流水线效果
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 的 Outstanding（未完成事务）处理能力：
//   - 连续发起 4 个写事务，不等待前一个完成就发送下一个
//   - 测试 Crossbar 能否正确处理多个同时在飞行中的事务
//
// 【AXI Outstanding 知识】
//   Outstanding 是 AXI 总线的重要特性：
//   - Master 可以在收到前一个事务的响应之前，继续发送新事务
//   - 这种流水线方式大大提高了总线利用率
//   - Crossbar 需要维护多个未完成事务的状态，正确返回响应
//   - Outstanding 深度表示可以同时有多少个未完成事务
//
// 【UVM 知识点】
//   - fork/join_none: 启动并行线程但不等待它们完成
//   - wait fork: 等待所有已启动的并行线程完成
//   - automatic 变量: 在 fork 内部使用 automatic 确保每个线程有独立的变量副本
//
//==========================================================================

// 【类定义】axi_outstanding_test 继承自 axi_base_test
class axi_outstanding_test extends axi_base_test;

    // 【工厂注册】
    `uvm_component_utils(axi_outstanding_test)

    // 【构造函数】
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】
    task run_phase(uvm_phase phase);

        // 【局部变量】写事务 sequence 句柄
        axi_wr_seq seq;

        // 【开始测试】
        phase.raise_objection(this);

        // 【等待复位释放 + 稳定】
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // T030: 4 个 Outstanding 写事务 — 流水线发出
        // ============================================================
        // 关键区别：使用 fork/join_none 而非顺序执行
        // 每个写事务在独立的线程中启动，主循环不等待就继续下一个
        for (int i = 0; i < 4; i++) begin

            // 【创建写 sequence】实例名如 "ostd_0"、"ostd_1" 等
            seq = axi_wr_seq::type_id::create($sformatf("ostd_%0d", i));

            // 【配置参数】
            // s_addr: 递增地址，每个事务写不同位置
            // s_data: 递增数据，便于区分
            // s_id:   相同 ID，测试同 ID 事务的顺序保证
            seq.s_addr = i * 16'h1000;
            seq.s_data = 32'hDEAD0000 + i;
            seq.s_id   = 8'h10;

            // 【fork/join_none 并行启动】
            // fork: 创建一个新线程
            // join_none: 不等待线程完成，立即继续执行
            // 这样主循环会快速发起所有 4 个事务，实现流水线效果
            fork
                // 【automatic 变量声明】
                // 关键！在 fork 内部必须使用 automatic
                // 否则所有线程会共享同一个变量 s，导致只有最后一个值生效
                // automatic 确保每个线程有自己独立的 seq 副本
                automatic axi_wr_seq s = seq;

                // 【在线程中启动 sequence】
                // 每个线程独立执行 start()，互不阻塞
                s.start(env.mst_agent[0].sequencer);
            join_none
        end

        // 【等待所有 outstanding 事务完成】
        // wait fork 等待当前 task 中所有 fork/join_none 创建的线程结束
        // 没有这行的话，可能会在事务未完成时就结束仿真
        wait fork;

        // 【等待】额外等待，确保所有响应都已返回
        #200;

        // 【结束测试】
        phase.drop_objection(this);
    endtask
endclass
