///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar UVM 测试顶层 (Testbench Top)
//
///////////////////////////////////////////////////////////////////////////////
// 【文件功能说明】
// 这是整个 UVM 验证环境的最顶层模块，负责：
//   1. 生成时钟和复位信号
//   2. 例化 AXI 接口（Interface）
//   3. 例化 DUT（Design Under Test，被测设计）
//   4. 将接口通过 config_db 传递给 UVM 组件
//   5. 启动 UVM 测试
//   6. 配置超时和波形转储
//
// 【UVM 知识点】
// testbench top 不是 UVM 组件，而是普通的 SystemVerilog module。
// 它是连接 UVM 世界和 DUT 的桥梁：
//   - UVM 世界：class-based，面向对象，不直接操作信号
//   - DUT 世界：module-based，通过端口连接信号
//   - Interface 是连接两者的纽带：UVM 通过 virtual interface 驱动/采样信号
//
// 【验证环境架构图】
//   +--------------------------------------------------+
//   |                Testbench Top (本文件)              |
//   |  +----------+    +----------+    +----------+    |
//   |  | mst_if[0]|    | mst_if[1]|    | mst_if[2]|... |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |       |               |               |           |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |  |  DUT      |    |          |    |          |    |
//   |  | (Crossbar)|    |          |    |          |    |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |       |               |               |           |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |  | slv_if[0]|    | slv_if[1]|    | slv_if[2]|... |
//   |  +----------+    +----------+    +----------+    |
//   +--------------------------------------------------+
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module axi_crossbar_tb;

    // 【导入 UVM 包】
    // import uvm_pkg::* 导入所有 UVM 类和方法
    // import axi_pkg::* 导入我们自定义的验证组件包
    import uvm_pkg::*;
    import axi_pkg::*;
    `include "uvm_macros.svh"  // 包含 UVM 宏定义（如 `uvm_component_utils 等）

    // 【参数定义】
    // 这些参数必须与 DUT 的参数保持一致
    // 使用 parameter 而非硬编码，方便修改和复用
    parameter AXI_ADDR_W = 16;  // 地址位宽：16位，可寻址 64KB 空间
    parameter AXI_ID_W   = 8;   // ID 位宽：8位，支持 256 个不同的事务 ID
    parameter AXI_DATA_W = 32;  // 数据位宽：32位，每次传输 4 字节

    //--------------------------------------------------------------------------
    // 时钟与复位生成 (Clock & Reset Generation)
    //--------------------------------------------------------------------------
    // 【时钟生成】
    // aclk 初始值为 0，每 5ns 翻转一次 → 时钟周期 = 10ns → 频率 = 100MHz
    // always #5 是 SystemVerilog 的周期性行为块
    logic aclk = 0;

    // 【复位信号】
    // aresetn: AXI 标准复位信号，低电平有效（active low）
    //   - 初始为 0（复位状态）
    //   - 100ns 后拉高为 1（释放复位）
    // srst: 同步复位信号，高电平有效
    //   - 初始为 1（复位状态）
    //   - 100ns 后拉低为 0（释放复位）
    logic aresetn = 0;
    logic srst = 1;
    always #5 aclk = ~aclk;              // 时钟翻转
    initial begin #100; aresetn = 1; srst = 0; end  // 100ns 后释放复位

    //--------------------------------------------------------------------------
    // AXI 接口例化 (Interface Instantiation)
    //--------------------------------------------------------------------------
    // 【Master 接口数组】
    // mst_if[4]: 4 个 Master 接口，连接 DUT 的 Slave 端口
    //   - 每个 Master 接口对应一个 Master Agent（driver + monitor）
    //   - Master Agent 通过这些接口发送读写请求
    //
    // 【Slave 接口数组】
    // slv_if[4]: 4 个 Slave 接口，连接 DUT 的 Master 端口
    //   - 每个 Slave 接口对应一个 Slave Agent（driver + monitor）
    //   - Slave Agent 通过这些接口模拟从设备行为（接收请求、返回响应）
    //
    // 【命名约定说明】
    // DUT 端口命名：slv0, slv1, slv2, slv3 → DUT 的 Slave 端口（连接外部 Master）
    //               mst0, mst1, mst2, mst3 → DUT 的 Master 端口（连接外部 Slave）
    // 这是因为 Crossbar 的 Slave 端口接收来自 Master 的请求，
    // 而 Master 端口将请求转发给下游 Slave 设备
    axi_if #(.AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W))
        mst_if[4] (.aclk(aclk));  // Master 接口，连接 DUT 的 Slave 端口

    axi_if #(.AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W))
        slv_if[4] (.aclk(aclk));  // Slave 接口，连接 DUT 的 Master 端口

    // 【复位信号同步驱动】
    // 使用 generate 块为每个接口的 aresetn 信号同步驱动
    // 这样 test 可以通过 vif 覆盖复位信号（用于 reset 测试）
    // always @(posedge aclk) 确保复位信号在时钟上升沿更新，避免亚稳态
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_rst
            always @(posedge aclk) mst_if[i].aresetn <= aresetn;
            always @(posedge aclk) slv_if[i].aresetn <= aresetn;
        end
    endgenerate

    //--------------------------------------------------------------------------
    // DUT 例化 (Design Under Test Instantiation)
    //--------------------------------------------------------------------------
    // 【DUT 说明】
    // axicb_crossbar_top 是被测的 AXI Crossbar 模块
    // 它实现了一个 4x4 的 AXI 交叉开关矩阵：
    //   - 4 个 Slave 端口（slv0~slv3）：接收来自 4 个 Master 的请求
    //   - 4 个 Master 端口（mst0~mst3）：将请求转发给 4 个 Slave 设备
    //
    // 【参数配置说明】
    // MST0_CDC(0): Master 0 不需要跨时钟域处理
    // MST0_OSTDREQ_NUM(4): Master 0 最多支持 4 个未完成请求
    // MST0_OSTDREQ_SIZE(1): 每个未完成请求最大 1 个数据拍
    // MST0_PRIORITY(0): Master 0 优先级为 0（最低）
    // MST0_ROUTES(4'b1111): Master 0 可以访问所有 4 个 Slave
    // MST0_ID_MASK(8'h10): Master 0 的 ID 掩码，用于区分不同 Master 的事务
    // MST0_RW(0): 读写模式，0 表示支持读写
    //
    // SLV0_START_ADDR(0), SLV0_END_ADDR(4095): Slave 0 的地址范围 0~4095 (4KB)
    // SLV1_START_ADDR(4096), SLV1_END_ADDR(8191): Slave 1 的地址范围 4096~8191 (4KB)
    // SLV2_START_ADDR(8192), SLV2_END_ADDR(12287): Slave 2 的地址范围 8192~12287 (4KB)
    // SLV3_START_ADDR(12288), SLV3_END_ADDR(16383): Slave 3 的地址范围 12288~16383 (4KB)
    axicb_crossbar_top #(
        .AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W),
        .MST_NB(4), .SLV_NB(4), .MST_PIPELINE(0), .SLV_PIPELINE(0),
        .AXI_SIGNALING(1), .USER_SUPPORT(0),
        .MST0_CDC(0), .MST0_OSTDREQ_NUM(4), .MST0_OSTDREQ_SIZE(1),
        .MST0_PRIORITY(0), .MST0_ROUTES(4'b1111), .MST0_ID_MASK(8'h10), .MST0_RW(0),
        .MST1_CDC(0), .MST1_OSTDREQ_NUM(4), .MST1_OSTDREQ_SIZE(1),
        .MST1_PRIORITY(0), .MST1_ROUTES(4'b1111), .MST1_ID_MASK(8'h20), .MST1_RW(0),
        .MST2_CDC(0), .MST2_OSTDREQ_NUM(4), .MST2_OSTDREQ_SIZE(1),
        .MST2_PRIORITY(0), .MST2_ROUTES(4'b1111), .MST2_ID_MASK(8'h30), .MST2_RW(0),
        .MST3_CDC(0), .MST3_OSTDREQ_NUM(4), .MST3_OSTDREQ_SIZE(1),
        .MST3_PRIORITY(0), .MST3_ROUTES(4'b1111), .MST3_ID_MASK(8'h40), .MST3_RW(0),
        .SLV0_CDC(0), .SLV0_START_ADDR(0),     .SLV0_END_ADDR(4095),
        .SLV0_OSTDREQ_NUM(4), .SLV0_OSTDREQ_SIZE(1), .SLV0_KEEP_BASE_ADDR(0),
        .SLV1_CDC(0), .SLV1_START_ADDR(4096),   .SLV1_END_ADDR(8191),
        .SLV1_OSTDREQ_NUM(4), .SLV1_OSTDREQ_SIZE(1), .SLV1_KEEP_BASE_ADDR(0),
        .SLV2_CDC(0), .SLV2_START_ADDR(8192),   .SLV2_END_ADDR(12287),
        .SLV2_OSTDREQ_NUM(4), .SLV2_OSTDREQ_SIZE(1), .SLV2_KEEP_BASE_ADDR(0),
        .SLV3_CDC(0), .SLV3_START_ADDR(12288),  .SLV3_END_ADDR(16383),
        .SLV3_OSTDREQ_NUM(4), .SLV3_OSTDREQ_SIZE(1), .SLV3_KEEP_BASE_ADDR(0)
    ) dut (
        // 【全局信号】
        .aclk(aclk),          // 全局时钟
        .aresetn(aresetn),     // 全局复位（低有效）
        .srst(srst),           // 同步复位（高有效）

        // 【Master 0 端口连接】
        // 连接到 mst_if[0]（外部 Master Agent 通过此接口驱动）
        // 注意：DUT 的 slv0 端口连接到 mst_if[0]，因为这是 DUT 的 Slave 端口
        .slv0_aclk(aclk), .slv0_aresetn(aresetn), .slv0_srst(srst),
        .slv0_awvalid(mst_if[0].awvalid), .slv0_awready(mst_if[0].awready),
        .slv0_awaddr(mst_if[0].awaddr),   .slv0_awlen(mst_if[0].awlen),
        .slv0_awsize(mst_if[0].awsize),   .slv0_awburst(mst_if[0].awburst),
        .slv0_awlock(mst_if[0].awlock),   .slv0_awcache(mst_if[0].awcache),
        .slv0_awprot(mst_if[0].awprot),   .slv0_awqos(mst_if[0].awqos),
        .slv0_awregion(mst_if[0].awregion), .slv0_awid(mst_if[0].awid),
        .slv0_awuser(1'b0),  // user 信号未使用，接地
        .slv0_wvalid(mst_if[0].wvalid),   .slv0_wready(mst_if[0].wready),
        .slv0_wlast(mst_if[0].wlast),     .slv0_wdata(mst_if[0].wdata),
        .slv0_wstrb(mst_if[0].wstrb),     .slv0_wuser(1'b0),
        .slv0_bvalid(mst_if[0].bvalid),   .slv0_bready(mst_if[0].bready),
        .slv0_bid(mst_if[0].bid),         .slv0_bresp(mst_if[0].bresp),
        .slv0_buser(1'b0),
        .slv0_arvalid(mst_if[0].arvalid), .slv0_arready(mst_if[0].arready),
        .slv0_araddr(mst_if[0].araddr),   .slv0_arlen(mst_if[0].arlen),
        .slv0_arsize(mst_if[0].arsize),   .slv0_arburst(mst_if[0].arburst),
        .slv0_arlock(mst_if[0].arlock),   .slv0_arcache(mst_if[0].arcache),
        .slv0_arprot(mst_if[0].arprot),   .slv0_arqos(mst_if[0].arqos),
        .slv0_arregion(mst_if[0].arregion), .slv0_arid(mst_if[0].arid),
        .slv0_aruser(1'b0),
        .slv0_rvalid(mst_if[0].rvalid),   .slv0_rready(mst_if[0].rready),
        .slv0_rid(mst_if[0].rid),         .slv0_rresp(mst_if[0].rresp),
        .slv0_rdata(mst_if[0].rdata),     .slv0_rlast(mst_if[0].rlast),
        .slv0_ruser(1'b0),

        // 【Master 1 端口连接】
        .slv1_aclk(aclk), .slv1_aresetn(aresetn), .slv1_srst(srst),
        .slv1_awvalid(mst_if[1].awvalid), .slv1_awready(mst_if[1].awready),
        .slv1_awaddr(mst_if[1].awaddr),   .slv1_awlen(mst_if[1].awlen),
        .slv1_awsize(mst_if[1].awsize),   .slv1_awburst(mst_if[1].awburst),
        .slv1_awlock(mst_if[1].awlock),   .slv1_awcache(mst_if[1].awcache),
        .slv1_awprot(mst_if[1].awprot),   .slv1_awqos(mst_if[1].awqos),
        .slv1_awregion(mst_if[1].awregion), .slv1_awid(mst_if[1].awid),
        .slv1_awuser(1'b0),
        .slv1_wvalid(mst_if[1].wvalid),   .slv1_wready(mst_if[1].wready),
        .slv1_wlast(mst_if[1].wlast),     .slv1_wdata(mst_if[1].wdata),
        .slv1_wstrb(mst_if[1].wstrb),     .slv1_wuser(1'b0),
        .slv1_bvalid(mst_if[1].bvalid),   .slv1_bready(mst_if[1].bready),
        .slv1_bid(mst_if[1].bid),         .slv1_bresp(mst_if[1].bresp),
        .slv1_buser(1'b0),
        .slv1_arvalid(mst_if[1].arvalid), .slv1_arready(mst_if[1].arready),
        .slv1_araddr(mst_if[1].araddr),   .slv1_arlen(mst_if[1].arlen),
        .slv1_arsize(mst_if[1].arsize),   .slv1_arburst(mst_if[1].arburst),
        .slv1_arlock(mst_if[1].arlock),   .slv1_arcache(mst_if[1].arcache),
        .slv1_arprot(mst_if[1].arprot),   .slv1_arqos(mst_if[1].arqos),
        .slv1_arregion(mst_if[1].arregion), .slv1_arid(mst_if[1].arid),
        .slv1_aruser(1'b0),
        .slv1_rvalid(mst_if[1].rvalid),   .slv1_rready(mst_if[1].rready),
        .slv1_rid(mst_if[1].rid),         .slv1_rresp(mst_if[1].rresp),
        .slv1_rdata(mst_if[1].rdata),     .slv1_rlast(mst_if[1].rlast),
        .slv1_ruser(1'b0),

        // 【Master 2 端口连接】
        .slv2_aclk(aclk), .slv2_aresetn(aresetn), .slv2_srst(srst),
        .slv2_awvalid(mst_if[2].awvalid), .slv2_awready(mst_if[2].awready),
        .slv2_awaddr(mst_if[2].awaddr),   .slv2_awlen(mst_if[2].awlen),
        .slv2_awsize(mst_if[2].awsize),   .slv2_awburst(mst_if[2].awburst),
        .slv2_awlock(mst_if[2].awlock),   .slv2_awcache(mst_if[2].awcache),
        .slv2_awprot(mst_if[2].awprot),   .slv2_awqos(mst_if[2].awqos),
        .slv2_awregion(mst_if[2].awregion), .slv2_awid(mst_if[2].awid),
        .slv2_awuser(1'b0),
        .slv2_wvalid(mst_if[2].wvalid),   .slv2_wready(mst_if[2].wready),
        .slv2_wlast(mst_if[2].wlast),     .slv2_wdata(mst_if[2].wdata),
        .slv2_wstrb(mst_if[2].wstrb),     .slv2_wuser(1'b0),
        .slv2_bvalid(mst_if[2].bvalid),   .slv2_bready(mst_if[2].bready),
        .slv2_bid(mst_if[2].bid),         .slv2_bresp(mst_if[2].bresp),
        .slv2_buser(1'b0),
        .slv2_arvalid(mst_if[2].arvalid), .slv2_arready(mst_if[2].arready),
        .slv2_araddr(mst_if[2].araddr),   .slv2_arlen(mst_if[2].arlen),
        .slv2_arsize(mst_if[2].arsize),   .slv2_arburst(mst_if[2].arburst),
        .slv2_arlock(mst_if[2].arlock),   .slv2_arcache(mst_if[2].arcache),
        .slv2_arprot(mst_if[2].arprot),   .slv2_arqos(mst_if[2].arqos),
        .slv2_arregion(mst_if[2].arregion), .slv2_arid(mst_if[2].arid),
        .slv2_aruser(1'b0),
        .slv2_rvalid(mst_if[2].rvalid),   .slv2_rready(mst_if[2].rready),
        .slv2_rid(mst_if[2].rid),         .slv2_rresp(mst_if[2].rresp),
        .slv2_rdata(mst_if[2].rdata),     .slv2_rlast(mst_if[2].rlast),
        .slv2_ruser(1'b0),

        // 【Master 3 端口连接】
        .slv3_aclk(aclk), .slv3_aresetn(aresetn), .slv3_srst(srst),
        .slv3_awvalid(mst_if[3].awvalid), .slv3_awready(mst_if[3].awready),
        .slv3_awaddr(mst_if[3].awaddr),   .slv3_awlen(mst_if[3].awlen),
        .slv3_awsize(mst_if[3].awsize),   .slv3_awburst(mst_if[3].awburst),
        .slv3_awlock(mst_if[3].awlock),   .slv3_awcache(mst_if[3].awcache),
        .slv3_awprot(mst_if[3].awprot),   .slv3_awqos(mst_if[3].awqos),
        .slv3_awregion(mst_if[3].awregion), .slv3_awid(mst_if[3].awid),
        .slv3_awuser(1'b0),
        .slv3_wvalid(mst_if[3].wvalid),   .slv3_wready(mst_if[3].wready),
        .slv3_wlast(mst_if[3].wlast),     .slv3_wdata(mst_if[3].wdata),
        .slv3_wstrb(mst_if[3].wstrb),     .slv3_wuser(1'b0),
        .slv3_bvalid(mst_if[3].bvalid),   .slv3_bready(mst_if[3].bready),
        .slv3_bid(mst_if[3].bid),         .slv3_bresp(mst_if[3].bresp),
        .slv3_buser(1'b0),
        .slv3_arvalid(mst_if[3].arvalid), .slv3_arready(mst_if[3].arready),
        .slv3_araddr(mst_if[3].araddr),   .slv3_arlen(mst_if[3].arlen),
        .slv3_arsize(mst_if[3].arsize),   .slv3_arburst(mst_if[3].arburst),
        .slv3_arlock(mst_if[3].arlock),   .slv3_arcache(mst_if[3].arcache),
        .slv3_arprot(mst_if[3].arprot),   .slv3_arqos(mst_if[3].arqos),
        .slv3_arregion(mst_if[3].arregion), .slv3_arid(mst_if[3].arid),
        .slv3_aruser(1'b0),
        .slv3_rvalid(mst_if[3].rvalid),   .slv3_rready(mst_if[3].rready),
        .slv3_rid(mst_if[3].rid),         .slv3_rresp(mst_if[3].rresp),
        .slv3_rdata(mst_if[3].rdata),     .slv3_rlast(mst_if[3].rlast),
        .slv3_ruser(1'b0),

        // 【Slave 0 端口连接】
        // 连接到 slv_if[0]（外部 Slave Agent 通过此接口响应）
        // DUT 的 mst0 端口连接到 slv_if[0]，因为这是 DUT 的 Master 端口
        .mst0_aclk(aclk), .mst0_aresetn(aresetn), .mst0_srst(srst),
        .mst0_awvalid(slv_if[0].awvalid), .mst0_awready(slv_if[0].awready),
        .mst0_awaddr(slv_if[0].awaddr),   .mst0_awlen(slv_if[0].awlen),
        .mst0_awsize(slv_if[0].awsize),   .mst0_awburst(slv_if[0].awburst),
        .mst0_awlock(slv_if[0].awlock),   .mst0_awcache(slv_if[0].awcache),
        .mst0_awprot(slv_if[0].awprot),   .mst0_awqos(slv_if[0].awqos),
        .mst0_awregion(slv_if[0].awregion), .mst0_awid(slv_if[0].awid),
        .mst0_awuser(1'b0),
        .mst0_wvalid(slv_if[0].wvalid),   .mst0_wready(slv_if[0].wready),
        .mst0_wlast(slv_if[0].wlast),     .mst0_wdata(slv_if[0].wdata),
        .mst0_wstrb(slv_if[0].wstrb),     .mst0_wuser(1'b0),
        .mst0_bvalid(slv_if[0].bvalid),   .mst0_bready(slv_if[0].bready),
        .mst0_bid(slv_if[0].bid),         .mst0_bresp(slv_if[0].bresp),
        .mst0_buser(1'b0),
        .mst0_arvalid(slv_if[0].arvalid), .mst0_arready(slv_if[0].arready),
        .mst0_araddr(slv_if[0].araddr),   .mst0_arlen(slv_if[0].arlen),
        .mst0_arsize(slv_if[0].arsize),   .mst0_arburst(slv_if[0].arburst),
        .mst0_arlock(slv_if[0].arlock),   .mst0_arcache(slv_if[0].arcache),
        .mst0_arprot(slv_if[0].arprot),   .mst0_arqos(slv_if[0].arqos),
        .mst0_arregion(slv_if[0].arregion), .mst0_arid(slv_if[0].arid),
        .mst0_aruser(1'b0),
        .mst0_rvalid(slv_if[0].rvalid),   .mst0_rready(slv_if[0].rready),
        .mst0_rid(slv_if[0].rid),         .mst0_rresp(slv_if[0].rresp),
        .mst0_rdata(slv_if[0].rdata),     .mst0_rlast(slv_if[0].rlast),
        .mst0_ruser(1'b0),

        // 【Slave 1 端口连接】
        .mst1_aclk(aclk), .mst1_aresetn(aresetn), .mst1_srst(srst),
        .mst1_awvalid(slv_if[1].awvalid), .mst1_awready(slv_if[1].awready),
        .mst1_awaddr(slv_if[1].awaddr),   .mst1_awlen(slv_if[1].awlen),
        .mst1_awsize(slv_if[1].awsize),   .mst1_awburst(slv_if[1].awburst),
        .mst1_awlock(slv_if[1].awlock),   .mst1_awcache(slv_if[1].awcache),
        .mst1_awprot(slv_if[1].awprot),   .mst1_awqos(slv_if[1].awqos),
        .mst1_awregion(slv_if[1].awregion), .mst1_awid(slv_if[1].awid),
        .mst1_awuser(1'b0),
        .mst1_wvalid(slv_if[1].wvalid),   .mst1_wready(slv_if[1].wready),
        .mst1_wlast(slv_if[1].wlast),     .mst1_wdata(slv_if[1].wdata),
        .mst1_wstrb(slv_if[1].wstrb),     .mst1_wuser(1'b0),
        .mst1_bvalid(slv_if[1].bvalid),   .mst1_bready(slv_if[1].bready),
        .mst1_bid(slv_if[1].bid),         .mst1_bresp(slv_if[1].bresp),
        .mst1_buser(1'b0),
        .mst1_arvalid(slv_if[1].arvalid), .mst1_arready(slv_if[1].arready),
        .mst1_araddr(slv_if[1].araddr),   .mst1_arlen(slv_if[1].arlen),
        .mst1_arsize(slv_if[1].arsize),   .mst1_arburst(slv_if[1].arburst),
        .mst1_arlock(slv_if[1].arlock),   .mst1_arcache(slv_if[1].arcache),
        .mst1_arprot(slv_if[1].arprot),   .mst1_arqos(slv_if[1].arqos),
        .mst1_arregion(slv_if[1].arregion), .mst1_arid(slv_if[1].arid),
        .mst1_aruser(1'b0),
        .mst1_rvalid(slv_if[1].rvalid),   .mst1_rready(slv_if[1].rready),
        .mst1_rid(slv_if[1].rid),         .mst1_rresp(slv_if[1].rresp),
        .mst1_rdata(slv_if[1].rdata),     .mst1_rlast(slv_if[1].rlast),
        .mst1_ruser(1'b0),

        // 【Slave 2 端口连接】
        .mst2_aclk(aclk), .mst2_aresetn(aresetn), .mst2_srst(srst),
        .mst2_awvalid(slv_if[2].awvalid), .mst2_awready(slv_if[2].awready),
        .mst2_awaddr(slv_if[2].awaddr),   .mst2_awlen(slv_if[2].awlen),
        .mst2_awsize(slv_if[2].awsize),   .mst2_awburst(slv_if[2].awburst),
        .mst2_awlock(slv_if[2].awlock),   .mst2_awcache(slv_if[2].awcache),
        .mst2_awprot(slv_if[2].awprot),   .mst2_awqos(slv_if[2].awqos),
        .mst2_awregion(slv_if[2].awregion), .mst2_awid(slv_if[2].awid),
        .mst2_awuser(1'b0),
        .mst2_wvalid(slv_if[2].wvalid),   .mst2_wready(slv_if[2].wready),
        .mst2_wlast(slv_if[2].wlast),     .mst2_wdata(slv_if[2].wdata),
        .mst2_wstrb(slv_if[2].wstrb),     .mst2_wuser(1'b0),
        .mst2_bvalid(slv_if[2].bvalid),   .mst2_bready(slv_if[2].bready),
        .mst2_bid(slv_if[2].bid),         .mst2_bresp(slv_if[2].bresp),
        .mst2_buser(1'b0),
        .mst2_arvalid(slv_if[2].arvalid), .mst2_arready(slv_if[2].arready),
        .mst2_araddr(slv_if[2].araddr),   .mst2_arlen(slv_if[2].arlen),
        .mst2_arsize(slv_if[2].arsize),   .mst2_arburst(slv_if[2].arburst),
        .mst2_arlock(slv_if[2].arlock),   .mst2_arcache(slv_if[2].arcache),
        .mst2_arprot(slv_if[2].arprot),   .mst2_arqos(slv_if[2].arqos),
        .mst2_arregion(slv_if[2].arregion), .mst2_arid(slv_if[2].arid),
        .mst2_aruser(1'b0),
        .mst2_rvalid(slv_if[2].rvalid),   .mst2_rready(slv_if[2].rready),
        .mst2_rid(slv_if[2].rid),         .mst2_rresp(slv_if[2].rresp),
        .mst2_rdata(slv_if[2].rdata),     .mst2_rlast(slv_if[2].rlast),
        .mst2_ruser(1'b0),

        // 【Slave 3 端口连接】
        .mst3_aclk(aclk), .mst3_aresetn(aresetn), .mst3_srst(srst),
        .mst3_awvalid(slv_if[3].awvalid), .mst3_awready(slv_if[3].awready),
        .mst3_awaddr(slv_if[3].awaddr),   .mst3_awlen(slv_if[3].awlen),
        .mst3_awsize(slv_if[3].awsize),   .mst3_awburst(slv_if[3].awburst),
        .mst3_awlock(slv_if[3].awlock),   .mst3_awcache(slv_if[3].awcache),
        .mst3_awprot(slv_if[3].awprot),   .mst3_awqos(slv_if[3].awqos),
        .mst3_awregion(slv_if[3].awregion), .mst3_awid(slv_if[3].awid),
        .mst3_awuser(1'b0),
        .mst3_wvalid(slv_if[3].wvalid),   .mst3_wready(slv_if[3].wready),
        .mst3_wlast(slv_if[3].wlast),     .mst3_wdata(slv_if[3].wdata),
        .mst3_wstrb(slv_if[3].wstrb),     .mst3_wuser(1'b0),
        .mst3_bvalid(slv_if[3].bvalid),   .mst3_bready(slv_if[3].bready),
        .mst3_bid(slv_if[3].bid),         .mst3_bresp(slv_if[3].bresp),
        .mst3_buser(1'b0),
        .mst3_arvalid(slv_if[3].arvalid), .mst3_arready(slv_if[3].arready),
        .mst3_araddr(slv_if[3].araddr),   .mst3_arlen(slv_if[3].arlen),
        .mst3_arsize(slv_if[3].arsize),   .mst3_arburst(slv_if[3].arburst),
        .mst3_arlock(slv_if[3].arlock),   .mst3_arcache(slv_if[3].arcache),
        .mst3_arprot(slv_if[3].arprot),   .mst3_arqos(slv_if[3].arqos),
        .mst3_arregion(slv_if[3].arregion), .mst3_arid(slv_if[3].arid),
        .mst3_aruser(1'b0),
        .mst3_rvalid(slv_if[3].rvalid),   .mst3_rready(slv_if[3].rready),
        .mst3_rid(slv_if[3].rid),         .mst3_rresp(slv_if[3].rresp),
        .mst3_rdata(slv_if[3].rdata),     .mst3_rlast(slv_if[3].rlast),
        .mst3_ruser(1'b0)
    );

    //--------------------------------------------------------------------------
    // UVM config_db 配置 (UVM Configuration Database)
    //--------------------------------------------------------------------------
    // 【config_db 说明】
    // uvm_config_db 是 UVM 的配置数据库机制，用于在组件之间传递配置信息。
    // 这里使用它将 virtual interface 传递给 UVM 组件：
    //   - set() 函数：将数据存入 config_db
    //   - 参数1 (null)：使用全局数据库（非特定组件）
    //   - 参数2 ("*.mst_drv0")：通配符路径，匹配所有层次下的 mst_drv0 组件
    //   - 参数3 ("vif")：配置项名称
    //   - 参数4 (mst_if[0])：配置项值（virtual interface）
    //
    // 【Virtual Interface 说明】
    // virtual interface 是 SystemVerilog 中指向 interface 实例的指针
    // UVM 组件（class）不能直接例化或访问 interface（module），
    // 但可以通过 virtual interface 间接驱动/采样接口信号
    // 这是连接 UVM 世界和 DUT 世界的桥梁
    initial begin
        // 将 mst_if[0] 传递给 Master Driver 0 和 Master Monitor 0
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv0", "vif", mst_if[0]);
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_mon0", "vif", mst_if[0]);
        // 将 slv_if[0] 传递给 Slave Driver 0 和 Slave Monitor 0
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_drv0", "vif", slv_if[0]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_mon0", "vif", slv_if[0]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv1", "vif", mst_if[1]);
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_mon1", "vif", mst_if[1]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_drv1", "vif", slv_if[1]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_mon1", "vif", slv_if[1]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv2", "vif", mst_if[2]);
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_mon2", "vif", mst_if[2]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_drv2", "vif", slv_if[2]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_mon2", "vif", slv_if[2]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv3", "vif", mst_if[3]);
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_mon3", "vif", mst_if[3]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_drv3", "vif", slv_if[3]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_mon3", "vif", slv_if[3]);

        // 【启动 UVM 测试】
        // run_test() 是 UVM 的入口函数，它会：
        //   1. 根据 +UVM_TESTNAME 命令行参数创建测试实例
        //   2. 如果没有指定，使用默认的 "axi_basic_test"
        //   3. 执行 UVM 的 phase 机制（build → connect → run → check → report）
        run_test("axi_basic_test");
    end

    //--------------------------------------------------------------------------
    // 超时机制 (Timeout Mechanism)
    //--------------------------------------------------------------------------
    // 【超时说明】
    // 如果仿真运行超过 50ms（50,000,000ns）仍未结束，强制终止
    // 这是为了防止测试卡死导致仿真无限运行
    // uvm_fatal 会打印错误信息并终止仿真
    initial begin
        #50000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end

    //--------------------------------------------------------------------------
    // 波形转储 (Waveform Dump)
    //--------------------------------------------------------------------------
    // 【波形说明】
    // $dumpfile: 指定波形文件名（VCD 格式）
    // $dumpvars: 指定要记录的信号范围
    //   - 0: 记录所有层次的信号
    //   - axi_crossbar_tb: 从 testbench 顶层开始记录
    // 生成的 .vcd 文件可以用 GTKWave 等工具查看
    initial begin
        $dumpfile("axi_crossbar_tb.vcd");
        $dumpvars(0, axi_crossbar_tb);
    end

endmodule
