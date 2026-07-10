//==========================================================================
// Write Sequence
//==========================================================================
class axi_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_seq)
    bit [15:0] s_addr;
    bit [31:0] s_data;
    bit [7:0]  s_id;

    function new(string name = "axi_wr_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind = axi_txn::WRITE;
        txn.addr = s_addr; txn.id = s_id;
        txn.len = 0; txn.size = 2;
        txn.wdata = new[1]; txn.wstrb = new[1];
        txn.wdata[0] = s_data; txn.wstrb[0] = 4'hF;
        start_item(txn); finish_item(txn);
    endtask
endclass
