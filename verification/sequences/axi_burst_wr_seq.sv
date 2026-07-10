//==========================================================================
// Burst Write Sequence
//==========================================================================
class axi_burst_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_burst_wr_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    bit [7:0]  s_len;

    function new(string name = "axi_burst_wr_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind = axi_txn::WRITE;
        txn.addr = s_addr; txn.id = s_id;
        txn.len = s_len; txn.size = 2;
        txn.wdata = new[s_len + 1]; txn.wstrb = new[s_len + 1];
        for (int i = 0; i <= s_len; i++) begin
            txn.wdata[i] = 32'hA500_0000 + i;
            txn.wstrb[i] = 4'hF;
        end
        start_item(txn); finish_item(txn);
    endtask
endclass
