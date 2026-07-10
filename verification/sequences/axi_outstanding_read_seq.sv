//==========================================================================
// Outstanding Read Sequence (T031)
//==========================================================================
class axi_outstanding_read_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_outstanding_read_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_outstanding_read_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        // Send 4 read requests back-to-back
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
