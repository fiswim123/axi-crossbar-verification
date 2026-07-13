//==========================================================================
// Burst Read Sequence — 突发读事务序列
// 功能说明：
//   本序列用于发起 AXI 突发读事务（Burst Read Transaction）。
//   AR 通道发送一次地址（含 burst 长度），R 通道连续接收 len+1 拍数据。
//   适用于验证 crossbar 在 burst 读场景下的数据完整性和返回顺序。
//
// AXI Burst 读协议要点：
//   - AR Channel（读地址通道）：发送 ARADDR、ARID、ARLEN、ARSIZE、ARBURST
//   - R Channel（读数据通道）：返回 RDATA、RID、RRESP、RLAST
//   - 每拍返回一个数据，最后一拍 RLAST=1
//   - 在 crossbar 中，burst 读可能涉及多次路由决策和数据对齐
//==========================================================================
class axi_burst_rd_seq extends uvm_sequence #(axi_txn);
    // 工厂注册
    `uvm_object_utils(axi_burst_rd_seq)

    // s_addr：读事务的起始地址
    bit [15:0] s_addr;

    // s_id：AXI 事务 ID
    bit [7:0]  s_id;

    // s_len：突发长度（对应 ARLEN）
    // 实际接收拍数 = s_len + 1
    bit [7:0]  s_len;

    function new(string name = "axi_burst_rd_seq");
        super.new(name);
    endfunction

    // body() task：产生 burst 读事务
    task body();
        axi_txn txn = axi_txn::type_id::create("txn");

        // 设置为读事务
        txn.kind = axi_txn::READ;

        // 填充地址和 ID
        txn.addr = s_addr; txn.id = s_id;

        // 设置 burst 参数
        // len = s_len：突发长度，由外部指定
        // size = 2：每拍 4 字节（32 位）
        txn.len = s_len; txn.size = 2;

        // 分配读数据数组：大小为 s_len + 1
        // rdata[] 由 driver 在接收到 R 通道数据后填充
        // sequence 只需分配空间，不预填数据
        txn.rdata = new[s_len + 1];

        // 发送 transaction
        // 对于 burst 读，finish_item 会阻塞直到 driver 完成整个 burst 读
        // （发送 AR 地址 + 接收全部 R 数据拍）
        start_item(txn); finish_item(txn);
    endtask
endclass
