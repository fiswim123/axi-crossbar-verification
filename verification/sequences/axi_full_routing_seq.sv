//==========================================================================
// Full Routing Sequence — 补全缺失的路由组合
// 已覆盖: MST0→SLV0/1/2/3, MST1→SLV0, MST2→SLV1, MST3→SLV3
// 待覆盖: MST1→SLV1/2/3, MST2→SLV0/2/3, MST3→SLV0/1/2
//==========================================================================
class axi_full_routing_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_full_routing_seq)
    bit [7:0]  s_id;
    bit [15:0] s_addr;

    function new(string name = "axi_full_routing_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind  = axi_txn::WRITE;
        txn.addr  = s_addr;
        txn.id    = s_id;
        txn.len   = 0;
        txn.size  = 2;
        txn.wdata = new[1];
        txn.wstrb = new[1];
        txn.wdata[0] = 32'hC0DE_0000;
        txn.wstrb[0] = 4'hF;
        start_item(txn);
        finish_item(txn);
    endtask
endclass
