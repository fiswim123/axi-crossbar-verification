//==========================================================================
// Slave Configuration (Error Injection & Backpressure)
//==========================================================================
class axi_slv_cfg extends uvm_object;
    `uvm_object_utils(axi_slv_cfg)

    // Error injection
    int unsigned err_pct = 0;          // Error response probability (0-100)
    bit [1:0]    err_resp = 2'b10;     // SLVERR=2'b10, DECERR=2'b11

    // Latency control
    int unsigned delay_min = 0;        // Minimum delay cycles
    int unsigned delay_max = 0;        // Maximum delay cycles

    // Backpressure
    int unsigned bp_awready_pct = 0;   // AW channel backpressure (0-100)
    int unsigned bp_wready_pct = 0;    // W channel backpressure
    int unsigned bp_arready_pct = 0;   // AR channel backpressure

    function new(string name = "axi_slv_cfg");
        super.new(name);
    endfunction

    // Randomize delay
    function int get_delay();
        if (delay_max == 0) return 0;
        return $urandom_range(delay_min, delay_max);
    endfunction

    // Check if should inject error
    function bit should_error();
        return ($urandom_range(0, 99) < err_pct);
    endfunction

    // Check if should apply backpressure
    function bit should_bp(int channel);
        case (channel)
            0: return ($urandom_range(0, 99) < bp_awready_pct);
            1: return ($urandom_range(0, 99) < bp_wready_pct);
            2: return ($urandom_range(0, 99) < bp_arready_pct);
            default: return 0;
        endcase
    endfunction
endclass
