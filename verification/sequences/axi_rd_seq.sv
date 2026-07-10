//==========================================================================
// Read Sequence
//==========================================================================
class axi_rd_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_rd_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_rd_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind = axi_txn::READ;
        txn.addr = s_addr; txn.id = s_id;
        txn.len = 0; txn.size = 2;
        txn.rdata = new[1];
        start_item(txn); finish_item(txn);
    endtask
endclass
