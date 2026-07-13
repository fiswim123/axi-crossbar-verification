//==========================================================================
// Outstanding Read Sequence (T031)
// 功能说明：Outstanding（未完成）读事务测试序列
//
// 测试目的：
//   验证AXI Crossbar在多个读请求连续发出、尚未收到响应时的行为。
//   在AXI协议中，"outstanding"是指主设备(Master)在收到前一个事务的响应之前，
//   就发出下一个事务的能力。这是AXI流水线机制的核心特性，可以显著提高总线吞吐量。
//
// 测试场景：
//   连续发送4个读请求（不等待前一个完成），观察crossbar能否正确处理：
//   - 读地址通道(AR Channel)的流水线请求
//   - 读数据通道(R Channel)的响应顺序
//   - 是否出现数据丢失或死锁
//
// AXI协议知识点：
//   - Outstanding机制允许Master同时有多个未完成的事务在总线上传输
//   - 通过ID来区分不同的事务，相同ID的事务必须保序(Ordering)
//   - 不同ID的事务可以乱序返回，提高效率
//==========================================================================

// 类定义：继承自uvm_sequence，参数化类型为axi_txn（AXI事务对象）
// uvm_sequence是UVM中产生激励(Stimulus)的核心组件
// 通过sequencer(序列器)将事务发送给driver(驱动器)
class axi_outstanding_read_seq extends uvm_sequence #(axi_txn);

    // `uvm_object_utils：UVM工厂注册宏
    // 将该类注册到UVM工厂中，使得可以通过工厂机制创建对象
    // 这是UVM实现可替换性和可配置性的基础
    `uvm_object_utils(axi_outstanding_read_seq)

    // s_addr：起始地址（16位）
    // 用于指定读操作的基地址，后续读请求的地址 = s_addr + i * 4
    // 由test或testbench在启动sequence前设置
    bit [15:0] s_addr;

    // s_id：事务ID（8位）
    // AXI协议中的Transaction ID，用于标识事务
    // 相同ID的事务必须保序返回，不同ID可以乱序
    // 在crossbar测试中，ID也用于路由决策
    bit [7:0]  s_id;

    // 构造函数
    // name：sequence的实例名称，用于UVM层次化路径标识和日志输出
    function new(string name = "axi_outstanding_read_seq");
        super.new(name);  // 调用父类构造函数，UVM要求必须调用super.new
    endfunction

    // body()任务：sequence的主体，是UVM sequence的核心方法
    // 当sequence被启动(start)时，UVM会自动调用body()任务
    // 所有激励生成的逻辑都写在body()中
    task body();
        axi_txn txn;  // 声明一个AXI事务句柄(句柄=指针)

        // 循环4次，连续发送4个读请求
        // 不等待前一个事务完成就发送下一个，模拟outstanding场景
        for (int i = 0; i < 4; i++) begin

            // axi_txn::type_id::create()：通过UVM工厂创建事务对象
            // $sformatf("rd_%0d", i)：生成唯一名称如"rd_0", "rd_1"等
            // 工厂创建的好处是支持类型重载(override)，便于扩展测试
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));

            // 设置事务类型为READ（读操作）
            txn.kind = axi_txn::READ;

            // 设置读地址：基地址 + 偏移量（每次偏移4字节，即一个32位字）
            // 例如：s_addr=0x100, 则地址为 0x100, 0x104, 0x108, 0x10C
            txn.addr = s_addr + i * 4;

            // 设置事务ID：所有事务使用相同ID，确保按序返回
            txn.id = s_id;

            // AXI读事务参数设置：
            // len = 0 表示突发长度(Burst Length)为1，即只读1个beat（AXI协议中len=0对应1拍）
            // size = 2 表示每个beat传输2^2 = 4字节（32位数据宽度）
            // burst = 1 表示突发类型为INCR（递增地址突发）
            //   AXI支持三种突发类型：FIXED(0), INCR(1), WRAP(2)
            //   INCR类型下，每次beat地址递增size指定的字节数
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区：1个元素，用于存储读返回的数据
            txn.rdata = new[1];

            // start_item() + finish_item()：UVM sequence发送事务的标准流程
            // start_item(txn)：通知sequencer准备发送，等待grant（授权）
            // finish_item(txn)：将事务发送给driver，并等待driver调用item_done()
            // 这两个任务配合实现了sequence与sequencer/driver之间的握手机制
            start_item(txn); finish_item(txn);
        end
        // 循环结束后，4个读请求已经全部发出
        // driver会按顺序将它们驱动到AXI总线上
        // 由于是连续发出，前一个的响应还未回来时下一个已经发出，形成outstanding
    endtask
endclass
