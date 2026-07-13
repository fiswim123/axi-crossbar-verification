//==========================================================================
// Backpressure Test Sequence — 背压测试序列
//==========================================================================
// 【测试目的】
//   测试AXI Crossbar在面对下游背压(backpressure)情况下的行为是否正确。
//
// 【什么是背压(Backpressure)】
//   背压是指下游模块(如Slave)因为忙碌(缓冲区满、正在处理等)
//   而暂时无法接收新数据，通过握手机制向上游施加压力的现象。
//
// 【AXI握手机制与背压】
//   AXI协议使用VALID/READY握手机制：
//   - VALID信号：发送方表示数据/地址有效
//   - READY信号：接收方表示可以接收
//   - 只有当VALID和READY同时为高时，数据才真正传输
//
//   当VALID=1但READY=0时，就是背压状态：
//   - 发送方必须保持VALID=1和数据稳定
//   - 接收方在准备好后将READY拉高完成传输
//   - 这个过程可能持续多个时钟周期
//
// 【本序列的测试策略】
//   发送多个burst写操作和读操作，每个burst有4拍(4 beats)。
//   在driver端或monitor端会模拟背压条件(通过延迟置位READY信号)。
//   测试Crossbar是否能正确处理：
//   - 写数据通道(W通道)的背压
//   - 写响应通道(B通道)的背压
//   - 读数据通道(R通道)的背压
//   - 地址通道(AR/AW通道)的背压
//==========================================================================
class axi_backpressure_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_backpressure_seq)

    // s_addr: 基地址，由test层配置
    bit [15:0] s_addr;

    // s_id: 事务ID
    bit [7:0]  s_id;

    // s_count: 测试次数，产生多少组写-读对
    // 默认4组，即4次写+4次读
    int        s_count = 4;

    // 构造函数
    function new(string name = "axi_backpressure_seq");
        super.new(name);
    endfunction

    // body()任务：产生多次burst写和读操作
    task body();
        axi_txn txn;

        // 循环s_count次，每次产生一对写-读操作
        for (int i = 0; i < s_count; i++) begin

            // ---- 写操作 ----
            // 产生一个4拍burst写事务
            txn = axi_txn::type_id::create($sformatf("bpw_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr;  // 使用相同基地址
            txn.id = s_id;

            // 设置为4拍burst传输：
            // len=3:  实际拍数 = 3+1 = 4拍
            // size=2: 每拍4字节(32位数据宽度)
            // burst=1: INCR模式，地址每拍递增4字节
            txn.len = 3; txn.size = 2; txn.burst = 1;

            // 分配4个元素的写数据和选通数组
            txn.wdata = new[4]; txn.wstrb = new[4];

            // 填充4拍的写数据
            for (int j = 0; j < 4; j++) begin
                // 数据模式: 0xBA5E_0000 + i*4 + j
                // BA5E 类似 "BASE"，便于在波形中识别
                txn.wdata[j] = 32'hBA5E_0000 + i * 4 + j;
                txn.wstrb[j] = 4'hF; // 所有字节有效
            end

            // 发送写事务给driver
            start_item(txn); finish_item(txn);

            // ---- 读操作 ----
            // 产生一个4拍burst读事务
            txn = axi_txn::type_id::create($sformatf("bpr_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr;  // 读取相同地址，验证写入数据
            txn.id = s_id;

            // 相同的burst参数
            txn.len = 3; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区
            // driver将从DUT读回数据填充到此数组
            txn.rdata = new[4];

            // 发送读事务给driver
            start_item(txn); finish_item(txn);
        end

        // 【验证原理】
        // 1. 写操作会通过写地址通道(AW)和写数据通道(W)发送到DUT
        //    如果DUT内部有背压，READY信号会延迟置位
        // 2. 读操作会通过读地址通道(AR)发送，读数据通过R通道返回
        //    同样受到背压影响
        // 3. scoreboard会比较写入和读回的数据，验证正确性
        // 4. 如果backpressure_ratio参数被设置(在test中)，
        //    driver或monitor会按比例模拟背压
    endtask
endclass
