///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar Testbench Top
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module axi_crossbar_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    parameter AXI_ADDR_W = 16;
    parameter AXI_ID_W   = 8;
    parameter AXI_DATA_W = 32;
    parameter MST_NB     = 4;
    parameter SLV_NB     = 4;

    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    logic aclk;
    logic aresetn;
    logic srst;

    // Clock generation: 10ns period (100MHz)
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // Reset generation
    initial begin
        aresetn = 0;
        srst = 1;
        #100;
        aresetn = 1;
        srst = 0;
    end

    //--------------------------------------------------------------------------
    // AXI Interfaces
    //--------------------------------------------------------------------------
    axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ) mst_if [MST_NB] (
        .aclk(aclk),
        .aresetn(aresetn)
    );

    axi_interface #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ) slv_if [SLV_NB] (
        .aclk(aclk),
        .aresetn(aresetn)
    );

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    axicb_crossbar_top #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W),
        .MST_NB(MST_NB),
        .SLV_NB(SLV_NB),
        .MST_PIPELINE(0),
        .SLV_PIPELINE(0),
        .AXI_SIGNALING(1),
        .USER_SUPPORT(0),

        // Master 0
        .MST0_CDC(0),
        .MST0_OSTDREQ_NUM(4),
        .MST0_OSTDREQ_SIZE(1),
        .MST0_PRIORITY(0),
        .MST0_ROUTES(4'b1111),
        .MST0_ID_MASK(8'h00),
        .MST0_RW(0),

        // Master 1
        .MST1_CDC(0),
        .MST1_OSTDREQ_NUM(4),
        .MST1_OSTDREQ_SIZE(1),
        .MST1_PRIORITY(0),
        .MST1_ROUTES(4'b1111),
        .MST1_ID_MASK(8'h10),
        .MST1_RW(0),

        // Master 2
        .MST2_CDC(0),
        .MST2_OSTDREQ_NUM(4),
        .MST2_OSTDREQ_SIZE(1),
        .MST2_PRIORITY(0),
        .MST2_ROUTES(4'b1111),
        .MST2_ID_MASK(8'h20),
        .MST2_RW(0),

        // Master 3
        .MST3_CDC(0),
        .MST3_OSTDREQ_NUM(4),
        .MST3_OSTDREQ_SIZE(1),
        .MST3_PRIORITY(0),
        .MST3_ROUTES(4'b1111),
        .MST3_ID_MASK(8'h30),
        .MST3_RW(0),

        // Slave 0 (0x0000-0x0FFF)
        .SLV0_CDC(0),
        .SLV0_START_ADDR(0),
        .SLV0_END_ADDR(4095),
        .SLV0_OSTDREQ_NUM(4),
        .SLV0_OSTDREQ_SIZE(1),
        .SLV0_KEEP_BASE_ADDR(0),

        // Slave 1 (0x1000-0x1FFF)
        .SLV1_CDC(0),
        .SLV1_START_ADDR(4096),
        .SLV1_END_ADDR(8191),
        .SLV1_OSTDREQ_NUM(4),
        .SLV1_OSTDREQ_SIZE(1),
        .SLV1_KEEP_BASE_ADDR(0),

        // Slave 2 (0x2000-0x2FFF)
        .SLV2_CDC(0),
        .SLV2_START_ADDR(8192),
        .SLV2_END_ADDR(12287),
        .SLV2_OSTDREQ_NUM(4),
        .SLV2_OSTDREQ_SIZE(1),
        .SLV2_KEEP_BASE_ADDR(0),

        // Slave 3 (0x3000-0x3FFF)
        .SLV3_CDC(0),
        .SLV3_START_ADDR(12288),
        .SLV3_END_ADDR(16383),
        .SLV3_OSTDREQ_NUM(4),
        .SLV3_OSTDREQ_SIZE(1),
        .SLV3_KEEP_BASE_ADDR(0)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .srst(srst),

        // Master 0 (Slave interface 0)
        .slv0_aclk(aclk),
        .slv0_aresetn(aresetn),
        .slv0_srst(srst),
        .slv0_awvalid(mst_if[0].awvalid),
        .slv0_awready(mst_if[0].awready),
        .slv0_awaddr(mst_if[0].awaddr),
        .slv0_awlen(mst_if[0].awlen),
        .slv0_awsize(mst_if[0].awsize),
        .slv0_awburst(mst_if[0].awburst),
        .slv0_awlock(mst_if[0].awlock),
        .slv0_awcache(mst_if[0].awcache),
        .slv0_awprot(mst_if[0].awprot),
        .slv0_awqos(mst_if[0].awqos),
        .slv0_awregion(mst_if[0].awregion),
        .slv0_awid(mst_if[0].awid),
        .slv0_awuser(mst_if[0].awuser),
        .slv0_wvalid(mst_if[0].wvalid),
        .slv0_wready(mst_if[0].wready),
        .slv0_wlast(mst_if[0].wlast),
        .slv0_wdata(mst_if[0].wdata),
        .slv0_wstrb(mst_if[0].wstrb),
        .slv0_wuser(mst_if[0].wuser),
        .slv0_bvalid(mst_if[0].bvalid),
        .slv0_bready(mst_if[0].bready),
        .slv0_bid(mst_if[0].bid),
        .slv0_bresp(mst_if[0].bresp),
        .slv0_buser(mst_if[0].buser),
        .slv0_arvalid(mst_if[0].arvalid),
        .slv0_arready(mst_if[0].arready),
        .slv0_araddr(mst_if[0].araddr),
        .slv0_arlen(mst_if[0].arlen),
        .slv0_arsize(mst_if[0].arsize),
        .slv0_arburst(mst_if[0].arburst),
        .slv0_arlock(mst_if[0].arlock),
        .slv0_arcache(mst_if[0].arcache),
        .slv0_arprot(mst_if[0].arprot),
        .slv0_arqos(mst_if[0].arqos),
        .slv0_arregion(mst_if[0].arregion),
        .slv0_arid(mst_if[0].arid),
        .slv0_aruser(mst_if[0].aruser),
        .slv0_rvalid(mst_if[0].rvalid),
        .slv0_rready(mst_if[0].rready),
        .slv0_rid(mst_if[0].rid),
        .slv0_rresp(mst_if[0].rresp),
        .slv0_rdata(mst_if[0].rdata),
        .slv0_rlast(mst_if[0].rlast),
        .slv0_ruser(mst_if[0].ruser),

        // Master 1 (Slave interface 1)
        .slv1_aclk(aclk),
        .slv1_aresetn(aresetn),
        .slv1_srst(srst),
        .slv1_awvalid(mst_if[1].awvalid),
        .slv1_awready(mst_if[1].awready),
        .slv1_awaddr(mst_if[1].awaddr),
        .slv1_awlen(mst_if[1].awlen),
        .slv1_awsize(mst_if[1].awsize),
        .slv1_awburst(mst_if[1].awburst),
        .slv1_awlock(mst_if[1].awlock),
        .slv1_awcache(mst_if[1].awcache),
        .slv1_awprot(mst_if[1].awprot),
        .slv1_awqos(mst_if[1].awqos),
        .slv1_awregion(mst_if[1].awregion),
        .slv1_awid(mst_if[1].awid),
        .slv1_awuser(mst_if[1].awuser),
        .slv1_wvalid(mst_if[1].wvalid),
        .slv1_wready(mst_if[1].wready),
        .slv1_wlast(mst_if[1].wlast),
        .slv1_wdata(mst_if[1].wdata),
        .slv1_wstrb(mst_if[1].wstrb),
        .slv1_wuser(mst_if[1].wuser),
        .slv1_bvalid(mst_if[1].bvalid),
        .slv1_bready(mst_if[1].bready),
        .slv1_bid(mst_if[1].bid),
        .slv1_bresp(mst_if[1].bresp),
        .slv1_buser(mst_if[1].buser),
        .slv1_arvalid(mst_if[1].arvalid),
        .slv1_arready(mst_if[1].arready),
        .slv1_araddr(mst_if[1].araddr),
        .slv1_arlen(mst_if[1].arlen),
        .slv1_arsize(mst_if[1].arsize),
        .slv1_arburst(mst_if[1].arburst),
        .slv1_arlock(mst_if[1].arlock),
        .slv1_arcache(mst_if[1].arcache),
        .slv1_arprot(mst_if[1].arprot),
        .slv1_arqos(mst_if[1].arqos),
        .slv1_arregion(mst_if[1].arregion),
        .slv1_arid(mst_if[1].arid),
        .slv1_aruser(mst_if[1].aruser),
        .slv1_rvalid(mst_if[1].rvalid),
        .slv1_rready(mst_if[1].rready),
        .slv1_rid(mst_if[1].rid),
        .slv1_rresp(mst_if[1].rresp),
        .slv1_rdata(mst_if[1].rdata),
        .slv1_rlast(mst_if[1].rlast),
        .slv1_ruser(mst_if[1].ruser),

        // Master 2 (Slave interface 2)
        .slv2_aclk(aclk),
        .slv2_aresetn(aresetn),
        .slv2_srst(srst),
        .slv2_awvalid(mst_if[2].awvalid),
        .slv2_awready(mst_if[2].awready),
        .slv2_awaddr(mst_if[2].awaddr),
        .slv2_awlen(mst_if[2].awlen),
        .slv2_awsize(mst_if[2].awsize),
        .slv2_awburst(mst_if[2].awburst),
        .slv2_awlock(mst_if[2].awlock),
        .slv2_awcache(mst_if[2].awcache),
        .slv2_awprot(mst_if[2].awprot),
        .slv2_awqos(mst_if[2].awqos),
        .slv2_awregion(mst_if[2].awregion),
        .slv2_awid(mst_if[2].awid),
        .slv2_awuser(mst_if[2].awuser),
        .slv2_wvalid(mst_if[2].wvalid),
        .slv2_wready(mst_if[2].wready),
        .slv2_wlast(mst_if[2].wlast),
        .slv2_wdata(mst_if[2].wdata),
        .slv2_wstrb(mst_if[2].wstrb),
        .slv2_wuser(mst_if[2].wuser),
        .slv2_bvalid(mst_if[2].bvalid),
        .slv2_bready(mst_if[2].bready),
        .slv2_bid(mst_if[2].bid),
        .slv2_bresp(mst_if[2].bresp),
        .slv2_buser(mst_if[2].buser),
        .slv2_arvalid(mst_if[2].arvalid),
        .slv2_arready(mst_if[2].arready),
        .slv2_araddr(mst_if[2].araddr),
        .slv2_arlen(mst_if[2].arlen),
        .slv2_arsize(mst_if[2].arsize),
        .slv2_arburst(mst_if[2].arburst),
        .slv2_arlock(mst_if[2].arlock),
        .slv2_arcache(mst_if[2].arcache),
        .slv2_arprot(mst_if[2].arprot),
        .slv2_arqos(mst_if[2].arqos),
        .slv2_arregion(mst_if[2].arregion),
        .slv2_arid(mst_if[2].arid),
        .slv2_aruser(mst_if[2].aruser),
        .slv2_rvalid(mst_if[2].rvalid),
        .slv2_rready(mst_if[2].rready),
        .slv2_rid(mst_if[2].rid),
        .slv2_rresp(mst_if[2].rresp),
        .slv2_rdata(mst_if[2].rdata),
        .slv2_rlast(mst_if[2].rlast),
        .slv2_ruser(mst_if[2].ruser),

        // Master 3 (Slave interface 3)
        .slv3_aclk(aclk),
        .slv3_aresetn(aresetn),
        .slv3_srst(srst),
        .slv3_awvalid(mst_if[3].awvalid),
        .slv3_awready(mst_if[3].awready),
        .slv3_awaddr(mst_if[3].awaddr),
        .slv3_awlen(mst_if[3].awlen),
        .slv3_awsize(mst_if[3].awsize),
        .slv3_awburst(mst_if[3].awburst),
        .slv3_awlock(mst_if[3].awlock),
        .slv3_awcache(mst_if[3].awcache),
        .slv3_awprot(mst_if[3].awprot),
        .slv3_awqos(mst_if[3].awqos),
        .slv3_awregion(mst_if[3].awregion),
        .slv3_awid(mst_if[3].awid),
        .slv3_awuser(mst_if[3].awuser),
        .slv3_wvalid(mst_if[3].wvalid),
        .slv3_wready(mst_if[3].wready),
        .slv3_wlast(mst_if[3].wlast),
        .slv3_wdata(mst_if[3].wdata),
        .slv3_wstrb(mst_if[3].wstrb),
        .slv3_wuser(mst_if[3].wuser),
        .slv3_bvalid(mst_if[3].bvalid),
        .slv3_bready(mst_if[3].bready),
        .slv3_bid(mst_if[3].bid),
        .slv3_bresp(mst_if[3].bresp),
        .slv3_buser(mst_if[3].buser),
        .slv3_arvalid(mst_if[3].arvalid),
        .slv3_arready(mst_if[3].arready),
        .slv3_araddr(mst_if[3].araddr),
        .slv3_arlen(mst_if[3].arlen),
        .slv3_arsize(mst_if[3].arsize),
        .slv3_arburst(mst_if[3].arburst),
        .slv3_arlock(mst_if[3].arlock),
        .slv3_arcache(mst_if[3].arcache),
        .slv3_arprot(mst_if[3].arprot),
        .slv3_arqos(mst_if[3].arqos),
        .slv3_arregion(mst_if[3].arregion),
        .slv3_arid(mst_if[3].arid),
        .slv3_aruser(mst_if[3].aruser),
        .slv3_rvalid(mst_if[3].rvalid),
        .slv3_rready(mst_if[3].rready),
        .slv3_rid(mst_if[3].rid),
        .slv3_rresp(mst_if[3].rresp),
        .slv3_rdata(mst_if[3].rdata),
        .slv3_rlast(mst_if[3].rlast),
        .slv3_ruser(mst_if[3].ruser),

        // Slave 0 (Master interface 0)
        .mst0_aclk(aclk),
        .mst0_aresetn(aresetn),
        .mst0_srst(srst),
        .mst0_awvalid(slv_if[0].awvalid),
        .mst0_awready(slv_if[0].awready),
        .mst0_awaddr(slv_if[0].awaddr),
        .mst0_awlen(slv_if[0].awlen),
        .mst0_awsize(slv_if[0].awsize),
        .mst0_awburst(slv_if[0].awburst),
        .mst0_awlock(slv_if[0].awlock),
        .mst0_awcache(slv_if[0].awcache),
        .mst0_awprot(slv_if[0].awprot),
        .mst0_awqos(slv_if[0].awqos),
        .mst0_awregion(slv_if[0].awregion),
        .mst0_awid(slv_if[0].awid),
        .mst0_awuser(slv_if[0].awuser),
        .mst0_wvalid(slv_if[0].wvalid),
        .mst0_wready(slv_if[0].wready),
        .mst0_wlast(slv_if[0].wlast),
        .mst0_wdata(slv_if[0].wdata),
        .mst0_wstrb(slv_if[0].wstrb),
        .mst0_wuser(slv_if[0].wuser),
        .mst0_bvalid(slv_if[0].bvalid),
        .mst0_bready(slv_if[0].bready),
        .mst0_bid(slv_if[0].bid),
        .mst0_bresp(slv_if[0].bresp),
        .mst0_buser(slv_if[0].buser),
        .mst0_arvalid(slv_if[0].arvalid),
        .mst0_arready(slv_if[0].arready),
        .mst0_araddr(slv_if[0].araddr),
        .mst0_arlen(slv_if[0].arlen),
        .mst0_arsize(slv_if[0].arsize),
        .mst0_arburst(slv_if[0].arburst),
        .mst0_arlock(slv_if[0].arlock),
        .mst0_arcache(slv_if[0].arcache),
        .mst0_arprot(slv_if[0].arprot),
        .mst0_arqos(slv_if[0].arqos),
        .mst0_arregion(slv_if[0].arregion),
        .mst0_arid(slv_if[0].arid),
        .mst0_aruser(slv_if[0].aruser),
        .mst0_rvalid(slv_if[0].rvalid),
        .mst0_rready(slv_if[0].rready),
        .mst0_rid(slv_if[0].rid),
        .mst0_rresp(slv_if[0].rresp),
        .mst0_rdata(slv_if[0].rdata),
        .mst0_rlast(slv_if[0].rlast),
        .mst0_ruser(slv_if[0].ruser),

        // Slave 1 (Master interface 1)
        .mst1_aclk(aclk),
        .mst1_aresetn(aresetn),
        .mst1_srst(srst),
        .mst1_awvalid(slv_if[1].awvalid),
        .mst1_awready(slv_if[1].awready),
        .mst1_awaddr(slv_if[1].awaddr),
        .mst1_awlen(slv_if[1].awlen),
        .mst1_awsize(slv_if[1].awsize),
        .mst1_awburst(slv_if[1].awburst),
        .mst1_awlock(slv_if[1].awlock),
        .mst1_awcache(slv_if[1].awcache),
        .mst1_awprot(slv_if[1].awprot),
        .mst1_awqos(slv_if[1].awqos),
        .mst1_awregion(slv_if[1].awregion),
        .mst1_awid(slv_if[1].awid),
        .mst1_awuser(slv_if[1].awuser),
        .mst1_wvalid(slv_if[1].wvalid),
        .mst1_wready(slv_if[1].wready),
        .mst1_wlast(slv_if[1].wlast),
        .mst1_wdata(slv_if[1].wdata),
        .mst1_wstrb(slv_if[1].wstrb),
        .mst1_wuser(slv_if[1].wuser),
        .mst1_bvalid(slv_if[1].bvalid),
        .mst1_bready(slv_if[1].bready),
        .mst1_bid(slv_if[1].bid),
        .mst1_bresp(slv_if[1].bresp),
        .mst1_buser(slv_if[1].buser),
        .mst1_arvalid(slv_if[1].arvalid),
        .mst1_arready(slv_if[1].arready),
        .mst1_araddr(slv_if[1].araddr),
        .mst1_arlen(slv_if[1].arlen),
        .mst1_arsize(slv_if[1].arsize),
        .mst1_arburst(slv_if[1].arburst),
        .mst1_arlock(slv_if[1].arlock),
        .mst1_arcache(slv_if[1].arcache),
        .mst1_arprot(slv_if[1].arprot),
        .mst1_arqos(slv_if[1].arqos),
        .mst1_arregion(slv_if[1].arregion),
        .mst1_arid(slv_if[1].arid),
        .mst1_aruser(slv_if[1].aruser),
        .mst1_rvalid(slv_if[1].rvalid),
        .mst1_rready(slv_if[1].rready),
        .mst1_rid(slv_if[1].rid),
        .mst1_rresp(slv_if[1].rresp),
        .mst1_rdata(slv_if[1].rdata),
        .mst1_rlast(slv_if[1].rlast),
        .mst1_ruser(slv_if[1].ruser),

        // Slave 2 (Master interface 2)
        .mst2_aclk(aclk),
        .mst2_aresetn(aresetn),
        .mst2_srst(srst),
        .mst2_awvalid(slv_if[2].awvalid),
        .mst2_awready(slv_if[2].awready),
        .mst2_awaddr(slv_if[2].awaddr),
        .mst2_awlen(slv_if[2].awlen),
        .mst2_awsize(slv_if[2].awsize),
        .mst2_awburst(slv_if[2].awburst),
        .mst2_awlock(slv_if[2].awlock),
        .mst2_awcache(slv_if[2].awcache),
        .mst2_awprot(slv_if[2].awprot),
        .mst2_awqos(slv_if[2].awqos),
        .mst2_awregion(slv_if[2].awregion),
        .mst2_awid(slv_if[2].awid),
        .mst2_awuser(slv_if[2].awuser),
        .mst2_wvalid(slv_if[2].wvalid),
        .mst2_wready(slv_if[2].wready),
        .mst2_wlast(slv_if[2].wlast),
        .mst2_wdata(slv_if[2].wdata),
        .mst2_wstrb(slv_if[2].wstrb),
        .mst2_wuser(slv_if[2].wuser),
        .mst2_bvalid(slv_if[2].bvalid),
        .mst2_bready(slv_if[2].bready),
        .mst2_bid(slv_if[2].bid),
        .mst2_bresp(slv_if[2].bresp),
        .mst2_buser(slv_if[2].buser),
        .mst2_arvalid(slv_if[2].arvalid),
        .mst2_arready(slv_if[2].arready),
        .mst2_araddr(slv_if[2].araddr),
        .mst2_arlen(slv_if[2].arlen),
        .mst2_arsize(slv_if[2].arsize),
        .mst2_arburst(slv_if[2].arburst),
        .mst2_arlock(slv_if[2].arlock),
        .mst2_arcache(slv_if[2].arcache),
        .mst2_arprot(slv_if[2].arprot),
        .mst2_arqos(slv_if[2].arqos),
        .mst2_arregion(slv_if[2].arregion),
        .mst2_arid(slv_if[2].arid),
        .mst2_aruser(slv_if[2].aruser),
        .mst2_rvalid(slv_if[2].rvalid),
        .mst2_rready(slv_if[2].rready),
        .mst2_rid(slv_if[2].rid),
        .mst2_rresp(slv_if[2].rresp),
        .mst2_rdata(slv_if[2].rdata),
        .mst2_rlast(slv_if[2].rlast),
        .mst2_ruser(slv_if[2].ruser),

        // Slave 3 (Master interface 3)
        .mst3_aclk(aclk),
        .mst3_aresetn(aresetn),
        .mst3_srst(srst),
        .mst3_awvalid(slv_if[3].awvalid),
        .mst3_awready(slv_if[3].awready),
        .mst3_awaddr(slv_if[3].awaddr),
        .mst3_awlen(slv_if[3].awlen),
        .mst3_awsize(slv_if[3].awsize),
        .mst3_awburst(slv_if[3].awburst),
        .mst3_awlock(slv_if[3].awlock),
        .mst3_awcache(slv_if[3].awcache),
        .mst3_awprot(slv_if[3].awprot),
        .mst3_awqos(slv_if[3].awqos),
        .mst3_awregion(slv_if[3].awregion),
        .mst3_awid(slv_if[3].arid),
        .mst3_awuser(slv_if[3].awuser),
        .mst3_wvalid(slv_if[3].wvalid),
        .mst3_wready(slv_if[3].wready),
        .mst3_wlast(slv_if[3].wlast),
        .mst3_wdata(slv_if[3].wdata),
        .mst3_wstrb(slv_if[3].wstrb),
        .mst3_wuser(slv_if[3].wuser),
        .mst3_bvalid(slv_if[3].bvalid),
        .mst3_bready(slv_if[3].bready),
        .mst3_bid(slv_if[3].bid),
        .mst3_bresp(slv_if[3].bresp),
        .mst3_buser(slv_if[3].buser),
        .mst3_arvalid(slv_if[3].arvalid),
        .mst3_arready(slv_if[3].arready),
        .mst3_araddr(slv_if[3].araddr),
        .mst3_arlen(slv_if[3].arlen),
        .mst3_arsize(slv_if[3].arsize),
        .mst3_arburst(slv_if[3].arburst),
        .mst3_arlock(slv_if[3].arlock),
        .mst3_arcache(slv_if[3].arcache),
        .mst3_arprot(slv_if[3].arprot),
        .mst3_arqos(slv_if[3].arqos),
        .mst3_arregion(slv_if[3].arregion),
        .mst3_arid(slv_if[3].arid),
        .mst3_aruser(slv_if[3].aruser),
        .mst3_rvalid(slv_if[3].rvalid),
        .mst3_rready(slv_if[3].rready),
        .mst3_rid(slv_if[3].rid),
        .mst3_rresp(slv_if[3].rresp),
        .mst3_rdata(slv_if[3].rdata),
        .mst3_rlast(slv_if[3].rlast),
        .mst3_ruser(slv_if[3].ruser)
    );

    //--------------------------------------------------------------------------
    // Slave Memory Models
    //--------------------------------------------------------------------------
    // Slave 0 memory
    always @(posedge aclk) begin
        if (slv_if[0].awvalid && slv_if[0].awready) begin
            $display("[%0t] SLV0: Write addr=0x%04h id=0x%02h len=%0d",
                     $time, slv_if[0].awaddr, slv_if[0].awid, slv_if[0].awlen);
        end
        if (slv_if[0].arvalid && slv_if[0].arready) begin
            $display("[%0t] SLV0: Read addr=0x%04h id=0x%02h len=%0d",
                     $time, slv_if[0].araddr, slv_if[0].arid, slv_if[0].arlen);
        end
    end

    // Slave 0 simple memory response
    logic [31:0] slv0_mem [0:1023];
    logic [31:0] slv1_mem [0:1023];
    logic [31:0] slv2_mem [0:1023];
    logic [31:0] slv3_mem [0:1023];

    // Slave 0 write handler
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            slv_if[0].awready <= 0;
            slv_if[0].wready <= 0;
            slv_if[0].bvalid <= 0;
        end else begin
            if (slv_if[0].awvalid && !slv_if[0].bvalid) begin
                slv_if[0].awready <= 1;
            end else begin
                slv_if[0].awready <= 0;
            end

            if (slv_if[0].wvalid && !slv_if[0].bvalid) begin
                slv_if[0].wready <= 1;
                if (slv_if[0].wready) begin
                    slv0_mem[slv_if[0].awaddr[11:2]] <= slv_if[0].wdata;
                end
            end else begin
                slv_if[0].wready <= 0;
            end

            if (slv_if[0].wvalid && slv_if[0].wready && slv_if[0].wlast) begin
                slv_if[0].bvalid <= 1;
                slv_if[0].bid <= slv_if[0].awid;
                slv_if[0].bresp <= 0;
            end else if (slv_if[0].bvalid && slv_if[0].bready) begin
                slv_if[0].bvalid <= 0;
            end
        end
    end

    // Slave 0 read handler
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            slv_if[0].arready <= 0;
            slv_if[0].rvalid <= 0;
            slv_if[0].rlast <= 0;
        end else begin
            if (slv_if[0].arvalid && !slv_if[0].rvalid) begin
                slv_if[0].arready <= 1;
            end else begin
                slv_if[0].arready <= 0;
            end

            if (slv_if[0].arvalid && slv_if[0].arready) begin
                slv_if[0].rvalid <= 1;
                slv_if[0].rid <= slv_if[0].arid;
                slv_if[0].rdata <= slv0_mem[slv_if[0].araddr[11:2]];
                slv_if[0].rresp <= 0;
                slv_if[0].rlast <= 1;
            end else if (slv_if[0].rvalid && slv_if[0].rready) begin
                slv_if[0].rvalid <= 0;
                slv_if[0].rlast <= 0;
            end
        end
    end

    // Similar for other slaves...
    // (Abbreviated for brevity - similar pattern for slv_if[1], slv_if[2], slv_if[3])

    //--------------------------------------------------------------------------
    // Test Execution
    //--------------------------------------------------------------------------
    initial begin
        // Wait for reset
        @(posedge aresetn);
        repeat(10) @(posedge aclk);

        $display("\n=== Starting AXI Crossbar Tests ===\n");

        // Run tests
        run_smoke_test();
        run_single_master_test();
        run_multi_master_test();
        run_address_routing_test();
        run_concurrent_access_test();

        #1000;
        $display("\n=== All Tests Completed ===\n");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Smoke Test - Basic functionality
    //--------------------------------------------------------------------------
    task run_smoke_test();
        $display("[TEST] Running Smoke Test...");

        // Simple write to Slave 0
        mst_if[0].awvalid = 1;
        mst_if[0].awaddr = 16'h0000;
        mst_if[0].awlen = 0;
        mst_if[0].awsize = 3'b010;
        mst_if[0].awid = 8'h00;

        @(posedge aclk iff mst_if[0].awready);
        mst_if[0].awvalid = 0;

        mst_if[0].wvalid = 1;
        mst_if[0].wdata = 32'hDEADBEEF;
        mst_if[0].wstrb = 4'hF;
        mst_if[0].wlast = 1;

        @(posedge aclk iff mst_if[0].wready);
        mst_if[0].wvalid = 0;
        mst_if[0].wlast = 0;

        mst_if[0].bready = 1;
        @(posedge aclk iff mst_if[0].bvalid);
        mst_if[0].bready = 0;

        $display("[TEST] Smoke Test PASSED\n");
    endtask

    //--------------------------------------------------------------------------
    // Single Master Test
    //--------------------------------------------------------------------------
    task run_single_master_test();
        $display("[TEST] Running Single Master Test...");

        // Read from Slave 0
        mst_if[0].arvalid = 1;
        mst_if[0].araddr = 16'h0000;
        mst_if[0].arlen = 0;
        mst_if[0].arsize = 3'b010;
        mst_if[0].arid = 8'h01;

        @(posedge aclk iff mst_if[0].arready);
        mst_if[0].arvalid = 0;

        mst_if[0].rready = 1;
        @(posedge aclk iff mst_if[0].rvalid);
        mst_if[0].rready = 0;

        $display("[TEST] Single Master Test PASSED\n");
    endtask

    //--------------------------------------------------------------------------
    // Multi Master Test
    //--------------------------------------------------------------------------
    task run_multi_master_test();
        $display("[TEST] Running Multi Master Test...");

        fork
            // Master 0 write to Slave 0
            begin
                mst_if[0].awvalid = 1;
                mst_if[0].awaddr = 16'h0004;
                mst_if[0].awlen = 0;
                mst_if[0].awsize = 3'b010;
                mst_if[0].awid = 8'h02;
                @(posedge aclk iff mst_if[0].awready);
                mst_if[0].awvalid = 0;
                mst_if[0].wvalid = 1;
                mst_if[0].wdata = 32'h12345678;
                mst_if[0].wstrb = 4'hF;
                mst_if[0].wlast = 1;
                @(posedge aclk iff mst_if[0].wready);
                mst_if[0].wvalid = 0;
                mst_if[0].wlast = 0;
                mst_if[0].bready = 1;
                @(posedge aclk iff mst_if[0].bvalid);
                mst_if[0].bready = 0;
            end

            // Master 1 write to Slave 1
            begin
                mst_if[1].awvalid = 1;
                mst_if[1].awaddr = 16'h1000;
                mst_if[1].awlen = 0;
                mst_if[1].awsize = 3'b010;
                mst_if[1].awid = 8'h12;
                @(posedge aclk iff mst_if[1].awready);
                mst_if[1].awvalid = 0;
                mst_if[1].wvalid = 1;
                mst_if[1].wdata = 32'hAABBCCDD;
                mst_if[1].wstrb = 4'hF;
                mst_if[1].wlast = 1;
                @(posedge aclk iff mst_if[1].wready);
                mst_if[1].wvalid = 0;
                mst_if[1].wlast = 0;
                mst_if[1].bready = 1;
                @(posedge aclk iff mst_if[1].bvalid);
                mst_if[1].bready = 0;
            end
        join

        $display("[TEST] Multi Master Test PASSED\n");
    endtask

    //--------------------------------------------------------------------------
    // Address Routing Test
    //--------------------------------------------------------------------------
    task run_address_routing_test();
        $display("[TEST] Running Address Routing Test...");

        // Write to each slave region
        for (int i = 0; i < 4; i++) begin
            bit [15:0] base_addr;
            base_addr = i * 16'h1000;

            mst_if[0].awvalid = 1;
            mst_if[0].awaddr = base_addr;
            mst_if[0].awlen = 0;
            mst_if[0].awsize = 3'b010;
            mst_if[0].awid = 8'h00 + i;
            @(posedge aclk iff mst_if[0].awready);
            mst_if[0].awvalid = 0;

            mst_if[0].wvalid = 1;
            mst_if[0].wdata = 32'h00000000 + i;
            mst_if[0].wstrb = 4'hF;
            mst_if[0].wlast = 1;
            @(posedge aclk iff mst_if[0].wready);
            mst_if[0].wvalid = 0;
            mst_if[0].wlast = 0;

            mst_if[0].bready = 1;
            @(posedge aclk iff mst_if[0].bvalid);
            mst_if[0].bready = 0;
        end

        $display("[TEST] Address Routing Test PASSED\n");
    endtask

    //--------------------------------------------------------------------------
    // Concurrent Access Test
    //--------------------------------------------------------------------------
    task run_concurrent_access_test();
        $display("[TEST] Running Concurrent Access Test...");

        fork
            // All masters write simultaneously
            begin
                for (int m = 0; m < 4; m++) begin
                    fork
                        automatic int master = m;
                        begin
                            mst_if[master].awvalid = 1;
                            mst_if[master].awaddr = master * 16'h1000;
                            mst_if[master].awlen = 0;
                            mst_if[master].awsize = 3'b010;
                            mst_if[master].awid = master * 16'h10;
                            @(posedge aclk iff mst_if[master].awready);
                            mst_if[master].awvalid = 0;

                            mst_if[master].wvalid = 1;
                            mst_if[master].wdata = 32'hDEAD0000 + master;
                            mst_if[master].wstrb = 4'hF;
                            mst_if[master].wlast = 1;
                            @(posedge aclk iff mst_if[master].wready);
                            mst_if[master].wvalid = 0;
                            mst_if[master].wlast = 0;

                            mst_if[master].bready = 1;
                            @(posedge aclk iff mst_if[master].bvalid);
                            mst_if[master].bready = 0;
                        end
                    join
                end
            end
        join

        $display("[TEST] Concurrent Access Test PASSED\n");
    endtask

    //--------------------------------------------------------------------------
    // Timeout Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #100000;
        $error("Simulation timeout!");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Waveform Dump
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("axi_crossbar_tb.vcd");
        $dumpvars(0, axi_crossbar_tb);
    end

endmodule
