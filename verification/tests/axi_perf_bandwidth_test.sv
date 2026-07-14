//==========================================================================
// T101: Bandwidth Performance Test（带宽性能测试）
//==========================================================================
// 【测试目的】
//   测量 AXI Crossbar 的最大吞吐带宽（Bandwidth/Throughput）。
//   带宽 = 单位时间内成功传输的数据量。
//
// 【验证功能点】
//   - Crossbar 在持续高负载下的数据吞吐能力
//   - 流水线是否能保持满载运行（无气泡）
//   - 仲裁器在连续请求下的效率
//
// 【测试方法】
//   与延迟测试使用相同的 axi_perf_seq 序列，但发送更多事务（20 笔）。
//   更多的事务可以让流水线充分填满，从而测得真实的峰值带宽。
//   序列内部会统计：总传输字节数 / 总耗时周期数 = 带宽
//
// 【与延迟测试的区别】
//   - 延迟测试：少量事务，关注单笔响应时间
//   - 带宽测试：大量事务，关注持续吞吐能力
//
// 【关键参数】
//   - s_addr = 16'h0000: 目标地址映射到 SLV0
//   - s_id   = 8'h10:    AXI 事务 ID
//   - s_count = 20:      发送 20 笔事务（比延迟测试多一倍）
//==========================================================================
class axi_perf_bandwidth_test extends axi_base_test;
    // 注册到 UVM 工厂
    `uvm_component_utils(axi_perf_bandwidth_test)

    // 构造函数
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase：测试激励执行阶段
    task run_phase(uvm_phase phase);
        // 性能测试序列对象
        axi_perf_seq seq;

        // 阻止仿真提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 创建性能测试序列（与延迟测试使用同一个序列类）
        seq = axi_perf_seq::type_id::create("seq");

        // 配置序列参数：
        //   s_addr  = 16'h0000: 目标地址
        //   s_id    = 8'h10:    AXI ID
        //   s_count = 20:       事务数量（带宽测试用较大值以填满流水线）
        seq.s_addr = 16'h0000; seq.s_id = 8'h10; seq.s_count = 20;

        // 在 Master 0 的 sequencer 上启动带宽测试序列
        seq.start(env.mst_agent[0].sequencer);

        // 等待所有响应返回
        #200;

        // 释放 objection
        phase.drop_objection(this);
    endtask
endclass
