//==========================================================================
// Read/Write Interleave Sequence (T042)
//==========================================================================
class axi_interleave_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_interleave_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_interleave_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        for (int i = 0; i < 4; i++) begin
            // Write
            txn = axi_txn::type_id::create($sformatf("wr_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'h1EAF0000 + i;
            txn.wstrb[0] = 4'hF;
            start_item(txn); finish_item(txn);

            // Read same address
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
