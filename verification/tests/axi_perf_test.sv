//==========================================================================
// Performance Test — 性能测试（合并版）
// 测试名称: 性能测试 (axi_perf_test)
//
// 【测试目的】
// 测量 AXI Crossbar 的性能指标。
// 本测试合并了以下两个性能测试：
//   1. 延迟测试：测量单笔事务的端到端延迟
//   2. 带宽测试：测量高负载下的吞吐量
//
// 【验证场景】
// - 单笔读/写事务的端到端延迟
// - Crossbar 内部仲裁和路由的延迟开销
// - 高负载下的吞吐量
// - 多 Master 并发时的带宽
//
// 【性能指标】
// - 延迟（Latency）：从请求发出到响应返回的时钟周期数
// - 带宽（Bandwidth）：单位时间内传输的数据量
//==========================================================================

class axi_perf_test extends axi_base_test;
    `uvm_component_utils(axi_perf_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_perf_seq perf_seq;

        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 测试1: 延迟测试（少量事务，精确测量）
        // ============================================================
        `uvm_info("TEST", "=== Latency Test ===", UVM_LOW)
        perf_seq = axi_perf_seq::type_id::create("latency_seq");
        perf_seq.s_addr = 16'h0000;
        perf_seq.s_id = 8'h10;
        perf_seq.s_count = 10;  // 10 笔事务
        perf_seq.start(env.mst_agent[0].sequencer);
        #200;

        // ============================================================
        // 测试2: 带宽测试（大量事务，测量吞吐量）
        // ============================================================
        `uvm_info("TEST", "=== Bandwidth Test ===", UVM_LOW)
        perf_seq = axi_perf_seq::type_id::create("bandwidth_seq");
        perf_seq.s_addr = 16'h1000;
        perf_seq.s_id = 8'h10;
        perf_seq.s_count = 100;  // 100 笔事务
        perf_seq.start(env.mst_agent[0].sequencer);
        #200;

        phase.drop_objection(this);
    endtask
endclass
