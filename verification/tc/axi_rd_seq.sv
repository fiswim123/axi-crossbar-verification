//==========================================================================
// Read Sequence — 单次读事务序列
// 功能说明：
//   本序列用于发起一笔 AXI 单次读事务（Single Read Transaction）。
//   即 AR 通道发送一次地址信息，R 通道等待一次读数据返回。
//   适用于基本读功能验证（T001 级别测试场景）。
//
// UVM 概念说明：
//   与写序列类似，sequence 继承自 uvm_sequence 并参数化为 axi_txn 类型。
//   参数化（#(axi_txn)）指定了该 sequence 产生的 transaction 类型，
//   同时将该类型绑定到 sequencer（sequencer 也需参数化为同一类型）。
//==========================================================================
class axi_rd_seq extends uvm_sequence #(axi_txn);
    // `uvm_object_utils：UVM 工厂注册宏
    // sequence 是 object（不是 component），所以使用 uvm_object_utils 而非 uvm_component_utils
    `uvm_object_utils(axi_rd_seq)

    // s_addr：读事务的目标地址，16 位宽
    // 对应 AXI 读地址通道（AR Channel）的 ARADDR
    bit [15:0] s_addr;

    // s_id：AXI 读事务的 ID 标识，8 位宽
    // 对应 ARID，用于标识该读事务的身份
    // 在 AXI 协议中，相同 ID 的读事务必须按序返回；不同 ID 可以乱序返回
    bit [7:0]  s_id;

    // 构造函数
    function new(string name = "axi_rd_seq");
        super.new(name); // 调用父类构造函数，完成 UVM 层次命名初始化
    endfunction

    // body() task：sequence 的主体入口
    // 读序列与写序列的主要区别：
    //   1. kind 设为 READ 而非 WRITE
    //   2. 不需要填充 wdata 和 wstrb（读操作没有写数据通道）
    //   3. 需要分配 rdata 数组来接收读回的数据
    task body();
        // 创建 transaction 对象（通过工厂创建）
        axi_txn txn = axi_txn::type_id::create("txn");

        // 设置事务类型为 READ
        // 驱动器（driver）根据 kind 字段判断是读还是写，从而决定操作哪个 AXI 通道
        txn.kind = axi_txn::READ;

        // 填充地址和 ID
        txn.addr = s_addr; txn.id = s_id;

        // AXI 协议参数：
        // len=0：突发长度为 1（单次传输，不 burst）
        // size=2：每拍传输 4 字节（32 位），即 2^2 = 4
        txn.len = 0; txn.size = 2;

        // rdata：读数据数组，动态数组
        // 分配大小为 1，表示接收 1 拍读数据
        // driver 在收到 R 通道的数据后，会填入该数组
        // sequence 本身不填充 rdata，而是由 driver 负责填入实际读到的值
        txn.rdata = new[1];

        // 发送 transaction：start_item 请求发送权，finish_item 等待 driver 完成
        // 对于读操作，finish_item 会阻塞直到 driver 完成整个读事务
        // （包括发送 AR 地址和接收 R 数据）
        start_item(txn); finish_item(txn);
    endtask
endclass
