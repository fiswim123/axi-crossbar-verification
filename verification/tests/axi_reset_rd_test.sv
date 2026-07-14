//==========================================================================
// T081: Reset During Read Test（读事务期间复位测试）
//       sequence 负责发起事务，test 负责控制 reset 时序
//==========================================================================
// 【测试目的】
//   验证 AXI Crossbar 在读事务进行过程中被复位时的行为是否正确。
//   与 T080（写事务复位测试）互补，覆盖读通道的复位场景。
//
// 【验证功能点】
//   - 读事务中途复位后，DUT 能正确清理读数据通道
//   - 复位释放后，读写功能都能恢复正常
//   - 读地址通道（AR）和读数据通道（R）的复位行为
//   - 不会出现读数据通道死锁
//
// 【测试流程】
//   1. 先写入一笔数据（作为后续读操作的参考数据）
//   2. fork-join 并行执行：
//      - 任务A：启动读事务序列
//      - 任务B：等待 10 周期后触发复位，保持 10 周期后释放
//   3. 等待 DUT 恢复稳定
//   4. 先写后读，验证读写功能都恢复正常
//==========================================================================
class axi_reset_rd_test extends axi_base_test;
    // 注册到 UVM 工厂
    `uvm_component_utils(axi_reset_rd_test)

    // 构造函数
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase：测试激励执行阶段
    task run_phase(uvm_phase phase);
        // 写序列和读序列对象
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

        // 阻止仿真提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // Pre-write: 先写入一笔数据到地址 0x0000
        // 读操作需要有可读的数据，所以先执行一次写操作
        wr_seq = axi_wr_seq::type_id::create("pre_wr");
        wr_seq.s_addr = 16'h0000;          // 写入地址
        wr_seq.s_data = 32'hA500_0003;     // 写入数据
        wr_seq.s_id   = 8'h10;             // AXI 事务 ID
        wr_seq.start(env.mst_agent[0].sequencer);          // 在 Master 0 上执行

        // 写完成后等待 50 个时间单位，确保数据已写入 Slave 存储
        #50;

        // T081: 读事务进行中触发 reset
        // fork-join 让读事务和复位控制并行执行
        fork
            begin
                // 任务A：sequence 发起读事务（会被 reset 打断）
                rd_seq = axi_rd_seq::type_id::create("rd_reset");
                rd_seq.s_addr = 16'h0000;   // 读取地址（与刚写入的地址相同）
                rd_seq.s_id   = 8'h10;      // AXI 事务 ID
                // start() 会阻塞直到读数据返回（但会被复位打断）
                rd_seq.start(env.mst_agent[0].sequencer);
            end
            begin
                // 任务B：test 控制 reset 时序
                // 等待 10 个时钟周期（此时读事务正在进行中）
                repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);

                // 拉低复位信号
                env.mst_agent[0].driver.vif.aresetn <= 0;

                // 保持复位 10 个时钟周期
                repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);

                // 释放复位
                env.mst_agent[0].driver.vif.aresetn <= 1;

                // 等待 10 个时钟周期让 DUT 从复位中恢复
                repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);
            end
        join

        // 等待 reset 恢复：给 DUT 足够时间清理内部状态
        repeat(50) @(posedge env.mst_agent[0].driver.vif.aclk);

        // T081 验证: reset 后应能正常读写
        // 步骤1: 先写入新数据
        wr_seq = axi_wr_seq::type_id::create("wr_after_reset");
        wr_seq.s_addr = 16'h0000;          // 写入地址
        wr_seq.s_data = 32'hA500_0004;     // 新数据
        wr_seq.s_id   = 8'h10;
        wr_seq.start(env.mst_agent[0].sequencer);

        // 步骤2: 读取刚才写入的数据
        // 如果 DUT 未恢复正常，读操作会失败或返回错误数据
        rd_seq = axi_rd_seq::type_id::create("rd_after_reset");
        rd_seq.s_addr = 16'h0000;          // 读取同一地址
        rd_seq.s_id   = 8'h10;
        rd_seq.start(env.mst_agent[0].sequencer);

        // 等待所有响应返回
        #200;

        // 释放 objection
        phase.drop_objection(this);
    endtask
endclass
