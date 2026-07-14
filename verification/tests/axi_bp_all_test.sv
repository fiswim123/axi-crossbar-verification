//==========================================================================
// T073: All Channels Backpressure Test
// 测试名称: 全通道反压测试
//
// 【测试目的】
// 验证 AXI Crossbar 在所有通道同时受到反压时的行为是否正确。
// 这是反压测试中最严苛的场景，同时对 AW、W、AR 三个通道施加反压。
//
// 【AXI 通道回顾】
// AXI 协议有 5 个通道：
//   写操作: AW（写地址）+ W（写数据）+ B（写响应）
//   读操作: AR（读地址）+ R（读数据）
//
// 本测试同时对以下 3 个通道施加反压：
//   - AW 通道: 通过 bp_awready_pct 控制 slave 的 awready 反压概率
//   - W  通道: 通过 bp_wready_pct  控制 slave 的 wready  反压概率
//   - AR 通道: 通过 bp_arready_pct 控制 slave 的 arready 反压概率
//
// B 通道和 R 通道的反压由 master 端控制（bready/rready），不在 slave 配置中
//
// 【验证场景】
// - 所有 3 个通道同时以 25% 的概率进行反压
// - 发送 6 个混合读写事务
// - 验证 crossbar 在极端反压条件下不会死锁或丢数据
// - 这是最接近真实场景的反压测试
//==========================================================================

// 继承自 axi_base_test 基类
class axi_bp_all_test extends axi_base_test;

    // 注册到 UVM 工厂
    `uvm_component_utils(axi_bp_all_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试主执行阶段
    task run_phase(uvm_phase phase);
        // 声明反压测试序列
        axi_backpressure_seq seq;

        // 举手反对
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 【配置所有通道的反压概率】
        // 遍历所有 4 个 slave，同时配置 3 个通道的反压
        // bp_awready_pct = 25: AW 通道（写地址）25% 概率反压
        //   slave 有 25% 的概率不拉高 awready，拒绝接收写地址
        // bp_wready_pct  = 25: W 通道（写数据）25% 概率反压
        //   slave 有 25% 的概率不拉高 wready，拒绝接收写数据
        // bp_arready_pct = 25: AR 通道（读地址）25% 概率反压
        //   slave 有 25% 的概率不拉高 arready，拒绝接收读地址
        //
        // 注意：三个通道的反压是独立随机的
        // 同一时刻可能 0~3 个通道同时被反压
        // 这种组合场景能更全面地测试 crossbar 的鲁棒性
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].bp_awready_pct = 25; // AW 通道 25% 反压
            env.slv_cfg[i].bp_wready_pct  = 25; // W  通道 25% 反压
            env.slv_cfg[i].bp_arready_pct = 25; // AR 通道 25% 反压
        end

        // 创建反压测试序列
        seq = axi_backpressure_seq::type_id::create("seq");

        // 配置序列参数：
        // s_addr  = 16'h0000: 起始地址
        // s_id    = 8'h10:    AXI 事务 ID
        // s_count = 6:        发送 6 个事务
        //   较多的事务数量可以在多通道反压下产生更丰富的交叉场景
        //   增加发现潜在 bug 的概率
        seq.s_addr  = 16'h0000;
        seq.s_id    = 8'h10;
        seq.s_count = 6;

        // 启动序列
        seq.start(env.mst_agent[0].sequencer);

        // 等待所有事务完成
        // 多通道反压下事务完成时间更长，需要充足的等待时间
        #200;

        // 放下反对
        phase.drop_objection(this);
    endtask
endclass
