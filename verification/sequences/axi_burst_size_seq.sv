//==========================================================================
// Burst Size Sequence (T024)
//==========================================================================
class axi_burst_size_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_burst_size_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_burst_size_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        for (int sz = 0; sz <= 2; sz++) begin
            txn = axi_txn::type_id::create($sformatf("txn_%0d", sz));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 0; txn.size = sz[2:0]; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hA500_0000 + sz;
            txn.wstrb[0] = (1 << (1 << sz)) - 1;
            start_item(txn); finish_item(txn);
        end
        // Read back each
        for (int sz = 0; sz <= 2; sz++) begin
            txn = axi_txn::type_id::create($sformatf("rd_%0d", sz));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 0; txn.size = sz[2:0]; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
