//==========================================================================
// Boundary Test Sequence
//==========================================================================
class axi_boundary_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_boundary_seq)
    bit [7:0] s_id;

    function new(string name = "axi_boundary_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        bit [15:0] addrs[9];
        addrs = '{16'h0000, 16'h0004, 16'h0FFC, 16'h1000,
                  16'h1FFC, 16'h2000, 16'h2FFC, 16'h3000,
                  16'h3FFC};

        // Test boundary addresses
        foreach (addrs[i]) begin
            txn = axi_txn::type_id::create($sformatf("addr_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = addrs[i]; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hB000_0000 + i;
            txn.wstrb[0] = 4'hF;
            start_item(txn); finish_item(txn);
        end

        // Read back
        foreach (addrs[i]) begin
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = addrs[i]; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// Max Burst Length Sequence
//==========================================================================
class axi_max_burst_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_max_burst_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;

    function new(string name = "axi_max_burst_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        // Test burst lengths: 1, 2, 4, 8, 16
        int lengths[5] = '{0, 1, 3, 7, 15};

        foreach (lengths[i]) begin
            txn = axi_txn::type_id::create($sformatf("burst_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = lengths[i][7:0]; txn.size = 2; txn.burst = 1;
            txn.wdata = new[lengths[i] + 1];
            txn.wstrb = new[lengths[i] + 1];
            for (int j = 0; j <= lengths[i]; j++) begin
                txn.wdata[j] = 32'hB550_0000 + j;
                txn.wstrb[j] = 4'hF;
            end
            start_item(txn); finish_item(txn);
        end

        // Read back with same burst lengths
        foreach (lengths[i]) begin
            txn = axi_txn::type_id::create($sformatf("rdb_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = lengths[i][7:0]; txn.size = 2; txn.burst = 1;
            txn.rdata = new[lengths[i] + 1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass

//==========================================================================
// Max Outstanding Sequence
//==========================================================================
class axi_max_ostd_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_max_ostd_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    int        s_ostd_num = 4;

    function new(string name = "axi_max_ostd_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;
        // Send max outstanding writes
        for (int i = 0; i < s_ostd_num; i++) begin
            txn = axi_txn::type_id::create($sformatf("owr_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'h057D_0000 + i;
            txn.wstrb[0] = 4'hF;
            start_item(txn); finish_item(txn);
        end

        // Send max outstanding reads
        for (int i = 0; i < s_ostd_num; i++) begin
            txn = axi_txn::type_id::create($sformatf("ord_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
