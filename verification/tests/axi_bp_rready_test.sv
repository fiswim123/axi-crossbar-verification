//==========================================================================
// T072: R Channel Backpressure Test (UVM Sequence 版本)
// 测试名称: 读数据通道（R 通道）反压测试
//
// 【测试目的】
// 验证 AXI Crossbar 在 R 通道受到反压时的行为是否正确。
//
// 【R 通道背景知识】
// AXI 读操作涉及 2 个通道：
//   1. AR 通道（读地址）: master 发送读地址和控制信息
//   2. R  通道（读数据）: slave 返回读数据和响应
//
// R 通道的握手机制：
//   - slave 通过 rvalid 表示有数据要返回
//   - master 通过 rready 表示可以接收数据
//   - 只有 rvalid && rready 同时为高时，读数据传输才成功
//
// R 通道反压是指 master 暂时无法接收读数据（rready 为低）
// 本测试通过配置 slave 的响应延迟来间接制造 R 通道压力
//
// 【测试策略】
// 本测试分为两个阶段：
//   阶段 1: 预写入 - 先往指定地址写入已知数据
//   阶段 2: 延迟读取 - 配置 slave 延迟后读取数据，制造 R 通道反压
//
// 【验证场景】
// - 先写入 4 个地址的数据，为后续读取做准备
// - 配置 slave 响应延迟 3~8 个周期
// - 发起读事务，验证在 R 通道反压下数据能否正确返回
// - 验证读数据的值与之前写入的值一致（需要 scoreboard 配合检查）
//==========================================================================

// 继承自 axi_base_test 基类
class axi_bp_rready_test extends axi_base_test;

    // 注册到 UVM 工厂
    `uvm_component_utils(axi_bp_rready_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase：测试主执行阶段
    task run_phase(uvm_phase phase);
        // 声明写序列和读序列变量
        // axi_wr_seq: 单拍写事务序列
        // axi_rd_seq: 单拍读事务序列
        axi_wr_seq  wr_seq;
        axi_rd_seq  rd_seq;

        // 举手反对
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_drv[0].vif.aresetn);

        // 等待 5 个时钟周期
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 【阶段 1: 预写入数据】
        // 先往 4 个连续地址写入已知数据
        // 这些数据将在后续的读操作中被读出
        // 写入的数据模式为 0xA500_0000 + i，便于识别和校验
        for (int i = 0; i < 4; i++) begin
            // 创建写序列实例，每个实例名不同（prewr_0, prewr_1, ...）
            wr_seq = axi_wr_seq::type_id::create($sformatf("prewr_%0d", i));

            // 配置写参数：
            // s_addr = i * 4: 地址按 4 字节递增（32 位数据宽度）
            // s_data = 32'hA500_0000 + i: 写入带标识的数据
            // s_id   = 8'h10: AXI 事务 ID
            wr_seq.s_addr = i * 4;
            wr_seq.s_data = 32'hA500_0000 + i;
            wr_seq.s_id   = 8'h10;

            // 启动写序列
            wr_seq.start(env.sqr[0]);
        end

        // 【配置 slave 响应延迟，制造 R 通道反压】
        // 设置 slave 在返回读数据前延迟 3~8 个时钟周期
        // 这会导致 R 通道的 rvalid 信号被推迟
        // 如果 master 持续发起读请求，crossbar 内部会积压待返回的读数据
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].delay_min = 3;
            env.slv_cfg[i].delay_max = 8;
        end

        // 【阶段 2: 读取数据，触发 R 通道反压】
        // 从之前写入的地址读取数据
        // 由于配置了 slave 延迟，R 通道会受到反压
        for (int i = 0; i < 4; i++) begin
            // 创建读序列实例
            rd_seq = axi_rd_seq::type_id::create($sformatf("bp_rd_%0d", i));

            // 配置读参数：
            // s_addr = i * 4: 读取与写入相同的地址
            // s_id   = 8'h10: 使用相同的 ID
            rd_seq.s_addr = i * 4;
            rd_seq.s_id   = 8'h10;

            // 启动读序列
            rd_seq.start(env.sqr[0]);
        end

        // 等待所有事务完成
        // 读操作需要等待 slave 延迟后返回数据
        #200;

        // 放下反对
        phase.drop_objection(this);
    endtask
endclass
