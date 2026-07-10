//==========================================================================
// Scoreboard (with Performance Stats)
//==========================================================================
class axi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_scoreboard)

    uvm_analysis_imp #(axi_txn, axi_scoreboard) imp;
    bit [31:0] exp_data[bit [31:0]];
    int unsigned wr_pass, wr_fail, rd_pass, rd_fail;

    // Performance tracking
    int unsigned wr_lat_sum, rd_lat_sum;
    int unsigned wr_cnt, rd_cnt;
    int unsigned wr_lat_max, rd_lat_max;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    function void write(axi_txn txn);
        if (txn.kind == axi_txn::WRITE) begin
            wr_cnt++;
            // Track latency
            if (txn.wr_latency > 0) begin
                wr_lat_sum += txn.wr_latency;
                if (txn.wr_latency > wr_lat_max)
                    wr_lat_max = txn.wr_latency;
            end

            // Store expected data for OKAY responses
            if (txn.bresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;
            end else begin
                wr_fail++;
            end
        end else begin
            rd_cnt++;
            // Track latency
            if (txn.rd_latency > 0) begin
                rd_lat_sum += txn.rd_latency;
                if (txn.rd_latency > rd_lat_max)
                    rd_lat_max = txn.rd_latency;
            end

            // Check read data for OKAY responses
            if (txn.rresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++) begin
                    bit [31:0] key = txn.addr + i * 4;
                    if (exp_data.exists(key) && txn.rdata[i] !== exp_data[key]) begin
                        `uvm_error("SCBD", $sformatf("RD DATA FAIL: addr=0x%04h got=0x%08h exp=0x%08h",
                                   key, txn.rdata[i], exp_data[key]))
                        rd_fail++; return;
                    end
                end
                rd_pass++;
            end else begin
                rd_fail++;
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCBD", "====================================", UVM_LOW)
        `uvm_info("SCBD", $sformatf("WR: %0d pass / %0d fail", wr_pass, wr_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("RD: %0d pass / %0d fail", rd_pass, rd_fail), UVM_LOW)
        `uvm_info("SCBD", "------------------------------------", UVM_LOW)
        if (wr_cnt > 0)
            `uvm_info("SCBD", $sformatf("WR Latency: avg=%0d max=%0d cycles", wr_lat_sum/wr_cnt, wr_lat_max), UVM_LOW)
        if (rd_cnt > 0)
            `uvm_info("SCBD", $sformatf("RD Latency: avg=%0d max=%0d cycles", rd_lat_sum/rd_cnt, rd_lat_max), UVM_LOW)
        `uvm_info("SCBD", $sformatf("Total Transactions: WR=%0d RD=%0d", wr_cnt, rd_cnt), UVM_LOW)
        `uvm_info("SCBD", "====================================", UVM_LOW)
        if (wr_fail > 0 || rd_fail > 0)
            `uvm_error("SCBD", "FAILURES DETECTED")
    endfunction
endclass
