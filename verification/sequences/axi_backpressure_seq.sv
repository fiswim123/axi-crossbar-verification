//==========================================================================
// Backpressure Test Sequence
//==========================================================================
class axi_backpressure_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_backpressure_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    int        s_count = 4;

    function new(string name = "axi_backpressure_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        for (int i = 0; i < s_count; i++) begin
            // Write
            txn = axi_txn::type_id::create($sformatf("bpw_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 3; txn.size = 2; txn.burst = 1; // 4-beat burst
            txn.wdata = new[4]; txn.wstrb = new[4];
            for (int j = 0; j < 4; j++) begin
                txn.wdata[j] = 32'hBA5E_0000 + i * 4 + j;
                txn.wstrb[j] = 4'hF;
            end
            start_item(txn); finish_item(txn);

            // Read
            txn = axi_txn::type_id::create($sformatf("bpr_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 3; txn.size = 2; txn.burst = 1;
            txn.rdata = new[4];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
