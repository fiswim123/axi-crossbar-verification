//==========================================================================
// T010-T018: Routing (UVM Sequence 版本)
//==========================================================================
//
// 【测试目的】
//   验证 AXI Crossbar 的路由功能，确保事务能正确到达目标 Slave：
//   - T010-T013: Master 0 依次访问所有 4 个 Slave（顺序路由）
//   - T014-T016: 多个 Master 同时访问不同 Slave（并行路由）
//
// 【路由原理】
//   AXI Crossbar 根据事务的目标地址将请求路由到对应的 Slave：
//   - 地址 0x0000~0x0FFF → Slave 0
//   - 地址 0x1000~0x1FFF → Slave 1
//   - 地址 0x2000~0x2FFF → Slave 2
//   - 地址 0x3000~0x3FFF → Slave 3
//
// 【UVM 知识点】
//   - fork/join: 并行启动多个线程，等待所有线程完成
//   - 多 sequencer: 每个 master 都有自己的 sequencer（env.sqr[0..3]）
//   - 通过不同的 sequencer 启动 sequence 实现多 master 并行操作
//
//==========================================================================

// 【类定义】axi_routing_test 继承自 axi_base_test
class axi_routing_test extends axi_base_test;

    // 【工厂注册】
    `uvm_component_utils(axi_routing_test)

    // 【构造函数】
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // 【主执行阶段】
    task run_phase(uvm_phase phase);

        // 【局部变量】写事务 sequence 句柄
        // 这里只用一个变量 seq，通过重新赋值来复用
        axi_wr_seq seq;

        // 【开始测试】raise_objection 阻止仿真提前结束
        phase.raise_objection(this);

        // 【等待复位释放】
        @(posedge env.mst_drv[0].vif.aresetn);

        // 【额外等待 5 个时钟周期】确保系统稳定
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // ============================================================
        // T010-T013: Master 0 顺序访问所有 4 个 Slave
        // ============================================================
        // 验证单个 Master 能正确路由到所有 Slave
        for (int s = 0; s < 4; s++) begin

            // 【创建写 sequence】实例名格式如 "m0_s0"、"m0_s1" 等
            // m0 表示 master 0，s0/s1/s2/s3 表示目标 slave
            seq = axi_wr_seq::type_id::create($sformatf("m0_s%0d", s));

            // 【配置参数】每个 sequence 目标地址不同，数据也不同
            // s_addr: 目标 slave 的基地址
            // s_data: 写入数据（0x00000000 + s），便于在波形中区分
            // s_id:   事务 ID，标识来源
            seq.s_addr = s * 16'h1000;
            seq.s_data = 32'h00000000 + s;
            seq.s_id   = 8'h10;

            // 【在 master 0 的 sequencer 上启动】
            // start() 是阻塞调用，会等待完成后再继续下一次循环
            seq.start(env.sqr[0]);
        end

        // ============================================================
        // T014-T016: 多 Master 并行访问不同 Slave
        // ============================================================
        // 验证多个 Master 同时发起事务时，Crossbar 能正确路由且不冲突
        //
        // 【fork/join 机制】
        // fork: 并行启动多个 begin...end 块
        // join: 等待所有并行块都完成后才继续
        // 这里 3 个 Master 同时发起写事务，测试 Crossbar 的并行处理能力
        fork
            // 【Master 1 → Slave 0】
            // 地址 0x0000 映射到 Slave 0
            // ID 0x20 区分于 Master 0 的 ID 0x10
            begin
                seq = axi_wr_seq::type_id::create("m1_s0");
                seq.s_addr = 16'h0000;
                seq.s_data = 32'h00000100;
                seq.s_id   = 8'h20;
                // 【在 master 1 的 sequencer 上启动】
                // 不同 master 使用不同的 sequencer
                seq.start(env.sqr[1]);
            end
            // 【Master 2 → Slave 1】
            // 地址 0x1000 映射到 Slave 1
            begin
                seq = axi_wr_seq::type_id::create("m2_s1");
                seq.s_addr = 16'h1000;
                seq.s_data = 32'h00000201;
                seq.s_id   = 8'h30;
                // 【在 master 2 的 sequencer 上启动】
                seq.start(env.sqr[2]);
            end
            // 【Master 3 → Slave 3】
            // 地址 0x3000 映射到 Slave 3
            begin
                seq = axi_wr_seq::type_id::create("m3_s3");
                seq.s_addr = 16'h3000;
                seq.s_data = 32'h00000303;
                seq.s_id   = 8'h40;
                // 【在 master 3 的 sequencer 上启动】
                seq.start(env.sqr[3]);
            end
        join  // 等待 3 个并行事务全部完成

        // 【等待】让所有事务有时间完成传输
        #200;

        // 【结束测试】撤回 objection，仿真可以结束
        phase.drop_objection(this);
    endtask
endclass
