//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_slv_if.sv
// 文件功能: 发起端接口适配器 (Slave Interface / Master Port Adapter)
// 模块描述:
//   本模块位于 AXI Crossbar 内部交换矩阵与外部 Master (发起方) 之间。
//   在外部 Master 视角下，它是接收 AXI 请求的 Slave 接口；
//   在 Crossbar 内部视角下，它是将外部请求转换、打包并注入内部交叉矩阵的入口适配层。
//
// 核心工作机制与设计要点:
//   1. 通道字段打包压缩 (Channel Flattening & Packing):
//      - 外部 AXI 协议 5 个通道包含数十根离散控制、属性及数据线。
//      - 本模块在入口处将离散信号按照高位到低位的规范，紧凑拼接为单根扁平总线:
//        * AWCH = {USER, REGION, QOS, PROT, CACHE, LOCK, BURST, SIZE, LEN, ID, ADDR}
//        * ARCH = {USER, REGION, QOS, PROT, CACHE, LOCK, BURST, SIZE, LEN, ID, ADDR}
//        * WCH  = {USER, STRB, DATA}
//        * BCH  = {USER, RESP, ID}
//        * RCH  = {USER, DATA, RESP, ID}
//      - 大幅降低内部交换路由矩阵 (Switch Top) 的连线拥塞与多路选择器面积开销。
//   2. 协议模式支持 (AXI4 vs AXI4-Lite):
//      - 当 AXI_SIGNALING=0 时运行于 AXI4-Lite 模式: 剥离 LEN/SIZE/BURST/LOCK 等突发字段，
//        并将 WLAST 信号内部恒置为 1'b1。
//      - 当 AXI_SIGNALING=1 时运行于完整 AXI4 模式，保留全套突发与 QoS 字段。
//   3. 双向数据流向:
//      - 前向通道 (AW, W, AR): Master 发送 -> 打包压入 FIFO 或直通 -> 送入 Crossbar。
//      - 反向通道 (B, R): Crossbar 内部响应 -> 接收并从 BCH/RCH 解包为离散信号 -> 返回 Master。
//   4. 三种可选缓冲模式:
//      - MST_CDC=1: 跨时钟域异步 FIFO 缓冲 (针对 Master 与 Crossbar 异步时钟应用场景)。
//      - MST_OSTDREQ_NUM>0: 单时钟同步 FIFO 缓冲 (axicb_scfifo)，支持多个在途事务排队。
//      - 否则: 纯零延迟组合直通 (NO_CDC_NO_BUFFERING)。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_slv_if

    #(
        //---------------------------------------------------------------------
        // 全局总线位宽参数
        //---------------------------------------------------------------------
        parameter AXI_ADDR_W = 8,           // 地址总线位宽 (单位: bit)
        parameter AXI_ID_W   = 8,           // 事务 ID 位宽
        parameter AXI_DATA_W = 8,           // 数据总线位宽 (如 32, 64 等)

        // 下游连接的目标从机 (Slave) 数量
        parameter SLV_NB = 4,

        // AXI 协议模式选择: 0 = AXI4-Lite, 1 = 完整 AXI4
        parameter AXI_SIGNALING = 0,

        // 跨时钟域使能: 1=使能异步 FIFO 跨时钟, 0=同频同步时钟
        parameter MST_CDC = 0,
        // 发起方支持的最大在途事务数 (Outstanding Requests Number)
        parameter MST_OSTDREQ_NUM = 4,
        // 单个在途请求的数据相位深度
        parameter MST_OSTDREQ_SIZE = 1,

        // USER 扩展用户自定义字段支持: 0=关闭, 1=开启
        parameter USER_SUPPORT = 0,
        parameter AXI_AUSER_W  = 0,         // AW/AR 通道用户字段位宽
        parameter AXI_WUSER_W  = 0,         // W 通道用户字段位宽
        parameter AXI_BUSER_W  = 0,         // B 通道用户字段位宽
        parameter AXI_RUSER_W  = 0,         // R 通道用户字段位宽

        // 内部打包后的各通道扁平位宽 (由外部计算并传入)
        parameter AWCH_W = 8,               // 打包后写地址通道位宽
        parameter WCH_W  = 8,               // 打包后写数据通道位宽
        parameter BCH_W  = 8,               // 打包后写响应通道位宽
        parameter ARCH_W = 8,               // 打包后读地址通道位宽
        parameter RCH_W  = 8                // 打包后读数据通道位宽
    )(
        //=====================================================================
        // 面向外部 Master 的标准 AXI 接口 (命名以 i_ 开头)
        //=====================================================================
        // 时钟与复位
        input  wire                       i_aclk,
        input  wire                       i_aresetn,
        input  wire                       i_srst,

        // 写地址通道 (AW Channel)
        input  wire                       i_awvalid,
        output logic                      i_awready,
        input  wire  [AXI_ADDR_W    -1:0] i_awaddr,
        input  wire  [8             -1:0] i_awlen,
        input  wire  [3             -1:0] i_awsize,
        input  wire  [2             -1:0] i_awburst,
        input  wire                       i_awlock,
        input  wire  [4             -1:0] i_awcache,
        input  wire  [3             -1:0] i_awprot,
        input  wire  [4             -1:0] i_awqos,
        input  wire  [4             -1:0] i_awregion,
        input  wire  [AXI_ID_W      -1:0] i_awid,
        input  wire  [AXI_AUSER_W   -1:0] i_awuser,

        // 写数据通道 (W Channel)
        input  wire                       i_wvalid,
        output logic                      i_wready,
        input  wire                       i_wlast,
        input  wire  [AXI_DATA_W    -1:0] i_wdata,
        input  wire  [AXI_DATA_W/8  -1:0] i_wstrb,
        input  wire  [AXI_WUSER_W   -1:0] i_wuser,

        // 写响应通道 (B Channel) - 反向输入至外部 Master
        output logic                      i_bvalid,
        input  wire                       i_bready,
        output logic [AXI_ID_W      -1:0] i_bid,
        output logic [2             -1:0] i_bresp,
        output logic [AXI_BUSER_W   -1:0] i_buser,

        // 读地址通道 (AR Channel)
        input  wire                       i_arvalid,
        output logic                      i_arready,
        input  wire  [AXI_ADDR_W    -1:0] i_araddr,
        input  wire  [8             -1:0] i_arlen,
        input  wire  [3             -1:0] i_arsize,
        input  wire  [2             -1:0] i_arburst,
        input  wire                       i_arlock,
        input  wire  [4             -1:0] i_arcache,
        input  wire  [3             -1:0] i_arprot,
        input  wire  [4             -1:0] i_arqos,
        input  wire  [4             -1:0] i_arregion,
        input  wire  [AXI_ID_W      -1:0] i_arid,
        input  wire  [AXI_AUSER_W   -1:0] i_aruser,

        // 读数据通道 (R Channel) - 反向输入至外部 Master
        output logic                      i_rvalid,
        input  wire                       i_rready,
        output logic [AXI_ID_W      -1:0] i_rid,
        output logic [2             -1:0] i_rresp,
        output logic [AXI_DATA_W    -1:0] i_rdata,
        output logic                      i_rlast,
        output logic [AXI_RUSER_W   -1:0] i_ruser,

        //=====================================================================
        // 面向内部 Crossbar 交换矩阵的接口 (命名以 o_ 开头)
        //=====================================================================
        input  wire                       o_aclk,
        input  wire                       o_aresetn,
        input  wire                       o_srst,

        // 打包后的写地址通道
        output logic                      o_awvalid,
        input  wire                       o_awready,
        output logic [AWCH_W        -1:0] o_awch,

        // 打包后的写数据通道
        output logic                      o_wvalid,
        input  wire                       o_wready,
        output logic                      o_wlast,
        output logic [WCH_W         -1:0] o_wch,

        // 打包后的写响应通道 (来自内部矩阵)
        input  wire                       o_bvalid,
        output logic                      o_bready,
        input  wire  [BCH_W         -1:0] o_bch,

        // 打包后的读地址通道
        output logic                      o_arvalid,
        input  wire                       o_arready,
        output logic [ARCH_W        -1:0] o_arch,

        // 打包后的读数据通道 (来自内部矩阵)
        input  wire                       o_rvalid,
        output logic                      o_rready,
        input  wire                       o_rlast,
        input  wire  [RCH_W         -1:0] o_rch
    );
    //-------------------------------------------------------------------------
    // 内部总线与暂存信号定义
    //-------------------------------------------------------------------------
    logic [AWCH_W        -1:0] awch;     // 本地打包生成的写地址通道复合总线
    logic [AWCH_W        -1:0] awch_f;   // 从 FIFO 读出的写地址通道总线
    logic [WCH_W         -1:0] wch;      // 本地打包生成的写数据通道复合总线
    logic [BCH_W         -1:0] bch;      // 准备解包返回给 Master 的写响应总线
    logic [ARCH_W        -1:0] arch;     // 本地打包生成的读地址通道复合总线
    logic [AWCH_W        -1:0] arch_f;   // 从 FIFO 读出的读地址通道总线
    logic [RCH_W         -1:0] rch;      // 准备解包返回给 Master 的读数据总线
    logic                      wlast;    // 经协议适配后内部统一的 WLAST 信号
    logic                      wlast_r;  // 从写数据 FIFO 中弹出的 WLAST 标记

    //=========================================================================
    // 1. 写/读地址通道字段打包逻辑 (AW & AR Channel Packing)
    //=========================================================================
    generate

    if (AXI_SIGNALING==0) begin : AXI4LITE_MODE

        if (USER_SUPPORT>0 && AXI_AUSER_W>0) begin: AUSER_ON

        assign awch = {
            i_awuser,
            i_awprot,
            i_awid,
            i_awaddr
        };

        assign arch = {
            i_aruser,
            i_arprot,
            i_arid,
            i_araddr
        };

        end else begin: AUSER_OFF

        assign awch = {
            i_awprot,
            i_awid,
            i_awaddr
        };

        assign arch = {
            i_arprot,
            i_arid,
            i_araddr
        };

        end

    end else begin : AXI4_MODE

        if (USER_SUPPORT>0 && AXI_AUSER_W>0) begin: AUSER_ON

        assign awch = {
            i_awuser,
            i_awregion,
            i_awqos,
            i_awprot,
            i_awcache,
            i_awlock,
            i_awburst,
            i_awsize,
            i_awlen,
            i_awid,
            i_awaddr
        };

        assign arch = {
            i_aruser,
            i_arregion,
            i_arqos,
            i_arprot,
            i_arcache,
            i_arlock,
            i_arburst,
            i_arsize,
            i_arlen,
            i_arid,
            i_araddr
        };

        end else begin: AUSER_OFF

        assign awch = {
            i_awregion,
            i_awqos,
            i_awprot,
            i_awcache,
            i_awlock,
            i_awburst,
            i_awsize,
            i_awlen,
            i_awid,
            i_awaddr
        };

        assign arch = {
            i_arregion,
            i_arqos,
            i_arprot,
            i_arcache,
            i_arlock,
            i_arburst,
            i_arsize,
            i_arlen,
            i_arid,
            i_araddr
        };

        end
    end
    endgenerate

    generate
        if (USER_SUPPORT>0 && AXI_WUSER_W>0) begin: WUSER_ON
            assign wch = {i_wuser, i_wstrb, i_wdata};
        end else begin: WUSER_OFF
            assign wch = {i_wstrb, i_wdata};
        end
    endgenerate

    generate
        if (USER_SUPPORT>0 && AXI_BUSER_W>0) begin: BUSER_ON
            assign {i_buser, i_bresp, i_bid} = bch;
        end else begin: BUSER_OFF
            assign {i_bresp, i_bid} = bch;
        end
    endgenerate

    generate
        if (USER_SUPPORT>0 && AXI_RUSER_W>0) begin: RUSER_ON
            assign {i_ruser, i_rdata, i_rresp, i_rid} = rch;
        end else begin: RUSER_OFF
            assign {i_rdata, i_rresp, i_rid} = rch;
        end
    endgenerate

    generate
        if (AXI_SIGNALING==0) begin: AXI4_LITE_WLAST
            assign wlast = 1'b1;
        end else begin: AXI4_WLAST
            assign wlast = i_wlast;
        end
    endgenerate

    generate

    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    if (MST_CDC > 0) begin: CDC_STAGE
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    localparam AW_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 :
                          (MST_OSTDREQ_NUM<2)  ? 2 :
                          $clog2(MST_OSTDREQ_NUM);

    localparam W_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 :
                         (MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE<2) ? 2 :
                         $clog2(MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE);

    localparam B_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 :
                         (MST_OSTDREQ_NUM<2)  ? 2 :
                         $clog2(MST_OSTDREQ_NUM);

    localparam AR_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 :
                          (MST_OSTDREQ_NUM<2)  ? 2 :
                          $clog2(MST_OSTDREQ_NUM);

    localparam R_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 :
                         (MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE<2) ? 2 :
                         $clog2(MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE);

    logic aw_winc;
    logic aw_full;
    logic aw_rinc;
    logic aw_empty;
    logic w_winc;
    logic w_full;
    logic w_rinc;
    logic w_empty;
    logic b_winc;
    logic b_full;
    logic b_rinc;
    logic b_empty;
    logic ar_winc;
    logic ar_full;
    logic ar_rinc;
    logic ar_empty;
    logic r_winc;
    logic r_full;
    logic r_rinc;
    logic r_empty;

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
    .wdata   (awch),
    .wfull   (aw_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (aw_rinc),
    .rdata   (awch_f),
    .rempty  (aw_empty),
    .arempty ()
    );

    assign i_awready = ~aw_full;
    assign aw_winc = i_awvalid & ~aw_full;

    assign o_awvalid = ~aw_empty;

    always @ (*) begin
        o_awch[AXI_ADDR_W +: (AWCH_W-AXI_ADDR_W)] = awch_f[AXI_ADDR_W +: (AWCH_W-AXI_ADDR_W)];
        // tied off AWADDR to avoid x in switches
        o_awch[0 +: AXI_ADDR_W] = (aw_empty) ? '0 : awch_f[0 +: AXI_ADDR_W];;
    end

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
    .wdata   ({wlast, wch}),
    .wfull   (w_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (w_rinc),
    .rdata   ({wlast_r, o_wch}),
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
    .wdata   (o_bch),
    .wfull   (b_full),
    .awfull  (),
    .rclk    (i_aclk),
    .rrst_n  (i_aresetn),
    .rinc    (b_rinc),
    .rdata   (bch),
    .rempty  (b_empty),
    .arempty ()
    );

    assign o_bready = ~b_full;
    assign b_winc = o_bvalid & ~b_full;

    assign i_bvalid = ~b_empty;
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
    .wdata   (arch),
    .wfull   (ar_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (ar_rinc),
    .rdata   (arch_f),
    .rempty  (ar_empty),
    .arempty ()
    );

    assign i_arready = ~ar_full;
    assign ar_winc = i_arvalid & ~ar_full;

    assign o_arvalid = ~ar_empty;
    assign ar_rinc = ~ar_empty & o_arready;

    always @ (*) begin
        o_arch[AXI_ADDR_W +: (ARCH_W-AXI_ADDR_W)] = arch_f[AXI_ADDR_W +: (ARCH_W-AXI_ADDR_W)];
        // tied off ARADDR to avoid x in switches
        o_arch[0 +: AXI_ADDR_W] = (ar_empty) ? '0 : arch_f[0 +: AXI_ADDR_W];;
    end

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
    .wdata   ({o_rlast, o_rch}),
    .wfull   (r_full),
    .awfull  (),
    .rclk    (i_aclk),
    .rrst_n  (i_aresetn),
    .rinc    (r_rinc),
    .rdata   ({i_rlast, rch}),
    .rempty  (r_empty),
    .arempty ()
    );

    assign o_rready = ~r_full;
    assign r_winc = o_rvalid & ~r_full;

    assign i_rvalid = ~r_empty;
    assign r_rinc = ~r_empty & i_rready;


    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    end else if (MST_OSTDREQ_NUM > 0) begin: BUFF_STAGE
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    localparam PASS_THRU = 0;
    localparam AW_ASIZE = (MST_OSTDREQ_NUM<2) ? 1 : $clog2(MST_OSTDREQ_NUM);
    localparam W_ASIZE = (MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE<2) ? 1 : $clog2(MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE);
    localparam B_ASIZE = (MST_OSTDREQ_NUM<2) ? 1 : $clog2(MST_OSTDREQ_NUM);
    localparam AR_ASIZE = (MST_OSTDREQ_NUM<2) ? 1 : $clog2(MST_OSTDREQ_NUM);
    localparam R_ASIZE = (MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE<2) ? 1 : $clog2(MST_OSTDREQ_NUM*MST_OSTDREQ_SIZE);

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
    .data_in  (awch),
    .push     (i_awvalid),
    .full     (aw_full),
    .data_out (awch_f),
    .pull     (o_awready),
    .empty    (aw_empty)
    );

    always @ (*) begin
        o_awch[AXI_ADDR_W +: (AWCH_W-AXI_ADDR_W)] = awch_f[AXI_ADDR_W +: (AWCH_W-AXI_ADDR_W)];
        // tied off AWADDR to avoid x in switches
        o_awch[0 +: AXI_ADDR_W] = (aw_empty) ? '0 : awch_f[0 +: AXI_ADDR_W];;
    end

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
    .data_in  ({wlast, wch}),
    .push     (i_wvalid),
    .full     (w_full),
    .data_out ({wlast_r, o_wch}),
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
    .data_in  (o_bch),
    .push     (o_bvalid),
    .full     (b_full),
    .data_out (bch),
    .pull     (i_bready),
    .empty    (b_empty)
    );

    assign i_bvalid = ~b_empty;
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
    .data_in  (arch),
    .push     (i_arvalid),
    .full     (ar_full),
    .data_out (arch_f),
    .pull     (o_arready),
    .empty    (ar_empty)
    );

    assign i_arready = ~ar_full;
    assign o_arvalid = ~ar_empty;

    always @ (*) begin
        o_arch[AXI_ADDR_W +: (ARCH_W-AXI_ADDR_W)] = arch_f[AXI_ADDR_W +: (ARCH_W-AXI_ADDR_W)];
        // tied off ARADDR to avoid x in switches
        o_arch[0 +: AXI_ADDR_W] = (ar_empty) ? '0 : arch_f[0 +: AXI_ADDR_W];;
    end

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
    .data_in  ({o_rlast,o_rch}),
    .push     (o_rvalid),
    .full     (r_full),
    .data_out ({i_rlast, rch}),
    .pull     (i_rready),
    .empty    (r_empty)
    );

    assign i_rvalid = ~r_empty;
    assign o_rready = ~r_full;


    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////
    end else begin: NO_CDC_NO_BUFFERING
    ///////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////

    assign o_awvalid = i_awvalid;
    assign i_awready = o_awready;

    assign o_awch = awch;

    assign o_wvalid = i_wvalid;
    assign i_wready = o_wready;
    assign o_wlast = wlast;

    assign o_wch = wch;

    assign i_bvalid = o_bvalid;
    assign o_bready = i_bready;

    assign bch = o_bch;

    assign o_arvalid = i_arvalid;
    assign i_arready = o_arready;

    assign o_arch = arch;

    assign i_rvalid = o_rvalid;
    assign o_rready = i_rready;
    assign i_rlast = o_rlast;

    assign rch = o_rch;

    end

    endgenerate

endmodule

`resetall
