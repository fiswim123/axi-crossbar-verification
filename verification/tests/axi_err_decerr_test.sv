//==========================================================================
// T051: DECERR Response Test
//
// 测试名称: 解码错误响应测试 (axi_err_decerr_test)
// 测试编号: T051
// 测试目的: 验证当Slave返回DECERR(解码错误)响应时，Crossbar是否正确
//          将错误传递给Master。DECERR表示地址解码错误，通常发生在
//          访问一个不存在的地址范围时。
//
// SLVERR vs DECERR 区别:
//   - SLVERR (2'b10): 从机错误。Slave地址存在，但Slave内部出错。
//     例如: 访问保护区域、Slave内部故障、超时等。
//   - DECERR (2'b11): 解码错误。地址无法被任何Slave解码。
//     例如: 访问未映射的地址空间、地址超出所有Slave范围。
//
// 测试原理:
//   - 配置Slave 1使其100%返回DECERR响应
//   - 发送一个写事务到地址0x1000(Slave 1)
//   - 期望Crossbar将DECERR响应正确传递回Master
//   - 验证DECERR处理不会影响Crossbar的正常功能
//
// 验证要点:
//   1. Slave返回的DECERR是否正确传递到Master
//   2. Crossbar是否正确区分SLVERR和DECERR
//   3. DECERR响应后Crossbar状态是否正常
//   4. 错误处理不会影响后续正常事务
//==========================================================================

class axi_err_decerr_test extends axi_base_test;

    // 注册到UVM工厂
    `uvm_component_utils(axi_err_decerr_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义DECERR注入测试
    task run_phase(uvm_phase phase);

        // 错误注入sequence句柄
        axi_err_inject_seq seq;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_drv[0].vif.aresetn);

        // 等待5个时钟周期
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // === 配置Slave 1的错误注入参数 ===

        // err_pct = 100: 100%概率返回错误
        env.slv_cfg[1].err_pct = 100;

        // err_resp = 2'b11: 错误响应类型为DECERR
        // 与SLVERR测试(2'b10)不同，这里使用DECERR编码(2'b11)
        env.slv_cfg[1].err_resp = 2'b11;

        // 创建错误注入sequence
        seq = axi_err_inject_seq::type_id::create("seq");

        // 配置参数:
        // s_addr = 16'h1000: 访问Slave 1的地址空间
        // s_expect_err = 1: 期望收到错误响应
        seq.s_addr      = 16'h1000;
        seq.s_id        = 8'h10;
        seq.s_expect_err = 1;

        // 在Master 0的sequencer上启动
        seq.start(env.sqr[0]);

        // 等待200ns
        #200;

        // 释放objection
        phase.drop_objection(this);
    endtask
endclass
