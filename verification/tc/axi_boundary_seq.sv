//==========================================================================
// Boundary Test Sequence — 边界测试序列文件
//==========================================================================
// 本文件包含三个序列类，用于测试AXI Crossbar的边界条件：
//   1. axi_boundary_seq   — 地址边界测试（各Slave地址空间的边界地址）
//   2. axi_max_burst_seq  — 最大突发长度测试（各种burst length）
//   3. axi_max_ostd_seq   — 最大未完成事务测试（outstanding transactions）
//
// 【UVM序列(Sequence)概念说明】
//   - uvm_sequence 是UVM中产生激励(stimulus)的核心机制
//   - sequence 不是组件(component)，而是对象(object)，通过body()任务产生事务
//   - 每个sequence通过 start_item() 和 finish_item() 将事务(transaction)发送给driver
//   - start_item() 等待driver准备好接收，finish_item() 等待driver处理完毕
//   - sequence 通过 sequencer(仲裁器) 与 driver 通信
//==========================================================================

//==========================================================================
// 类1：axi_boundary_seq — 地址边界测试序列
//==========================================================================
// 【测试目的】
//   测试AXI Crossbar在各种地址边界条件下的行为是否正确。
//   地址边界是指各个Slave地址空间的起始地址和结束地址附近的关键地址。
//   例如：如果Slave0地址范围是0x0000~0x0FFF，那么0x0000、0x0FFC就是边界地址。
//
// 【为什么需要边界测试】
//   地址解码逻辑通常在边界处容易出错，比如：
//   - 地址正好等于某个slave的起始/结束地址
//   - 地址在两个slave地址空间的交界处
//   - 地址对齐问题（4字节对齐）
//
// 【AXI协议知识点】
//   - addr: AXI传输的起始地址
//   - id:   事务ID，用于乱序处理和匹配请求/响应
//   - len:  突发长度(beats数-1)，len=0表示单次传输(1 beat)
//   - size: 每次传输的字节数(2^size)，size=2表示4字节(32位)
//   - burst: 突发类型，0=FIXED, 1=INCR, 2=WRAP
//   - wstrb: 写字节选通，4位对应4个字节，1=有效
//==========================================================================
class axi_boundary_seq extends uvm_sequence #(axi_txn);
    // `uvm_object_utils 宏：向UVM工厂(factory)注册此类
    // 工厂机制允许在运行时用子类替换父类，无需修改代码
    `uvm_object_utils(axi_boundary_seq)

    // s_id: 事务ID，用于标识来源master
    // 在AXI协议中，ID用于支持乱序完成和outstanding传输
    bit [7:0] s_id;

    // 构造函数：创建sequence对象时调用
    // UVM要求所有sequence都必须有构造函数，并调用父类构造函数
    function new(string name = "axi_boundary_seq");
        super.new(name);
    endfunction

    // body()任务：sequence的核心逻辑，当sequence被启动(start)时自动执行
    // 这是UVM sequence的入口点，所有激励产生逻辑都在这里编写
    task body();
        axi_txn txn; // 声明一个AXI事务对象句柄(handle)

        // 定义9个边界测试地址数组
        // 这些地址覆盖了4个Slave地址空间(0x0000-0x3FFF)的关键边界：
        //   Slave0: 0x0000-0x0FFF → 测试 0x0000(起始), 0x0004(起始+4), 0x0FFC(末尾)
        //   Slave1: 0x1000-0x1FFF → 测试 0x1000(起始), 0x1FFC(末尾)
        //   Slave2: 0x2000-0x2FFF → 测试 0x2000(起始), 0x2FFC(末尾)
        //   Slave3: 0x3000-0x3FFF → 测试 0x3000(起始), 0x3FFC(末尾)
        // 注意：所有地址都是4字节对齐的(末位为0, 4, 8, C)
        bit [15:0] addrs[9];
        addrs = '{16'h0000, 16'h0004, 16'h0FFC, 16'h1000,
                  16'h1FFC, 16'h2000, 16'h2FFC, 16'h3000,
                  16'h3FFC};

        // ---- 第一阶段：写操作测试 ----
        // 对每个边界地址执行一次写操作
        foreach (addrs[i]) begin
            // type_id::create 是UVM工厂创建方式，替代直接new()
            // 优点：可以在test层通过factory override替换为子类
            // $sformatf 格式化字符串，为每个txn生成唯一名称如 "addr_0", "addr_1"...
            txn = axi_txn::type_id::create($sformatf("addr_%0d", i));

            // 设置事务为写操作
            txn.kind = axi_txn::WRITE;
            txn.addr = addrs[i]; // 设置目标地址
            txn.id = s_id;       // 设置事务ID

            // AXI传输参数设置：
            // len=0:  突发长度为1(单次传输，1个beat)
            // size=2: 每次传输4字节(2^2=4)
            // burst=1: INCR模式(地址递增突发)
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 写数据和写字节选通
            // new[1] 分配1个元素的数组(因为len=0，只有1个beat)
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hB000_0000 + i; // 写入数据，每个地址不同便于验证
            txn.wstrb[0] = 4'hF;               // 4'hF = 4'b1111，所有4个字节都有效

            // start_item: 等待sequencer和driver准备好接收此事务
            // finish_item: 将事务发送给driver并等待driver完成处理
            // 这两步是UVM sequence向driver发送事务的标准流程
            start_item(txn); finish_item(txn);
        end

        // ---- 第二阶段：读回验证 ----
        // 对相同的边界地址执行读操作，验证之前写入的数据是否正确
        // 这是一种 write-then-read 验证策略
        foreach (addrs[i]) begin
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));

            // 设置事务为读操作
            txn.kind = axi_txn::READ;
            txn.addr = addrs[i]; // 读取相同地址
            txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区(虽然driver会填充数据，但需要分配空间)
            txn.rdata = new[1];

            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// 类2：axi_max_burst_seq — 最大突发长度测试序列
//==========================================================================
// 【测试目的】
//   测试AXI Crossbar对不同突发长度(burst length)的支持是否正确。
//   AXI3协议支持1~16拍(beats)的突发传输，AXI4支持1~256拍。
//
// 【AXI突发传输知识】
//   - 突发长度(AXI len字段) = 实际拍数 - 1
//   - len=0 → 1拍传输(single beat)
//   - len=1 → 2拍传输
//   - len=3 → 4拍传输
//   - len=7 → 8拍传输
//   - len=15 → 16拍传输
//   - 突发传输可以提高总线效率，因为地址只发一次，数据发多次
//
// 【为什么测试burst length很重要】
//   - Crossbar内部可能有FIFO缓冲区，不同burst长度对FIFO压力不同
//   - 地址递增逻辑需要正确处理各种burst长度
//   - 某些设计可能有burst length限制
//==========================================================================
class axi_max_burst_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_max_burst_seq)

    // s_addr: 基地址，burst传输的起始地址
    // 由test层配置，决定访问哪个slave
    bit [15:0] s_addr;

    // s_id: 事务ID
    bit [7:0]  s_id;

    // 构造函数
    function new(string name = "axi_max_burst_seq");
        super.new(name);
    endfunction

    // body()任务：产生不同burst长度的传输
    task body();
        axi_txn txn;

        // 定义5种burst长度的len值
        // len值 = 实际拍数 - 1，对应关系：
        //   len=0  → 1拍(single beat)
        //   len=1  → 2拍
        //   len=3  → 4拍
        //   len=7  → 8拍
        //   len=15 → 16拍(maximum burst length for AXI3)
        int lengths[5] = '{0, 1, 3, 7, 15};

        // ---- 写操作：各种burst长度 ----
        foreach (lengths[i]) begin
            txn = axi_txn::type_id::create($sformatf("burst_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr;  // 所有burst使用相同基地址
            txn.id = s_id;

            // 设置burst参数
            // lengths[i][7:0] 将int转换为bit[7:0]，因为txn.len是8位宽
            txn.len = lengths[i][7:0]; // burst长度
            txn.size = 2;              // 每拍4字节(32位)
            txn.burst = 1;             // INCR模式(地址递增)

            // 分配写数据和选通数组，大小 = burst长度 + 1
            // 因为len字段是"拍数-1"，所以实际拍数 = len + 1
            txn.wdata = new[lengths[i] + 1];
            txn.wstrb = new[lengths[i] + 1];

            // 填充每拍的写数据
            for (int j = 0; j <= lengths[i]; j++) begin
                txn.wdata[j] = 32'hB550_0000 + j; // 每拍数据不同，便于验证
                txn.wstrb[j] = 4'hF;               // 所有字节有效
            end

            start_item(txn); finish_item(txn);
        end

        // ---- 读操作：用相同burst长度读回 ----
        // 验证写入的数据是否正确
        foreach (lengths[i]) begin
            txn = axi_txn::type_id::create($sformatf("rdb_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr;
            txn.id = s_id;
            txn.len = lengths[i][7:0];
            txn.size = 2;
            txn.burst = 1;

            // 分配读数据缓冲区
            txn.rdata = new[lengths[i] + 1];

            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// 类3：axi_max_ostd_seq — 最大未完成事务(Outstanding)测试序列
//==========================================================================
// 【测试目的】
//   测试AXI Crossbar处理多个未完成事务(outstanding transactions)的能力。
//
// 【什么是Outstanding Transactions】
//   AXI协议允许master在前一个事务完成之前就发送下一个事务。
//   例如：master发出写请求W0后，不等W0的写响应(B通道)回来，
//   就可以继续发出写请求W1、W2...
//   这些"已发出但尚未收到响应"的事务称为 outstanding transactions。
//
// 【Outstanding的好处】
//   - 提高总线利用率：master不需要等待响应就可以继续发请求
//   - 掩盖延迟：特别是读操作，outstanding可以隐藏读数据返回的延迟
//   - 提高系统吞吐量
//
// 【Crossbar需要处理的问题】
//   - 需要足够深度的FIFO/缓冲区来存储outstanding事务
//   - 需要正确维护事务顺序(对于相同ID的事务)
//   - 需要正确处理outstanding限制
//==========================================================================
class axi_max_ostd_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_max_ostd_seq)

    // s_addr: 基地址
    bit [15:0] s_addr;

    // s_id: 事务ID
    bit [7:0]  s_id;

    // s_ostd_num: 最大未完成事务数量
    // 默认值为4，表示测试4个outstanding事务
    // 可以在test层修改此值来测试不同的outstanding深度
    int        s_ostd_num = 4;

    // 构造函数
    function new(string name = "axi_max_ostd_seq");
        super.new(name);
    endfunction

    // body()任务：产生多个outstanding的写和读事务
    task body();
        axi_txn txn;

        // ---- 写操作：发送s_ostd_num个写请求 ----
        // 注意：这里用顺序循环发送，但因为是同一个sequence，
        // 每个txn会依次通过start_item/finish_item发送给driver
        // driver端可能会利用AXI的outstanding能力并行处理
        for (int i = 0; i < s_ostd_num; i++) begin
            txn = axi_txn::type_id::create($sformatf("owr_%0d", i));
            txn.kind = axi_txn::WRITE;

            // 每个事务访问不同地址(偏移4字节)，避免地址冲突
            txn.addr = s_addr + i * 4;
            txn.id = s_id;

            // 单拍传输(len=0)
            txn.len = 0; txn.size = 2; txn.burst = 1;

            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'h057D_0000 + i; // 特殊数据模式，便于识别
            txn.wstrb[0] = 4'hF;

            start_item(txn); finish_item(txn);
        end

        // ---- 读操作：发送s_ostd_num个读请求 ----
        // 读操作的outstanding更有意义，因为读延迟通常比写高
        // 多个读请求可以流水线化，提高读带宽
        for (int i = 0; i < s_ostd_num; i++) begin
            txn = axi_txn::type_id::create($sformatf("ord_%0d", i));
            txn.kind = axi_txn::READ;

            // 读取相同地址，验证之前写入的数据
            txn.addr = s_addr + i * 4;
            txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区
            txn.rdata = new[1];

            start_item(txn); finish_item(txn);
        end
    endtask
endclass
