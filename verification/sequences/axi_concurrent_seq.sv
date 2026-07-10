//==========================================================================
// Concurrent Read/Write Sequence
//==========================================================================
class axi_concurrent_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_concurrent_seq)

    function new(string name = "axi_concurrent_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info(get_type_name(), "Starting concurrent read/write sequence", UVM_LOW)

        fork
            // 写通道
            begin
                for (int i = 0; i < 8; i++) begin
                    req = axi_txn::type_id::create($sformatf("cwr_%0d", i));
                    start_item(req);
                    assert(req.randomize() with {
                        kind == axi_txn::WRITE;
                        addr inside {16'h0100, 16'h0200, 16'h0400, 16'h0800};
                    });
                    finish_item(req);
                end
            end
            // 读通道
            begin
                for (int i = 0; i < 8; i++) begin
                    req = axi_txn::type_id::create($sformatf("crd_%0d", i));
                    start_item(req);
                    assert(req.randomize() with {
                        kind == axi_txn::READ;
                        addr inside {16'h0100, 16'h0200, 16'h0400, 16'h0800};
                    });
                    finish_item(req);
                end
            end
        join

        `uvm_info(get_type_name(), "Concurrent read/write sequence completed", UVM_LOW)
    endtask
endclass
