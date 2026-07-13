//==========================================================================
// T061: Max Burst Length Test
// 测试名称: 最大突发长度边界测试
//
// 【测试目的】
// 验证 AXI Crossbar 在处理最大突发长度（Burst Length）事务时的行为是否正确。
// AXI 协议中，AXI4 的最大突发长度为 256 拍（len=255，即 AWLEN/ARLEN=0xFF）。
// 这是一个边界条件测试（boundary test），专门测试设计在极端参数下的鲁棒性。
//
// 【验证场景】
// - 发送最大长度的突发写/读事务，验证 crossbar 能否正确传输所有数据拍
// - 验证地址递增逻辑在长突发下不会溢出或出错
// - 验证 crossbar 内部的 FIFO/缓冲区能否容纳最大突发的数据量
//
// 【测试策略】
// - 使用 axi_max_burst_seq 序列，该序列专门生成最大突发长度的事务
// - 从 master 0 发送，目标地址 0x0100，ID 为 0x10
// - 重复多次事务以增加覆盖率
//==========================================================================

// 继承自 axi_base_test 基类
// axi_base_test 中已经完成了环境（env）的创建、配置和连接
// 子类只需要重写 run_phase 来定义具体的测试行为
class axi_boundary_burst_test extends axi_base_test;

    // `uvm_component_utils 是 UVM 的工厂注册宏
    // 将该类注册到 UVM 工厂中，使得可以通过类名字符串来创建实例
    // 这是 UVM 工厂模式的核心：可以在不修改代码的情况下替换测试类
    `uvm_component_utils(axi_boundary_burst_test)

    // 构造函数
    // name: 组件实例名，通常由 UVM 自动生成
    // parent: 父组件指针，形成 UVM 组件的层次结构树
    function new(string name, uvm_component parent);
        super.new(name, parent); // 调用父类构造函数，完成 UVM 组件的基本初始化
    endfunction

    // run_phase 是 UVM 12 个 phase 中最核心的一个
    // 所有测试的激励生成和检查都在这个 phase 中完成
    // run_phase 在所有 build/connect/configure phase 完成之后才开始执行
    task run_phase(uvm_phase phase);

        // 声明一个 axi_max_burst_seq 类型的序列变量
        // axi_max_burst_seq 是专门用于生成最大突发长度事务的序列
        axi_max_burst_seq seq;

        // 【关键】raise_objection（举手反对）
        // UVM 的 phase 机制：当所有组件都 drop_objection 后，phase 才会结束
        // raise_objection 告诉 UVM："我还有事要做，不要结束 run_phase"
        // 如果不 raise_objection，run_phase 会立即结束，测试什么都不会做
        phase.raise_objection(this);

        // 等待复位释放（aresetn 从 0 变为 1）
        // aresetn 是 AXI 的异步复位信号，低电平有效
        // 在复位期间不能发送事务，必须等到复位结束
        @(posedge env.mst_drv[0].vif.aresetn);

        // 复位释放后再等待 5 个时钟周期
        // 这是为了让 DUT（被测设计）内部状态稳定下来
        // 确保所有寄存器和状态机都已进入正常工作状态
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 【创建序列实例】
        // type_id::create 是 UVM 工厂的创建方法
        // 它会根据工厂中注册的类型来创建实例
        // 如果有人在 testbench 顶层 override 了这个序列类型，这里会创建替代类型
        // "seq" 是实例名称，用于 UVM 的层次路径和日志标识
        seq = axi_max_burst_seq::type_id::create("seq");

        // 【配置序列参数】
        // s_addr = 16'h0100: 设置起始地址为 0x0100
        //   这个地址会被 crossbar 用于路由判断，决定事务发往哪个 slave
        // s_id = 8'h10: 设置 AXI 事务的 ID 为 0x10
        //   AXI 的 ID 用于支持乱序完成和事务标识
        //   在验证中，ID 也用于 scoreboard 中的事务匹配
        seq.s_addr = 16'h0100;
        seq.s_id   = 8'h10;

        // 【启动序列】
        // seq.start() 将序列绑定到指定的 sequencer 上开始执行
        // env.sqr[0] 是 master 0 对应的 sequencer
        // sequencer 负责将序列中的事务项（sequence item）发送给 driver
        // driver 再将事务转换为 AXI 总线信号驱动到 DUT
        seq.start(env.sqr[0]);

        // 等待 200 个时间单位
        // 给 DUT 足够的时间完成所有事务的处理和响应
        // 包括写响应（B 通道）和读数据（R 通道）的返回
        #200;

        // 【放下反对】
        // 与 raise_objection 配对使用
        // 告诉 UVM "我做完了，可以结束 run_phase 了"
        // 当所有 objection 都被 drop 后，UVM 会结束 run_phase 进入下一个 phase
        phase.drop_objection(this);
    endtask
endclass
