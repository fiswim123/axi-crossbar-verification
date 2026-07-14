//==========================================================================
// Full Routing Test（全路由覆盖测试）— 补全缺失的路由交叉覆盖
// 注: MST3 只能访问 SLV3（DUT 路由限制），其余 3 条路由无法覆盖
//==========================================================================
// 【测试目的】
//   验证 AXI Crossbar 的地址路由功能，覆盖尽可能多的 Master-Slave 路由组合。
//   地址路由是 Crossbar 的核心功能：根据事务地址将请求转发到正确的 Slave。
//
// 【验证功能点】
//   - 地址解码逻辑：不同地址范围路由到不同 Slave
//   - 路由表配置的正确性
//   - Master 1 可以访问 Slave 1, 2, 3（MST1 → SLV1/SLV2/SLV3）
//   - Master 2 可以访问 Slave 0, 2, 3（MST2 → SLV0/SLV2/SLV3）
//
// 【DUT 路由限制说明】
//   MST3 只能访问 SLV3（硬件设计限制），所以 MST3 → SLV0/SLV1/SLV2 无法测试。
//   这 3 条路由在设计上被禁止，不需要覆盖。
//
// 【地址映射表】（假设）
//   0x0000 ~ 0x0FFF → SLV0
//   0x1000 ~ 0x1FFF → SLV1
//   0x2000 ~ 0x2FFF → SLV2
//   0x3000 ~ 0x3FFF → SLV3
//
// 【测试路由矩阵】
//        SLV0  SLV1  SLV2  SLV3
//  MST0   ✓     -     -     -     （基础测试已覆盖）
//  MST1   -     ✓     ✓     ✓     （本测试覆盖）
//  MST2   ✓     -     ✓     ✓     （本测试覆盖）
//  MST3   -     -     -     ✓     （DUT 限制，只能访问 SLV3）
//==========================================================================
class axi_full_routing_test extends axi_base_test;
    // 注册到 UVM 工厂
    `uvm_component_utils(axi_full_routing_test)

    // 构造函数
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // run_phase：测试激励执行阶段
    task run_phase(uvm_phase phase);
        // 全路由测试序列对象
        axi_full_routing_seq seq;

        // 阻止仿真提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // === MST1 → SLV1, SLV2, SLV3 ===
        // Master 1 访问 Slave 1（地址 0x1000）
        seq = axi_full_routing_seq::type_id::create("m1_s1");
        seq.s_addr = 16'h1000;    // 地址 0x1000 映射到 SLV1
        seq.s_id = 8'h20;         // AXI ID = 0x20（MST1 的 ID 前缀）
        seq.start(env.mst_agent[1].sequencer);    // 在 Master 1 的 sequencer 上执行

        // Master 1 访问 Slave 2（地址 0x2000）
        seq = axi_full_routing_seq::type_id::create("m1_s2");
        seq.s_addr = 16'h2000;    // 地址 0x2000 映射到 SLV2
        seq.s_id = 8'h20;
        seq.start(env.mst_agent[1].sequencer);

        // Master 1 访问 Slave 3（地址 0x3000）
        seq = axi_full_routing_seq::type_id::create("m1_s3");
        seq.s_addr = 16'h3000;    // 地址 0x3000 映射到 SLV3
        seq.s_id = 8'h20;
        seq.start(env.mst_agent[1].sequencer);

        // === MST2 → SLV0, SLV2, SLV3 ===
        // Master 2 访问 Slave 0（地址 0x0000）
        seq = axi_full_routing_seq::type_id::create("m2_s0");
        seq.s_addr = 16'h0000;    // 地址 0x0000 映射到 SLV0
        seq.s_id = 8'h30;         // AXI ID = 0x30（MST2 的 ID 前缀）
        seq.start(env.mst_agent[2].sequencer);    // 在 Master 2 的 sequencer 上执行

        // Master 2 访问 Slave 2（地址 0x2000）
        seq = axi_full_routing_seq::type_id::create("m2_s2");
        seq.s_addr = 16'h2000;    // 地址 0x2000 映射到 SLV2
        seq.s_id = 8'h30;
        seq.start(env.mst_agent[2].sequencer);

        // Master 2 访问 Slave 3（地址 0x3000）
        seq = axi_full_routing_seq::type_id::create("m2_s3");
        seq.s_addr = 16'h3000;    // 地址 0x3000 映射到 SLV3
        seq.s_id = 8'h30;
        seq.start(env.mst_agent[2].sequencer);

        // 等待所有响应返回
        #200;

        // 释放 objection
        phase.drop_objection(this);
    endtask
endclass
