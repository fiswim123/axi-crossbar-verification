//==========================================================================
// T090: Random Test (1000+ transactions)
// 测试名称: 随机测试
//
// 【测试目的】
// 通过大量随机事务来验证 AXI Crossbar 的整体功能正确性。
// 随机测试是 UVM 验证中最强大的方法之一，能够发现定向测试遗漏的 bug。
//
// 【随机测试 vs 定向测试】
// - 定向测试（如 boundary、backpressure 测试）：针对特定场景，验证已知的功能点
// - 随机测试：随机生成各种参数的事务，覆盖大量意想不到的组合
//   包括：随机地址、随机数据、随机突发长度、随机 ID、随机事务类型等
//
// 【验证场景】
// - 生成大量随机的读写事务（1000+）
// - 事务的地址、数据、ID、突发长度等参数全部随机
// - 随机混合读写操作，模拟真实使用场景
// - 验证 crossbar 在各种随机组合下都能正确工作
// - 通过 scoreboard 自动比对读写数据的一致性
//
// 【测试策略】
// - 使用 axi_random_seq 序列，该序列内部会随机化所有事务参数
// - s_count = 3 表示序列的循环次数（实际事务数由序列内部决定）
// - 测试运行时间较长，需要充足的仿真时间
//==========================================================================

// 继承自 axi_base_test 基类
class axi_random_test extends axi_base_test;

    // 注册到 UVM 工厂
    // 随机测试通常是回归测试（regression）中的必跑用例
    `uvm_component_utils(axi_random_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试主执行阶段
    task run_phase(uvm_phase phase);
        // 声明随机测试序列
        // axi_random_seq 内部使用 SystemVerilog 的 constraint 随机化机制
        // 自动生成各种参数组合的读写事务
        axi_random_seq seq;

        // 举手反对
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 创建随机测试序列
        seq = axi_random_seq::type_id::create("seq");

        // 配置序列参数：
        // s_count = 3: 控制序列的执行轮数
        //   每轮会生成多个随机事务
        //   具体每轮多少个事务由 axi_random_seq 内部实现决定
        //   总事务数可达 1000+，实现充分的随机覆盖
        seq.s_count = 3;

        // 启动序列，绑定到 master 0 的 sequencer
        // 随机序列会持续生成事务直到所有轮次完成
        seq.start(env.mst_agent[0].sequencer);

        // 等待所有随机事务完成
        // 随机测试的事务数量多，需要较长的等待时间
        // 如果仿真提前结束，可能会遗漏未完成的事务
        #200;

        // 放下反对
        phase.drop_objection(this);
    endtask
endclass
