///////////////////////////////////////////////////////////////////////////////
//
// AXI Transaction Class
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

class axi_transaction #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
);

    // Transaction type
    typedef enum {READ, WRITE} txn_type_e;
    rand txn_type_e txn_type;

    // Address channel fields
    rand bit [AXI_ADDR_W-1:0] addr;
    rand bit [AXI_ID_W-1:0]   id;
    rand bit [7:0]             len;
    rand bit [2:0]             size;
    rand bit [1:0]             burst;
    rand bit                   lock;
    rand bit [3:0]             cache;
    rand bit [2:0]             prot;
    rand bit [3:0]             qos;
    rand bit [3:0]             region;

    // Write data
    rand bit [AXI_DATA_W-1:0]   wdata[];
    rand bit [AXI_DATA_W/8-1:0] wstrb[];

    // Response
    bit [AXI_ID_W-1:0] bid;
    bit [1:0]           bresp;
    bit [AXI_ID_W-1:0] rid;
    bit [1:0]           rresp;
    bit [AXI_DATA_W-1:0] rdata[];

    // Constraints
    constraint c_size {
        size inside {[0:2]};  // Max 4 bytes per beat
        (1 << size) <= AXI_DATA_W / 8;
    }

    constraint c_len {
        len inside {[0:15]};  // AXI4 supports 1-256 beats
    }

    constraint c_burst {
        burst inside {2'b00, 2'b01};  // FIXED or INCR
    }

    constraint c_aligned {
        addr % (1 << size) == 0;  // Aligned address
    }

    constraint c_wdata_size {
        wdata.size() == len + 1;
        wstrb.size() == len + 1;
    }

    constraint c_cache {
        cache inside {4'h0, 4'h2, 4'h3};  // Common cache values
    }

    // Constructor
    function new();
        burst = 2'b01;  // Default INCR
        lock  = 1'b0;
        prot  = 3'b010;  // Data, secure, unprivileged
        qos   = 4'h0;
        region = 4'h0;
    endfunction

    // Copy
    function axi_transaction copy();
        axi_transaction txn = new();
        txn.txn_type = this.txn_type;
        txn.addr     = this.addr;
        txn.id       = this.id;
        txn.len      = this.len;
        txn.size     = this.size;
        txn.burst    = this.burst;
        txn.lock     = this.lock;
        txn.cache    = this.cache;
        txn.prot     = this.prot;
        txn.qos      = this.qos;
        txn.region   = this.region;
        txn.wdata    = new[this.wdata.size()];
        txn.wstrb    = new[this.wstrb.size()];
        foreach(wdata[i]) txn.wdata[i] = this.wdata[i];
        foreach(wstrb[i]) txn.wstrb[i] = this.wstrb[i];
        return txn;
    endfunction

    // Print
    function void print();
        $display("=== AXI Transaction ===");
        $display("Type:  %s", txn_type.name());
        $display("Addr:  0x%08h", addr);
        $display("ID:    0x%02h", id);
        $display("Len:   %0d", len);
        $display("Size:  %0d (bytes: %0d)", size, 1<<size);
        $display("Burst: %0d", burst);
        if (txn_type == WRITE) begin
            $display("WData: %0d beats", wdata.size());
            foreach(wdata[i]) begin
                $display("  [%0d]: data=0x%08h strb=0b%04b", i, wdata[i], wstrb[i]);
            end
        end
        $display("========================");
    endfunction

endclass
