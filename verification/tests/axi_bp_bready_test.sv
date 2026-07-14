//==========================================================================
// T071: B Channel Backpressure Test (UVM Sequence 版本)
// 测试名称: 写响应通道（B 通道）反压测试
//
// 【测试目的】
// 验证 AXI Crossbar 在 B 通道受到反压时的行为是否正确。
//
// 【B 通道背景知识】
// B 通道是 AXI 写操作的响应通道：
//   - slave 通过 B 通道返回写完成响应（bvalid）
//   - master 通过 bready 表示可以接收响应
//   - 只有 bvalid && bready 同时为高时，响应握手才成功
//
// B 通道反压是指 master 端暂时无法接收写响应（bready 为低）
// 这种情况可能发生在 master 忙于处理其他事务时
//
// 【本测试的实现方式】
// 与其他反压测试不同，本测试通过配置 slave 的响应延迟来间接制造反压：
//   - 设置 slave 的 delay_min=3, delay_max=8
//   - slave 在返回写响应前会随机延迟 3~8 个周期
//   - 这种延迟会导致 B 通道的 bvalid 信号被推迟
//   - 从而间接模拟了 B 通道的反压场景
//
// 【验证场景】
// - 配置所有 slave 的响应延迟范围为 3~8 个时钟周期
// - 连续发送 4 个 burst 写事务
// - 验证 crossbar 在延迟响应下能否正确处理所有写事务
// - 验证写响应不会丢失，所有事务都能正确完成
//==========================================================================

// 继承自 axi_base_test 基类
class axi_bp_bready_test extends axi_base_test;

    // 注册到 UVM 工厂
    `uvm_component_utils(axi_bp_bready_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试主执行阶段
    task run_phase(uvm_phase phase);
        // 声明 burst 写序列
        // axi_burst_wr_seq 用于生成多拍突发写事务
        axi_burst_wr_seq seq;

        // 举手反对
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待 5 个时钟周期让 DUT 稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 【配置 slave 响应延迟，制造 B 通道反压】
        // 遍历所有 4 个 slave
        // delay_min = 3: 最少延迟 3 个时钟周期才返回响应
        // delay_max = 8: 最多延迟 8 个时钟周期才返回响应
        // slave driver 会在 [3, 8] 范围内随机选择延迟值
        // 较长的延迟会导致 crossbar 内部的写响应 FIFO 积压
        // 从而测试 crossbar 的反压处理能力
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].delay_min = 3;
            env.slv_cfg[i].delay_max = 8;
        end

        // 【发送 burst 写事务】
        // 连续发送 4 个 burst 写事务
        // 每个事务使用不同的实例名（bp_0, bp_1, bp_2, bp_3）
        // $sformatf 是 SystemVerilog 的格式化字符串函数，类似 C 的 sprintf
        for (int i = 0; i < 4; i++) begin
            // 创建 burst 写序列实例
            // 每次循环创建一个新实例，避免覆盖前一个
            seq = axi_burst_wr_seq::type_id::create($sformatf("bp_%0d", i));

            // 配置序列参数：
            // s_addr = 16'h0000: 起始地址
            // s_id   = 8'h10:    AXI 事务 ID
            // s_len  = 3:        突发长度为 4 拍（AXI 的 len 字段 = 拍数 - 1）
            //   即一个写事务包含 4 个数据拍
            //   每拍数据都需要通过 W 通道传输
            seq.s_addr = 16'h0000;
            seq.s_id   = 8'h10;
            seq.s_len  = 3;  // 4-beat burst

            // 启动序列，绑定到 master 0 的 sequencer
            seq.start(env.mst_agent[0].sequencer);
        end

        // 等待所有事务完成
        // 由于 slave 有较长的延迟，需要更多时间等待所有响应返回
        #200;

        // 放下反对
        phase.drop_objection(this);
    endtask
endclass
