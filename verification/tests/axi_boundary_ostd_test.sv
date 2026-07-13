//==========================================================================
// T063: Max Outstanding Test
// 测试名称: 最大 Outstanding（未完成事务数）边界测试
//
// 【测试目的】
// 验证 AXI Crossbar 在达到最大 outstanding 事务数时的行为是否正确。
// Outstanding 是 AXI 协议中的重要概念：master 可以在前一个事务还未完成时
// 就发出下一个事务，从而提高总线利用率。
// 最大 outstanding 数由 crossbar 内部的 FIFO 深度和配置决定。
//
// 【验证场景】
// - 连续发送多个事务而不等待前一个完成，达到 outstanding 上限
// - 验证 crossbar 内部的计数器和流控逻辑是否正确
// - 验证达到上限后，crossbar 是否正确地反压 master（不再接受新事务）
// - 验证所有 outstanding 事务最终都能正确完成
//
// 【测试策略】
// - 使用 axi_max_ostd_seq 序列，该序列专门生成连续的 outstanding 事务
// - 设置 s_ostd_num = 4，表示同时最多有 4 个未完成事务
// - 从 master 0 发送，目标地址 0x0000，ID 为 0x10
//==========================================================================

// 继承自 axi_base_test 基类
class axi_boundary_ostd_test extends axi_base_test;

    // 将该测试类注册到 UVM 工厂
    // 注册后可以通过 +UVM_TESTNAME=axi_boundary_ostd_test 在命令行选择此测试
    `uvm_component_utils(axi_boundary_ostd_test)

    // 构造函数：完成 UVM 组件的基本初始化
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试的主执行阶段
    task run_phase(uvm_phase phase);
        // 声明 outstanding 测试专用序列
        axi_max_ostd_seq seq;

        // 举手反对：防止 run_phase 提前结束
        phase.raise_objection(this);

        // 等待复位释放，DUT 进入正常工作状态
        @(posedge env.mst_drv[0].vif.aresetn);

        // 复位后等待 5 个时钟周期，让 DUT 内部状态稳定
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 通过 UVM 工厂创建序列实例
        seq = axi_max_ostd_seq::type_id::create("seq");

        // 【配置序列参数】
        // s_addr = 16'h0000: 起始地址为 0x0000
        //   地址 0x0000 会被 crossbar 路由到对应的 slave 端口
        // s_id = 8'h10: AXI 事务 ID
        //   所有 outstanding 事务使用相同的 ID
        //   AXI 协议要求同一 ID 的事务必须保序（in-order completion）
        // s_ostd_num = 4: 设置 outstanding 数量为 4
        //   这意味着序列会连续发出 4 个事务，不等待前一个完成
        //   这是测试 crossbar 流控能力的关键参数
        seq.s_addr     = 16'h0000;
        seq.s_id       = 8'h10;
        seq.s_ostd_num = 4;

        // 启动序列，绑定到 master 0 的 sequencer
        // sequencer 将事务项发送给 driver，driver 驱动 AXI 总线信号
        seq.start(env.sqr[0]);

        // 等待 200 个时间单位
        // outstanding 事务需要时间来逐一完成
        // 这个等待时间确保所有未完成事务都能收到响应并完成
        #200;

        // 放下反对：允许 run_phase 结束
        phase.drop_objection(this);
    endtask
endclass
