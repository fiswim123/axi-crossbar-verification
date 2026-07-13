//==========================================================================
// Concurrent Read/Write Sequence
// 功能说明：并发读写测试序列
//
// 测试目的：
//   验证AXI Crossbar同时处理读和写操作的能力。
//   与interleave序列不同，这里使用fork-join实现真正的并行执行，
//   读和写操作在同一时刻同时进行，而不是交替串行执行。
//
// 测试场景：
//   使用fork-join并行启动8个写操作和8个读操作。
//   地址在4个不同的目标地址之间随机选择，模拟真实的多地址并发访问。
//
// AXI协议知识点：
//   - AXI协议设计的核心优势之一就是读写通道分离，支持全双工操作
//   - 写通道(AW+W+B)和读通道(AR+R)可以同时工作，互不阻塞
//   - Crossbar内部需要为读和写提供独立的数据通路
//   - 并发访问时需要考虑：死锁(Deadlock)、活锁(Livelock)、饥饿(Starvation)
//   - 地址0x0100, 0x0200, 0x0400, 0x0800通常映射到4个不同的slave端口
//==========================================================================

// 类定义：并发读写测试sequence
class axi_concurrent_seq extends uvm_sequence #(axi_txn);

    // 工厂注册
    `uvm_object_utils(axi_concurrent_seq)

    // 构造函数
    function new(string name = "axi_concurrent_seq");
        super.new(name);
    endfunction

    // body()任务：使用fork-join实现真正的并发读写
    // 注意：这里声明为virtual task，允许子类重写(override)
    virtual task body();

        // UVM信息打印：标记sequence开始
        // get_type_name()返回类名"axi_concurrent_seq"
        // UVM_LOW是信息的冗余度级别，LOW级别通常都会显示
        `uvm_info(get_type_name(), "Starting concurrent read/write sequence", UVM_LOW)

        // fork-join块：并行执行两个begin-end块
        // fork：创建并行线程
        // join：等待所有并行线程都完成后才继续
        // 这是实现真正并发的关键机制
        fork

            // ==================== 写通道线程 ====================
            // 这个线程独立执行8个写操作
            begin
                for (int i = 0; i < 8; i++) begin

                    // 使用内置的req句柄（uvm_sequence自带的成员变量）
                    // req是uvm_sequence预定义的sequence_item句柄
                    req = axi_txn::type_id::create($sformatf("cwr_%0d", i));

                    // start_item：向sequencer请求发送授权
                    // 在并发场景下，sequencer需要协调读写两个线程的请求
                    start_item(req);

                    // 随机化事务参数，带约束条件
                    // assert确保随机化成功，如果失败会报告错误
                    // randomize with {} 语法允许在调用时添加额外约束
                    assert(req.randomize() with {
                        kind == axi_txn::WRITE;  // 约束为写操作
                        // addr约束在4个地址中随机选择一个
                        // 这4个地址分别对应4个不同的slave端口
                        // 16'h0100 = slave 0, 16'h0200 = slave 1
                        // 16'h0400 = slave 2, 16'h0800 = slave 3
                        addr inside {16'h0100, 16'h0200, 16'h0400, 16'h0800};
                    });

                    // finish_item：完成事务发送，等待driver的item_done
                    finish_item(req);
                end
            end

            // ==================== 读通道线程 ====================
            // 这个线程独立执行8个读操作，与写操作并行进行
            begin
                for (int i = 0; i < 8; i++) begin

                    // 创建读事务对象
                    req = axi_txn::type_id::create($sformatf("crd_%0d", i));

                    // 请求sequencer授权
                    start_item(req);

                    // 随机化读事务参数
                    assert(req.randomize() with {
                        kind == axi_txn::READ;  // 约束为读操作
                        // 同样在4个地址中随机选择
                        // 读写可能访问相同或不同的地址
                        // 相同地址的并发读写测试数据一致性
                        // 不同地址的并发读写测试crossbar的并行处理能力
                        addr inside {16'h0100, 16'h0200, 16'h0400, 16'h0800};
                    });

                    // 完成读事务发送
                    finish_item(req);
                end
            end

        // join：等待fork中的所有线程都完成
        // 只有当8个写操作和8个读操作全部完成后，body()才继续执行
        join

        // 打印完成信息
        `uvm_info(get_type_name(), "Concurrent read/write sequence completed", UVM_LOW)

        // 测试验证点：
        // 1. crossbar是否能同时处理读和写操作而不互相阻塞
        // 2. 并发访问同一地址时数据是否一致
        // 3. 不同地址的并发访问是否都能正确完成
        // 4. 是否存在死锁或活锁情况
        // 5. 所有16个事务是否都能在合理时间内完成
    endtask
endclass
