//==========================================================================
// T091: Random Concurrent Test（随机并发测试）
//==========================================================================
// 【测试目的】
//   验证 AXI Crossbar 在多个 Master 同时发起随机事务时的并发处理能力。
//   这是一个压力测试，模拟真实场景中多个主设备同时访问总线的情况。
//
// 【验证功能点】
//   - 多 Master 并发仲裁功能
//   - 随机地址/数据/ID 下的协议正确性
//   - Crossbar 内部 FIFO 和流水线不会溢出或死锁
//
// 【测试流程】
//   1. 等待复位完成
//   2. 依次在 4 个 Master 的 sequencer 上启动随机并发序列
//   3. 每个 Master 发送 5 笔随机读写事务
//   4. 等待所有事务完成
//==========================================================================
class axi_random_concurrent_test extends axi_base_test;
    // `uvm_component_utils 宏：将该类注册到 UVM 工厂（factory）
    // 注册后可以通过类型名字符串动态创建对象，实现工厂覆盖（override）机制
    `uvm_component_utils(axi_random_concurrent_test)

    // 构造函数
    // name: 组件实例名称（UVM 树中的路径名）
    // parent: 父组件指针（通常为 uvm_test_top 或 uvm_env）
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase 任务：UVM 12 个 phase 中的核心执行阶段
    // 所有测试激励的产生都在这个 phase 中完成
    task run_phase(uvm_phase phase);
        // 声明一个随机并发序列对象
        axi_random_concurrent_seq seq;

        // 【关键机制】raise_objection / drop_objection
        // UVM phase 机制通过 objection 计数来控制仿真结束时机：
        //   - raise_objection: 表示"我还有工作要做，不要结束仿真"
        //   - drop_objection:  表示"我的工作做完了，可以结束仿真"
        // 当所有组件都 drop 了 objection，仿真才会结束
        phase.raise_objection(this);

        // 等待复位释放（aresetn 从 0 变为 1）
        // env.mst_agent[0].driver.vif 是 Master 驱动器的虚拟接口（virtual interface）
        // aresetn 是 AXI 协议的复位信号，低电平有效
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 复位释放后再等 5 个时钟周期，确保 DUT 内部状态稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 依次在 4 个 Master 的 sequencer 上启动随机并发序列
        // for 循环变量 i 表示 Master 编号（0~3，对应 MST0~MST3）
        for (int i = 0; i < 4; i++) begin
            // 使用 UVM 工厂创建序列实例
            // type_id::create 是 UVM 推荐的对象创建方式（而非 new()）
            // $sformatf 生成带编号的唯一名称，便于波形调试时区分
            seq = axi_random_concurrent_seq::type_id::create($sformatf("seq_%0d", i));

            // 设置序列参数：s_count = 5 表示每个 Master 发送 5 笔事务
            seq.s_count = 5;

            // 启动序列：将序列发送到第 i 个 Master 的 sequencer 上执行
            // env.sqr[i] 是环境（env）中第 i 个 Master 的 sequencer
            // start() 会阻塞直到序列中的所有 item 都发送完毕
            seq.start(env.sqr[i]);
        end

        // 等待 200 个时间单位，确保所有 DUT 内部流水线清空、响应全部返回
        #200;

        // 释放 objection，表示测试完成，允许仿真结束
        phase.drop_objection(this);
    endtask
endclass
