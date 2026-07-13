//==========================================================================
// T053: Error Recovery Test
//
// 测试名称: 错误恢复测试 (axi_err_recovery_test)
// 测试编号: T053
// 测试目的: 验证Crossbar在经历错误响应后是否能正确恢复到正常工作状态。
//          这是可靠性测试的重要组成部分，确保瞬态错误不会导致系统永久故障。
//
// 测试原理:
//   分三个阶段执行:
//   阶段1 - 错误注入阶段:
//     - 配置Slave 0以50%概率返回SLVERR
//     - 发送8个事务(混合成功和错误响应)
//     - 验证Crossbar能正确处理混合响应
//
//   阶段2 - 错误恢复阶段:
//     - 关闭错误注入(err_pct = 0)
//     - 发送一个写事务
//     - 验证写操作能正常完成(响应为OKAY)
//
//   阶段3 - 数据验证阶段:
//     - 读回之前写入的数据
//     - 验证数据完整性(写入的值能被正确读出)
//
// 验证要点:
//   1. Crossbar能否正确处理混合成功/错误响应
//   2. 错误响应不会导致Crossbar内部状态异常
//   3. 关闭错误注入后，系统能否完全恢复正常
//   4. 恢复后的读写操作数据是否正确
//   5. 长时间运行的稳定性(8个事务的批量测试)
//==========================================================================

class axi_err_recovery_test extends axi_base_test;

    // 注册到UVM工厂
    `uvm_component_utils(axi_err_recovery_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义三阶段错误恢复测试
    task run_phase(uvm_phase phase);

        // err_seq: 错误注入多事务序列
        // axi_err_multi_seq可以发送多个事务，其中一些期望错误，一些期望成功
        axi_err_multi_seq err_seq;

        // wr_seq: 普通写序列(用于恢复后的正常操作)
        axi_wr_seq wr_seq;

        // rd_seq: 普通读序列(用于验证数据完整性)
        axi_rd_seq rd_seq;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_drv[0].vif.aresetn);

        // 等待5个时钟周期
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // ==================== 阶段1: 错误注入 ====================

        // 配置Slave 0的错误参数
        // err_pct = 50: 50%概率返回错误，制造混合成功/错误的场景
        env.slv_cfg[0].err_pct = 50;
        // err_resp = 2'b10: 错误类型为SLVERR
        env.slv_cfg[0].err_resp = 2'b10;

        // 创建错误注入sequence
        err_seq = axi_err_multi_seq::type_id::create("err_seq");
        // 配置参数:
        // s_addr = 16'h0000: 访问Slave 0
        // s_id = 8'h10: 事务ID
        // s_count = 8: 发送8个事务
        //   由于错误概率50%，大约一半事务会收到SLVERR
        err_seq.s_addr  = 16'h0000;
        err_seq.s_id    = 8'h10;
        err_seq.s_count = 8;

        // 在Master 0的sequencer上启动批量错误注入
        err_seq.start(env.sqr[0]);

        // 等待100ns，让所有错误事务完成
        #100;

        // ==================== 阶段2: 关闭错误并执行正常写操作 ====================

        // 关闭错误注入: 将错误概率设为0
        // 从此刻起，Slave 0将返回正常OKAY响应
        env.slv_cfg[0].err_pct = 0;

        // 创建普通写sequence
        wr_seq = axi_wr_seq::type_id::create("wr_seq");
        // 写入数据0xA500_0001到地址0x0000
        // 这个特殊的数据值便于在波形中识别
        wr_seq.s_addr = 16'h0000;
        wr_seq.s_id   = 8'h10;
        wr_seq.s_data = 32'hA500_0001;

        // 执行写操作
        wr_seq.start(env.sqr[0]);

        // ==================== 阶段3: 读回验证 ====================

        // 创建普通读sequence
        rd_seq = axi_rd_seq::type_id::create("rd_seq");
        // 读取地址0x0000的数据(与写入地址相同)
        rd_seq.s_addr = 16'h0000;
        rd_seq.s_id   = 8'h10;

        // 执行读操作
        // sequence内部或scoreboard会比较读出的数据与写入的数据
        rd_seq.start(env.sqr[0]);

        // 等待200ns
        #200;

        // 释放objection
        phase.drop_objection(this);
    endtask
endclass
