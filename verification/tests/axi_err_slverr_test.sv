//==========================================================================
// T050: SLVERR Response Test
//
// 测试名称: 从机错误响应测试 (axi_err_slverr_test)
// 测试编号: T050
// 测试目的: 验证当Slave返回SLVERR(从机错误)响应时，Crossbar是否正确
//          将错误响应传递给Master。SLVERR是AXI协议中常见的错误类型，
//          表示Slave检测到了错误(如访问保护违规、内部错误等)。
//
// AXI响应编码 (RRESP/BRESP):
//   2'b00 = OKAY   (正常响应)
//   2'b01 = EXOKAY (独占访问成功)
//   2'b10 = SLVERR (从机错误 - Slave error)
//   2'b11 = DECERR (解码错误 - Decode error)
//
// 测试原理:
//   - 配置Slave 0使其100%返回SLVERR响应
//   - 发送一个写事务到Slave 0
//   - 期望Crossbar将SLVERR响应正确传递回Master
//   - 验证错误响应不会导致Crossbar挂死或行为异常
//
// 验证要点:
//   1. Slave返回的SLVERR是否正确传递到Master
//   2. Crossbar是否正确处理错误响应而不挂死
//   3. 错误响应后Crossbar是否能继续正常工作
//   4. err_inject_seq的错误检测机制是否正常工作
//==========================================================================

class axi_err_slverr_test extends axi_base_test;

    // 注册到UVM工厂
    `uvm_component_utils(axi_err_slverr_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义SLVERR注入测试
    task run_phase(uvm_phase phase);

        // seq: 错误注入序列对象
        // axi_err_inject_seq是专门用于错误注入测试的sequence
        // 它会发送事务并检查响应是否为预期的错误类型
        axi_err_inject_seq seq;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待5个时钟周期
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // === 配置Slave 0的错误注入参数 ===

        // err_pct = 100: 设置错误注入概率为100%
        // 这意味着Slave 0将对每个请求都返回错误响应
        // 在实际测试中，可以设置为50%来测试混合场景
        env.slv_cfg[0].err_pct = 100;

        // err_resp = 2'b10: 设置错误响应类型为SLVERR
        // 2'b10是SLVERR在AXI响应编码中的值
        // Slave在返回响应时会使用这个配置值
        env.slv_cfg[0].err_resp = 2'b10;

        // 创建错误注入sequence
        seq = axi_err_inject_seq::type_id::create("seq");

        // 配置sequence参数:
        // s_addr = 16'h0000: 访问地址0x0000(Slave 0)
        // s_id = 8'h10: 事务ID
        // s_expect_err = 1: 告诉sequence期望收到错误响应
        //   sequence会检查响应是否为SLVERR/DECERR
        //   如果没有收到错误，sequence会报错(UVM_ERROR)
        seq.s_addr      = 16'h0000;
        seq.s_id        = 8'h10;
        seq.s_expect_err = 1;

        // 在Master 0的sequencer上启动sequence
        seq.start(env.mst_agent[0].sequencer);

        // 等待200ns
        #200;

        // 释放objection
        phase.drop_objection(this);
    endtask
endclass
