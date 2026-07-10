`timescale 1ns/1ps

module axi_simple_test;

    parameter AXI_ADDR_W = 16;
    parameter AXI_ID_W   = 8;
    parameter AXI_DATA_W = 32;

    reg aclk, aresetn, srst;
    initial begin aclk=0; forever #5 aclk=~aclk; end
    initial begin aresetn=0; srst=1; #100; aresetn=1; srst=0; end

    reg slv0_awvalid; wire slv0_awready;
    reg [15:0] slv0_awaddr; reg [7:0] slv0_awlen; reg [2:0] slv0_awsize; reg [7:0] slv0_awid;
    reg slv0_wvalid; wire slv0_wready; reg slv0_wlast; reg [31:0] slv0_wdata; reg [3:0] slv0_wstrb;
    wire slv0_bvalid; reg slv0_bready; wire [7:0] slv0_bid; wire [1:0] slv0_bresp;
    reg slv0_arvalid; wire slv0_arready;
    reg [15:0] slv0_araddr; reg [7:0] slv0_arlen; reg [2:0] slv0_arsize; reg [7:0] slv0_arid;
    wire slv0_rvalid; reg slv0_rready; wire [7:0] slv0_rid; wire [1:0] slv0_rresp;
    wire [31:0] slv0_rdata; wire slv0_rlast;

    wire mst0_awvalid, mst0_wvalid, mst0_bready, mst0_arvalid, mst0_rready;
    wire [15:0] mst0_awaddr, mst0_araddr;
    wire [7:0] mst0_awlen, mst0_arlen, mst0_awid, mst0_arid;
    wire [2:0] mst0_awsize, mst0_arsize;
    wire mst0_wlast; wire [31:0] mst0_wdata; wire [3:0] mst0_wstrb;

    wire mst0_awready = mst0_awvalid;
    wire mst0_wready = mst0_wvalid;
    wire mst0_bvalid = mst0_awvalid & mst0_wvalid & mst0_wlast;
    wire [7:0] mst0_bid = mst0_awid;
    wire [1:0] mst0_bresp = 2'b00;
    wire mst0_arready = mst0_arvalid;
    wire mst0_rvalid = mst0_arvalid;
    wire [7:0] mst0_rid = mst0_arid;
    wire [1:0] mst0_rresp = 2'b00;
    wire [31:0] mst0_rdata = 32'hDEADBEEF;
    wire mst0_rlast = 1'b1;

    axicb_crossbar_top #(
        .AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W),
        .MST_NB(4), .SLV_NB(4), .MST_PIPELINE(0), .SLV_PIPELINE(0),
        .AXI_SIGNALING(1), .USER_SUPPORT(0),
        .MST0_CDC(0), .MST0_OSTDREQ_NUM(4), .MST0_OSTDREQ_SIZE(1), .MST0_PRIORITY(0),
        .MST0_ROUTES(4'b1111), .MST0_ID_MASK(8'h0F), .MST0_RW(0),
        .MST1_CDC(0), .MST1_OSTDREQ_NUM(4), .MST1_OSTDREQ_SIZE(1), .MST1_PRIORITY(0),
        .MST1_ROUTES(4'b1111), .MST1_ID_MASK(8'h10), .MST1_RW(0),
        .MST2_CDC(0), .MST2_OSTDREQ_NUM(4), .MST2_OSTDREQ_SIZE(1), .MST2_PRIORITY(0),
        .MST2_ROUTES(4'b1111), .MST2_ID_MASK(8'h20), .MST2_RW(0),
        .MST3_CDC(0), .MST3_OSTDREQ_NUM(4), .MST3_OSTDREQ_SIZE(1), .MST3_PRIORITY(0),
        .MST3_ROUTES(4'b1111), .MST3_ID_MASK(8'h30), .MST3_RW(0),
        .SLV0_CDC(0), .SLV0_START_ADDR(0), .SLV0_END_ADDR(4095),
        .SLV0_OSTDREQ_NUM(4), .SLV0_OSTDREQ_SIZE(1), .SLV0_KEEP_BASE_ADDR(0),
        .SLV1_CDC(0), .SLV1_START_ADDR(4096), .SLV1_END_ADDR(8191),
        .SLV1_OSTDREQ_NUM(4), .SLV1_OSTDREQ_SIZE(1), .SLV1_KEEP_BASE_ADDR(0),
        .SLV2_CDC(0), .SLV2_START_ADDR(8192), .SLV2_END_ADDR(12287),
        .SLV2_OSTDREQ_NUM(4), .SLV2_OSTDREQ_SIZE(1), .SLV2_KEEP_BASE_ADDR(0),
        .SLV3_CDC(0), .SLV3_START_ADDR(12288), .SLV3_END_ADDR(16383),
        .SLV3_OSTDREQ_NUM(4), .SLV3_OSTDREQ_SIZE(1), .SLV3_KEEP_BASE_ADDR(0)
    ) dut (
        .aclk(aclk), .aresetn(aresetn), .srst(srst),
        .slv0_aclk(aclk), .slv0_aresetn(aresetn), .slv0_srst(srst),
        .slv0_awvalid(slv0_awvalid), .slv0_awready(slv0_awready),
        .slv0_awaddr(slv0_awaddr), .slv0_awlen(slv0_awlen), .slv0_awsize(slv0_awsize),
        .slv0_awburst(2'b01), .slv0_awlock(1'b0), .slv0_awcache(4'h0), .slv0_awprot(3'b010),
        .slv0_awqos(4'h0), .slv0_awregion(4'h0), .slv0_awid(slv0_awid), .slv0_awuser(1'b0),
        .slv0_wvalid(slv0_wvalid), .slv0_wready(slv0_wready), .slv0_wlast(slv0_wlast),
        .slv0_wdata(slv0_wdata), .slv0_wstrb(slv0_wstrb), .slv0_wuser(1'b0),
        .slv0_bvalid(slv0_bvalid), .slv0_bready(slv0_bready), .slv0_bid(slv0_bid),
        .slv0_bresp(slv0_bresp), .slv0_buser(),
        .slv0_arvalid(slv0_arvalid), .slv0_arready(slv0_arready),
        .slv0_araddr(slv0_araddr), .slv0_arlen(slv0_arlen), .slv0_arsize(slv0_arsize),
        .slv0_arburst(2'b01), .slv0_arlock(1'b0), .slv0_arcache(4'h0), .slv0_arprot(3'b010),
        .slv0_arqos(4'h0), .slv0_arregion(4'h0), .slv0_arid(slv0_arid), .slv0_aruser(1'b0),
        .slv0_rvalid(slv0_rvalid), .slv0_rready(slv0_rready), .slv0_rid(slv0_rid),
        .slv0_rresp(slv0_rresp), .slv0_rdata(slv0_rdata), .slv0_rlast(slv0_rlast), .slv0_ruser(),
        .slv1_aclk(aclk), .slv1_aresetn(aresetn), .slv1_srst(srst),
        .slv1_awvalid(1'b0), .slv1_awready(), .slv1_awaddr(16'h0), .slv1_awlen(8'h0),
        .slv1_awsize(3'b010), .slv1_awburst(2'b01), .slv1_awlock(1'b0), .slv1_awcache(4'h0),
        .slv1_awprot(3'b010), .slv1_awqos(4'h0), .slv1_awregion(4'h0), .slv1_awid(8'h0), .slv1_awuser(1'b0),
        .slv1_wvalid(1'b0), .slv1_wready(), .slv1_wlast(1'b0), .slv1_wdata(32'h0), .slv1_wstrb(4'h0), .slv1_wuser(1'b0),
        .slv1_bvalid(), .slv1_bready(1'b0), .slv1_bid(), .slv1_bresp(), .slv1_buser(),
        .slv1_arvalid(1'b0), .slv1_arready(), .slv1_araddr(16'h0), .slv1_arlen(8'h0), .slv1_arsize(3'b010),
        .slv1_arburst(2'b01), .slv1_arlock(1'b0), .slv1_arcache(4'h0), .slv1_arprot(3'b010),
        .slv1_arqos(4'h0), .slv1_arregion(4'h0), .slv1_arid(8'h0), .slv1_aruser(1'b0),
        .slv1_rvalid(), .slv1_rready(1'b0), .slv1_rid(), .slv1_rresp(), .slv1_rdata(), .slv1_rlast(), .slv1_ruser(),
        .slv2_aclk(aclk), .slv2_aresetn(aresetn), .slv2_srst(srst),
        .slv2_awvalid(1'b0), .slv2_awready(), .slv2_awaddr(16'h0), .slv2_awlen(8'h0),
        .slv2_awsize(3'b010), .slv2_awburst(2'b01), .slv2_awlock(1'b0), .slv2_awcache(4'h0),
        .slv2_awprot(3'b010), .slv2_awqos(4'h0), .slv2_awregion(4'h0), .slv2_awid(8'h0), .slv2_awuser(1'b0),
        .slv2_wvalid(1'b0), .slv2_wready(), .slv2_wlast(1'b0), .slv2_wdata(32'h0), .slv2_wstrb(4'h0), .slv2_wuser(1'b0),
        .slv2_bvalid(), .slv2_bready(1'b0), .slv2_bid(), .slv2_bresp(), .slv2_buser(),
        .slv2_arvalid(1'b0), .slv2_arready(), .slv2_araddr(16'h0), .slv2_arlen(8'h0), .slv2_arsize(3'b010),
        .slv2_arburst(2'b01), .slv2_arlock(1'b0), .slv2_arcache(4'h0), .slv2_arprot(3'b010),
        .slv2_arqos(4'h0), .slv2_arregion(4'h0), .slv2_arid(8'h0), .slv2_aruser(1'b0),
        .slv2_rvalid(), .slv2_rready(1'b0), .slv2_rid(), .slv2_rresp(), .slv2_rdata(), .slv2_rlast(), .slv2_ruser(),
        .slv3_aclk(aclk), .slv3_aresetn(aresetn), .slv3_srst(srst),
        .slv3_awvalid(1'b0), .slv3_awready(), .slv3_awaddr(16'h0), .slv3_awlen(8'h0),
        .slv3_awsize(3'b010), .slv3_awburst(2'b01), .slv3_awlock(1'b0), .slv3_awcache(4'h0),
        .slv3_awprot(3'b010), .slv3_awqos(4'h0), .slv3_awregion(4'h0), .slv3_awid(8'h0), .slv3_awuser(1'b0),
        .slv3_wvalid(1'b0), .slv3_wready(), .slv3_wlast(1'b0), .slv3_wdata(32'h0), .slv3_wstrb(4'h0), .slv3_wuser(1'b0),
        .slv3_bvalid(), .slv3_bready(1'b0), .slv3_bid(), .slv3_bresp(), .slv3_buser(),
        .slv3_arvalid(1'b0), .slv3_arready(), .slv3_araddr(16'h0), .slv3_arlen(8'h0), .slv3_arsize(3'b010),
        .slv3_arburst(2'b01), .slv3_arlock(1'b0), .slv3_arcache(4'h0), .slv3_arprot(3'b010),
        .slv3_arqos(4'h0), .slv3_arregion(4'h0), .slv3_arid(8'h0), .slv3_aruser(1'b0),
        .slv3_rvalid(), .slv3_rready(1'b0), .slv3_rid(), .slv3_rresp(), .slv3_rdata(), .slv3_rlast(), .slv3_ruser(),
        .mst0_aclk(aclk), .mst0_aresetn(aresetn), .mst0_srst(srst),
        .mst0_awvalid(mst0_awvalid), .mst0_awready(mst0_awready),
        .mst0_awaddr(mst0_awaddr), .mst0_awlen(mst0_awlen), .mst0_awsize(mst0_awsize),
        .mst0_awburst(), .mst0_awlock(), .mst0_awcache(), .mst0_awprot(), .mst0_awqos(), .mst0_awregion(),
        .mst0_awid(mst0_awid), .mst0_awuser(),
        .mst0_wvalid(mst0_wvalid), .mst0_wready(mst0_wready), .mst0_wlast(mst0_wlast),
        .mst0_wdata(mst0_wdata), .mst0_wstrb(mst0_wstrb), .mst0_wuser(),
        .mst0_bvalid(mst0_bvalid), .mst0_bready(mst0_bready), .mst0_bid(mst0_bid),
        .mst0_bresp(mst0_bresp), .mst0_buser(1'b0),
        .mst0_arvalid(mst0_arvalid), .mst0_arready(mst0_arready),
        .mst0_araddr(mst0_araddr), .mst0_arlen(mst0_arlen), .mst0_arsize(mst0_arsize),
        .mst0_arburst(), .mst0_arlock(), .mst0_arcache(), .mst0_arprot(), .mst0_arqos(), .mst0_arregion(),
        .mst0_arid(mst0_arid), .mst0_aruser(),
        .mst0_rvalid(mst0_rvalid), .mst0_rready(mst0_rready), .mst0_rid(mst0_rid),
        .mst0_rresp(mst0_rresp), .mst0_rdata(mst0_rdata), .mst0_rlast(mst0_rlast), .mst0_ruser(1'b0),
        .mst1_aclk(aclk), .mst1_aresetn(aresetn), .mst1_srst(srst),
        .mst1_awvalid(), .mst1_awready(1'b0), .mst1_awaddr(), .mst1_awlen(), .mst1_awsize(),
        .mst1_awburst(), .mst1_awlock(), .mst1_awcache(), .mst1_awprot(), .mst1_awqos(), .mst1_awregion(),
        .mst1_awid(), .mst1_awuser(),
        .mst1_wvalid(), .mst1_wready(1'b0), .mst1_wlast(), .mst1_wdata(), .mst1_wstrb(), .mst1_wuser(),
        .mst1_bvalid(1'b0), .mst1_bready(), .mst1_bid(8'h0), .mst1_bresp(2'b00), .mst1_buser(1'b0),
        .mst1_arvalid(), .mst1_arready(1'b0), .mst1_araddr(), .mst1_arlen(), .mst1_arsize(),
        .mst1_arburst(), .mst1_arlock(), .mst1_arcache(), .mst1_arprot(), .mst1_arqos(), .mst1_arregion(),
        .mst1_arid(), .mst1_aruser(),
        .mst1_rvalid(1'b0), .mst1_rready(), .mst1_rid(8'h0), .mst1_rresp(2'b00),
        .mst1_rdata(32'h0), .mst1_rlast(1'b0), .mst1_ruser(1'b0),
        .mst2_aclk(aclk), .mst2_aresetn(aresetn), .mst2_srst(srst),
        .mst2_awvalid(), .mst2_awready(1'b0), .mst2_awaddr(), .mst2_awlen(), .mst2_awsize(),
        .mst2_awburst(), .mst2_awlock(), .mst2_awcache(), .mst2_awprot(), .mst2_awqos(), .mst2_awregion(),
        .mst2_awid(), .mst2_awuser(),
        .mst2_wvalid(), .mst2_wready(1'b0), .mst2_wlast(), .mst2_wdata(), .mst2_wstrb(), .mst2_wuser(),
        .mst2_bvalid(1'b0), .mst2_bready(), .mst2_bid(8'h0), .mst2_bresp(2'b00), .mst2_buser(1'b0),
        .mst2_arvalid(), .mst2_arready(1'b0), .mst2_araddr(), .mst2_arlen(), .mst2_arsize(),
        .mst2_arburst(), .mst2_arlock(), .mst2_arcache(), .mst2_arprot(), .mst2_arqos(), .mst2_arregion(),
        .mst2_arid(), .mst2_aruser(),
        .mst2_rvalid(1'b0), .mst2_rready(), .mst2_rid(8'h0), .mst2_rresp(2'b00),
        .mst2_rdata(32'h0), .mst2_rlast(1'b0), .mst2_ruser(1'b0),
        .mst3_aclk(aclk), .mst3_aresetn(aresetn), .mst3_srst(srst),
        .mst3_awvalid(), .mst3_awready(1'b0), .mst3_awaddr(), .mst3_awlen(), .mst3_awsize(),
        .mst3_awburst(), .mst3_awlock(), .mst3_awcache(), .mst3_awprot(), .mst3_awqos(), .mst3_awregion(),
        .mst3_awid(), .mst3_awuser(),
        .mst3_wvalid(), .mst3_wready(1'b0), .mst3_wlast(), .mst3_wdata(), .mst3_wstrb(), .mst3_wuser(),
        .mst3_bvalid(1'b0), .mst3_bready(), .mst3_bid(8'h0), .mst3_bresp(2'b00), .mst3_buser(1'b0),
        .mst3_arvalid(), .mst3_arready(1'b0), .mst3_araddr(), .mst3_arlen(), .mst3_arsize(),
        .mst3_arburst(), .mst3_arlock(), .mst3_arcache(), .mst3_arprot(), .mst3_arqos(), .mst3_arregion(),
        .mst3_arid(), .mst3_aruser(),
        .mst3_rvalid(1'b0), .mst3_rready(), .mst3_rid(8'h0), .mst3_rresp(2'b00),
        .mst3_rdata(32'h0), .mst3_rlast(1'b0), .mst3_ruser(1'b0)
    );

    integer pass = 0, fail = 0;

    initial begin
        slv0_awvalid=0; slv0_awaddr=0; slv0_awlen=0; slv0_awsize=3'b010; slv0_awid=0;
        slv0_wvalid=0; slv0_wlast=0; slv0_wdata=0; slv0_wstrb=0; slv0_bready=0;
        slv0_arvalid=0; slv0_araddr=0; slv0_arlen=0; slv0_arsize=3'b010; slv0_arid=0; slv0_rready=0;

        @(posedge aresetn); repeat(10) @(posedge aclk);

        $display("");
        $display("============================================");
        $display(" AXI Crossbar Simple Test");
        $display("============================================");
        $display("");

        // Test 1: Write to SLV0
        $display("[TEST 1] Write to Slave 0");
        @(posedge aclk);
        slv0_awvalid=1; slv0_awaddr=16'h0000; slv0_awid=8'h0F;
        @(posedge aclk iff slv0_awready);
        slv0_awvalid=0;
        slv0_wvalid=1; slv0_wdata=32'hDEADBEEF; slv0_wstrb=4'hF; slv0_wlast=1;
        @(posedge aclk iff slv0_wready);
        slv0_wvalid=0; slv0_wlast=0;
        slv0_bready=1;
        @(posedge aclk iff slv0_bvalid);
        $display("  BRESP=%0d BID=0x%02h", slv0_bresp, slv0_bid);
        if (slv0_bresp==2'b00) pass=pass+1; else fail=fail+1;
        slv0_bready=0;
        #20;

        // Test 2: Read from SLV0
        $display("[TEST 2] Read from Slave 0");
        @(posedge aclk);
        slv0_arvalid=1; slv0_araddr=16'h0000; slv0_arid=8'h0F;
        @(posedge aclk iff slv0_arready);
        slv0_arvalid=0;
        slv0_rready=1;
        @(posedge aclk iff slv0_rvalid);
        $display("  RRESP=%0d RDATA=0x%08h", slv0_rresp, slv0_rdata);
        if (slv0_rresp==2'b00) pass=pass+1; else fail=fail+1;
        slv0_rready=0;
        #20;

        // Test 3: Write to SLV1
        $display("[TEST 3] Write to Slave 1");
        @(posedge aclk);
        slv0_awvalid=1; slv0_awaddr=16'h1000; slv0_awid=8'h0F;
        @(posedge aclk iff slv0_awready);
        slv0_awvalid=0;
        slv0_wvalid=1; slv0_wdata=32'hCAFEBABE; slv0_wstrb=4'hF; slv0_wlast=1;
        @(posedge aclk iff slv0_wready);
        slv0_wvalid=0; slv0_wlast=0;
        slv0_bready=1;
        @(posedge aclk iff slv0_bvalid);
        $display("  BRESP=%0d BID=0x%02h", slv0_bresp, slv0_bid);
        if (slv0_bresp==2'b00) pass=pass+1; else fail=fail+1;
        slv0_bready=0;
        #20;

        $display("");
        $display("============================================");
        $display(" Results: %0d passed, %0d failed", pass, fail);
        $display("============================================");
        if (fail==0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $display("");
        #100; $finish;
    end

    initial begin #20000; $display("[TIMEOUT]"); $finish; end
    initial begin $dumpfile("axi_simple_test.vcd"); $dumpvars(0, axi_simple_test); end
endmodule
