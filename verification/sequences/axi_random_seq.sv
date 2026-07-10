//==========================================================================
// Random Test Sequence
//==========================================================================
class axi_random_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_random_seq)
    int s_count = 100;

    function new(string name = "axi_random_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        bit [15:0] addrs[4];
        addrs = '{16'h0000, 16'h1000, 16'h2000, 16'h3000};

        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("rand_%0d", i));
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;
            txn.addr = addrs[i % 4];
            txn.id = 8'h10;
            txn.len = 0;
            txn.size = 2;
            txn.burst = 1;
            if (txn.kind == axi_txn::WRITE) begin
                txn.wdata = new[1];
                txn.wstrb = new[1];
                txn.wdata[0] = 32'hA500_0000 + i;
                txn.wstrb[0] = 4'hF;
            end else begin
                txn.rdata = new[1];
            end
            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// Random Concurrent Sequence (Multiple Masters)
//==========================================================================
class axi_random_concurrent_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_random_concurrent_seq)
    int s_count = 50;

    function new(string name = "axi_random_concurrent_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        bit [15:0] addrs[4];
        addrs = '{16'h0000, 16'h1000, 16'h2000, 16'h3000};

        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("rc_%0d", i));
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;
            txn.addr = addrs[i % 4];
            txn.id = 8'h20;
            txn.len = 0;
            txn.size = 2;
            txn.burst = 1;
            if (txn.kind == axi_txn::WRITE) begin
                txn.wdata = new[1];
                txn.wstrb = new[1];
                txn.wdata[0] = 32'hB600_0000 + i;
                txn.wstrb[0] = 4'hF;
            end else begin
                txn.rdata = new[1];
            end
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
