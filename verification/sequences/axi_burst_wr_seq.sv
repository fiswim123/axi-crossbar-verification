//==========================================================================
// Burst Write Sequence — 突发写事务序列
// 功能说明：
//   本序列用于发起 AXI 突发写事务（Burst Write Transaction）。
//   与单次写不同，burst 写在一次地址传输后，连续传输多拍数据。
//   AW 通道发送一次地址（含 burst 长度），W 通道连续发送 len+1 拍数据。
//   适用于验证 crossbar 在 burst 传输下的数据完整性和通道仲裁能力。
//
// AXI Burst 协议要点：
//   - AWLEN（len）：突发长度，实际传输拍数 = AWLEN + 1
//     例：len=3 表示传输 4 拍数据
//   - AWSIZE（size）：每拍字节数 = 2^AWSIZE
//     例：size=2 表示每拍 4 字节
//   - AWBURST（burst）：突发类型
//     0=FIXED（地址不变），1=INCR（地址递增），2=WRAP（地址回卷）
//   - WSTRB：每拍的写选通，指示哪些字节有效
//==========================================================================
class axi_burst_wr_seq extends uvm_sequence #(axi_txn);
    // 工厂注册
    `uvm_object_utils(axi_burst_wr_seq)

    // s_addr：写事务的起始地址
    bit [15:0] s_addr;

    // s_id：AXI 事务 ID
    bit [7:0]  s_id;

    // s_len：突发长度（对应 AXI 协议的 AxLEN 字段）
    // 实际传输拍数 = s_len + 1
    // 例如 s_len=3 表示一次 burst 传输 4 拍数据
    bit [7:0]  s_len;

    function new(string name = "axi_burst_wr_seq");
        super.new(name);
    endfunction

    // body() task：产生 burst 写事务
    task body();
        axi_txn txn = axi_txn::type_id::create("txn");

        // 设置为写事务
        txn.kind = axi_txn::WRITE;

        // 填充地址和 ID
        txn.addr = s_addr; txn.id = s_id;

        // 设置 burst 参数
        // len = s_len：突发长度，由外部指定
        // size = 2：每拍 4 字节（32 位）
        txn.len = s_len; txn.size = 2;

        // 动态数组分配：大小为 s_len + 1（即传输拍数）
        // wdata[]：存放每一拍要写入的数据
        // wstrb[]：存放每一拍的写选通信号
        txn.wdata = new[s_len + 1]; txn.wstrb = new[s_len + 1];

        // 循环填充每一拍的数据和写选通
        // i 从 0 到 s_len，共 s_len+1 拍
        for (int i = 0; i <= s_len; i++) begin
            // 数据模式：0xA500_0000 + 拍序号
            // 这种模式便于在读回时验证数据正确性（检查递增模式）
            txn.wdata[i] = 32'hA500_0000 + i;
            // 每拍全部 4 字节有效（4'hF = 4'b1111）
            txn.wstrb[i] = 4'hF;
        end

        // 将整个 burst transaction 一次性发送给 driver
        // driver 内部会将其拆分为 AW 地址 + 多个 W 数据拍来驱动
        start_item(txn); finish_item(txn);
    endtask
endclass
