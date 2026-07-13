//==========================================================================
// T040: Multi-master concurrent (UVM Sequence 版本)
//
// 测试名称: 多主机并发测试 (axi_multi_master_test)
// 测试编号: T040
// 测试目的: 验证AXI Crossbar在多个Master同时发起写操作时的并发处理能力。
//          这是一个关键的互连验证场景，确保Crossbar能正确仲裁和转发
//          来自不同Master的并发事务，不会产生数据丢失或地址冲突。
//
// 测试原理:
//   - 4个Master同时向4个不同的Slave发起写操作
//   - Master 0 -> Slave 0 (地址 0x0000)
//   - Master 1 -> Slave 1 (地址 0x1000)
//   - Master 2 -> Slave 2 (地址 0x2000)
//   - Master 3 -> Slave 3 (地址 0x3000)
//   - 使用fork-join实现真正的并行执行
//   - 每个Master使用不同的ID，便于在波形中追踪
//
// 验证要点:
//   1. Crossbar的仲裁逻辑是否正确处理并发请求
//   2. 地址解码是否将事务路由到正确的Slave
//   3. 多个并行写操作是否互不干扰
//   4. 数据完整性是否得到保证
//==========================================================================

// 继承自axi_base_test基类
// UVM测试类通常继承自base_test，base_test负责创建env、配置参数等基础工作
// 子类只需要在run_phase中定义具体的测试激励即可
class axi_multi_master_test extends axi_base_test;

    // `uvm_component_utils宏: 将该类注册到UVM工厂(factory)中
    // 这使得可以通过类名字符串来创建该类的实例
    // 例如: factory.create("axi_multi_master_test") 即可通过工厂创建该测试
    // 这是UVM工厂模式的核心机制，支持运行时类型替换
    `uvm_component_utils(axi_multi_master_test)

    // 构造函数: 创建测试类实例
    // name: 组件名称，用于UVM层次结构中的标识
    // parent: 父组件句柄，形成UVM组件树
    // super.new(): 调用父类构造函数完成基类初始化
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: UVM的核心运行阶段
    // 这是测试激励生成和执行的主要场所
    // run_phase在所有build_phase、connect_phase完成后自动执行
    // 一个测试类通常只实现run_phase来定义测试行为
    task run_phase(uvm_phase phase);

        // seq: AXI写操作序列对象句柄
        // axi_wr_seq是一个UVM sequence，封装了一次完整的AXI写事务
        // 包括: 发送AWADDR(写地址) -> 发送WDATA(写数据) -> 接收BRESP(写响应)
        axi_wr_seq seq;

        // raise_objection: 阻止当前phase结束
        // UVM的phase机制会在所有objection被drop后才结束当前phase
        // 如果不raise_objection，run_phase会立即结束，测试就来不及执行
        // 这是UVM控制仿真结束的关键机制
        phase.raise_objection(this);

        // 等待复位释放: 监测 aresetn 信号的上升沿
        // aresetn是AXI协议的复位信号，低电平有效
        // 上升沿表示复位结束，系统进入正常工作状态
        // env.mst_drv[0].vif 引用Master驱动器0的虚拟接口(通过env层次访问)
        @(posedge env.mst_drv[0].vif.aresetn);

        // 额外等待5个时钟周期，让系统稳定后再发送激励
        // 这是一个常用的工程实践，避免复位后立即操作带来的时序问题
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // fork-join块: 创建4个并行执行的线程
        // fork: 启动多个并行线程
        // join: 等待所有线程执行完毕后才继续
        // 这是实现多Master并发的核心机制
        fork
            // === Master 0 写操作线程 ===
            begin
                // type_id::create(): 通过UVM工厂创建sequence实例
                // "m0"是实例名称，用于调试时标识这个sequence
                seq = axi_wr_seq::type_id::create("m0");

                // 配置sequence参数:
                // s_addr = 16'h0000: 目标地址为0x0000，对应Slave 0
                // s_data = 32'hAAAAAAAA: 写入的数据为0xAAAAAAAA
                // s_id   = 8'h10: AXI事务ID为0x10，用于标识事务来源
                //   ID在AXI协议中用于乱序和交织传输的标识
                seq.s_addr = 16'h0000;
                seq.s_data = 32'hAAAAAAAA;
                seq.s_id   = 8'h10;

                // seq.start(): 在指定的sequencer上启动sequence
                // env.sqr[0] 是Master 0对应的sequencer
                // sequencer负责将sequence item发送给driver
                // driver再将事务转化为AXI总线信号
                seq.start(env.sqr[0]);
            end

            // === Master 1 写操作线程 ===
            begin
                seq = axi_wr_seq::type_id::create("m1");
                // 目标地址0x1000 -> Slave 1, 数据0xBBBBBBBB, ID=0x20
                seq.s_addr = 16'h1000;
                seq.s_data = 32'hBBBBBBBB;
                seq.s_id   = 8'h20;
                seq.start(env.sqr[1]);  // 在Master 1的sequencer上执行
            end

            // === Master 2 写操作线程 ===
            begin
                seq = axi_wr_seq::type_id::create("m2");
                // 目标地址0x2000 -> Slave 2, 数据0xCCCCCCCC, ID=0x30
                seq.s_addr = 16'h2000;
                seq.s_data = 32'hCCCCCCCC;
                seq.s_id   = 8'h30;
                seq.start(env.sqr[2]);  // 在Master 2的sequencer上执行
            end

            // === Master 3 写操作线程 ===
            begin
                seq = axi_wr_seq::type_id::create("m3");
                // 目标地址0x3000 -> Slave 3, 数据0xDDDDDDDD, ID=0x40
                seq.s_addr = 16'h3000;
                seq.s_data = 32'hDDDDDDDD;
                seq.s_id   = 8'h40;
                seq.start(env.sqr[3]);  // 在Master 3的sequencer上执行
            end
        join  // 等待所有4个Master的写操作都完成

        // 等待200ns，让所有事务完成传输和响应
        // 给Crossbar和Slave足够时间处理完所有挂起的事务
        #200;

        // drop_objection: 允许run_phase结束
        // 与前面的raise_objection配对使用
        // 当所有组件的objection都被drop后，UVM才会结束run_phase
        // 随后进入extract_phase、check_phase等后续阶段
        phase.drop_objection(this);
    endtask
endclass
