//==========================================================================
// T080: Reset During Write Test（写事务期间复位测试）
//       sequence 负责发起事务，test 负责控制 reset 时序
//==========================================================================
// 【测试目的】
//   验证 AXI Crossbar 在写事务进行过程中被复位时的行为是否正确。
//   这是一个边界条件测试，确保 DUT 不会因为意外复位而进入死锁状态。
//
// 【验证功能点】
//   - 写事务中途复位后，DUT 能正确清理内部状态
//   - 复位释放后，DUT 能恢复正常工作
//   - 不会出现总线死锁（handshake 卡住）
//   - 内部 FIFO/计数器能正确复位
//
// 【测试流程】
//   1. 等待复位完成，DUT 进入正常工作状态
//   2. fork-join 并行执行两个任务：
//      - 任务A：启动写事务序列
//      - 任务B：等待 20 周期后拉低复位，再等 10 周期后释放
//   3. 等待 DUT 恢复稳定
//   4. 再次发起写事务，验证 DUT 功能恢复正常
//
// 【fork-join 说明】
//   fork-join 让两个 begin-end 块并行执行，两个都完成后才继续。
//   这样可以精确控制"在写事务进行中"触发复位。
//==========================================================================
class axi_reset_wr_test extends axi_base_test;
    // 注册到 UVM 工厂
    `uvm_component_utils(axi_reset_wr_test)

    // 构造函数
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase：测试激励执行阶段
    task run_phase(uvm_phase phase);
        // 写事务序列对象
        axi_wr_seq seq;

        // 阻止仿真提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // T080: 写事务进行中触发 reset
        // fork-join 让写事务和复位控制并行执行
        fork
            begin
                // 任务A：sequence 发起写事务（会被 reset 打断）
                // 创建写序列并配置参数
                seq = axi_wr_seq::type_id::create("wr_reset");
                seq.s_addr = 16'h0000;        // 写入地址 0x0000
                seq.s_data = 32'hDEAD_BEEF;   // 写入数据（特殊值便于波形识别）
                seq.s_id   = 8'h10;           // AXI 事务 ID
                // start() 会阻塞直到序列完成（但会被复位打断）
                seq.start(env.mst_agent[0].sequencer);
            end
            begin
                // 任务B：test 控制 reset 时序
                // 等待 20 个时钟周期（此时写事务正在进行中）
                repeat(20) @(posedge env.mst_agent[0].driver.vif.aclk);

                // 拉低复位信号（aresetn = 0 表示复位有效）
                // 使用 <= 非阻塞赋值，因为要驱动接口信号
                env.mst_agent[0].driver.vif.aresetn <= 0;

                // 保持复位 10 个时钟周期
                repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);

                // 释放复位（aresetn = 1 表示正常工作）
                env.mst_agent[0].driver.vif.aresetn <= 1;

                // 等待 10 个时钟周期让 DUT 从复位中恢复
                repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);
            end
        join

        // 等待 reset 恢复：给 DUT 足够时间清理内部状态
        repeat(50) @(posedge env.mst_agent[0].driver.vif.aclk);

        // T080 验证: reset 后应能正常工作
        // 再次发起写事务，确认 DUT 功能恢复正常
        seq = axi_wr_seq::type_id::create("wr_after_reset");
        seq.s_addr = 16'h0000;          // 写入地址 0x0000
        seq.s_data = 32'hA500_0002;     // 写入新数据（与之前不同，便于区分）
        seq.s_id   = 8'h10;             // 相同的 AXI ID
        seq.start(env.mst_agent[0].sequencer);          // 如果 DUT 未恢复正常，这里会卡住或报错

        // 等待所有响应返回
        #200;

        // 释放 objection
        phase.drop_objection(this);
    endtask
endclass
