//==========================================================================
// Outstanding Test — 未完成事务测试（合并版）
// 测试名称: Outstanding 测试 (axi_outstanding_test)
//
// 【测试目的】
// 验证 AXI Crossbar 在处理多个未完成事务时的行为是否正确。
// 本测试合并了以下两个 Outstanding 测试：
//   1. Outstanding 写测试：连续发送多个写请求不等响应
//   2. Outstanding 读测试：连续发送多个读请求不等响应
//
// 【验证场景】
// - Master 连续发起多个事务，不等待前一个事务完成
// - Crossbar 需要内部缓存和调度这些未完成的事务
// - 验证事务的响应能正确返回（按 ID 匹配）
// - 验证不会因为 Outstanding 导致死锁或数据丢失
//
// 【Outstanding 机制】
// AXI 协议支持 Outstanding，允许 Master 在前一个事务完成前发起新事务。
// 这可以提高总线利用率，但需要 Crossbar 具备以下能力：
// - 内部 FIFO 缓存未完成的事务
// - 按 ID 跟踪事务状态
// - 正确排序和返回响应
//==========================================================================

class axi_outstanding_test extends axi_base_test;
    `uvm_component_utils(axi_outstanding_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;
        axi_outstanding_read_seq ostd_rd_seq;

        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 测试1: Outstanding 写测试
        // ============================================================
        `uvm_info("TEST", "=== Outstanding Write Test ===", UVM_LOW)

        // 连续发送多个写请求（使用 fork/join_none 实现流水线）
        for (int i = 0; i < 4; i++) begin
            automatic int idx = i;
            wr_seq = axi_wr_seq::type_id::create($sformatf("wr_ostd_%0d", idx));
            wr_seq.s_addr = idx * 16'h1000;
            wr_seq.s_data = 32'hDEAD0000 + idx;
            wr_seq.s_id = 8'h10;
            fork
                wr_seq.start(env.mst_agent[0].sequencer);
            join_none
        end
        wait fork;
        #200;

        // ============================================================
        // 测试2: Outstanding 读测试
        // ============================================================
        `uvm_info("TEST", "=== Outstanding Read Test ===", UVM_LOW)

        // 先写入数据
        for (int i = 0; i < 4; i++) begin
            wr_seq = axi_wr_seq::type_id::create($sformatf("wr_for_rd_%0d", i));
            wr_seq.s_addr = i * 16'h1000;
            wr_seq.s_data = 32'hCAFEBABE + i;
            wr_seq.s_id = 8'h10;
            wr_seq.start(env.mst_agent[0].sequencer);
        end
        #100;

        // 连续发送多个读请求
        for (int i = 0; i < 4; i++) begin
            automatic int idx = i;
            rd_seq = axi_rd_seq::type_id::create($sformatf("rd_ostd_%0d", idx));
            rd_seq.s_addr = idx * 16'h1000;
            rd_seq.s_id = 8'h10;
            fork
                rd_seq.start(env.mst_agent[0].sequencer);
            join_none
        end
        wait fork;
        #200;

        phase.drop_objection(this);
    endtask
endclass
