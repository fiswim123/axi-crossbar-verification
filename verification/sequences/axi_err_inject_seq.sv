//==========================================================================
// Error Injection Sequence
//==========================================================================
class axi_err_inject_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_err_inject_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    bit        s_expect_err;

    function new(string name = "axi_err_inject_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;

        // Write with error expected
        txn = axi_txn::type_id::create("wr_err");
        txn.kind = axi_txn::WRITE;
        txn.addr = s_addr; txn.id = s_id;
        txn.len = 0; txn.size = 2; txn.burst = 1;
        txn.wdata = new[1]; txn.wstrb = new[1];
        txn.wdata[0] = 32'hDEAD_BEEF;
        txn.wstrb[0] = 4'hF;
        txn.expect_err = s_expect_err;
        start_item(txn); finish_item(txn);

        // Read same address
        txn = axi_txn::type_id::create("rd_err");
        txn.kind = axi_txn::READ;
        txn.addr = s_addr; txn.id = s_id;
        txn.len = 0; txn.size = 2; txn.burst = 1;
        txn.rdata = new[1];
        txn.expect_err = s_expect_err;
        start_item(txn); finish_item(txn);
    endtask
endclass

//==========================================================================
// Multiple Error Injection Sequence
//==========================================================================
class axi_err_multi_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_err_multi_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    int        s_count = 4;

    function new(string name = "axi_err_multi_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("txn_%0d", i));
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            if (txn.kind == axi_txn::WRITE) begin
                txn.wdata = new[1]; txn.wstrb = new[1];
                txn.wdata[0] = 32'hCAFE_0000 + i;
                txn.wstrb[0] = 4'hF;
            end else begin
                txn.rdata = new[1];
            end
            // 50% chance of error expectation
            txn.expect_err = ($urandom_range(0, 1) == 0);
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
