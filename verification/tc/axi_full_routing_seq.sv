// One read or write on a selected path.  The test iterates the full 4x4
// matrix; IDs are 0x10/0x20/0x30/0x40 for masters 0/1/2/3 respectively.
class axi_full_routing_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_full_routing_seq)

    // s_id carries the configured master prefix, not the 0..3 port number.
    bit [7:0]  s_id;

    // s_addr: 目标地址，决定路由到哪个Slave
    // 在test层设置：SLV0=0x0000, SLV1=0x1000, SLV2=0x2000, SLV3=0x3000
    bit [15:0] s_addr;
    axi_txn::kind_e s_kind = axi_txn::WRITE;
    bit [31:0] s_data = 32'hC0DE_0000;

    // 构造函数
    function new(string name = "axi_full_routing_seq");
        super.new(name);
    endfunction

    // One item per invocation; test selects READ or WRITE.
    task body();
        // 创建一个AXI事务对象
        // 注意：这里直接用create创建了一个txn，而不是声明后再create
        axi_txn txn = axi_txn::type_id::create("txn");

        // The full-routing test sends both kinds on every path.
        txn.kind  = s_kind;

        // 设置路由地址(由test层配置)
        // Crossbar会根据此地址决定发往哪个Slave
        txn.addr  = s_addr;

        // 设置事务ID(由test层配置)
        txn.id    = s_id;

        // 单拍传输参数
        // len=0:  1拍(最简单的传输形式)
        // size=2: 4字节(32位)
        // burst=1: INCR模式
        txn.len   = 0;
        txn.size  = 2;
        txn.burst = 2'b01;

        // Allocate W fields even for READ; the read driver ignores them.
        txn.wdata = new[1];
        txn.wstrb = new[1];

        // Unique value per path helps waveform debug and data comparison.
        txn.wdata[0] = s_data;
        txn.wstrb[0] = 4'hF; // 所有字节有效

        // 发送事务并等待完成
        // The scoreboard checks both master/slave observations at check_phase.
        start_item(txn);
        finish_item(txn);

    endtask
endclass
