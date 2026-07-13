//==========================================================================
// T100: Latency Performance Test（延迟性能测试）
//==========================================================================
// 【测试目的】
//   测量 AXI Crossbar 的单笔事务延迟（Latency）。
//   延迟 = 从 Master 发出请求到收到响应的时钟周期数。
//
// 【验证功能点】
//   - 单笔读/写事务的端到端延迟
//   - Crossbar 内部仲裁和路由的延迟开销
//   - Slave 响应路径的延迟
//
// 【测试方法】
//   通过 axi_perf_seq 序列发送少量事务（10 笔），
//   序列内部会记录每笔事务的起始和结束时间，计算平均延迟。
//   使用少量事务可以更精确地测量单笔延迟（减少流水线重叠的影响）。
//
// 【关键参数】
//   - s_addr: 起始地址，决定事务路由到哪个 Slave
//   - s_id:   AXI ID，用于标识事务流
//   - s_count: 事务数量，延迟测试用较小值（10）
//==========================================================================
class axi_perf_latency_test extends axi_base_test;
    // 注册到 UVM 工厂，支持工厂覆盖（例如在 regression 中替换为其他测试类）
    `uvm_component_utils(axi_perf_latency_test)

    // 构造函数：创建测试组件实例
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase：测试激励的主要执行阶段
    task run_phase(uvm_phase phase);
        // 性能测试序列对象
        axi_perf_seq seq;

        // raise_objection 阻止仿真提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_drv[0].vif.aresetn);
        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 创建性能测试序列
        seq = axi_perf_seq::type_id::create("seq");

        // 配置序列参数：
        //   s_addr = 16'h0000: 目标地址为 0x0000，通常映射到 SLV0
        //   s_id   = 8'h10:    AXI ID 为 0x10，用于标识这笔事务流
        //   s_count = 10:      发送 10 笔事务（延迟测试用较少数量）
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_count = 10;

        // 在 Master 0 的 sequencer 上启动性能序列
        // 序列会自动记录延迟数据并在 scoreboard 中统计
        seq.start(env.sqr[0]);

        // 等待所有响应返回
        #200;

        // 释放 objection，允许仿真结束
        phase.drop_objection(this);
    endtask
endclass
