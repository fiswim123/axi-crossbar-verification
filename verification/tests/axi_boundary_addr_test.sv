//==========================================================================
// T060: Boundary Address Test
//
// 测试名称: 边界地址测试 (axi_boundary_addr_test)
// 测试编号: T060
// 测试目的: 验证Crossbar在地址边界条件下的行为是否正确。边界测试是
//          验证中非常重要的测试类型，因为地址解码逻辑在边界值时
//          容易出现off-by-one错误或其他边界问题。
//
// 测试原理:
//   - 使用axi_boundary_seq，该sequence会测试各种边界地址
//   - 典型的边界地址包括:
//     * 各Slave地址空间的起始地址(如0x0000, 0x1000, 0x2000, 0x3000)
//     * 各Slave地址空间的结束地址(如0x0FFF, 0x1FFF, 0x2FFF, 0x3FFF)
//     * 地址空间的交界处(如0x0FFE~0x1001跨越Slave 0和Slave 1边界)
//     * 最大地址值(如0xFFFF)
//     * 最小地址值(如0x0000)
//     * 突发传输跨越地址边界的情况
//
// 验证要点:
//   1. 地址解码在边界值时是否正确
//   2. 事务是否被路由到正确的Slave
//   3. 边界地址是否导致意外的DECERR
//   4. 突发传输跨越地址边界时的数据完整性
//   5. 地址回绕(wrap)行为是否正确
//
// 为什么边界测试重要:
//   地址解码通常使用比较器实现，例如:
//     slave_sel = (addr >= BASE_LO) && (addr <= BASE_HI)
//   边界值(如BASE_LO-1, BASE_HI+1)容易暴露比较器的设计缺陷
//==========================================================================

class axi_boundary_addr_test extends axi_base_test;

    // 注册到UVM工厂
    `uvm_component_utils(axi_boundary_addr_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义边界地址测试激励
    task run_phase(uvm_phase phase);

        // seq: 边界地址序列对象
        // axi_boundary_seq是专门设计的sequence，内部会测试各种边界地址
        // 包括: 起始地址、结束地址、跨边界、最大/最小地址等
        axi_boundary_seq seq;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待5个时钟周期
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 创建边界sequence实例
        seq = axi_boundary_seq::type_id::create("seq");

        // 配置sequence参数:
        // s_id = 8'h10: 事务ID
        // 注意: 这里没有设置s_addr，因为boundary_seq内部会自行
        // 遍历所有需要测试的边界地址
        seq.s_id = 8'h10;

        // 在Master 0的sequencer上启动边界测试
        // sequence会自动测试所有边界地址条件
        seq.start(env.mst_agent[0].sequencer);

        // 等待200ns，让所有边界测试事务完成
        #200;

        // 释放objection
        phase.drop_objection(this);
    endtask
endclass
