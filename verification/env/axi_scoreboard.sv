// Compare completed transactions on both sides of the crossbar.  In this
// configuration the slave ports see local addresses (KEEP_BASE_ADDR=0).
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_scoreboard)

    uvm_analysis_imp_master #(axi_txn, axi_scoreboard) mst_imp;
    uvm_analysis_imp_slave  #(axi_txn, axi_scoreboard) slv_imp;
    // Only successfully checked paths are published to routing coverage.
    uvm_analysis_port #(axi_txn) checked_ap;

    axi_txn master_txns[$];
    axi_txn slave_txns[$];
    int unsigned route_pass, route_fail, data_pass, data_fail;
    int unsigned master_writes, master_reads, slave_writes, slave_reads;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mst_imp = new("mst_imp", this);
        slv_imp = new("slv_imp", this);
        checked_ap = new("checked_ap", this);
    endfunction

    function void write_master(axi_txn t);
        master_txns.push_back(t);
        if (t.kind == axi_txn::WRITE) master_writes++;
        else                            master_reads++;
    endfunction

    function void write_slave(axi_txn t);
        slave_txns.push_back(t);
        if (t.kind == axi_txn::WRITE) slave_writes++;
        else                            slave_reads++;
    endfunction

    // Source ID and local address are the identity of the routed port.  Data
    // deliberately is NOT part of the match key: otherwise corruption hides.
    function bit same_request(axi_txn m, axi_txn s);
        bit [15:0] local_addr;
        local_addr = m.addr & 16'h0fff;
        return m.kind == s.kind && m.id == s.id &&
               m.addr[15:12] == s.source_id && local_addr == s.addr &&
               m.len == s.len && m.size == s.size;
    endfunction

    function void check_phase(uvm_phase phase);
        bit used[];
        int match_idx;
        bit good;
        super.check_phase(phase);
        used = new[slave_txns.size()];

        foreach (master_txns[i]) begin
            axi_txn m = master_txns[i];
            match_idx = -1;
            good = 1;

            if (m.source_id < 0 || m.source_id > 3) begin
                `uvm_error("SCBD", $sformatf("Invalid master source_id=%0d", m.source_id))
                route_fail++;
                continue;
            end
            if (m.id[7:4] != m.source_id + 1) begin
                `uvm_error("SCBD", $sformatf("Master %0d used ID %02h with wrong routing prefix", m.source_id, m.id))
                route_fail++;
                good = 0;
            end
            if (m.kind == axi_txn::WRITE && m.bid != m.id) begin
                `uvm_error("SCBD", $sformatf("Master %0d BID %02h != AWID %02h", m.source_id, m.bid, m.id))
                data_fail++;
                good = 0;
            end
            if (m.kind == axi_txn::READ && m.rid != m.id) begin
                `uvm_error("SCBD", $sformatf("Master %0d RID %02h != ARID %02h", m.source_id, m.rid, m.id))
                data_fail++;
                good = 0;
            end

            // Addresses outside the four mapped 4-KiB windows must be DECERR
            // and must never appear on a slave port.
            if (m.addr[15:12] > 3) begin
                if ((m.kind == axi_txn::WRITE && m.bresp != 2'b11) ||
                    (m.kind == axi_txn::READ  && m.rresp != 2'b11)) begin
                    `uvm_error("SCBD", $sformatf("Unmapped %s addr=%04h did not return DECERR", m.kind.name(), m.addr))
                    route_fail++;
                end
                continue;
            end

            foreach (slave_txns[j]) begin
                if (!used[j] && same_request(m, slave_txns[j])) begin
                    match_idx = j;
                    break;
                end
            end
            if (match_idx < 0) begin
                `uvm_error("SCBD", $sformatf("Missing slave %s: master=%0d addr=%04h id=%02h len=%0d",
                    m.kind.name(), m.source_id, m.addr, m.id, m.len))
                route_fail++;
                continue;
            end
            used[match_idx] = 1;
            begin
                axi_txn s = slave_txns[match_idx];
                if (m.kind == axi_txn::WRITE) begin
                    if (m.bresp != s.bresp || s.bid != m.id) begin
                        `uvm_error("SCBD", $sformatf("B response mismatch addr=%04h: master id/resp=%02h/%0h slave=%02h/%0h",
                            m.addr, m.bid, m.bresp, s.bid, s.bresp))
                        data_fail++;
                        good = 0;
                    end
                    for (int beat = 0; beat <= m.len; beat++) begin
                        if (m.wdata[beat] !== s.wdata[beat] || m.wstrb[beat] !== s.wstrb[beat]) begin
                            `uvm_error("SCBD", $sformatf("W beat %0d mismatch master=%0d addr=%04h", beat, m.source_id, m.addr))
                            data_fail++;
                            good = 0;
                        end
                    end
                end else begin
                    if (m.rresp != s.rresp || s.rid != m.id) begin
                        `uvm_error("SCBD", $sformatf("R response mismatch addr=%04h: master id/resp=%02h/%0h slave=%02h/%0h",
                            m.addr, m.rid, m.rresp, s.rid, s.rresp))
                        data_fail++;
                        good = 0;
                    end
                    for (int beat = 0; beat <= m.len; beat++) begin
                        if (m.rdata[beat] !== s.rdata[beat]) begin
                            `uvm_error("SCBD", $sformatf("R beat %0d mismatch master=%0d addr=%04h expected=%08h actual=%08h",
                                beat, m.source_id, m.addr, s.rdata[beat], m.rdata[beat]))
                            data_fail++;
                            good = 0;
                        end
                    end
                end
            end
            if (good) begin
                route_pass++;
                data_pass++;
                checked_ap.write(m);
            end else route_fail++;
        end

        foreach (slave_txns[j]) begin
            if (!used[j]) begin
                `uvm_error("SCBD", $sformatf("Unexpected slave %s: slave=%0d local_addr=%04h id=%02h",
                    slave_txns[j].kind.name(), slave_txns[j].source_id,
                    slave_txns[j].addr, slave_txns[j].id))
                route_fail++;
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCBD", $sformatf("Routing: %0d pass / %0d fail; data: %0d pass / %0d fail",
            route_pass, route_fail, data_pass, data_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("Transactions: master W/R=%0d/%0d slave W/R=%0d/%0d",
            master_writes, master_reads, slave_writes, slave_reads), UVM_LOW)
        if (route_fail || data_fail)
            `uvm_error("SCBD", "CHECKS FAILED")
        else if (master_writes + master_reads == 0)
            `uvm_error("SCBD", "No completed master transactions")
        else
            `uvm_info("SCBD", "ALL CHECKS PASSED", UVM_LOW)
    endfunction
endclass
