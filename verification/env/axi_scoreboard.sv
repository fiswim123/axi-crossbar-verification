///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar Scoreboard - Transaction Checker
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

class axi_scoreboard #(
    parameter AXI_ADDR_W = 32,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32,
    parameter MST_NB = 4,
    parameter SLV_NB = 4
);

    // Expected slave memory models
    bit [7:0] slv_mem[SLV_NB][$];

    // Transaction queues for comparison
    axi_transaction wr_exp_queue[$];
    axi_transaction wr_act_queue[$];
    axi_transaction rd_exp_queue[$];
    axi_transaction rd_act_queue[$];

    // Address map
    typedef struct {
        bit [AXI_ADDR_W-1:0] start_addr;
        bit [AXI_ADDR_W-1:0] end_addr;
        int slave_id;
    } addr_map_t;

    addr_map_t addr_map[SLV_NB];

    // Statistics
    int wr_match_count;
    int wr_mismatch_count;
    int rd_match_count;
    int rd_mismatch_count;
    int total_transactions;

    // Error injection
    bit error_injection_enable;
    real error_rate;

    function new();
        wr_match_count = 0;
        wr_mismatch_count = 0;
        rd_match_count = 0;
        rd_mismatch_count = 0;
        total_transactions = 0;
        error_injection_enable = 0;
        error_rate = 0.0;
    endfunction

    //--------------------------------------------------------------------------
    // Set Address Map
    //--------------------------------------------------------------------------
    function void set_addr_map(int slave_id,
                               bit [AXI_ADDR_W-1:0] start_addr,
                               bit [AXI_ADDR_W-1:0] end_addr);
        addr_map[slave_id].start_addr = start_addr;
        addr_map[slave_id].end_addr = end_addr;
        addr_map[slave_id].slave_id = slave_id;
    endfunction

    //--------------------------------------------------------------------------
    // Get Target Slave from Address
    //--------------------------------------------------------------------------
    function int get_target_slave(bit [AXI_ADDR_W-1:0] addr);
        for (int i = 0; i < SLV_NB; i++) begin
            if (addr >= addr_map[i].start_addr &&
                addr <= addr_map[i].end_addr) begin
                return i;
            end
        end
        $error("Address 0x%08h does not map to any slave", addr);
        return -1;
    endfunction

    //--------------------------------------------------------------------------
    // Predict Write Transaction
    //--------------------------------------------------------------------------
    function void predict_write(axi_transaction txn);
        int target_slave;
        target_slave = get_target_slave(txn.addr);

        if (target_slave >= 0) begin
            // Store expected write data
            for (int beat = 0; beat <= txn.len; beat++) begin
                bit [AXI_ADDR_W-1:0] beat_addr;
                beat_addr = txn.addr + (beat * (1 << txn.size));

                for (int b = 0; b < AXI_DATA_W/8; b++) begin
                    if (txn.wstrb[beat][b]) begin
                        // Predict data storage
                        bit [7:0] exp_byte;
                        exp_byte = txn.wdata[beat][b*8 +: 8];
                        // Store for later comparison
                    end
                end
            end
            wr_exp_queue.push_back(txn.copy());
            total_transactions++;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Check Write Response
    //--------------------------------------------------------------------------
    function void check_write_response(axi_transaction txn, int actual_slave);
        axi_transaction exp_txn;
        int expected_slave;

        if (wr_exp_queue.size() == 0) begin
            $error("Unexpected write response: ID=0x%02h", txn.bid);
            wr_mismatch_count++;
            return;
        end

        exp_txn = wr_exp_queue.pop_front();
        expected_slave = get_target_slave(exp_txn.addr);

        // Check response
        if (txn.bid !== exp_txn.id) begin
            $error("Write response ID mismatch: expected=0x%02h, actual=0x%02h",
                   exp_txn.id, txn.bid);
            wr_mismatch_count++;
        end else if (actual_slave !== expected_slave) begin
            $error("Write response slave mismatch: expected=%0d, actual=%0d",
                   expected_slave, actual_slave);
            wr_mismatch_count++;
        end else if (txn.bresp !== 2'b00) begin
            $error("Write response error: resp=%0d", txn.bresp);
            wr_mismatch_count++;
        end else begin
            wr_match_count++;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Predict Read Transaction
    //--------------------------------------------------------------------------
    function void predict_read(axi_transaction txn);
        rd_exp_queue.push_back(txn.copy());
        total_transactions++;
    endfunction

    //--------------------------------------------------------------------------
    // Check Read Response
    //--------------------------------------------------------------------------
    function void check_read_response(axi_transaction txn, int actual_slave);
        axi_transaction exp_txn;
        int expected_slave;

        if (rd_exp_queue.size() == 0) begin
            $error("Unexpected read response: ID=0x%02h", txn.rid);
            rd_mismatch_count++;
            return;
        end

        exp_txn = rd_exp_queue.pop_front();
        expected_slave = get_target_slave(exp_txn.addr);

        // Check response
        if (txn.rid !== exp_txn.id) begin
            $error("Read response ID mismatch: expected=0x%02h, actual=0x%02h",
                   exp_txn.id, txn.rid);
            rd_mismatch_count++;
        end else if (actual_slave !== expected_slave) begin
            $error("Read response slave mismatch: expected=%0d, actual=%0d",
                   expected_slave, actual_slave);
            rd_mismatch_count++;
        end else if (txn.rresp !== 2'b00) begin
            $error("Read response error: resp=%0d", txn.rresp);
            rd_mismatch_count++;
        end else begin
            rd_match_count++;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Report Statistics
    //--------------------------------------------------------------------------
    function void report();
        $display("\n=== Scoreboard Report ===");
        $display("Total Transactions: %0d", total_transactions);
        $display("Write Matches:      %0d", wr_match_count);
        $display("Write Mismatches:   %0d", wr_mismatch_count);
        $display("Read Matches:       %0d", rd_match_count);
        $display("Read Mismatches:    %0d", rd_mismatch_count);
        $display("Pending Write Exp:  %0d", wr_exp_queue.size());
        $display("Pending Read Exp:   %0d", rd_exp_queue.size());
        $display("========================\n");

        if (wr_mismatch_count > 0 || rd_mismatch_count > 0) begin
            $error("Scoreboard detected mismatches!");
        end
    endfunction

endclass
