//==========================================================================
// T082: Reset Recovery Test（复位恢复测试）
//       多次 reset 循环，验证 DUT 每次都能恢复正常
//==========================================================================
// 【测试目的】
//   验证 AXI Crossbar 在经历多次复位后仍能稳定恢复正常工作。
//   实际芯片中，复位可能多次发生（如上电复位、看门狗复位等），
//   DUT 必须保证每次复位后都能正确初始化并恢复功能。
//
// 【验证功能点】
//   - 多次复位后的状态一致性
//   - 内部状态机每次复位后都能回到初始状态
//   - 不会出现"复位积累"导致的异常（如计数器未清零）
//   - FIFO 指针在复位后能正确复位
//
// 【测试流程】
//   执行 3 次"正常操作 -> 复位"循环：
//     每次循环：
//       1. 发送 4 笔写事务（验证正常工作）
//       2. 触发复位（拉低 aresetn 10 周期）
//       3. 释放复位，等待恢复
//   最终验证：再发送 4 笔写事务，确认最后一次复位后功能正常
//
// 【数据编码说明】
//   s_data = 32'hA500_0000 + cycle * 4 + i
//   - 高 16 位 A500 是固定标识
//   - 低 16 位编码了循环号和事务号，便于波形调试时区分
//==========================================================================
class axi_reset_recovery_test extends axi_base_test;
    // 注册到 UVM 工厂
    `uvm_component_utils(axi_reset_recovery_test)

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

        // T082: 执行 3 次 reset 循环
        // cycle 变量表示当前是第几次复位循环（0, 1, 2）
        for (int cycle = 0; cycle < 3; cycle++) begin
            // === 正常操作阶段 ===
            // 发送 4 笔写事务，验证 DUT 在复位后能正常工作
            for (int i = 0; i < 4; i++) begin
                // 创建唯一名称的序列实例
                // 例如: c0_w0, c0_w1, c0_w2, c0_w3 (第0轮)
                //       c1_w0, c1_w1, c1_w2, c1_w3 (第1轮)
                seq = axi_wr_seq::type_id::create(
                    $sformatf("c%0d_w%0d", cycle, i));

                // 地址递增：0, 4, 8, 12（每个地址间隔 4 字节，即 32 位）
                seq.s_addr = i * 4;

                // 数据编码：高 16 位固定 A500，低 16 位 = cycle*4 + i
                // 例如第 0 轮: A500_0000, A500_0001, A500_0002, A500_0003
                // 例如第 1 轮: A500_0004, A500_0005, A500_0006, A500_0007
                seq.s_data = 32'hA500_0000 + cycle * 4 + i;

                // AXI 事务 ID
                seq.s_id   = 8'h10;

                // 在 Master 0 上执行写事务
                seq.start(env.mst_agent[0].sequencer);
            end

            // 写事务完成后等待 50 个时间单位
            #50;

            // === 复位阶段 ===
            // 拉低复位信号（aresetn = 0 表示复位有效）
            env.mst_agent[0].driver.vif.aresetn <= 0;

            // 保持复位 10 个时钟周期
            repeat(10) @(posedge env.mst_agent[0].driver.vif.aclk);

            // 释放复位（aresetn = 1 表示正常工作）
            env.mst_agent[0].driver.vif.aresetn <= 1;

            // 等待 20 个时钟周期让 DUT 从复位中完全恢复
            repeat(20) @(posedge env.mst_agent[0].driver.vif.aclk);
        end

        // === 最终验证阶段 ===
        // 3 次复位循环结束后，再发送 4 笔写事务
        // 验证 DUT 在经历多次复位后仍能正常工作
        for (int i = 0; i < 4; i++) begin
            seq = axi_wr_seq::type_id::create($sformatf("final_%0d", i));
            seq.s_addr = i * 4;               // 地址 0, 4, 8, 12
            seq.s_data = 32'hA500_0010 + i;   // 数据标识为 final 阶段
            seq.s_id   = 8'h10;
            seq.start(env.mst_agent[0].sequencer);
        end

        // 等待所有响应返回
        #200;

        // 释放 objection
        phase.drop_objection(this);
    endtask
endclass
