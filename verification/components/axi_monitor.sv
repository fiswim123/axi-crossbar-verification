//==========================================================================
// Monitor（监视器）
// UVM验证组件：axi_monitor
// 功能：监听AXI总线接口上的事务（transaction），将观测到的事务通过
//       analysis port广播给scoreboard和coverage等组件进行后续处理。
// 原理：monitor是纯粹的被动观测者，它不驱动任何信号，只在总线上
//       发生有效握手时采样信号值，组装成事务对象后发送出去。
// 继承自 uvm_monitor，这是UVM标准的监视器基类。
//==========================================================================
class axi_monitor extends uvm_monitor;
    // `uvm_component_utils 是UVM工厂注册宏
    // 注册后可以通过工厂机制创建对象，支持类型替换（override）等高级功能
    `uvm_component_utils(axi_monitor)

    // virtual interface：指向DUT的AXI接口的虚拟句柄
    // 通过uvm_config_db在仿真开始前从testbench顶层传入
    // monitor通过它来采样总线信号（如awvalid, awready, wdata等）
    virtual axi_if vif;

    // uvm_analysis_port：UVM的分析端口
    // 类型参数为axi_txn，表示该端口只能发送axi_txn类型的事务
    // analysis port是一种一对多的广播机制：一个port可以连接多个export
    // 当monitor调用ap.write(txn)时，所有连接到该port的组件都会收到事务
    uvm_analysis_port #(axi_txn) ap;

    // 构造函数
    // name: 组件实例名称（由父组件在create时指定）
    // parent: 父组件句柄（通常是env或test）
    // 所有UVM组件的构造函数都必须调用super.new()传递这两个参数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase：UVM构建阶段
    // 在仿真开始时由UVM自动调用，用于创建子组件和获取配置
    // phase参数是UVM phase机制的对象，一般不需要直接操作
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 创建analysis port实例，名称为"ap"，父组件为this（即本monitor）
        ap = new("ap", this);

        // 从uvm_config_db中获取virtual interface
        // uvm_config_db是UVM的全局配置数据库，用于组件间传递配置信息
        // 参数说明：#(virtual axi_if) - 要获取的数据类型
        //          this - 当前组件上下文
        //          "" - 字段名（空表示匹配所有）
        //          "vif" - 查找的key名称
        //          vif - 存储到的本地变量
        // 如果获取失败（顶层没有配置该vif），则用uvm_fatal终止仿真
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction

    // run_phase：UVM运行阶段
    // 这是monitor的主工作阶段，仿真开始后持续运行直到仿真结束
    // 使用fork...join同时启动写通道监视和读通道监视两个并行任务
    // AXI协议的读和写是独立的通道，所以需要并行监测
    task run_phase(uvm_phase phase);
        fork
            mon_wr();  // 监视写通道（AW + W + B）
            mon_rd();  // 监视读通道（AR + R）
        join
    endtask

    // mon_wr：写通道监视任务
    // AXI写事务由三个阶段组成：
    //   1. AW通道（地址写通道）：主机发送写地址和控制信息
    //   2. W通道（写数据通道）：主机发送写数据（可能多拍）
    //   3. B通道（写响应通道）：从机返回写响应
    // 每个通道都有valid/ready握手信号，当valid&&ready同时为高时数据传输有效
    task mon_wr();
        forever begin
            axi_txn txn;  // 声明一个事务对象变量

            // === 阶段1：等待AW通道握手 ===
            // @(posedge vif.aclk iff (...)) 的含义：
            // 在aclk的上升沿检查条件，如果条件不满足则继续等待下一个上升沿
            // iff（if and only if）使得只在条件为真时才触发，避免在无效时钟沿采样
            // awvalid=1表示主机发起写地址请求，awready=1表示从机准备好接收
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));

            // 通过UVM工厂创建axi_txn对象，名称为"wr_txn"
            // 工厂创建的好处是可以用factory override替换为子类
            txn = axi_txn::type_id::create("wr_txn");

            // 设置事务类型为写操作
            txn.kind = axi_txn::WRITE;

            // 从AW通道信号中采样地址和控制信息
            // awaddr: 写地址    awid: 写事务ID（用于乱序和交织）
            // awlen: 突发长度（实际拍数 = awlen + 1）  awsize: 每拍字节数（2^awsize）
            txn.addr = vif.awaddr; txn.id = vif.awid;
            txn.len = vif.awlen; txn.size = vif.awsize;

            // 根据突发长度分配写数据和写字节选通数组
            // new[len+1]：动态数组，len是突发长度，实际数据拍数为len+1
            txn.wdata = new[txn.len + 1]; txn.wstrb = new[txn.len + 1];

            // === 阶段2：等待W通道数据传输（多拍循环） ===
            // AXI突发传输：一次地址对应多拍数据，每拍都需要独立握手
            for (int i = 0; i <= txn.len; i++) begin
                // 等待W通道握手：wvalid=1表示主机发送数据，wready=1表示从机接收就绪
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));
                // 采样写数据和字节选通信号
                // wdata: 写数据（宽度由总线位宽决定）  wstrb: 字节选通（哪些字节有效）
                txn.wdata[i] = vif.wdata; txn.wstrb[i] = vif.wstrb;
            end

            // === 阶段3：等待B通道写响应 ===
            // 从机在接收完所有写数据后，通过B通道返回写响应
            // bvalid=1表示从机发起响应，bready=1表示主机准备好接收
            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            // 采样写响应信息
            // bid: 响应ID（与awid对应，用于标识是哪个事务的响应）
            // bresp: 写响应（2'b00=OKAY正常，其他值表示错误）
            txn.bid = vif.bid; txn.bresp = vif.bresp;

            // 通过analysis port将完整的写事务广播出去
            // scorecard和coverage组件会接收到这个事务进行校验和覆盖收集
            ap.write(txn);
        end
    endtask

    // mon_rd：读通道监视任务
    // AXI读事务由两个阶段组成：
    //   1. AR通道（地址读通道）：主机发送读地址和控制信息
    //   2. R通道（读数据通道）：从机返回读数据（可能多拍）
    // 注意：读操作没有单独的响应通道，响应信息(rresp)随每拍数据一起返回
    task mon_rd();
        forever begin
            axi_txn txn;  // 声明一个事务对象变量

            // === 阶段1：等待AR通道握手 ===
            // arvalid=1表示主机发起读地址请求，arready=1表示从机准备好接收
            @(posedge vif.aclk iff (vif.arvalid && vif.arready));

            // 通过工厂创建axi_txn对象，名称为"rd_txn"
            txn = axi_txn::type_id::create("rd_txn");

            // 设置事务类型为读操作
            txn.kind = axi_txn::READ;

            // 从AR通道信号中采样读地址和控制信息
            // araddr: 读地址    arid: 读事务ID
            // arlen: 突发长度   arsize: 每拍字节数
            txn.addr = vif.araddr; txn.id = vif.arid;
            txn.len = vif.arlen; txn.size = vif.arsize;

            // 根据突发长度分配读数据数组
            txn.rdata = new[txn.len + 1];

            // === 阶段2：等待R通道数据传输（多拍循环） ===
            // 从机返回读数据，每拍独立握手
            for (int i = 0; i <= txn.len; i++) begin
                // 等待R通道握手：rvalid=1表示从机发送数据，rready=1表示主机接收就绪
                @(posedge vif.aclk iff (vif.rvalid && vif.rready));
                // 采样读数据
                txn.rdata[i] = vif.rdata;
                // 采样读响应信息（每拍数据都带有rid和rresp）
                // rid: 响应ID    rresp: 读响应（2'b00=OKAY）
                // 注意：在最后一拍时这些值才是最终有效的
                txn.rid = vif.rid; txn.rresp = vif.rresp;
            end

            // 通过analysis port将完整的读事务广播出去
            ap.write(txn);
        end
    endtask
endclass
