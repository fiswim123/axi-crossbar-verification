//==========================================================================
// Master Driver - 主设备驱动器
//==========================================================================
// 【文件功能说明】
// 本文件实现了 AXI Master Driver，负责将 sequence_item (抽象事务)
// 转换为实际的 AXI 总线信号，驱动到 DUT 的 Master 端口。
//
// 【UVM 架构知识点】
// uvm_driver 是 UVM 验证平台的核心组件之一，负责：
//   1. 从 sequencer 获取 sequence_item (通过 seq_item_port)
//   2. 将抽象的事务转换为时序精确的信号级激励
//   3. 通过虚拟接口(virtual interface)驱动信号到 DUT
//
// 数据流：Sequence 产生 transaction -> Sequencer 调度 -> Driver 驱动到 DUT
//
// 【AXI 协议知识点 - 握手机制】
// AXI 所有通道都使用 valid/ready 握手协议：
//   - 发送方拉高 valid 表示数据有效
//   - 接收方拉高 ready 表示已准备好接收
//   - 当 valid && ready 同时为高时，数据传输完成(在时钟上升沿)
//   - valid 不能等待 ready 拉高后才拉高 (防止死锁)
//
// 【AXI 协议知识点 - 写操作流程】
//   1. AW通道：Master 发送写地址信息 (地址、长度、大小等)
//   2. W通道： Master 发送写数据 (可以和AW同时或之后)
//   3. B通道： Slave 返回写响应 (OKAY/SLVERR/DECERR)
//
// 【AXI 协议知识点 - 读操作流程】
//   1. AR通道：Master 发送读地址信息
//   2. R通道： Slave 返回读数据和响应
//==========================================================================
class axi_mst_drv extends uvm_driver #(axi_txn);
    // 【参数化说明】uvm_driver#(axi_txn) 表示此 driver 只处理 axi_txn 类型的事务。
    // #(axi_txn) 是 SystemVerilog 的参数化类语法，使得 seq_item_port
    // 自动类型化为处理 axi_txn 的端口。

    // 【工厂注册】将 axi_mst_drv 注册到 UVM 工厂
    `uvm_component_utils(axi_mst_drv)
    // uvm_component_utils 用于注册 uvm_component 类型 (有固定层次位置的组件)
    // 与 uvm_object_utils 不同，component 需要 parent 参数来构建层次结构

    // 【虚拟接口】指向 DUT 的 AXI 接口
    // virtual interface 是 SystemVerilog 中访问物理接口的句柄。
    // 通过 config_db 机制从 test/testbench 传递到 driver 中。
    virtual axi_if vif;

    // ================================================================
    // 【构造函数】
    // ================================================================
    // uvm_component 的构造函数需要两个参数：
    //   name   - 组件名称 (用于在层次结构中标识)
    //   parent - 父组件 (用于构建 UVM 组件树)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // ================================================================
    // 【build_phase - 构建阶段】
    // ================================================================
    // build_phase 是 UVM 生命周期的第一个 phase，用于：
    //   1. 获取配置参数 (通过 config_db)
    //   2. 创建子组件
    //   3. 初始化变量
    //
    // uvm_config_db 是 UVM 的配置数据库机制，允许在 test 层设置参数，
    // 在 driver 等组件中获取这些参数，实现参数的层次化传递。
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 从 config_db 获取虚拟接口
        // get() 方法参数：(this, "", "vif", vif)
        //   this     - 当前组件
        //   ""       - 使用相对路径 (空表示从当前位置查找)
        //   "vif"    - 字段名
        //   vif      - 存储获取结果的变量
        // 如果获取失败 (vif 未在 config_db 中设置)，则使用 `uvm_fatal 报告致命错误并终止仿真
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction

    // ================================================================
    // 【run_phase - 运行阶段】
    // ================================================================
    // run_phase 是 UVM 的主运行阶段，driver 在此阶段持续从 sequencer 获取事务并驱动。
    // run_phase 是所有 phase 中唯一一个消耗仿真时间的 task-based phase。
    //
    // 工作流程：
    //   1. 初始化所有输出信号为无效状态
    //   2. 进入 forever 循环，不断获取事务
    //   3. 根据事务类型调用对应的驱动任务
    //   4. 通知 sequencer 当前事务已完成
    task run_phase(uvm_phase phase);
        // 【信号初始化】将所有 AXI Master 端口信号初始化为无效/默认状态
        // 使用 <= 非阻塞赋值，确保在时钟边沿同步更新
        vif.awvalid <= 0; vif.wvalid <= 0;     // 地址和数据通道 valid 无效
        vif.bready  <= 0; vif.arvalid <= 0; vif.rready <= 0;  // 响应和读通道
        // AXI 附加信号初始化 (本设计中不使用这些信号，设为默认值)
        vif.awlock <= 0; vif.awcache <= 0; vif.awprot <= 0;   // 写地址保护/缓存信号
        vif.awqos  <= 0; vif.awregion <= 0;                    // QoS 和 region 信号
        vif.arlock <= 0; vif.arcache <= 0; vif.arprot <= 0;   // 读地址保护/缓存信号
        vif.arqos  <= 0; vif.arregion <= 0;                    // QoS 和 region 信号

        // 【主循环】持续获取并驱动事务
        forever begin
            axi_txn txn;                         // 声明事务句柄
            seq_item_port.get_next_item(txn);     // 从 sequencer 获取下一个事务
                                                // get_next_item() 会阻塞直到有新事务
            if (txn.kind == axi_txn::WRITE)       // 判断事务类型
                drive_wr(txn);                    // 驱动写操作
            else
                drive_rd(txn);                    // 驱动读操作
            seq_item_port.item_done();            // 通知 sequencer 当前事务完成
                                                // item_done() 后 driver 才能获取下一个事务
        end
    endtask

    // ================================================================
    // 【task】drive_wr - 驱动写操作
    // ================================================================
    // 按照 AXI 写操作协议，依次完成：
    //   阶段1: AW通道 - 发送写地址
    //   阶段2: W通道  - 发送写数据 (多拍)
    //   阶段3: B通道  - 接收写响应
    task drive_wr(axi_txn txn);
        // ---- 阶段1: AW通道 (写地址通道) ----
        @(posedge vif.aclk);  // 等待时钟上升沿，确保时序同步
        // 驱动写地址通道信号
        vif.awvalid <= 1;                  // 拉高 valid，表示地址信息有效
        vif.awaddr <= txn.addr;            // 写地址
        vif.awlen <= txn.len;              // 突发长度 (len+1 拍)
        vif.awsize <= txn.size;            // 每拍字节数 (2^size)
        vif.awburst <= txn.burst;          // 突发类型 (INCR/WRAP/FIXED)
        vif.awid <= txn.id;                // 事务ID
        // 以下信号在本设计中固定为默认值
        vif.awlock <= 0;                   // 锁定类型 (不使用)
        vif.awcache <= 0;                  // 缓存属性 (不使用)
        vif.awprot <= 3'b010;              // 保护属性：非安全、非特权、数据访问

        // 【握手等待】等待 slave 拉高 awready
        // 这是一个标准的 valid-ready 握手等待模式：
        // 在每个时钟上升沿检查 awready，直到握手完成
        do @(posedge vif.aclk); while (!vif.awready);
        vif.awvalid <= 0;  // 握手完成，拉低 valid

        // ---- 阶段2: W通道 (写数据通道) ----
        // 发送 len+1 拍写数据
        for (int i = 0; i <= txn.len; i++) begin
            vif.wvalid <= 1;                   // 拉高 wvalid，表示数据有效
            vif.wdata <= txn.wdata[i];         // 当前拍的写数据
            vif.wstrb <= txn.wstrb[i];         // 当前拍的写选通
            vif.wlast <= (i == txn.len);       // 最后一拍时拉高 wlast
            // 等待 slave 拉高 wready (握手等待)
            do @(posedge vif.aclk); while (!vif.wready);
        end
        vif.wvalid <= 0; vif.wlast <= 0;       // 所有数据发完，清除信号

        // ---- 阶段3: B通道 (写响应通道) ----
        vif.bready <= 1;                       // Master 准备好接收响应
        // 等待 slave 拉高 bvalid (表示响应数据有效)
        do @(posedge vif.aclk); while (!vif.bvalid);
        // 采样响应信息，存回 transaction 对象
        txn.bid = vif.bid;                     // 响应ID (应与请求ID匹配)
        txn.bresp = vif.bresp;                 // 响应码 (OKAY/SLVERR/DECERR)
        vif.bready <= 0;                       // 握手完成，拉低 bready
    endtask

    // ================================================================
    // 【task】drive_rd - 驱动读操作
    // ================================================================
    // 按照 AXI 读操作协议，依次完成：
    //   阶段1: AR通道 - 发送读地址
    //   阶段2: R通道  - 接收读数据 (多拍)
    task drive_rd(axi_txn txn);
        vif.rready <= 1;                       // 提前拉高 rready，准备接收数据
        @(posedge vif.aclk);                   // 等待时钟上升沿

        // ---- 阶段1: AR通道 (读地址通道) ----
        vif.arvalid <= 1;                  // 拉高 valid，表示地址信息有效
        vif.araddr <= txn.addr;            // 读地址
        vif.arlen <= txn.len;              // 突发长度
        vif.arsize <= txn.size;            // 每拍字节数
        vif.arburst <= txn.burst;          // 突发类型
        vif.arid <= txn.id;                // 事务ID
        // 以下信号固定为默认值
        vif.arlock <= 0;                   // 锁定类型
        vif.arcache <= 0;                  // 缓存属性
        vif.arprot <= 3'b010;              // 保护属性

        // 【握手等待】等待 slave 拉高 arready
        do @(posedge vif.aclk); while (!vif.arready);
        vif.arvalid <= 0;  // 握手完成，拉低 valid

        // ---- 阶段2: R通道 (读数据通道) ----
        // 接收 len+1 拍读数据
        txn.rdata = new[txn.len + 1];      // 动态分配 rdata 数组大小
        for (int i = 0; i <= txn.len; i++) begin
            @(posedge vif.aclk);                   // 等待时钟上升沿
            while (!vif.rvalid) @(posedge vif.aclk); // 等待 slave 拉高 rvalid
            txn.rdata[i] = vif.rdata;              // 采样读数据
            txn.rid = vif.rid;                     // 采样响应ID
            txn.rresp = vif.rresp;                 // 采样响应码
        end
        vif.rready <= 0;                           // 所有数据收完，拉低 rready
    endtask
endclass
