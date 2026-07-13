//==========================================================================
// Burst Size Sequence (T024) — 不同传输大小的写后读验证序列
// 功能说明：
//   本序列用于验证 AXI crossbar 在不同 AxSIZE 设置下的正确性。
//   AxSIZE 决定每拍传输的字节数：size=0 传 1 字节，size=1 传 2 字节，size=2 传 4 字节。
//   序列依次发送 size=0/1/2 的写事务，再依次读回，验证写入数据与读出数据一致。
//   这是一个写后读（Write-then-Read）测试，确保不同粒度的数据传输都能正确路由。
//
// AXI Size 编码说明：
//   AxSIZE[2:0] | 每拍字节数 | 对应位宽
//       000     |    1       |   8 位
//       001     |    2       |  16 位
//       010     |    4       |  32 位
//       011     |    8       |  64 位
//       100     |   16       | 128 位
//       101     |   32       | 256 位
//       110     |   64       | 512 位
//       111     |  128       |1024 位
//
// 写选通（WSTRB）与 Size 的关系：
//   WSTRB 的有效位数 = 2^size
//   size=0: WSTRB 只有 bit[0] 有效，即 1'b1     = 4'h1（但只看低 1 位）
//   size=1: WSTRB 低 2 位有效，即 2'b11          = 4'h3（但只看低 2 位）
//   size=2: WSTRB 低 4 位有效，即 4'b1111        = 4'hF（全部 4 字节有效）
//==========================================================================
class axi_burst_size_seq extends uvm_sequence #(axi_txn);
    // 工厂注册
    `uvm_object_utils(axi_burst_size_seq)

    // s_addr：测试的基地址，所有写和读操作都使用同一地址
    // 这样可以确保写入的数据能被正确读回
    bit [15:0] s_addr;

    // s_id：AXI 事务 ID
    bit [7:0]  s_id;

    function new(string name = "axi_burst_size_seq");
        super.new(name);
    endfunction

    // body() task：先依次写入 3 种 size，再依次读回
    task body();
        axi_txn txn;

        // ===== 第一阶段：依次写入 size=0, 1, 2 =====
        // 循环变量 sz 从 0 到 2，分别对应 1 字节、2 字节、4 字节
        for (int sz = 0; sz <= 2; sz++) begin
            // 使用 $sformatf 生成唯一名称，避免工厂创建时名称冲突
            // 例如：txn_0, txn_1, txn_2
            txn = axi_txn::type_id::create($sformatf("txn_%0d", sz));

            txn.kind = axi_txn::WRITE;  // 写事务
            txn.addr = s_addr;           // 使用同一基地址
            txn.id = s_id;

            // len=0：单次传输（非 burst）
            // size=sz：传输大小随循环变化
            // burst=1：INCR 模式（地址递增），虽然 len=0 只有一拍，但仍显式指定 burst 类型
            txn.len = 0; txn.size = sz[2:0]; txn.burst = 1;

            // 分配 1 拍数据和写选通
            txn.wdata = new[1]; txn.wstrb = new[1];

            // 写入数据 = 0xA500_0000 + size 值
            // 例如：sz=0 时写 0xA500_0000，sz=1 时写 0xA500_0001，sz=2 时写 0xA500_0002
            txn.wdata[0] = 32'hA500_0000 + sz;

            // 写选通计算：(1 << (1 << sz)) - 1
            //   sz=0: (1 << (1<<0)) - 1 = (1 << 1) - 1 = 1     = 4'b0001  （1 字节有效）
            //   sz=1: (1 << (1<<1)) - 1 = (1 << 2) - 1 = 3     = 4'b0011  （2 字节有效）
            //   sz=2: (1 << (1<<2)) - 1 = (1 << 4) - 1 = 15    = 4'b1111  （4 字节有效）
            // 这个表达式自动生成与 size 匹配的写选通掩码
            txn.wstrb[0] = (1 << (1 << sz)) - 1;

            // 发送写 transaction
            start_item(txn); finish_item(txn);
        end

        // ===== 第二阶段：依次读回 size=0, 1, 2 =====
        // 读回与写入相同的 size 设置，确保 crossbar 以相同粒度处理读数据
        for (int sz = 0; sz <= 2; sz++) begin
            // 读 transaction 使用 "rd_" 前缀命名
            txn = axi_txn::type_id::create($sformatf("rd_%0d", sz));

            txn.kind = axi_txn::READ;   // 读事务
            txn.addr = s_addr;           // 同一地址
            txn.id = s_id;

            // 读参数与写参数对齐
            txn.len = 0; txn.size = sz[2:0]; txn.burst = 1;

            // 分配 1 拍读数据空间，由 driver 填入实际值
            txn.rdata = new[1];

            // 发送读 transaction
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
