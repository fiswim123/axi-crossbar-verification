//==========================================================================
// Write Sequence — 单次写事务序列
// 功能说明：
//   本序列用于发起一笔 AXI 单次写事务（Single Write Transaction）。
//   即 AW 通道发送一次地址信息，W 通道发送一次数据，B 通道等待一次写响应。
//   适用于基本写功能验证（T001 级别测试场景）。
//
// UVM 概念说明：
//   uvm_sequence 是 UVM 中产生激励（transaction）的核心机制。
//   sequence 不是 component，而是 object，它通过 body() task 产生一个或多个 transaction，
//   并通过 sequencer 发送给 driver 执行。
//==========================================================================
class axi_wr_seq extends uvm_sequence #(axi_txn);
    // `uvm_object_utils：UVM 工厂注册宏
    // 将该类注册到 UVM 工厂中，使得可以通过工厂方式创建实例，
    // 支持 type_override 等高级特性（如用子类替换父类）。
    `uvm_object_utils(axi_wr_seq)

    // s_addr：写事务的目标地址，16 位宽
    // 在 test 或 virtual sequence 中调用该 sequence 前，通过 s_addr = xxx 赋值
    bit [15:0] s_addr;

    // s_data：要写入的数据，32 位宽
    // AXI 协议中 WDATA 的内容，一次写一笔数据
    bit [31:0] s_data;

    // s_id：AXI 写事务的 ID 标识，8 位宽
    // 对应 AWID，用于乱序（out-of-order）和交织（interleaving）场景下的事务匹配
    bit [7:0]  s_id;

    // 构造函数：创建 sequence 对象时调用
    // 参数 name 用于 UVM 的层次化命名，便于 debug 和日志追踪
    function new(string name = "axi_wr_seq");
        super.new(name); // 调用父类 uvm_sequence 的构造函数
    endfunction

    // body() task：sequence 的主体，是 UVM sequence 的核心入口
    // 当 sequence 被 start() 启动后，UVM 框架会自动调用 body()
    // body() 内部负责创建 transaction 并发送给 sequencer
    task body();
        // --- 第 1 步：创建 transaction 对象 ---
        // 使用 UVM 工厂的 type_id::create 方法创建 axi_txn 实例
        // 工厂创建的好处是支持 type_override，便于在不修改代码的情况下替换类型
        axi_txn txn = axi_txn::type_id::create("txn");

        // --- 第 2 步：填充 transaction 的各个字段 ---
        // kind：事务类型，这里设置为 WRITE（写操作）
        txn.kind = axi_txn::WRITE;

        // addr：AXI 写地址通道（AW Channel）的地址
        // id：   AXI 写地址通道的事务 ID（AWID）
        txn.addr = s_addr; txn.id = s_id;

        // AXI 协议关键参数说明：
        // len（AxLEN）：突发长度 = AxLEN + 1，即实际传输拍数
        //   len=0 表示只传 1 拍（Single Transfer），不进行 burst
        // size（AxSIZE）：每拍传输的字节数 = 2^size
        //   size=2 表示 2^2 = 4 字节 = 32 位，与 32 位数据宽度匹配
        txn.len = 0; txn.size = 2;

        // wdata：写数据数组，动态数组
        // 因为 len=0，只有 1 拍数据，所以数组大小为 1
        // wstrb：写选通信号（Write Strobe），指示数据中哪些字节有效
        //   4'hF = 4'b1111，表示 4 个字节全部有效（32 位全部写入）
        txn.wdata = new[1]; txn.wstrb = new[1];
        txn.wdata[0] = s_data; txn.wstrb[0] = 4'hF;

        // --- 第 3 步：将 transaction 发送给 sequencer ---
        // start_item(txn)：向 sequencer 请求发送许可（仲裁机制）
        //   如果 sequencer 正忙或被 lock/grab，此调用会阻塞等待
        // finish_item(txn)：将 transaction 发送给 driver，并等待 driver 的 item_done 响应
        //   即 finish_item 会阻塞直到 driver 完成该 transaction 的驱动
        // 通常 start_item 和 finish_item 配对使用
        start_item(txn); finish_item(txn);
    endtask
endclass
