//==========================================================================
// Coverage
//==========================================================================
class axi_coverage extends uvm_subscriber #(axi_txn);
    `uvm_component_utils(axi_coverage)

    axi_txn txn;

    covergroup cg;
        cp_kind: coverpoint txn.kind {
            bins rd = {0}; bins wr = {1};
        }
        cp_slave: coverpoint txn.addr[15:12] {
            bins s0 = {0}; bins s1 = {1}; bins s2 = {2}; bins s3 = {3};
        }
        cp_master: coverpoint txn.id[7:4] {
            bins m0 = {1}; bins m1 = {2}; bins m2 = {3}; bins m3 = {4};
        }
        cp_len: coverpoint txn.len {
            bins single = {0}; bins short = {[1:3]};
            bins med    = {[4:7]}; bins long_b = {[8:15]};
        }
        cp_size: coverpoint txn.size {
            bins b1 = {0}; bins b2 = {1}; bins b4 = {2};
        }
        cp_resp: coverpoint (txn.kind ? txn.bresp : txn.rresp) {
            bins okay = {0};
        }

        cx_routing:   cross cp_master, cp_slave;
        cx_kind_len:  cross cp_kind, cp_len;
        cx_kind_size: cross cp_kind, cp_size;
        cx_kind_slave: cross cp_kind, cp_slave;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg = new();
    endfunction

    function void write(axi_txn t);
        txn = t;
        cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Coverage: %.1f%%", cg.get_coverage()), UVM_LOW)
    endfunction
endclass
