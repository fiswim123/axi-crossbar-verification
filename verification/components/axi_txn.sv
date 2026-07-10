//==========================================================================
// Transaction
//==========================================================================
class axi_txn extends uvm_sequence_item;
    typedef enum {READ, WRITE} kind_e;
    rand kind_e     kind;
    rand bit [15:0] addr;
    rand bit [7:0]  id;
    rand bit [7:0]  len;
    rand bit [2:0]  size;
    rand bit [1:0]  burst;
    rand bit [31:0] wdata[];
    rand bit [3:0]  wstrb[];
    bit [7:0]  bid, rid;
    bit [1:0]  bresp, rresp;
    bit [31:0] rdata[];

    // Performance tracking
    time aw_time, w_time, b_time;    // Write timing
    time ar_time, r_time;            // Read timing
    int  wr_latency, rd_latency;     // Calculated latency

    // Error injection flag (for scoreboard)
    bit expect_err = 0;

    constraint c_basic {
        size inside {[0:2]};
        len  inside {[0:15]};
        burst == 2'b01;
        addr[1:0] == 2'b00;
        wdata.size() == len + 1;
        wstrb.size() == len + 1;
    }

    // Boundary test constraints
    constraint c_boundary_addr {
        addr inside {16'h0000, 16'h0004, 16'h0FFC, 16'h1000,
                     16'h1FFC, 16'h2000, 16'h2FFC, 16'h3000,
                     16'h3FFC};
    }

    constraint c_boundary_burst {
        len inside {0, 1, 3, 7, 15};
    }

    constraint c_boundary_id {
        id inside {8'h00, 8'h0F, 8'h10, 8'h1F, 8'hFF};
    }

    `uvm_object_utils_begin(axi_txn)
        `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(id,    UVM_ALL_ON)
        `uvm_field_int(len,   UVM_ALL_ON)
        `uvm_field_int(size,  UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_array_int(wdata, UVM_ALL_ON)
        `uvm_field_array_int(wstrb, UVM_ALL_ON)
        `uvm_field_int(bresp, UVM_ALL_ON)
        `uvm_field_int(rresp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_txn");
        super.new(name);
    endfunction

    // Calculate write latency
    function int calc_wr_latency();
        if (aw_time > 0 && b_time > 0)
            return (b_time - aw_time) / 1000; // ns
        return 0;
    endfunction

    // Calculate read latency
    function int calc_rd_latency();
        if (ar_time > 0 && r_time > 0)
            return (r_time - ar_time) / 1000; // ns
        return 0;
    endfunction
endclass
