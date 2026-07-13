//==========================================================================
// T001-T003: Basic write/read (UVM Sequence 版本)
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 的基本读写功能：
//   - T001: Master 0 依次向 4 个 Slave 发起写事务
//   - T002: Master 0 依次从 4 个 Slave 读回数据
//   - T003: 验证读回的数据与写入的数据一致（在 scoreboard 中检查）
//
// 【UVM 知识点】
//   - run_phase: 测试的主要执行阶段，所有测试逻辑都在这里编写
//   - raise_objection / drop_objection: 控制仿真结束的机制
//     仿真不会在 run_phase 结束时自动停止，必须等到所有 objection 被撤回
//   - sequence.start(sqr): 在指定的 sequencer 上启动一个 sequence
//
// 【测试流程】
//   1. 等待复位释放 + 额外时钟周期（稳定信号）
//   2. 依次向 4 个 slave 地址写入不同数据
//   3. 等待 200 个时间单位（让写事务完成）
//   4. 依次从 4 个 slave 地址读回数据
//   5. 等待 200 个时间单位（让读事务完成）
//   6. 撤回 objection，仿真结束
//
//==========================================================================

// 【类定义】axi_basic_test 继承自 axi_base_test
// 继承了基类的 env（验证环境），可以直接使用
class axi_basic_test extends axi_base_test;

    // 【工厂注册】注册到 UVM 工厂，支持通过 +UVM_TESTNAME 指定运行
    `uvm_component_utils(axi_basic_test)

    // 【构造函数】简写形式，直接调用父类构造函数
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】run_phase
    // 这是测试的核心逻辑所在
    // run_phase 与所有其他 phase（如 build_phase）并行运行
    // 但 run_phase 是唯一一个消耗仿真时间的 phase（task 而非 function）
    task run_phase(uvm_phase phase);

        // 【局部变量】声明 sequence 句柄
        // axi_wr_seq: 写事务 sequence，用于生成写请求
        // axi_rd_seq: 读事务 sequence，用于生成读请求
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

        // 【objection 机制】raise_objection 表示"我还有工作要做，仿真不要结束"
        // 必须与 drop_objection 配对使用
        // 如果忘记 drop_objection，仿真会永远挂起（hanging）
        phase.raise_objection(this);

        // 【等待复位释放】等待 aresetn 信号的上升沿（复位结束）
        // aresetn 是 AXI 的全局复位信号，低有效
        // 上升沿表示复位释放，系统开始正常工作
        @(posedge env.mst_drv[0].vif.aresetn);

        // 【额外等待】复位释放后再等 5 个时钟周期
        // 确保所有信号稳定后再开始发送事务
        // env.mst_drv[0]: master 0 的 driver
        // vif: virtual interface，driver 通过它访问 DUT 的信号
        // aclk: AXI 时钟信号
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // ============================================================
        // T001: 写测试 — Master 0 依次向 4 个 Slave 写入数据
        // ============================================================
        // 地址映射：
        //   Slave 0: 0x0000 ~ 0x0FFF
        //   Slave 1: 0x1000 ~ 0x1FFF
        //   Slave 2: 0x2000 ~ 0x2FFF
        //   Slave 3: 0x3000 ~ 0x3FFF
        for (int s = 0; s < 4; s++) begin

            // 【创建写 sequence】通过工厂创建 axi_wr_seq 实例
            // $sformatf 生成带编号的实例名，如 "wr_seq0"、"wr_seq1" 等
            wr_seq = axi_wr_seq::type_id::create($sformatf("wr_seq%0d", s));

            // 【配置 sequence 参数】
            // s_addr: 目标地址，s*0x1000 映射到不同 slave
            // s_data: 写入数据，0xDEAD0000 + s 用于区分不同 slave
            // s_id:   事务 ID，用于乱序返回时识别事务
            wr_seq.s_addr = s * 16'h1000;
            wr_seq.s_data = 32'hDEAD0000 + s;
            wr_seq.s_id   = 8'h10;

            // 【启动 sequence】在 sequencer env.sqr[0] 上启动
            // start() 是阻塞调用，会等待 sequence 执行完毕后才返回
            // env.sqr[0] 是 master 0 对应的 sequencer
            wr_seq.start(env.sqr[0]);
        end

        // 【等待】让写事务有时间完成传输
        // #200 表示等待 200 个仿真时间单位
        #200;

        // ============================================================
        // T002+T003: 读测试 — Master 0 依次从 4 个 Slave 读回数据
        // ============================================================
        for (int s = 0; s < 4; s++) begin

            // 【创建读 sequence】
            rd_seq = axi_rd_seq::type_id::create($sformatf("rd_seq%0d", s));

            // 【配置读 sequence 参数】
            // 地址和 ID 与写操作对应，确保读回同一位置的数据
            rd_seq.s_addr = s * 16'h1000;
            rd_seq.s_id   = 8'h10;

            // 【启动读 sequence】
            rd_seq.start(env.sqr[0]);
        end

        // 【等待】让读事务有时间完成
        #200;

        // 【撤回 objection】表示测试完成，仿真可以结束
        // 与 raise_objection 配对使用
        phase.drop_objection(this);
    endtask
endclass
