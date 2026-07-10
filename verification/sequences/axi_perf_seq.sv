//==========================================================================
// Performance Test Sequence
//==========================================================================
class axi_perf_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_perf_seq)
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    int        s_count = 10;

    function new(string name = "axi_perf_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn txn;

        // Sequential writes (measure latency)
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("pw_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hA500_0000 + i;
            txn.wstrb[0] = 4'hF;
            start_item(txn); finish_item(txn);
        end

        // Sequential reads (measure latency)
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("pr_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr + i * 4; txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;
            txn.rdata = new[1];
            start_item(txn); finish_item(txn);
        end

        // Burst writes (measure bandwidth)
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("bw_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 15; txn.size = 2; txn.burst = 1; // 16-beat burst
            txn.wdata = new[16]; txn.wstrb = new[16];
            for (int j = 0; j < 16; j++) begin
                txn.wdata[j] = 32'h8A00_0000 + i * 16 + j;
                txn.wstrb[j] = 4'hF;
            end
            start_item(txn); finish_item(txn);
        end

        // Burst reads (measure bandwidth)
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("br_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr; txn.id = s_id;
            txn.len = 15; txn.size = 2; txn.burst = 1;
            txn.rdata = new[16];
            start_item(txn); finish_item(txn);
        end
    endtask
endclass
