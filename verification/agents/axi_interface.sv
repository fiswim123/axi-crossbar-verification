///////////////////////////////////////////////////////////////////////////////
//
// AXI4 Interface Definition
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

interface axi_interface #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
)(
    input logic aclk,
    input logic aresetn
);

    // Write Address Channel
    logic                      awvalid;
    logic                      awready;
    logic [AXI_ADDR_W-1:0]     awaddr;
    logic [7:0]                awlen;
    logic [2:0]                awsize;
    logic [1:0]                awburst;
    logic                      awlock;
    logic [3:0]                awcache;
    logic [2:0]                awprot;
    logic [3:0]                awqos;
    logic [3:0]                awregion;
    logic [AXI_ID_W-1:0]       awid;
    logic [0:0]                awuser;

    // Write Data Channel
    logic                      wvalid;
    logic                      wready;
    logic                      wlast;
    logic [AXI_DATA_W-1:0]     wdata;
    logic [AXI_DATA_W/8-1:0]   wstrb;
    logic [0:0]                wuser;

    // Write Response Channel
    logic                      bvalid;
    logic                      bready;
    logic [AXI_ID_W-1:0]       bid;
    logic [1:0]                bresp;
    logic [0:0]                buser;

    // Read Address Channel
    logic                      arvalid;
    logic                      arready;
    logic [AXI_ADDR_W-1:0]     araddr;
    logic [7:0]                arlen;
    logic [2:0]                arsize;
    logic [1:0]                arburst;
    logic                      arlock;
    logic [3:0]                arcache;
    logic [2:0]                arprot;
    logic [3:0]                arqos;
    logic [3:0]                arregion;
    logic [AXI_ID_W-1:0]       arid;
    logic [0:0]                aruser;

    // Read Data Channel
    logic                      rvalid;
    logic                      rready;
    logic [AXI_ID_W-1:0]       rid;
    logic [1:0]                rresp;
    logic [AXI_DATA_W-1:0]     rdata;
    logic                      rlast;
    logic [0:0]                ruser;

    // Clocking block for master driver
    clocking mst_drv_cb @(posedge aclk);
        default input #1 output #1;
        output awvalid, awaddr, awlen, awsize, awburst, awlock;
        output awcache, awprot, awqos, awregion, awid, awuser;
        output wvalid, wlast, wdata, wstrb, wuser;
        output bready;
        output arvalid, araddr, arlen, arsize, arburst, arlock;
        output arcache, arprot, arqos, arregion, arid, aruser;
        output rready;
        input awready, wready, bvalid, bid, bresp, buser;
        input arready, rvalid, rid, rresp, rdata, rlast, ruser;
    endclocking

    // Clocking block for master monitor
    clocking mst_mon_cb @(posedge aclk);
        default input #1 output #1;
        input awvalid, awready, awaddr, awlen, awsize, awburst, awlock;
        input awcache, awprot, awqos, awregion, awid, awuser;
        input wvalid, wready, wlast, wdata, wstrb, wuser;
        input bvalid, bready, bid, bresp, buser;
        input arvalid, arready, araddr, arlen, arsize, arburst, arlock;
        input arcache, arprot, arqos, arregion, arid, aruser;
        input rvalid, rready, rid, rresp, rdata, rlast, ruser;
    endclocking

    // Clocking block for slave driver
    clocking slv_drv_cb @(posedge aclk);
        default input #1 output #1;
        output awready;
        output wready;
        output bvalid, bid, bresp, buser;
        output arready;
        output rvalid, rid, rresp, rdata, rlast, ruser;
        input awvalid, awaddr, awlen, awsize, awburst, awlock;
        input awcache, awprot, awqos, awregion, awid, awuser;
        input wvalid, wlast, wdata, wstrb, wuser;
        input bready;
        input arvalid, araddr, arlen, arsize, arburst, arlock;
        input arcache, arprot, arqos, arregion, arid, aruser;
        input rready;
    endclocking

    // Clocking block for slave monitor
    clocking slv_mon_cb @(posedge aclk);
        default input #1 output #1;
        input awvalid, awready, awaddr, awlen, awsize, awburst, awlock;
        input awcache, awprot, awqos, awregion, awid, awuser;
        input wvalid, wready, wlast, wdata, wstrb, wuser;
        input bvalid, bready, bid, bresp, buser;
        input arvalid, arready, araddr, arlen, arsize, arburst, arlock;
        input arcache, arprot, arqos, arregion, arid, aruser;
        input rvalid, rready, rid, rresp, rdata, rlast, ruser;
    endclocking

    // Modports
    modport master_driver (clocking mst_drv_cb, input aclk, aresetn);
    modport master_monitor (clocking mst_mon_cb, input aclk, aresetn);
    modport slave_driver (clocking slv_drv_cb, input aclk, aresetn);
    modport slave_monitor (clocking slv_mon_cb, input aclk, aresetn);

    //--------------------------------------------------------------------------
    // Protocol Checks
    //--------------------------------------------------------------------------

    // Check: AWVALID must remain asserted until AWREADY
    property awvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        awvalid && !awready |=> awvalid;
    endproperty
    assert property (awvalid_stable) else
        $error("AWVALID deasserted before AWREADY");

    // Check: WVALID must remain asserted until WREADY
    property wvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        wvalid && !wready |=> wvalid;
    endproperty
    assert property (wvalid_stable) else
        $error("WVALID deasserted before WREADY");

    // Check: BVALID must remain asserted until BREADY
    property bvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        bvalid && !bready |=> bvalid;
    endproperty
    assert property (bvalid_stable) else
        $error("BVALID deasserted before BREADY");

    // Check: ARVALID must remain asserted until ARREADY
    property arvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (arvalid_stable) else
        $error("ARVALID deasserted before ARREADY");

    // Check: RVALID must remain asserted until RREADY
    property rvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        rvalid && !rready |=> rvalid;
    endproperty
    assert property (rvalid_stable) else
        $error("RVALID deasserted before RREADY");

    // Check: RLAST assertion with RVALID
    property rlast_with_rvalid;
        @(posedge aclk) disable iff (!aresetn)
        rlast |-> rvalid;
    endproperty
    assert property (rlast_with_rvalid) else
        $error("RLAST asserted without RVALID");

endinterface
