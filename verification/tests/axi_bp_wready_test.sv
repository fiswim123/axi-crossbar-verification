//==========================================================================
// T070: W Channel Backpressure Test
// 测试名称: 写数据通道（W 通道）反压测试
//
// 【测试目的】
// 验证 AXI Crossbar 在 W 通道受到反压时的行为是否正确。
//
// 【AXI 写通道背景知识】
// AXI 写操作涉及 3 个通道：
//   1. AW 通道（写地址）: master 发送写地址和控制信息
//   2. W  通道（写数据）: master 发送写数据
//   3. B  通道（写响应）: slave 返回写完成响应
//
// W 通道的握手机制：
//   - master 通过 wvalid 表示有数据要发送
//   - slave  通过 wready 表示可以接收数据
//   - 只有当 wvalid 和 wready 同时为高时，数据传输才发生（握手成功）
//
// 【反压（Backpressure）概念】
// 反压是指 slave 通过拉低 wready 来告诉 master "我暂时接收不了数据"
// 这是 AXI 协议中流控的重要机制
// 设计必须正确处理反压：不能丢失数据，不能死锁
//
// 【验证场景】
// - 配置 slave 以 30% 的概率拉低 wready，模拟慢速从设备
// - 发送多个写事务，验证 crossbar 在 W 通道反压下能否正确传输数据
// - 验证不会出现数据丢失、死锁或协议违规
//==========================================================================

// 继承自 axi_base_test 基类
class axi_bp_wready_test extends axi_base_test;

    // 注册到 UVM 工厂，支持命令行选择和工厂替换
    `uvm_component_utils(axi_bp_wready_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试主执行阶段
    task run_phase(uvm_phase phase);
        // 声明反压测试专用序列
        // axi_backpressure_seq 是一个支持反压配置的通用序列
        axi_backpressure_seq seq;

        // 举手反对：防止 run_phase 提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_drv[0].vif.aresetn);

        // 复位后等待 5 个时钟周期，让 DUT 稳定
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 【关键配置：设置 W 通道反压概率】
        // 遍历所有 4 个 slave 的配置对象
        // 将每个 slave 的 wready 反压概率设为 30%
        // 这意味着 slave 有 30% 的概率不拉高 wready（拒绝接收数据）
        // bp_wready_pct 是 slave 配置中的反压百分比参数
        // slave 的 driver 会根据这个概率随机地延迟 wready 的拉高
        for (int i = 0; i < 4; i++)
            env.slv_cfg[i].bp_wready_pct = 30; // 30% 反压概率

        // 创建反压测试序列
        seq = axi_backpressure_seq::type_id::create("seq");

        // 配置序列参数：
        // s_addr  = 16'h0000: 起始地址
        // s_id    = 8'h10:    AXI 事务 ID
        // s_count = 4:        发送 4 个事务
        //   多个事务可以更充分地测试反压场景下的 crossbar 行为
        seq.s_addr  = 16'h0000;
        seq.s_id    = 8'h10;
        seq.s_count = 4;

        // 启动序列，绑定到 master 0 的 sequencer
        seq.start(env.sqr[0]);

        // 等待所有事务完成
        #200;

        // 放下反对，允许 phase 结束
        phase.drop_objection(this);
    endtask
endclass
