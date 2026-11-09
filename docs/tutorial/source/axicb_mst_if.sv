//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_mst_if.sv
// 文件功能: 目标端接口适配器 (Master Interface / Slave Port Adapter)
// 模块描述:
//   本模块位于 AXI Crossbar 内部交换矩阵与外部 Slave (目标方从机) 之间。
//   在外部 Slave 视角下，它是发起请求的 Master 端口；
//   在 Crossbar 内部视角下，它是将内部交叉矩阵的打包请求还原、解包并驱动外部从机的出口适配层。
//
// 核心工作机制与设计要点:
//   1. 通道字段解包还原 (Channel Unpacking & Deserialization):
//      - 内部交换矩阵传输的是高度压缩的扁平总线 (i_awch, i_wch, i_arch 等)。
//      - 本模块在出口端将打包总线拆解还原为标准 AXI 离散端口 (o_awaddr, o_awlen, o_wdata 等)。
//   2. 基地址偏移减除与局部地址映射 (Base Address Subtraction):
//      - 由参数 KEEP_BASE_ADDR 控制:
//        * KEEP_BASE_ADDR = 0: 开启局部地址变换。将系统全局绝对地址减去从机基地址:
//          o_awaddr = raw_awaddr - BASE_ADDR;
//          o_araddr = raw_araddr - BASE_ADDR;
//          使得下游从机感知到的地址是从 0x0000 起始的内部局部偏移量。
//        * KEEP_BASE_ADDR = 1: 保持系统全局绝对地址不变，透传给从机。
//   3. 突发协议解包适配:
//      - 支持 AXI4 与 AXI4-Lite。在 AXI4-Lite 模式下忽略突发控制位，固定 RLAST 为 1。
//   4. 缓冲与 CDC 选项:
//      - SLV_CDC=1: 跨时钟域异步 FIFO 缓冲。
//      - SLV_OSTDREQ_NUM>0: 单时钟同步 FIFO 缓冲 (axicb_scfifo)。
//      - 否则: 纯组合零延迟直通 (NO_CDC_NO_BUFFERING)。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_mst_if

    #(
        //---------------------------------------------------------------------
        // 全局总线位宽参数
        //---------------------------------------------------------------------
        parameter AXI_ADDR_W = 8,           // 地址总线位宽 (单位: bit)
        parameter AXI_ID_W   = 8,           // 事务 ID 位宽
        parameter AXI_DATA_W = 8,           // 数据总线位宽

        // AXI 协议模式选择: 0 = AXI4-Lite, 1 = 完整 AXI4
        parameter AXI_SIGNALING = 0,

        // 基地址配置与保留策略
        parameter KEEP_BASE_ADDR = 0,       // 0=减去基地址转为局部偏移, 1=保留全局绝对地址
        parameter BASE_ADDR      = 0,       // 本 Slave 的起始基地址

        // 跨时钟域与缓冲设置
        parameter SLV_CDC = 0,              // 跨时钟使能: 1=异步 FIFO, 0=同步时钟
        parameter SLV_OSTDREQ_NUM = 4,      // 目标从机支持的最大在途请求数
        parameter SLV_OSTDREQ_SIZE = 1,     // 单个在途请求数据相位深度

        // USER 扩展用户自定义字段支持: 0=关闭, 1=开启
        parameter USER_SUPPORT = 0,
        parameter AXI_AUSER_W  = 0,         // AW/AR 通道用户字段位宽
        parameter AXI_WUSER_W  = 0,         // W 通道用户字段位宽
        parameter AXI_BUSER_W  = 0,         // B 通道用户字段位宽
        parameter AXI_RUSER_W  = 0,         // R 通道用户字段位宽

        // 内部打包后的各通道扁平位宽
        parameter AWCH_W = 8,               // 内部写地址通道位宽
        parameter WCH_W  = 8,               // 内部写数据通道位宽
        parameter BCH_W  = 8,               // 内部写响应通道位宽
        parameter ARCH_W = 8,               // 内部读地址通道位宽
        parameter RCH_W  = 8                // 内部读数据通道位宽
    )(
        //=====================================================================
        // 来自 Crossbar 内部交换矩阵的接口 (命名以 i_ 开头)
        //=====================================================================
        input  wire                       i_aclk,
        input  wire                       i_aresetn,
        input  wire                       i_srst,

        // 内部写地址通道
        input  wire                       i_awvalid,
        output logic                      i_awready,
        input  wire  [AWCH_W        -1:0] i_awch,

        // 内部写数据通道
        input  wire                       i_wvalid,
        output logic                      i_wready,
        input  wire                       i_wlast,
        input  wire  [WCH_W         -1:0] i_wch,

        // 内部写响应通道 (反向送入 Crossbar)
        output logic                      i_bvalid,
        input  wire                       i_bready,
        output logic [BCH_W         -1:0] i_bch,

        // 内部读地址通道
        input  wire                       i_arvalid,
        output logic                      i_arready,
        input  wire  [ARCH_W        -1:0] i_arch,

        // 内部读数据通道 (反向送入 Crossbar)
        output logic                      i_rvalid,
        input  wire                       i_rready,
        output logic                      i_rlast,
        output logic [RCH_W         -1:0] i_rch,

        //=====================================================================
        // 面向外部 Slave 从机的标准 AXI 接口 (命名以 o_ 开头)
        //=====================================================================
        input  wire                       o_aclk,
        input  wire                       o_aresetn,
        input  wire                       o_srst,

        // 外部写地址通道
        output logic                      o_awvalid,
        input  wire                       o_awready,
        output logic [AXI_ADDR_W    -1:0] o_awaddr,
        output logic [8             -1:0] o_awlen,
        output logic [3             -1:0] o_awsize,
        output logic [2             -1:0] o_awburst,
        output logic                      o_awlock,
        output logic [4             -1:0] o_awcache,
        output logic [3             -1:0] o_awprot,
        output logic [4             -1:0] o_awqos,
        output logic [4             -1:0] o_awregion,
        output logic [AXI_ID_W      -1:0] o_awid,
        output logic [AXI_AUSER_W   -1:0] o_awuser,

        // 外部写数据通道
        output logic                      o_wvalid,
        input  wire                       o_wready,
        output logic                      o_wlast,
        output logic [AXI_DATA_W    -1:0] o_wdata,
        output logic [AXI_DATA_W/8  -1:0] o_wstrb,
        output logic [AXI_WUSER_W   -1:0] o_wuser,

        // 外部写响应通道 (从机返回)
        input  wire                       o_bvalid,
        output logic                      o_bready,
        input  wire  [AXI_ID_W      -1:0] o_bid,
        input  wire  [2             -1:0] o_bresp,
        input  wire  [AXI_BUSER_W   -1:0] o_buser,

        // 外部读地址通道
        output logic                      o_arvalid,
        input  wire                       o_arready,
        output logic [AXI_ADDR_W    -1:0] o_araddr,
        output logic [8             -1:0] o_arlen,
        output logic [3             -1:0] o_arsize,
        output logic [2             -1:0] o_arburst,
        output logic                      o_arlock,
        output logic [4             -1:0] o_arcache,
        output logic [3             -1:0] o_arprot,
        output logic [4             -1:0] o_arqos,
        output logic [4             -1:0] o_arregion,
        output logic [AXI_ID_W      -1:0] o_arid,
        output logic [AXI_AUSER_W   -1:0] o_aruser,

        // 外部读数据通道 (从机返回)
        input  wire                       o_rvalid,
        output logic                      o_rready,
        input  wire  [AXI_ID_W      -1:0] o_rid,
        input  wire  [2             -1:0] o_rresp,
        input  wire  [AXI_DATA_W    -1:0] o_rdata,
        input  wire                       o_rlast,
        input  wire  [AXI_RUSER_W   -1:0] o_ruser
    );
    //-------------------------------------------------------------------------
    // 内部连线与解包缓冲信号定义
    //-------------------------------------------------------------------------
    logic [AWCH_W        -1:0] awch;
    logic [WCH_W         -1:0] wch;
    logic [BCH_W         -1:0] bch;
    logic [ARCH_W        -1:0] arch;
    logic [RCH_W         -1:0] rch;
    logic                      rlast;
    logic                      rlast_r;
    logic [AXI_ADDR_W    -1:0] awaddr;
    logic [AXI_ADDR_W    -1:0] araddr;
    logic                      wlast_r;

    logic [BCH_W         -1:0] bch_f;
    logic [RCH_W         -1:0] rch_f;

    generate

    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    if (SLV_CDC) begin: CDC_STAGE
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    localparam AW_ASIZE = (SLV_OSTDREQ_NUM==0) ? 2 :
                          (SLV_OSTDREQ_NUM<2)  ? 2 :
                          $clog2(SLV_OSTDREQ_NUM);

    localparam W_ASIZE = (SLV_OSTDREQ_NUM==0) ? 2 :
                         (SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE<2) ? 2 :
                         $clog2(SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE);

    localparam B_ASIZE = (SLV_OSTDREQ_NUM==0) ? 2 :
                         (SLV_OSTDREQ_NUM<2)  ? 2 :
                         $clog2(SLV_OSTDREQ_NUM);

    localparam AR_ASIZE = (SLV_OSTDREQ_NUM==0) ? 2 :
                          (SLV_OSTDREQ_NUM<2)  ? 2 :
                          $clog2(SLV_OSTDREQ_NUM);

    localparam R_ASIZE = (SLV_OSTDREQ_NUM==0) ? 2 :
                         (SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE<2) ? 2 :
                         $clog2(SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE);

    logic             aw_winc;
    logic             aw_full;
    logic             aw_rinc;
    logic             aw_empty;
    logic             w_winc;
    logic             w_full;
    logic             w_rinc;
    logic             w_empty;
    logic             b_winc;
    logic             b_full;
    logic             b_rinc;
    logic             b_empty;
    logic             ar_winc;
    logic             ar_full;
    logic             ar_rinc;
    logic             ar_empty;
    logic             r_winc;
    logic             r_full;
    logic             r_rinc;
    logic             r_empty;

    ///////////////////////////////////////////////////////////////////////////
    // Write Address Channel
    ///////////////////////////////////////////////////////////////////////////

    async_fifo
    #(
    .DSIZE       (AWCH_W),
    .ASIZE       (AW_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    aw_dcfifo
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (aw_winc),
    .wdata   (i_awch),
    .wfull   (aw_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (aw_rinc),
    .rdata   (awch),
    .rempty  (aw_empty),
    .arempty ()
    );

    assign i_awready = ~aw_full;
    assign aw_winc = i_awvalid & ~aw_full;

    assign o_awvalid = ~aw_empty;
    assign aw_rinc = ~aw_empty & o_awready;

    ///////////////////////////////////////////////////////////////////////////
    // Write Data Channel
    ///////////////////////////////////////////////////////////////////////////

    async_fifo
    #(
    .DSIZE       (WCH_W+1),
    .ASIZE       (W_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    w_dcfifo
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (w_winc),
    .wdata   ({i_wlast, i_wch}),
    .wfull   (w_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (w_rinc),
    .rdata   ({wlast_r, wch}),
    .rempty  (w_empty),
    .arempty ()
    );

    assign i_wready = ~w_full;
    assign w_winc = i_wvalid & ~w_full;

    assign o_wvalid = ~w_empty;
    assign o_wlast = (w_empty) ? 1'b0 : wlast_r;
    assign w_rinc = ~w_empty & o_wready;

    ///////////////////////////////////////////////////////////////////////////
    // Write Response Channel
    ///////////////////////////////////////////////////////////////////////////

    async_fifo
    #(
    .DSIZE       (BCH_W),
    .ASIZE       (B_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    b_dcfifo
    (
    .wclk    (o_aclk),
    .wrst_n  (o_aresetn),
    .winc    (b_winc),
    .wdata   (bch),
    .wfull   (b_full),
    .awfull  (),
    .rclk    (i_aclk),
    .rrst_n  (i_aresetn),
    .rinc    (b_rinc),
    .rdata   (bch_f),
    .rempty  (b_empty),
    .arempty ()
    );

    assign o_bready = ~b_full;
    assign b_winc = o_bvalid & ~b_full;

    assign i_bvalid = ~b_empty;
    assign i_bch = (b_empty) ? '0 : bch_f;
    assign b_rinc = ~b_empty & i_bready;

    ///////////////////////////////////////////////////////////////////////////
    // Read Address Channel
    ///////////////////////////////////////////////////////////////////////////

    async_fifo
    #(
    .DSIZE       (ARCH_W),
    .ASIZE       (AR_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    ar_dcfifo
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (ar_winc),
    .wdata   (i_arch),
    .wfull   (ar_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (ar_rinc),
    .rdata   (arch),
    .rempty  (ar_empty),
    .arempty ()
    );

    assign i_arready = ~ar_full;
    assign ar_winc = i_arvalid & ~ar_full;

    assign o_arvalid = ~ar_empty;
    assign ar_rinc = ~ar_empty & o_arready;

    ///////////////////////////////////////////////////////////////////////////
    // Read Data Channel
    ///////////////////////////////////////////////////////////////////////////

    async_fifo
    #(
    .DSIZE       (RCH_W+1),
    .ASIZE       (R_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    r_dcfifo
    (
    .wclk    (o_aclk),
    .wrst_n  (o_aresetn),
    .winc    (r_winc),
    .wdata   ({rlast, rch}),
    .wfull   (r_full),
    .awfull  (),
    .rclk    (i_aclk),
    .rrst_n  (i_aresetn),
    .rinc    (r_rinc),
    .rdata   ({rlast_r, rch_f}),
    .rempty  (r_empty),
    .arempty ()
    );

    assign o_rready = ~r_full;
    assign r_winc = o_rvalid & ~r_full;

    assign i_rvalid = ~r_empty;
    assign r_rinc = ~r_empty & i_rready;
    assign i_rlast = (r_empty) ? 1'b0 : rlast_r;

    always @ (*) begin

        // +2 = RESP width
        i_rch[AXI_ID_W+2 +: (RCH_W-AXI_ID_W-2)] = rch_f[AXI_ID_W+2 +: (RCH_W-AXI_ID_W-2)];

        // Tied off ID and RESP to ensure correct values
        if (r_empty) begin
            i_rch[0 +: (AXI_ID_W+2)] = '0;
        end else begin
            i_rch[0 +: (AXI_ID_W+2)] = rch_f[0 +: (AXI_ID_W+2)];
        end
    end


    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    end else if (SLV_OSTDREQ_NUM>0) begin: BUFF_STAGE
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    localparam PASS_THRU = 0;
    localparam AW_ASIZE = (SLV_OSTDREQ_NUM<2) ? 1 : $clog2(SLV_OSTDREQ_NUM);
    localparam W_ASIZE = (SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE<2) ? 1 : $clog2(SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE);
    localparam B_ASIZE = (SLV_OSTDREQ_NUM<2) ? 1 : $clog2(SLV_OSTDREQ_NUM);
    localparam AR_ASIZE = (SLV_OSTDREQ_NUM<2) ? 1 : $clog2(SLV_OSTDREQ_NUM);
    localparam R_ASIZE = (SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE<2) ? 1 : $clog2(SLV_OSTDREQ_NUM*SLV_OSTDREQ_SIZE);

    logic aw_full;
    logic aw_empty;
    logic w_full;
    logic w_empty;
    logic ar_full;
    logic ar_empty;
    logic r_full;
    logic r_empty;
    logic b_full;
    logic b_empty;

    ///////////////////////////////////////////////////////////////////////////
    // Write Address Channel
    ///////////////////////////////////////////////////////////////////////////

    axicb_scfifo
    #(
    .PASS_THRU  (PASS_THRU),
    .ADDR_WIDTH (AW_ASIZE),
    .DATA_WIDTH (AWCH_W)
    )
    aw_scfifo
    (
    .aclk     (i_aclk),
    .aresetn  (i_aresetn),
    .srst     (i_srst),
    .flush    (1'b0),
    .data_in  (i_awch),
    .push     (i_awvalid),
    .full     (aw_full),
    .data_out (awch),
    .pull     (o_awready),
    .empty    (aw_empty)
    );
    assign i_awready = ~aw_full;
    assign o_awvalid = ~aw_empty;

    ///////////////////////////////////////////////////////////////////////////
    // Write Data Channel
    ///////////////////////////////////////////////////////////////////////////

    axicb_scfifo
    #(
    .PASS_THRU  (PASS_THRU),
    .ADDR_WIDTH (W_ASIZE),
    .DATA_WIDTH (WCH_W+1)
    )
    w_scfifo
    (
    .aclk     (i_aclk),
    .aresetn  (i_aresetn),
    .srst     (i_srst),
    .flush    (1'b0),
    .data_in  ({i_wlast, i_wch}),
    .push     (i_wvalid),
    .full     (w_full),
    .data_out ({wlast_r, wch}),
    .pull     (o_wready),
    .empty    (w_empty)
    );
    assign i_wready = ~w_full;
    assign o_wvalid = ~w_empty;
    assign o_wlast = (w_empty) ? 1'b0 : wlast_r;

    ///////////////////////////////////////////////////////////////////////////
    // Write Response Channel
    ///////////////////////////////////////////////////////////////////////////

    axicb_scfifo
    #(
    .PASS_THRU  (PASS_THRU),
    .ADDR_WIDTH (B_ASIZE),
    .DATA_WIDTH (BCH_W)
    )
    b_scfifo
    (
    .aclk     (o_aclk),
    .aresetn  (o_aresetn),
    .srst     (o_srst),
    .flush    (1'b0),
    .data_in  (bch),
    .push     (o_bvalid),
    .full     (b_full),
    .data_out (bch_f),
    .pull     (i_bready),
    .empty    (b_empty)
    );

    assign i_bvalid = ~b_empty;
    assign i_bch = (b_empty) ? '0 : bch_f;
    assign o_bready = ~b_full;

    ///////////////////////////////////////////////////////////////////////////
    // Read Address Channel
    ///////////////////////////////////////////////////////////////////////////

    axicb_scfifo
    #(
    .PASS_THRU  (PASS_THRU),
    .ADDR_WIDTH (AR_ASIZE),
    .DATA_WIDTH (ARCH_W)
    )
    ar_scfifo
    (
    .aclk     (i_aclk),
    .aresetn  (i_aresetn),
    .srst     (i_srst),
    .flush    (1'b0),
    .data_in  (i_arch),
    .push     (i_arvalid),
    .full     (ar_full),
    .data_out (arch),
    .pull     (o_arready),
    .empty    (ar_empty)
    );

    assign i_arready = ~ar_full;
    assign o_arvalid = ~ar_empty;

    ///////////////////////////////////////////////////////////////////////////
    // Read Data Channel
    ///////////////////////////////////////////////////////////////////////////

    axicb_scfifo
    #(
    .PASS_THRU  (PASS_THRU),
    .ADDR_WIDTH (R_ASIZE),
    .DATA_WIDTH (RCH_W+1)
    )
    r_scfifo
    (
    .aclk     (o_aclk),
    .aresetn  (o_aresetn),
    .srst     (o_srst),
    .flush    (1'b0),
    .data_in  ({rlast, rch}),
    .push     (o_rvalid),
    .full     (r_full),
    .data_out ({rlast_r,rch_f}),
    .pull     (i_rready),
    .empty    (r_empty)
    );

    assign i_rvalid = ~r_empty;
    assign i_rlast = (r_empty) ? 1'b0 : rlast_r;
    assign o_rready = ~r_full;

    always @ (*) begin

        // +2 = RESP width
        i_rch[AXI_ID_W+2 +: (RCH_W-AXI_ID_W-2)] = rch_f[AXI_ID_W+2 +: (RCH_W-AXI_ID_W-2)];

        // Tied off ID and RESP to ensure correct values
        if (r_empty) begin
            i_rch[0 +: (AXI_ID_W+2)] = '0;
        end else begin
            i_rch[0 +: (AXI_ID_W+2)] = rch_f[0 +: (AXI_ID_W+2)];
        end
    end

    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    end else begin: NO_CDC_NO_BUFFERING
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    assign o_awvalid = i_awvalid;
    assign i_awready = o_awready;
    assign awch = i_awch;

    assign o_wvalid = i_wvalid;
    assign i_wready = o_wready;
    assign o_wlast = i_wlast;

    assign wch = i_wch;

    assign i_bvalid = o_bvalid;
    assign o_bready = i_bready;
    assign i_bch = bch;

    assign o_arvalid = i_arvalid;
    assign i_arready = o_arready;
    assign arch = i_arch;

    assign i_rvalid = o_rvalid;
    assign o_rready = i_rready;
    assign i_rlast = rlast;
    assign i_rch = rch;

    end
    endgenerate

    generate

    if (AXI_SIGNALING==0) begin : AXI4LITE_MODE

        if (USER_SUPPORT>0 && AXI_AUSER_W>0) begin: AUSER_ON

            assign {
                o_awuser,
                o_awprot,
                o_awid,
                awaddr
            } = awch;

            assign {
                o_aruser,
                o_arprot,
                o_arid,
                araddr
            }  = arch;

            end else begin: AUSER_OFF

            assign {
                o_awprot,
                o_awid,
                awaddr
            } = awch;

            assign {
                o_arprot,
                o_arid,
                araddr
            }  = arch;

            end

        end else begin : AXI4_MODE

            if (USER_SUPPORT>0 && AXI_AUSER_W>0) begin: AUSER_ON

            assign {
                o_awuser,
                o_awregion,
                o_awqos,
                o_awprot,
                o_awcache,
                o_awlock,
                o_awburst,
                o_awsize,
                o_awlen,
                o_awid,
                awaddr
            } = awch;

            assign {
                o_aruser,
                o_arregion,
                o_arqos,
                o_arprot,
                o_arcache,
                o_arlock,
                o_arburst,
                o_arsize,
                o_arlen,
                o_arid,
                araddr
            } = arch;

            end else begin: AUSER_OFF

            assign {
                o_awregion,
                o_awqos,
                o_awprot,
                o_awcache,
                o_awlock,
                o_awburst,
                o_awsize,
                o_awlen,
                o_awid,
                awaddr
            } = awch;

            assign {
                o_arregion,
                o_arqos,
                o_arprot,
                o_arcache,
                o_arlock,
                o_arburst,
                o_arsize,
                o_arlen,
                o_arid,
                araddr
            } = arch;
        end

    end

    endgenerate

    generate

        if (KEEP_BASE_ADDR>0) begin: KEEP_BASE_ADDRESS
            assign o_awaddr = awaddr;
            assign o_araddr = araddr;
        end else begin: REMOVE_BASE_ADDRESS
            assign o_awaddr = awaddr - BASE_ADDR[0+:AXI_ADDR_W];
            assign o_araddr = araddr - BASE_ADDR[0+:AXI_ADDR_W];
        end

    endgenerate

    generate

        if (USER_SUPPORT>0 && AXI_WUSER_W>0) begin: WUSER_ON
            assign{o_wuser, o_wstrb, o_wdata} = wch;
        end else begin: WUSER_OFF
            assign {o_wstrb, o_wdata} = wch;
        end

    endgenerate

    generate
        if (USER_SUPPORT>0 && AXI_BUSER_W>0) begin: BUSER_ON
            assign bch = {o_buser, o_bresp, o_bid};
        end else begin: BUSER_OFF
            assign bch = {o_bresp, o_bid};
        end
    endgenerate

    generate
        if (USER_SUPPORT>0 && AXI_RUSER_W>0) begin: RUSER_ON
            assign rch = {o_ruser, o_rdata, o_rresp, o_rid};
        end else begin: RUSER_OFF
            assign rch = {o_rdata, o_rresp, o_rid};
        end
    endgenerate

    generate
        if (AXI_SIGNALING==0) begin: AXI4_LITE_RLAST
            assign rlast = 1'b1;
        end else begin: AXI4_RLAST
            assign rlast = o_rlast;
        end
    endgenerate

endmodule

`resetall
