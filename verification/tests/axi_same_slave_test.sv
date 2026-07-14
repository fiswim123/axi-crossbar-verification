//==========================================================================
// T041: Same Slave Contention test
//
// 测试名称: 同一Slave竞争测试 (axi_same_slave_test)
// 测试编号: T041
// 测试目的: 验证当多个Master同时访问同一个Slave时，Crossbar的仲裁和
//          缓冲机制是否正确工作。这是互连设计中最重要的竞争场景之一。
//
// 测试原理:
//   - Master 0 和 Master 1 同时向 Slave 1 (地址 0x1000) 发起写操作
//   - 两个Master使用不同的事务ID (0x10 和 0x20)
//   - Crossbar必须串行化这两个请求，一次只能有一个Master访问Slave
//   - 另一个Master必须等待，直到前一个事务完成
//
// 验证要点:
//   1. Crossbar的仲裁策略是否正确(固定优先级/轮询/其他)
//   2. 在竞争情况下，数据是否完整，没有丢失或覆盖
//   3. Slave端的请求是否被正确串行化
//   4. 等待的Master是否能正确完成事务
//   5. 写响应(BRESP)是否正确返回给发起请求的Master
//
// 与multi_master_test的区别:
//   - multi_master: 每个Master访问不同Slave，无竞争
//   - same_slave:   多个Master访问同一Slave，存在竞争，需要仲裁
//==========================================================================

class axi_same_slave_test extends axi_base_test;

    // 注册到UVM工厂，支持通过工厂机制创建实例
    `uvm_component_utils(axi_same_slave_test)

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // run_phase: 定义测试的主要激励行为
    task run_phase(uvm_phase phase);

        // seq0, seq1: 两个axi_same_slave_seq实例
        // axi_same_slave_seq是专门用于同一Slave竞争测试的sequence
        // 它可能包含多次读写操作，以充分测试竞争场景
        axi_same_slave_seq seq0, seq1;

        // 阻止phase提前结束
        phase.raise_objection(this);

        // 等待复位释放
        @(posedge env.mst_agent[0].driver.vif.aresetn);

        // 等待5个时钟周期，系统稳定
        repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

        // 创建第一个sequence实例: 用于Master 0
        seq0 = axi_same_slave_seq::type_id::create("seq0");
        // 设置目标地址为0x1000，对应Slave 1
        seq0.s_addr = 16'h1000;
        // 设置事务ID为0x10，用于标识Master 0的事务
        seq0.s_id   = 8'h10;

        // 创建第二个sequence实例: 用于Master 1
        seq1 = axi_same_slave_seq::type_id::create("seq1");
        // 两个sequence访问相同的地址0x1000，制造竞争
        seq1.s_addr = 16'h1000;
        // 不同的ID标识不同的Master来源
        seq1.s_id   = 8'h20;

        // fork-join: 并行启动两个sequence
        // 两个Master同时发起请求，制造竞争条件
        fork
            // Master 0: 通过sqr[0](sequencer 0)发送事务
            seq0.start(env.mst_agent[0].sequencer);
            // Master 1: 通过sqr[1](sequencer 1)发送事务
            // 两个sequence同时start，但目标是同一个Slave
            // Crossbar必须决定先处理哪一个
            seq1.start(env.mst_agent[1].sequencer);
        join  // 等待两个sequence都执行完毕

        // 等待200ns，确保所有事务和响应完成
        #200;

        // 释放objection，允许phase结束
        phase.drop_objection(this);
    endtask
endclass
