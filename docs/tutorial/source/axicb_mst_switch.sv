//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_mst_switch.sv
// 文件功能: 目标端综合读写交换单元 (Master Combined Switch Wrapper)
// 模块描述:
//   本模块针对单个 Slave 目标从机，汇集来自多个 Master 的读写请求并仲裁:
//   1. 例化 axicb_mst_switch_wr: 处理多个 Master 针对该从机的 AW 轮询仲裁、
//      W 突发来源锁定以及 B 响应反向解复用。
//   2. 例化 axicb_mst_switch_rd: 处理多个 Master 针对该从机的 AR 轮询仲裁与
//      R 读数据流按 RID 反向分发。
//   读写两个仲裁单元各自独立运行，实现了读写并发执行的高性能互联特性。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_mst_switch

    #(
        // ID width in bits
        parameter AXI_ID_W = 8,
        // Data width in bits
        parameter AXI_DATA_W = 8,

        // Number of master(s)
        parameter MST_NB = 4,

        // Activate the timer to avoid deadlock
        parameter TIMEOUT_ENABLE = 1,

        // Masters ID mask
        parameter [AXI_ID_W-1:0] MST0_ID_MASK = 'h00,
        parameter [AXI_ID_W-1:0] MST1_ID_MASK = 'h10,
        parameter [AXI_ID_W-1:0] MST2_ID_MASK = 'h20,
        parameter [AXI_ID_W-1:0] MST3_ID_MASK = 'h30,

        // Masters priorities
        parameter MST0_PRIORITY = 0,
        parameter MST1_PRIORITY = 0,
        parameter MST2_PRIORITY = 0,
        parameter MST3_PRIORITY = 0,

        // Channels' width (concatenated)
        parameter AWCH_W = 8,
        parameter WCH_W = 8,
        parameter BCH_W = 8,
        parameter ARCH_W = 8,
        parameter RCH_W = 8
    )(
        // Global interface
        input  wire                           aclk,
        input  wire                           aresetn,
        input  wire                           srst,
        // Input interfaces from masters
        input  wire  [MST_NB            -1:0] i_awvalid,
        output logic [MST_NB            -1:0] i_awready,
        input  wire  [MST_NB*AWCH_W     -1:0] i_awch,
        input  wire  [MST_NB            -1:0] i_wvalid,
        output logic [MST_NB            -1:0] i_wready,
        input  wire  [MST_NB            -1:0] i_wlast,
        input  wire  [MST_NB*WCH_W      -1:0] i_wch,
        output logic [MST_NB            -1:0] i_bvalid,
        input  wire  [MST_NB            -1:0] i_bready,
        output logic [BCH_W             -1:0] i_bch,
        input  wire  [MST_NB            -1:0] i_arvalid,
        output logic [MST_NB            -1:0] i_arready,
        input  wire  [MST_NB*ARCH_W     -1:0] i_arch,
        output logic [MST_NB            -1:0] i_rvalid,
        input  wire  [MST_NB            -1:0] i_rready,
        output logic [MST_NB            -1:0] i_rlast,
        output logic [RCH_W             -1:0] i_rch,
        // Output interfaces to slaves
        output logic                          o_awvalid,
        input  wire                           o_awready,
        output logic [AWCH_W            -1:0] o_awch,
        output logic                          o_wvalid,
        input  wire                           o_wready,
        output logic                          o_wlast,
        output logic [WCH_W             -1:0] o_wch,
        input  wire                           o_bvalid,
        output logic                          o_bready,
        input  wire  [BCH_W             -1:0] o_bch,
        output logic                          o_arvalid,
        input  wire                           o_arready,
        output logic [ARCH_W            -1:0] o_arch,
        input  wire                           o_rvalid,
        output logic                          o_rready,
        input  wire                           o_rlast,
        input  wire  [RCH_W             -1:0] o_rch
    );

    axicb_mst_switch_wr
    #(
        .AXI_ID_W       (AXI_ID_W),
        .AXI_DATA_W     (AXI_DATA_W),
        .MST_NB         (MST_NB),
        .TIMEOUT_ENABLE (TIMEOUT_ENABLE),
        .MST0_ID_MASK   (MST0_ID_MASK),
        .MST1_ID_MASK   (MST1_ID_MASK),
        .MST2_ID_MASK   (MST2_ID_MASK),
        .MST3_ID_MASK   (MST3_ID_MASK),
        .MST0_PRIORITY  (MST0_PRIORITY),
        .MST1_PRIORITY  (MST1_PRIORITY),
        .MST2_PRIORITY  (MST2_PRIORITY),
        .MST3_PRIORITY  (MST3_PRIORITY),
        .AWCH_W         (AWCH_W),
        .WCH_W          (WCH_W),
        .BCH_W          (BCH_W),
        .ARCH_W         (ARCH_W),
        .RCH_W          (RCH_W)
    )
    mst_switch_wr
    (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .srst      (srst),
        .i_awvalid (i_awvalid),
        .i_awready (i_awready),
        .i_awch    (i_awch),
        .i_wvalid  (i_wvalid),
        .i_wready  (i_wready),
        .i_wlast   (i_wlast),
        .i_wch     (i_wch),
        .i_bvalid  (i_bvalid),
        .i_bready  (i_bready),
        .i_bch     (i_bch),
        .o_awvalid (o_awvalid),
        .o_awready (o_awready),
        .o_awch    (o_awch),
        .o_wvalid  (o_wvalid),
        .o_wready  (o_wready),
        .o_wlast   (o_wlast),
        .o_wch     (o_wch),
        .o_bvalid  (o_bvalid),
        .o_bready  (o_bready),
        .o_bch     (o_bch)
    );

    axicb_mst_switch_rd
    #(
        .AXI_ID_W       (AXI_ID_W),
        .AXI_DATA_W     (AXI_DATA_W),
        .MST_NB         (MST_NB),
        .TIMEOUT_ENABLE (TIMEOUT_ENABLE),
        .MST0_ID_MASK   (MST0_ID_MASK),
        .MST1_ID_MASK   (MST1_ID_MASK),
        .MST2_ID_MASK   (MST2_ID_MASK),
        .MST3_ID_MASK   (MST3_ID_MASK),
        .MST0_PRIORITY  (MST0_PRIORITY),
        .MST1_PRIORITY  (MST1_PRIORITY),
        .MST2_PRIORITY  (MST2_PRIORITY),
        .MST3_PRIORITY  (MST3_PRIORITY),
        .AWCH_W         (AWCH_W),
        .WCH_W          (WCH_W),
        .BCH_W          (BCH_W),
        .ARCH_W         (ARCH_W),
        .RCH_W          (RCH_W)
    )
    mst_switch_rd
    (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .srst      (srst),
        .i_arvalid (i_arvalid),
        .i_arready (i_arready),
        .i_arch    (i_arch),
        .i_rvalid  (i_rvalid),
        .i_rready  (i_rready),
        .i_rlast   (i_rlast),
        .i_rch     (i_rch),
        .o_arvalid (o_arvalid),
        .o_arready (o_arready),
        .o_arch    (o_arch),
        .o_rvalid  (o_rvalid),
        .o_rready  (o_rready),
        .o_rlast   (o_rlast),
        .o_rch     (o_rch)
    );

endmodule

`resetall
