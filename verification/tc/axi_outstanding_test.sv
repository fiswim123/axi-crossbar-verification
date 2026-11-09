//==========================================================================
// Outstanding Test — 未完成事务测试（合并版）
// 测试名称: Outstanding 测试 (axi_outstanding_test)
//
// 【测试目的】
// 验证多个 Master 同时发起请求并正确返回。
// 注意：当前 driver 每路串行，不能证明单个 Master 的多笔 outstanding。
//
// 【验证场景】
// - 四个 Master 各发起一笔，形成跨 Master 并发
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
        axi_wr_seq wr_parallel[4];
        axi_rd_seq rd_parallel[4];
        axi_outstanding_read_seq ostd_rd_seq;

        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // ============================================================
        // 测试1: Outstanding 写测试
        // ============================================================
        `uvm_info("TEST", "=== Outstanding Write Test ===", UVM_LOW)

        // Four masters issue concurrently.  A single master driver is serial,
        // so this tests cross-master outstanding, not same-master pipelining.
        for (int i = 0; i < 4; i++) begin
            wr_parallel[i] = axi_wr_seq::type_id::create($sformatf("wr_ostd_%0d", i));
            wr_parallel[i].s_addr = i * 16'h1000;
            wr_parallel[i].s_data = 32'hDEAD0000 + i;
            wr_parallel[i].s_id = (i + 1) << 4;
        end
        for (int i = 0; i < 4; i++) begin
            automatic int idx = i;
            fork
                wr_parallel[idx].start(env.mst_agent[idx].sequencer);
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

        // Repeat the same four-port concurrency for read responses.
        for (int i = 0; i < 4; i++) begin
            rd_parallel[i] = axi_rd_seq::type_id::create($sformatf("rd_ostd_%0d", i));
            rd_parallel[i].s_addr = i * 16'h1000;
            rd_parallel[i].s_id = (i + 1) << 4;
        end
        for (int i = 0; i < 4; i++) begin
            automatic int idx = i;
            fork
                rd_parallel[idx].start(env.mst_agent[idx].sequencer);
            join_none
        end
        wait fork;
        #200;

        phase.drop_objection(this);
    endtask
endclass
