`timescale 1ns/1ps

interface axi_if #(
    parameter AXI_ADDR_W = 16,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
)(
    input logic aclk
);

    // aresetn: 可由 testbench 驱动，也可由 test 通过 vif 驱动
    logic aresetn = 0;

    // Write Address Channel
    logic                  awvalid, awready;
    logic [AXI_ADDR_W-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache, awqos, awregion;
    logic [2:0]            awprot;
    logic [AXI_ID_W-1:0]   awid;

    // Write Data Channel
    logic                  wvalid, wready, wlast;
    logic [AXI_DATA_W-1:0] wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;

    // Write Response Channel
    logic                  bvalid, bready;
    logic [AXI_ID_W-1:0]   bid;
    logic [1:0]            bresp;

    // Read Address Channel
    logic                  arvalid, arready;
    logic [AXI_ADDR_W-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache, arqos, arregion;
    logic [2:0]            arprot;
    logic [AXI_ID_W-1:0]   arid;

    // Read Data Channel
    logic                  rvalid, rready, rlast;
    logic [AXI_ID_W-1:0]   rid;
    logic [1:0]            rresp;
    logic [AXI_DATA_W-1:0] rdata;

    // Modports
    modport master (
        input  aclk, aresetn,
        output awvalid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awqos, awregion, awid,
        input  awready,
        output wvalid, wlast, wdata, wstrb,
        input  wready,
        input  bvalid, bid, bresp,
        output bready,
        output arvalid, araddr, arlen, arsize, arburst, arlock,
               arcache, arprot, arqos, arregion, arid,
        input  arready,
        input  rvalid, rid, rresp, rdata, rlast,
        output rready
    );

    modport slave (
        input  aclk, aresetn,
        input  awvalid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awqos, awregion, awid,
        output awready,
        input  wvalid, wlast, wdata, wstrb,
        output wready,
        output bvalid, bid, bresp,
        input  bready,
        input  arvalid, araddr, arlen, arsize, arburst, arlock,
               arcache, arprot, arqos, arregion, arid,
        output arready,
        output rvalid, rid, rresp, rdata, rlast,
        input  rready
    );

    // SVA: valid stability checks
    property sig_stable(sig, ready);
        @(posedge aclk) disable iff (!aresetn)
        sig && !ready |=> sig;
    endproperty

    assert property (sig_stable(awvalid, awready)) else $error("[SVA] AWVALID unstable");
    assert property (sig_stable(wvalid, wready))   else $error("[SVA] WVALID unstable");
    assert property (sig_stable(bvalid, bready))   else $error("[SVA] BVALID unstable");
    assert property (sig_stable(arvalid, arready))  else $error("[SVA] ARVALID unstable");
    assert property (sig_stable(rvalid, rready))   else $error("[SVA] RVALID unstable");

    assert property (@(posedge aclk) disable iff (!aresetn) wlast |-> wvalid)
        else $error("[SVA] WLAST without WVALID");
    assert property (@(posedge aclk) disable iff (!aresetn) rlast |-> rvalid)
        else $error("[SVA] RLAST without RVALID");

endinterface
