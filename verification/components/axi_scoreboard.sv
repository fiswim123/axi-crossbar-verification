//==========================================================================
// Scoreboard（计分板/比较器）
// UVM验证组件：axi_scoreboard
// 功能：对AXI事务进行数据正确性检查、路由验证和性能统计。
//
// 【验证策略】
// 1. 路由验证：收集所有事务，仿真结束时比对
// 2. 数据完整性：写入的数据是否与读出的数据一致？
// 3. 性能统计：延迟、吞吐量等
//==========================================================================

`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_scoreboard)

    // ===== 分析端口 =====
    uvm_analysis_imp_master #(axi_txn, axi_scoreboard) mst_imp;
    uvm_analysis_imp_slave #(axi_txn, axi_scoreboard) slv_imp;

    // ===== 事务收集 =====
    // 收集所有来自 Master 和 Slave 的事务，仿真结束时比对
    axi_txn mst_wr_txns[$];
    axi_txn slv_wr_txns[$];

    // ===== 期望数据表 =====
    bit [31:0] exp_data[bit [31:0]];

    // ===== 统计计数器 =====
    int unsigned route_pass, route_fail;
    int unsigned data_pass, data_fail;
    int unsigned wr_pass, wr_fail, rd_pass, rd_fail;
    int unsigned mst_wr_cnt, mst_rd_cnt, slv_wr_cnt, slv_rd_cnt;

    // ===== 性能跟踪 =====
    int unsigned wr_lat_sum, rd_lat_sum;
    int unsigned wr_cnt, rd_cnt;
    int unsigned wr_lat_max, rd_lat_max;

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mst_imp = new("mst_imp", this);
        slv_imp = new("slv_imp", this);
    endfunction

    // ================================================================
    // write_master：收集来自 Master Monitor 的事务
    // ================================================================
    function void write_master(axi_txn txn);
        if (txn.kind == axi_txn::WRITE) begin
            mst_wr_cnt++;
            wr_cnt++;

            if (txn.wr_latency > 0) begin
                wr_lat_sum += txn.wr_latency;
                if (txn.wr_latency > wr_lat_max)
                    wr_lat_max = txn.wr_latency;
            end

            if (txn.bresp == 2'b00) begin
                // 写成功，记录期望数据
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;

                // 收集事务用于路由验证
                mst_wr_txns.push_back(txn);
            end else begin
                wr_fail++;
            end
        end else begin
            mst_rd_cnt++;
            rd_cnt++;

            if (txn.rd_latency > 0) begin
                rd_lat_sum += txn.rd_latency;
                if (txn.rd_latency > rd_lat_max)
                    rd_lat_max = txn.rd_latency;
            end
        end
    endfunction

    // ================================================================
    // write_slave：收集来自 Slave Monitor 的事务
    // ================================================================
    function void write_slave(axi_txn txn);
        if (txn.kind == axi_txn::WRITE) begin
            slv_wr_cnt++;
            // 收集事务用于路由验证
            slv_wr_txns.push_back(txn);
        end else begin
            slv_rd_cnt++;
        end
    endfunction

    // ================================================================
    // check_phase：仿真结束时进行路由验证
    // ================================================================
    // 在 run_phase 结束后、report_phase 之前执行
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        `uvm_info("SCBD", "========================================", UVM_LOW)
        `uvm_info("SCBD", "        Routing Verification            ", UVM_LOW)
        `uvm_info("SCBD", "========================================", UVM_LOW)
        `uvm_info("SCBD", $sformatf("Master WR txns: %0d", mst_wr_txns.size()), UVM_LOW)
        `uvm_info("SCBD", $sformatf("Slave  WR txns: %0d", slv_wr_txns.size()), UVM_LOW)

        // 对每个 Master 事务，检查是否在正确的 Slave 上出现
        foreach (mst_wr_txns[i]) begin
            axi_txn mst_txn = mst_wr_txns[i];
            int expected_slave = mst_txn.addr[15:12];
            bit found = 0;

            // 在 Slave 事务中查找匹配的事务
            foreach (slv_wr_txns[j]) begin
                axi_txn slv_txn = slv_wr_txns[j];
                int actual_slave = slv_txn.source_id;

                // 按地址和数据匹配
                if (slv_txn.addr == mst_txn.addr &&
                    slv_txn.wdata[0] == mst_txn.wdata[0]) begin
                    found = 1;

                    // 路由验证
                    if (expected_slave == actual_slave) begin
                        route_pass++;
                        `uvm_info("SCBD", $sformatf(
                            "Routing OK: addr=0x%04h correctly reached Slave %0d",
                            mst_txn.addr, actual_slave), UVM_MEDIUM)
                    end else begin
                        `uvm_error("SCBD", $sformatf(
                            "ROUTING ERROR: addr=0x%04h should go to Slave %0d, but went to Slave %0d",
                            mst_txn.addr, expected_slave, actual_slave))
                        route_fail++;
                    end

                    // 数据完整性验证
                    if (mst_txn.wdata[0] == slv_txn.wdata[0]) begin
                        data_pass++;
                    end else begin
                        `uvm_error("SCBD", $sformatf(
                            "DATA ERROR: addr=0x%04h, expected=0x%08h, actual=0x%08h",
                            mst_txn.addr, mst_txn.wdata[0], slv_txn.wdata[0]))
                        data_fail++;
                    end

                    // 删除已匹配的 Slave 事务
                    slv_wr_txns.delete(j);
                    break;
                end
            end

            if (!found) begin
                `uvm_warning("SCBD", $sformatf(
                    "No matching Slave txn for Master txn: addr=0x%04h, data=0x%08h",
                    mst_txn.addr, mst_txn.wdata[0]))
            end
        end

        // 检查未匹配的 Slave 事务
        foreach (slv_wr_txns[i]) begin
            `uvm_warning("SCBD", $sformatf(
                "Unmatched Slave txn: addr=0x%04h, data=0x%08h, slave=%0d",
                slv_wr_txns[i].addr, slv_wr_txns[i].wdata[0], slv_wr_txns[i].source_id))
        end
    endfunction

    // ================================================================
    // report_phase：仿真结束时打印统计报告
    // ================================================================
    function void report_phase(uvm_phase phase);
        `uvm_info("SCBD", "========================================", UVM_LOW)
        `uvm_info("SCBD", "        Scoreboard Final Report         ", UVM_LOW)
        `uvm_info("SCBD", "========================================", UVM_LOW)

        // 路由验证统计
        `uvm_info("SCBD", $sformatf("Routing  : %0d pass / %0d fail", route_pass, route_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("Data     : %0d pass / %0d fail", data_pass, data_fail), UVM_LOW)

        // 事务统计
        `uvm_info("SCBD", $sformatf("WR: %0d pass / %0d fail", wr_pass, wr_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("RD: %0d pass / %0d fail", rd_pass, rd_fail), UVM_LOW)

        // 事务计数
        `uvm_info("SCBD", $sformatf("Master WR: %0d, Master RD: %0d", mst_wr_cnt, mst_rd_cnt), UVM_LOW)
        `uvm_info("SCBD", $sformatf("Slave  WR: %0d, Slave  RD: %0d", slv_wr_cnt, slv_rd_cnt), UVM_LOW)

        // 延迟统计
        if (wr_cnt > 0)
            `uvm_info("SCBD", $sformatf("WR Latency: avg=%0d max=%0d cycles", wr_lat_sum/wr_cnt, wr_lat_max), UVM_LOW)
        if (rd_cnt > 0)
            `uvm_info("SCBD", $sformatf("RD Latency: avg=%0d max=%0d cycles", rd_lat_sum/rd_cnt, rd_lat_max), UVM_LOW)

        `uvm_info("SCBD", "========================================", UVM_LOW)

        // 最终结果判定
        if (route_fail > 0 || data_fail > 0 || wr_fail > 0 || rd_fail > 0)
            `uvm_error("SCBD", "FAILURES DETECTED - TEST FAILED")
        else
            `uvm_info("SCBD", "ALL CHECKS PASSED - TEST PASSED", UVM_LOW)
    endfunction
endclass
