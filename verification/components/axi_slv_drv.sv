//==========================================================================
// Slave Driver - 从设备驱动器 (Memory Model with Error Injection & Backpressure)
//==========================================================================
// 【文件功能说明】
// 本文件实现了 AXI Slave Driver，它充当 DUT 的从设备，模拟一个存储器模型。
// 与 Master Driver 不同，Slave Driver 不从 sequencer 获取事务，而是被动地
// 响应 DUT 发出的请求。
//
// Slave Driver 的主要功能：
//   1. 接收 DUT 的写请求，将数据写入内部存储器模型
//   2. 响应 DUT 的读请求，从内部存储器模型读取数据返回
//   3. 支持错误注入：按概率返回错误响应 (SLVERR/DECERR)
//   4. 支持背压：按概率拉低 ready 信号，模拟从设备繁忙
//   5. 支持延迟：在响应前插入可配置的延迟
//
// 【验证方法学知识点】
// Slave Driver 使用存储器模型 (memory model) 来保存写入的数据，
// 这样在读操作时可以返回之前写入的值，实现自检查(self-checking)。
// Scoreboard 可以通过访问同一个存储器来验证 DUT 读出的数据是否正确。
//
// 【UVM 架构知识点】
// 与 Master Driver 通过 sequencer 获取事务不同，Slave Driver 是被动响应型：
// - Master Driver: 主动从 sequencer 获取事务并驱动
// - Slave Driver:  被动监听 DUT 的请求并响应
// 因此 Slave Driver 不需要 sequencer 连接，也不需要 sequence。
//
// 【AXI 协议知识点 - 并行通道处理】
// AXI 的写操作和读操作是独立的，可以并行进行。
// 因此 Slave Driver 使用 fork...join 来同时处理写和读请求。
// wr_handler() 和 rd_handler() 是两个并行运行的无限循环任务。
//==========================================================================
class axi_slv_drv extends uvm_driver #(axi_txn);
    // 【工厂注册】注册到 UVM 工厂
    `uvm_component_utils(axi_slv_drv)

    // 【虚拟接口】指向 DUT 的 AXI 接口
    virtual axi_if vif;

    // 【存储器模型】使用关联数组(associative array)模拟从设备存储器
    // bit [7:0] mem[bit [31:0]] 表示：
    //   - 索引类型: bit [31:0] (32位地址)
    //   - 元素类型: bit [7:0]  (8位数据，即1字节)
    // 关联数组的优势：不需要预先分配存储空间，只在实际访问时创建条目
    // 每次写操作写入4字节 (32位数据拆分为4个字节)
    bit [7:0] mem[bit [31:0]];

    // 【配置对象】从 config_db 获取的 slave 配置，控制错误注入和背压行为
    axi_slv_cfg cfg;

    // ================================================================
    // 【构造函数】
    // ================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // ================================================================
    // 【build_phase - 构建阶段】
    // ================================================================
    // 在 build_phase 中获取虚拟接口和配置对象。
    // 如果没有配置对象，则使用工厂创建一个默认配置 (所有参数为0，即正常行为)。
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 获取虚拟接口 (与 master driver 相同的方式)
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
        // 获取配置对象，如果未配置则创建默认配置
        // uvm_config_db#(axi_slv_cfg)::get 尝试从配置数据库获取
        // 如果失败，使用工厂方法 type_id::create 创建默认实例
        if (!uvm_config_db#(axi_slv_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = axi_slv_cfg::type_id::create("cfg");
            // type_id::create 是 UVM 工厂的标准创建方式
            // 相比直接 new，它允许通过工厂重载来替换类型
        end
    endfunction

    // ================================================================
    // 【run_phase - 运行阶段】
    // ================================================================
    // 初始化所有输出信号，然后并行启动写处理和读处理任务。
    task run_phase(uvm_phase phase);
        // 【信号初始化】将所有 Slave 端口信号初始化为无效状态
        vif.awready <= 0; vif.wready <= 0;          // 地址和数据通道 ready 无效
        vif.bvalid <= 0; vif.bid <= 0; vif.bresp <= 0;  // 写响应通道无效
        vif.arready <= 0; vif.rvalid <= 0;           // 读地址和读数据通道无效
        vif.rid <= 0; vif.rresp <= 0; vif.rdata <= 0; vif.rlast <= 0;  // 读响应信号

        // 【并行处理】使用 fork...join 同时启动写和读处理
        // fork...join 会等待所有并行线程都完成后才继续
        // 由于 wr_handler 和 rd_handler 都是 forever 循环，它们永远不会结束
        // 所以 run_phase 会一直运行到仿真结束
        fork
            wr_handler();   // 写处理任务 (处理 AW + W + B 通道)
            rd_handler();   // 读处理任务 (处理 AR + R 通道)
        join
    endtask

    // ================================================================
    // 【task】wr_handler - 写操作处理任务
    // ================================================================
    // 处理 AXI 写操作的全部三个阶段：
    //   1. AW通道：接收写地址 (支持背压)
    //   2. W通道：接收写数据并写入存储器 (支持背压)
    //   3. B通道：发送写响应 (支持错误注入和延迟)
    task wr_handler();
        // 【局部变量】用于保存当前写事务的信息
        bit [7:0]  awid;                     // 写地址ID
        bit [31:0] awaddr, wr_addr;          // 写起始地址 / 当前写地址 (递增)
        bit [7:0]  awlen;                    // 突发长度
        bit        inject_err;               // 是否注入错误标志

        forever begin  // 无限循环，持续处理写请求

            // ---- 阶段1: AW通道 (接收写地址) ----
            vif.awready <= 0;                // 初始状态：未准备好
            @(posedge vif.aclk);             // 等待时钟上升沿

            // 【握手循环】等待写地址握手完成 (awvalid && awready 同时为高)
            while (!(vif.awvalid && vif.awready)) begin
                // 根据配置决定是否施加背压 (拉低 awready)
                // should_bp(0) 表示检查 AW 通道的背压概率
                // !cfg.should_bp(0) 表示：如果应该背压则返回 false (ready=0)
                vif.awready <= !cfg.should_bp(0);
                @(posedge vif.aclk);
            end

            // 【采样地址信息】在握手完成的时钟沿采样地址通道信号
            awid = vif.awid;                 // 采样写ID
            awaddr = vif.awaddr;             // 采样写起始地址
            awlen = vif.awlen;               // 采样突发长度
            wr_addr = awaddr;                // 初始化当前写地址
            inject_err = cfg.should_error(); // 根据概率决定是否注入错误
            vif.awready <= 0;                // 拉低 ready，表示地址接收完成

            // ---- 阶段2: W通道 (接收写数据) ----
            // 接收 awlen+1 拍写数据
            for (int i = 0; i < awlen + 1; i++) begin
                vif.wready <= !cfg.should_bp(1);  // 根据配置决定是否背压 W 通道
                @(posedge vif.aclk);

                // 【握手循环】等待写数据握手完成
                while (!(vif.wvalid && vif.wready)) begin
                    vif.wready <= !cfg.should_bp(1);  // 每拍都可能有不同的背压
                    @(posedge vif.aclk);
                end

                // 【存储器写入】如果未注入错误，则将数据写入存储器模型
                // 32位数据拆分为4个字节，按小端序写入
                if (!inject_err) begin
                    mem[wr_addr]     = vif.wdata[7:0];    // 字节0 (最低字节)
                    mem[wr_addr + 1] = vif.wdata[15:8];   // 字节1
                    mem[wr_addr + 2] = vif.wdata[23:16];  // 字节2
                    mem[wr_addr + 3] = vif.wdata[31:24];  // 字节3 (最高字节)
                end
                // 如果注入错误，数据不写入存储器，模拟写操作失败
                wr_addr += 4;  // 地址递增4字节 (每个数据拍4字节)
            end
            vif.wready <= 0;  // 所有数据收完，拉低 ready

            // ---- 阶段2.5: 可选延迟 ----
            // 在发送响应前插入配置的延迟，模拟从设备处理时间
            repeat(cfg.get_delay()) @(posedge vif.aclk);

            // ---- 阶段3: B通道 (发送写响应) ----
            vif.bid <= awid;                 // 响应ID = 请求ID (必须匹配)
            // 根据是否注入错误选择响应码
            // 正常: 2'b00 = OKAY
            // 错误: cfg.err_resp (SLVERR=2'b10 或 DECERR=2'b11)
            vif.bresp <= inject_err ? cfg.err_resp : 2'b00;
            vif.bvalid <= 1;                 // 拉高 bvalid，表示响应有效
            @(posedge vif.aclk);
            // 【握手等待】等待 master 拉高 bready
            while (!vif.bready) @(posedge vif.aclk);
            vif.bvalid <= 0;                 // 握手完成，拉低 bvalid
        end
    endtask

    // ================================================================
    // 【task】rd_handler - 读操作处理任务
    // ================================================================
    // 处理 AXI 读操作的全部两个阶段：
    //   1. AR通道：接收读地址 (支持背压)
    //   2. R通道：发送读数据 (支持错误注入、延迟)
    task rd_handler();
        // 【局部变量】用于保存当前读事务的信息
        bit [7:0]  arid;                     // 读地址ID
        bit [31:0] araddr;                   // 读起始地址
        int        blen;                     // 突发长度 (实际拍数 = arlen + 1)
        bit        inject_err;               // 是否注入错误标志

        forever begin  // 无限循环，持续处理读请求

            // ---- 阶段1: AR通道 (接收读地址) ----
            vif.arready <= 0;                // 初始状态：未准备好
            @(posedge vif.aclk);             // 等待时钟上升沿

            // 【握手循环】等待读地址握手完成 (arvalid && arready 同时为高)
            while (!(vif.arvalid && vif.arready)) begin
                // 根据配置决定是否施加背压 (拉低 arready)
                // should_bp(2) 表示检查 AR 通道的背压概率
                vif.arready <= !cfg.should_bp(2);
                @(posedge vif.aclk);
            end

            // 【采样地址信息】在握手完成的时钟沿采样地址通道信号
            arid = vif.arid;                 // 采样读ID
            araddr = vif.araddr;             // 采样读起始地址
            blen = vif.arlen + 1;            // 计算实际突发拍数
            inject_err = cfg.should_error(); // 根据概率决定是否注入错误
            vif.arready <= 0;                // 拉低 ready，表示地址接收完成

            // ---- 阶段1.5: 可选延迟 ----
            // 在发送数据前插入配置的延迟，模拟从设备读取时间
            repeat(cfg.get_delay()) @(posedge vif.aclk);

            // ---- 阶段2: R通道 (发送读数据) ----
            // 发送 blen 拍读数据
            for (int i = 0; i < blen; i++) begin
                vif.rid <= arid;             // 响应ID = 请求ID

                // 【数据选择】根据是否注入错误选择数据来源
                // 正常: 从存储器模型读取数据 (小端序拼接)
                // 错误: 返回 0xDEAD_BEEF (一个明显的错误标记值)
                vif.rdata <= inject_err ? 32'hDEAD_BEEF :
                             {mem[araddr+3], mem[araddr+2],
                              mem[araddr+1], mem[araddr]};
                // 拼接方式：{字节3, 字节2, 字节1, 字节0} = 32位数据

                // 响应码选择
                vif.rresp <= inject_err ? cfg.err_resp : 2'b00;
                // rlast 在最后一拍时拉高，表示突发传输结束
                vif.rlast <= (i == blen - 1);
                vif.rvalid <= 1;             // 拉高 rvalid，表示数据有效
                @(posedge vif.aclk);         // 等待时钟上升沿

                // 【握手等待】等待 master 拉高 rready
                while (!vif.rready) @(posedge vif.aclk);
                araddr += 4;                 // 地址递增4字节
            end
            vif.rvalid <= 0; vif.rlast <= 0; // 所有数据发完，清除信号
        end
    endtask
endclass
