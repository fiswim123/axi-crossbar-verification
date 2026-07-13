`timescale 1ns/1ps
/* ============================================================================
 * 文件: axi_if.sv
 * 功能: AXI4 接口定义 (Interface Definition)
 *
 * 【初学者须知】
 * SystemVerilog 的 interface 是一种将多个相关信号封装在一起的结构，
 * 类似于"信号线束"。使用 interface 的好处:
 *   1. 减少端口声明的重复代码（不需要在每个模块中逐一声明信号）
 *   2. 方便通过 virtual interface 在 UVM testbench 中驱动/采样信号
 *   3. 可以包含断言(SVA)、任务(task)和函数(function)
 *
 * 【AXI 协议简介】
 * AXI (Advanced eXtensible Interface) 是 ARM 公司 AMBA 总线协议的一部分，
 * 广泛用于 SoC 中处理器与外设之间的高速数据传输。
 * AXI4 协议定义了 5 个独立的通道（Channel），每个通道都有自己的握手信号:
 *
 *   1. Write Address Channel  (AW) - 写地址通道：主设备发送写操作的地址和控制信息
 *   2. Write Data Channel     (W)  - 写数据通道：主设备发送要写入的数据
 *   3. Write Response Channel (B)  - 写响应通道：从设备返回写操作的完成状态
 *   4. Read Address Channel   (AR) - 读地址通道：主设备发送读操作的地址和控制信息
 *   5. Read Data Channel      (R)  - 读数据通道：从设备返回读取的数据和状态
 *
 * 【AXI 握手机制 (Handshake Mechanism)】
 * AXI 每个通道使用 VALID/READY 握手机制进行数据传输:
 *   - 发送方拉高 valid 信号，表示数据/地址有效
 *   - 接收方拉高 ready 信号，表示已准备好接收
 *   - 只有当 valid 和 ready 同时为高时（同一个时钟上升沿），传输才发生
 *   - 规则: valid 一旦拉高，在 ready 拉高之前不能撤销（必须保持稳定）
 *   - 规则: ready 可以在 valid 之前或之后拉高，也可以和 valid 同时拉高
 * ============================================================================ */

interface axi_if #(
    /* ---- 参数定义 (Parameters) ----
     * 使用 parameter 可以让接口在例化时灵活配置位宽，
     * 适用于不同配置的 AXI 互联（crossbar）验证。
     *
     * AXI_ADDR_W: 地址位宽，决定可寻址的地址空间大小
     *   - 16 位 → 可寻址 2^16 = 65536 个字节地址
     *   - 实际 SoC 中通常为 32 或 64 位
     *
     * AXI_ID_W: ID 位宽，用于支持乱序(out-of-order)和多事务(multiple outstanding)传输
     *   - AXI 允许同一 ID 的事务保序，不同 ID 的事务可以乱序完成
     *   - ID 越宽，可同时跟踪的独立事务越多
     *
     * AXI_DATA_W: 数据位宽，决定每次数据传输的宽度
     *   - 32 位 → 每次传输 4 字节
     *   - 常见配置: 32, 64, 128, 256, 512 位
     */
    parameter AXI_ADDR_W = 16,  // 地址位宽，单位: bit
    parameter AXI_ID_W   = 8,   // 事务 ID 位宽
    parameter AXI_DATA_W = 32   // 数据位宽
)(
    /* ---- 端口列表 ----
     * aclk: 全局时钟信号，所有 AXI 信号在此时钟上升沿采样
     * 注意: aclk 通过 input 声明，由外部（通常是 testbench 的顶层）驱动
     */
    input logic aclk
);

    // =========================================================================
    // 复位信号
    // =========================================================================
    /* aresetn: AXI 全局复位信号，低电平有效（active-low）
     *   - "n" 后缀表示 "negative" 或 "not"，即低有效
     *   - 当 aresetn=0 时，接口处于复位状态，所有信号应为初始值
     *   - 当 aresetn=1 时，接口正常工作
     *   - 初始值设为 0，表示上电时默认处于复位状态
     *   - 可由 testbench 直接驱动，也可由 test 通过 virtual interface (vif) 驱动
     */
    logic aresetn = 0;

    // =========================================================================
    // 通道 1: Write Address Channel (AW) - 写地址通道
    // =========================================================================
    /* 写地址通道的功能:
     * 主设备(Master)通过此通道向从设备(Slave)发送写事务的地址和控制信息。
     * 当主设备要写入数据时，首先在此通道上给出目标地址和传输参数。
     *
     * 【各信号含义】
     * awvalid : 主设备 → 从设备。为 1 表示写地址信息有效，主设备已准备好发起写事务
     * awready : 从设备 → 主设备。为 1 表示从设备已准备好接收写地址信息
     * awaddr  : 写目标地址。宽度由参数 AXI_ADDR_W 决定
     * awlen   : 突发长度(Burst Length) = awlen + 1
     *           例如 awlen=3 表示一次突发传输 4 拍(data beat)
     *           AXI4 中 awlen 为 8 位，最大突发长度为 256 拍
     * awsize  : 每拍字节数 = 2^awsize (单位: 字节)
     *           例如 awsize=2 表示每拍传输 2^2 = 4 字节
     *           最大值为 2^7 = 128 字节（对应 1024 位数据总线）
     * awburst : 突发类型(Burst Type)
     *           2'b00 = FIXED（固定地址，用于 FIFO 类外设）
     *           2'b01 = INCR（地址递增，最常用）
     *           2'b10 = WRAP（地址回环，用于 cache line fill）
     * awlock  : 锁定类型。0=正常访问，1=独占访问(Exclusive Access)
     *           独占访问用于实现原子操作(atomic operation)
     * awcache : 缓存属性(Cache Type)，定义事务的缓存策略
     *           例如: 是否可缓存、是否可缓冲、是否可分配等
     * awprot  : 保护属性(Protection Type)，3 位
     *           bit[0]: 0=安全(Secure), 1=非安全(Non-secure)
     *           bit[1]: 0=普通访问, 1=特权访问(Privileged)
     *           bit[2]: 0=数据访问, 1=指令访问
     * awqos   : QoS (Quality of Service) 标识符，用于服务质量控制
     *           值越大优先级越高（具体实现由 crossbar 决定）
     * awregion: 区域标识符，用于将地址空间划分为不同区域
     *           可用于实现外设的地址解码
     * awid    : 写事务 ID，用于标识此写事务
     *           相同 ID 的事务必须保序完成，不同 ID 可以乱序
     */
    logic                  awvalid, awready;          // 握手信号对
    logic [AXI_ADDR_W-1:0] awaddr;                    // 写地址
    logic [7:0]            awlen;                     // 突发长度 (0~255，实际传输 1~256 拍)
    logic [2:0]            awsize;                    // 每拍字节数 = 2^awsize
    logic [1:0]            awburst;                   // 突发类型: FIXED/INCR/WRAP
    logic                  awlock;                    // 锁定类型: 0=正常, 1=独占
    logic [3:0]            awcache, awqos, awregion;  // 缓存/QoS/区域属性
    logic [2:0]            awprot;                    // 保护属性
    logic [AXI_ID_W-1:0]   awid;                     // 写事务 ID

    // =========================================================================
    // 通道 2: Write Data Channel (W) - 写数据通道
    // =========================================================================
    /* 写数据通道的功能:
     * 主设备通过此通道向从设备发送实际要写入的数据。
     * 写数据通道与写地址通道是独立的，可以先发地址再发数据，也可以交替发送。
     * 但同一事务的数据必须在地址发出后才能完成。
     *
     * 【各信号含义】
     * wvalid : 主设备 → 从设备。为 1 表示写数据有效
     * wready : 从设备 → 主设备。为 1 表示从设备已准备好接收数据
     * wlast  : 最后一拍标识。为 1 表示这是当前突发传输的最后一拍数据
     *          从设备收到 wlast 后，知道可以准备写响应了
     * wdata  : 写数据，宽度由参数 AXI_DATA_W 决定
     * wstrb  : 写字节选通(Write Strobe)，每一位对应 wdata 中的一个字节
     *          为 1 表示对应字节有效需要写入，为 0 表示该字节无效不写入
     *          例如: wdata=32'hDEADBEEF, wstrb=4'b1010
     *                只写字节 3 和字节 1 (0xDE 和 0xBE)
     *          位宽 = AXI_DATA_W / 8（一个字节对应一个 strobe 位）
     */
    logic                  wvalid, wready, wlast;     // 握手信号 + 最后一拍标识
    logic [AXI_DATA_W-1:0] wdata;                     // 写数据
    logic [AXI_DATA_W/8-1:0] wstrb;                   // 字节选通，每位控制一个字节

    // =========================================================================
    // 通道 3: Write Response Channel (B) - 写响应通道
    // =========================================================================
    /* 写响应通道的功能:
     * 从设备通过此通道向主设备返回写操作的完成状态。
     * 一次写响应对应一个完整的写突发事务（不是每一拍数据一个响应）。
     *
     * 【各信号含义】
     * bvalid : 从设备 → 主设备。为 1 表示写响应有效
     * bready : 主设备 → 从设备。为 1 表示主设备已准备好接收响应
     * bid    : 写响应 ID，必须与对应写事务的 awid 一致
     *          主设备通过 bid 知道这个响应对应哪个写事务
     * bresp  : 写响应状态，2 位
     *          2'b00 = OKAY   (正常完成)
     *          2'b01 = EXOKAY (独占访问成功)
     *          2'b10 = SLVERR (从设备错误)
     *          2'b11 = DECERR (解码错误，地址无效)
     */
    logic                  bvalid, bready;            // 握手信号对
    logic [AXI_ID_W-1:0]   bid;                      // 写响应 ID
    logic [1:0]            bresp;                     // 写响应状态

    // =========================================================================
    // 通道 4: Read Address Channel (AR) - 读地址通道
    // =========================================================================
    /* 读地址通道的功能:
     * 主设备通过此通道向从设备发送读事务的地址和控制信息。
     * 信号含义与写地址通道类似，只是前缀从 aw 变为 ar (A=Address, R=Read)。
     *
     * 【各信号含义】（与写地址通道对应信号含义相同，仅方向相反）
     * arvalid : 主设备 → 从设备。为 1 表示读地址信息有效
     * arready : 从设备 → 主设备。为 1 表示从设备已准备好接收读地址
     * araddr  : 读目标地址
     * arlen   : 突发长度 = arlen + 1
     * arsize  : 每拍字节数 = 2^arsize
     * arburst : 突发类型 (FIXED/INCR/WRAP)
     * arlock  : 锁定类型
     * arcache : 缓存属性
     * arprot  : 保护属性
     * arqos   : QoS 属性
     * arregion: 区域标识
     * arid    : 读事务 ID
     */
    logic                  arvalid, arready;          // 握手信号对
    logic [AXI_ADDR_W-1:0] araddr;                    // 读地址
    logic [7:0]            arlen;                     // 突发长度
    logic [2:0]            arsize;                    // 每拍字节数
    logic [1:0]            arburst;                   // 突发类型
    logic                  arlock;                    // 锁定类型
    logic [3:0]            arcache, arqos, arregion;  // 缓存/QoS/区域属性
    logic [2:0]            arprot;                    // 保护属性
    logic [AXI_ID_W-1:0]   arid;                     // 读事务 ID

    // =========================================================================
    // 通道 5: Read Data Channel (R) - 读数据通道
    // =========================================================================
    /* 读数据通道的功能:
     * 从设备通过此通道向主设备返回读取到的数据和状态。
     * 注意: 读通道没有单独的"读响应通道"，读数据和读响应共享同一通道。
     *
     * 【各信号含义】
     * rvalid : 从设备 → 主设备。为 1 表示读数据有效
     * rready : 主设备 → 从设备。为 1 表示主设备已准备好接收数据
     * rlast  : 最后一拍标识。为 1 表示这是当前突发的最后一拍数据
     * rid    : 读数据 ID，必须与对应读事务的 arid 一致
     * rresp  : 读响应状态 (同 bresp 的编码)
     *          2'b00 = OKAY, 2'b01 = EXOKAY, 2'b10 = SLVERR, 2'b11 = DECERR
     * rdata  : 读取到的数据
     */
    logic                  rvalid, rready, rlast;     // 握手信号 + 最后一拍标识
    logic [AXI_ID_W-1:0]   rid;                      // 读数据 ID
    logic [1:0]            rresp;                     // 读响应状态
    logic [AXI_DATA_W-1:0] rdata;                     // 读数据

    // =========================================================================
    // Modport 定义
    // =========================================================================
    /* 【Modport 概念详解 - 初学者必读】
     *
     * Modport (Module Port) 是 SystemVerilog interface 中用于定义信号方向的机制。
     * 同一个 interface 中的信号，在不同 modport 视角下方向是不同的。
     *
     * 【为什么要用 modport?】
     * 在 AXI 总线中，主设备(Master)和从设备(Slave)看到的信号方向是相反的:
     *   - 对于 Master: awvalid 是输出(output)，awready 是输入(input)
     *   - 对于 Slave:  awvalid 是输入(input)，  awready 是输出(output)
     *
     * 如果不使用 modport，编译器无法知道信号的方向，可能会导致:
     *   - 多个模块同时驱动同一个信号（编译警告或错误）
     *   - 无法进行正确的信号方向检查
     *
     * 【使用方式】
     * 在模块端口声明时使用 modport 指定方向:
     *   module my_master(axi_if.master vif);  // 声明为 master 视角
     *   module my_slave(axi_if.slave vif);    // 声明为 slave 视角
     *
     * 【注意事项】
     *   - aclk 和 aresetn 在 master 和 slave 中都是 input，因为它们由外部驱动
     *   - Master 驱动的信号（如 awvalid）在 master modport 中是 output
     *   - Slave 驱动的信号（如 awready）在 slave modport 中是 output
     *   - Modport 仅在编译时起方向检查作用，不影响仿真行为
     */

    /* master modport: 主设备视角
     * 主设备（如 CPU、DMA）连接到此接口时使用的 modport
     * 主设备发起读/写事务，驱动地址和数据，接收响应
     */
    modport master (
        input  aclk, aresetn,                        // 时钟和复位：外部驱动，始终为输入
        // Write Address Channel - 主设备输出地址信息
        output awvalid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awqos, awregion, awid,
        input  awready,                              // 从设备的准备好信号：主设备接收
        // Write Data Channel - 主设备输出数据
        output wvalid, wlast, wdata, wstrb,
        input  wready,                               // 从设备的准备好信号
        // Write Response Channel - 主设备接收写响应
        input  bvalid, bid, bresp,                   // 从设备输出的响应信息
        output bready,                               // 主设备的准备好信号
        // Read Address Channel - 主设备输出读地址
        output arvalid, araddr, arlen, arsize, arburst, arlock,
               arcache, arprot, arqos, arregion, arid,
        input  arready,                              // 从设备的准备好信号
        // Read Data Channel - 主设备接收读数据
        input  rvalid, rid, rresp, rdata, rlast,     // 从设备输出的读数据
        output rready                                // 主设备的准备好信号
    );

    /* slave modport: 从设备视角
     * 从设备（如 SRAM、外设控制器）连接到此接口时使用的 modport
     * 从设备接收读/写事务，返回响应和数据
     * 注意: 信号方向与 master modport 完全相反！
     */
    modport slave (
        input  aclk, aresetn,                        // 时钟和复位：始终为输入
        // Write Address Channel - 从设备接收地址信息
        input  awvalid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awqos, awregion, awid,
        output awready,                              // 从设备输出准备好信号
        // Write Data Channel - 从设备接收数据
        input  wvalid, wlast, wdata, wstrb,
        output wready,                               // 从设备输出准备好信号
        // Write Response Channel - 从设备输出写响应
        output bvalid, bid, bresp,                   // 从设备驱动响应信息
        input  bready,                               // 接收主设备的准备好信号
        // Read Address Channel - 从设备接收读地址
        input  arvalid, araddr, arlen, arsize, arburst, arlock,
               arcache, arprot, arqos, arregion, arid,
        output arready,                              // 从设备输出准备好信号
        // Read Data Channel - 从设备输出读数据
        output rvalid, rid, rresp, rdata, rlast,     // 从设备驱动读数据
        input  rready                                // 接收主设备的准备好信号
    );

    // =========================================================================
    // SVA: SystemVerilog Assertions (系统验证断言)
    // =========================================================================
    /* 【SVA 概念详解 - 初学者必读】
     *
     * SVA (SystemVerilog Assertions) 是一种声明式的检查机制，
     * 用于在仿真过程中自动验证设计是否符合协议规范。
     *
     * 【为什么要用 SVA?】
     * 1. 协议检查: 自动验证 AXI 握手协议的规则，无需手动编写检查代码
     * 2. 早期发现问题: 在仿真过程中实时检测违规，快速定位 bug
     * 3. 文档作用: 断言本身就是协议规范的可执行描述
     *
     * 【SVA 基本语法】
     * property: 定义一个时序属性（要检查的行为规则）
     * assert property: 断言该属性必须始终为真
     * 如果属性为假，仿真器会报告错误
     *
     * 【断言类型】
     * - 并发断言 (Concurrent Assertion): 基于时钟边沿，每个周期检查
     *   本文件中使用的就是并发断言
     * - 即时断言 (Immediate Assertion): 类似 if 语句，在过程块中使用
     */

    /* ---- 断言 1: VALID 信号稳定性检查 ----
     *
     * 【AXI 协议规则】
     * 在 VALID/READY 握手中，一旦发送方拉高 VALID 信号，
     * 在接收方拉高 READY 之前，VALID 必须保持为高，不能撤销。
     * 这是为了防止死锁和数据丢失。
     *
     * 【property 语法解析】
     * property sig_stable(sig, ready);
     *   - 定义一个名为 sig_stable 的属性，接受两个参数: sig 和 ready
     *
     * @(posedge aclk)
     *   - 在每个时钟上升沿检查
     *
     * disable iff (!aresetn)
     *   - 当 aresetn=0（复位状态）时，禁用此断言检查
     *   - 复位期间信号不稳定是正常的，不需要检查
     *
     * sig && !ready |=> sig
     *   - "sig && !ready" 是前提条件(antecedent):
     *     当 sig=1 且 ready=0 时（发送方已就绪但接收方未准备好）
     *   - "|=>" 是"下一个周期蕴含"操作符:
     *     表示在满足前提条件的下一个时钟周期，后续条件必须为真
     *   - "sig" 是后续条件(consequent):
     *     下一个周期 sig 必须仍然为 1（不能撤销）
     *
     * 总结: 当某个 valid 信号为高但对应的 ready 为低时，
     *       下一个时钟周期该 valid 信号必须保持为高。
     */
    property sig_stable(sig, ready);
        @(posedge aclk) disable iff (!aresetn)
        sig && !ready |=> sig;
    endproperty

    /* ---- 5 个通道的 VALID 稳定性断言 ----
     * 分别检查 5 个通道的 valid 信号在握手完成前是否保持稳定
     * 如果违反，仿真器会输出 "[SVA] XXVALID unstable" 错误信息
     */
    assert property (sig_stable(awvalid, awready)) else $error("[SVA] AWVALID unstable");
    assert property (sig_stable(wvalid, wready))   else $error("[SVA] WVALID unstable");
    assert property (sig_stable(bvalid, bready))   else $error("[SVA] BVALID unstable");
    assert property (sig_stable(arvalid, arready))  else $error("[SVA] ARVALID unstable");
    assert property (sig_stable(rvalid, rready))   else $error("[SVA] RVALID unstable");

    /* ---- 断言 2: LAST 信号必须伴随 VALID ----
     *
     * 【AXI 协议规则】
     * WLAST 和 RLAST 信号只有在对应的 VALID 为高时才有意义。
     * 如果 VALID 为低，LAST 信号不应为高（这是协议违规）。
     *
     * 【语法解析】
     * @(posedge aclk): 每个时钟上升沿检查
     * disable iff (!aresetn): 复位时禁用
     * wlast |-> wvalid: "|" 是"蕴含"操作符（同一周期内）
     *   - 当 wlast=1 时，wvalid 必须也为 1
     *   - 如果 wlast=1 但 wvalid=0，断言失败
     *
     * 类似地检查 rlast 和 rvalid
     */
    assert property (@(posedge aclk) disable iff (!aresetn) wlast |-> wvalid)
        else $error("[SVA] WLAST without WVALID");
    assert property (@(posedge aclk) disable iff (!aresetn) rlast |-> rvalid)
        else $error("[SVA] RLAST without RVALID");

endinterface
