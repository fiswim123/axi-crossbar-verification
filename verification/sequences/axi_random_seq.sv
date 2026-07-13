//==========================================================================
// Random Test Sequence — 随机测试序列文件
//==========================================================================
// 本文件包含两个序列类：
//   1. axi_random_seq            — 单master随机测试
//   2. axi_random_concurrent_seq — 多master并发随机测试
//
// 【随机测试的重要性】
//   定向测试(directed test)只能覆盖我们能想到的场景，
//   但真实的芯片使用场景是不可预测的。
//   随机测试可以产生大量我们想不到的激励组合，
//   从而发现设计中的隐藏bug。
//
// 【本文件的特点】
//   虽然名称叫"random"，但这里的随机性主要体现在：
//   - 地址轮流访问4个slave(模拟随机路由)
//   - 读写交替(模拟真实使用场景)
//   - 大量重复(100次)，增加覆盖率
//   注意：真正的随机化通常在txn类中用constraint实现
//==========================================================================

//==========================================================================
// 类1：axi_random_seq — 单Master随机测试序列
//==========================================================================
// 【测试目的】
//   用单个master发起大量随机的读写操作，测试Crossbar的基本功能。
//   模拟一个master随机访问多个slave的场景。
//
// 【测试策略】
//   - 100次迭代(可配置)
//   - 读写交替：偶数次写，奇数次读
//   - 地址轮流：循环访问4个slave地址
//   - 单拍传输：len=0，简化测试，专注于路由功能
//==========================================================================
class axi_random_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_random_seq)

    // s_count: 测试次数，默认100次
    // 增大此值可以提高覆盖率，但会增加仿真时间
    int s_count = 100;

    // 构造函数
    function new(string name = "axi_random_seq");
        super.new(name);
    endfunction

    // body()任务：产生随机读写激励
    task body();
        axi_txn txn;

        // 定义4个目标地址，分别对应4个slave
        // 每个地址是对应slave地址空间的起始地址
        // Slave0: 0x0000, Slave1: 0x1000, Slave2: 0x2000, Slave3: 0x3000
        bit [15:0] addrs[4];
        addrs = '{16'h0000, 16'h1000, 16'h2000, 16'h3000};

        // 循环s_count次产生激励
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("rand_%0d", i));

            // 读写交替：偶数(i%2==0)为写，奇数为读
            // 这模拟了真实的读写混合场景
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;

            // 地址轮流：i%4 决定访问哪个slave
            // 0→Slave0, 1→Slave1, 2→Slave2, 3→Slave3, 4→Slave0, ...
            // 这确保了所有slave都被均匀访问
            txn.addr = addrs[i % 4];

            // 使用固定的事务ID = 0x10
            // 注意：在AXI中，相同ID的事务必须保序(ordering)
            txn.id = 8'h10;

            // 单拍传输参数
            // len=0:  1拍
            // size=2: 4字节
            // burst=1: INCR模式
            txn.len = 0;
            txn.size = 2;
            txn.burst = 1;

            // 如果是写操作，需要设置写数据
            if (txn.kind == axi_txn::WRITE) begin
                txn.wdata = new[1]; // 1个元素(1拍)
                txn.wstrb = new[1];
                txn.wdata[0] = 32'hA500_0000 + i; // 数据包含迭代计数，便于调试
                txn.wstrb[0] = 4'hF;               // 所有字节有效
            end else begin
                // 如果是读操作，分配读数据缓冲区
                txn.rdata = new[1];
            end

            // 发送事务
            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// 类2：axi_random_concurrent_seq — 多Master并发随机测试序列
//==========================================================================
// 【测试目的】
//   模拟多个master同时访问Crossbar的场景。
//   与axi_random_seq的区别是，这个sequence会在不同的sequencer上运行，
//   由test层启动多个实例来模拟并发访问。
//
// 【并发测试的意义】
//   - 测试Crossbar的仲裁(arbitration)逻辑
//   - 测试多个master访问同一个slave时的冲突处理
//   - 测试内部FIFO/缓冲区的并发访问安全性
//   - 测试数据通路的隔离性(不同master的数据不应混淆)
//
// 【使用方式】
//   在test中，为每个master创建一个virtual sequence，
//   然后用fork...join同时启动多个axi_random_concurrent_seq实例。
//   每个实例使用不同的sequencer和不同的ID。
//==========================================================================
class axi_random_concurrent_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_random_concurrent_seq)

    // s_count: 每个master的测试次数，默认50次
    // 因为有多个master并发，所以单个master的次数可以少一些
    int s_count = 50;

    // 构造函数
    function new(string name = "axi_random_concurrent_seq");
        super.new(name);
    endfunction

    // body()任务：产生随机读写激励
    task body();
        axi_txn txn;

        // 同样的4个slave地址
        bit [15:0] addrs[4];
        addrs = '{16'h0000, 16'h1000, 16'h2000, 16'h3000};

        // 循环产生激励
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("rc_%0d", i));

            // 读写交替
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;

            // 地址轮流访问4个slave
            txn.addr = addrs[i % 4];

            // 使用事务ID = 0x20，与axi_random_seq的ID(0x10)不同
            // 不同ID的事务在AXI中不需要保序
            // 这有助于测试Crossbar的乱序处理能力
            txn.id = 8'h20;

            // 单拍传输
            txn.len = 0;
            txn.size = 2;
            txn.burst = 1;

            // 设置数据缓冲区
            if (txn.kind == axi_txn::WRITE) begin
                txn.wdata = new[1];
                txn.wstrb = new[1];
                txn.wdata[0] = 32'hB600_0000 + i; // 不同的数据模式(0xB6xx)
                txn.wstrb[0] = 4'hF;
            end else begin
                txn.rdata = new[1];
            end

            start_item(txn); finish_item(txn);
        end
    endtask
endclass
