//==========================================================================
// Same Slave Contention Sequence (T041)
//==========================================================================
class axi_same_slave_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_same_slave_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_same_slave_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("txn_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hC0DE0000 + s_id;
            txn.wstrb[0] = 4'hF;
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
