//==========================================================================
// Scoreboard（计分板/比较器）
// UVM验证组件：axi_scoreboard
// 功能：对AXI事务进行数据正确性检查、路由验证和性能统计。
//
// 【验证策略】
// 1. 路由验证：通过 Master Monitor 和 Slave Monitor 的事务比对
//    - Master Monitor 看到"进入DUT"的事务
//    - Slave Monitor 看到"离开DUT"的事务
//    - 比对：事务是否到达正确的 Slave？
// 2. 数据完整性：写入的数据是否与读出的数据一致？
// 3. 性能统计：延迟、吞吐量等
//
// 【架构】
//   Master Monitor ──→ mst_imp ──→ write_master()
//                                      │
//                                      ▼
//                                 记录期望路由
//                                      │
//   Slave Monitor  ──→ slv_imp ──→ write_slave()
//                                      │
//                                      ▼
//                                 检查实际路由
//==========================================================================

// 使用 uvm_analysis_imp_decl 宏声明不同类型的 analysis_imp
// 这样可以在同一个类中使用多个 analysis_imp 端口
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi_scoreboard extends uvm_scoreboard;
    // 工厂注册宏
    `uvm_component_utils(axi_scoreboard)

    // ===== 分析端口 =====
    // Master Monitor 的分析端口（接收"进入DUT"的事务）
    uvm_analysis_imp_master #(axi_txn, axi_scoreboard) mst_imp;
    // Slave Monitor 的分析端口（接收"离开DUT"的事务）
    uvm_analysis_imp_slave #(axi_txn, axi_scoreboard) slv_imp;

    // ===== 期望队列 =====
    // 按 Slave ID 索引，存储期望在该 Slave 上出现的事务
    // 当 Master Monitor 看到 addr=0x1000 时，期望在 Slave 1 上出现
    axi_txn expected_queue[4][$];

    // ===== 期望数据表 =====
    // 用于读数据比对（写后读验证）
    bit [31:0] exp_data[bit [31:0]];

    // ===== 统计计数器 =====
    // 路由验证统计
    int unsigned route_pass, route_fail;
    // 数据完整性统计
    int unsigned data_pass, data_fail;
    // 写/读事务统计
    int unsigned wr_pass, wr_fail, rd_pass, rd_fail;
    // 事务计数
    int unsigned mst_wr_cnt, mst_rd_cnt, slv_wr_cnt, slv_rd_cnt;

    // ===== 性能跟踪 =====
    int unsigned wr_lat_sum, rd_lat_sum;
    int unsigned wr_cnt, rd_cnt;
    int unsigned wr_lat_max, rd_lat_max;

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase：创建分析端口
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mst_imp = new("mst_imp", this);
        slv_imp = new("slv_imp", this);
    endfunction

    // ================================================================
    // write_master：处理来自 Master Monitor 的事务
    // ================================================================
    // Master Monitor 观测"进入DUT"的事务
    // 根据地址计算期望的 Slave ID，存入期望队列
    function void write_master(axi_txn txn);
        // 计算期望的 Slave ID（根据地址高位）
        // 0x0000~0x0FFF → Slave 0 (addr[15:12] = 0)
        // 0x1000~0x1FFF → Slave 1 (addr[15:12] = 1)
        // 0x2000~0x2FFF → Slave 2 (addr[15:12] = 2)
        // 0x3000~0x3FFF → Slave 3 (addr[15:12] = 3)
        int expected_slave = txn.addr[15:12];

        if (txn.kind == axi_txn::WRITE) begin
            mst_wr_cnt++;
            wr_cnt++;

            // 延迟统计
            if (txn.wr_latency > 0) begin
                wr_lat_sum += txn.wr_latency;
                if (txn.wr_latency > wr_lat_max)
                    wr_lat_max = txn.wr_latency;
            end

            // 检查写响应
            if (txn.bresp == 2'b00) begin
                // 写成功，存入期望队列
                // 创建一个副本，标记来源
                axi_txn exp_txn = axi_txn::type_id::create("exp_txn");
                exp_txn.kind = txn.kind;
                exp_txn.addr = txn.addr;
                exp_txn.id = txn.id;
                exp_txn.len = txn.len;
                exp_txn.wdata = new[txn.wdata.size()];
                foreach (txn.wdata[i]) exp_txn.wdata[i] = txn.wdata[i];
                exp_txn.source_id = expected_slave;  // 期望出现在这个 Slave

                expected_queue[expected_slave].push_back(exp_txn);

                // 存入期望数据表（用于读数据比对）
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];

                wr_pass++;

                `uvm_info("SCBD", $sformatf(
                    "Master write: addr=0x%04h, data=0x%08h, expect Slave %0d",
                    txn.addr, txn.wdata[0], expected_slave), UVM_MEDIUM)
            end else begin
                wr_fail++;
            end

        end else begin
            // 读事务处理
            mst_rd_cnt++;
            rd_cnt++;

            if (txn.rd_latency > 0) begin
                rd_lat_sum += txn.rd_latency;
                if (txn.rd_latency > rd_lat_max)
                    rd_lat_max = txn.rd_latency;
            end

            // 读事务的路由验证在 Slave 侧处理
        end
    endfunction

    // ================================================================
    // write_slave：处理来自 Slave Monitor 的事务
    // ================================================================
    // Slave Monitor 观测"离开DUT"的事务
    // 检查：这个事务是否应该出现在这个 Slave 上？
    function void write_slave(axi_txn txn);
        // 局部变量声明（必须在函数开头）
        int actual_slave;
        int expected_slave;
        axi_txn exp_txn;

        // 获取实际的 Slave ID（从 Monitor 的 source_id）
        actual_slave = txn.source_id;

        if (txn.kind == axi_txn::WRITE) begin
            slv_wr_cnt++;

            // 从期望队列中取出
            if (expected_queue[actual_slave].size() == 0) begin
                `uvm_error("SCBD", $sformatf(
                    "Unexpected write on Slave %0d: addr=0x%04h (no expected transaction)",
                    actual_slave, txn.addr))
                route_fail++;
                return;
            end

            exp_txn = expected_queue[actual_slave].pop_front();

            // ===== 路由验证 =====
            // 检查：这个事务是否出现在正确的 Slave 上？
            if (exp_txn.source_id != actual_slave) begin
                `uvm_error("SCBD", $sformatf(
                    "ROUTING ERROR: addr=0x%04h should go to Slave %0d, but went to Slave %0d",
                    exp_txn.addr, exp_txn.source_id, actual_slave))
                route_fail++;
            end else begin
                route_pass++;
                `uvm_info("SCBD", $sformatf(
                    "Routing OK: addr=0x%04h correctly reached Slave %0d",
                    txn.addr, actual_slave), UVM_HIGH)
            end

            // ===== 数据完整性验证 =====
            // 检查：数据是否正确传输？
            if (exp_txn.wdata.size() == txn.wdata.size()) begin
                bit data_match = 1;
                foreach (exp_txn.wdata[i]) begin
                    if (exp_txn.wdata[i] !== txn.wdata[i]) begin
                        data_match = 0;
                        break;
                    end
                end

                if (data_match) begin
                    data_pass++;
                end else begin
                    `uvm_error("SCBD", $sformatf(
                        "DATA ERROR: addr=0x%04h, expected=0x%08h, actual=0x%08h",
                        txn.addr, exp_txn.wdata[0], txn.wdata[0]))
                    data_fail++;
                end
            end else begin
                `uvm_error("SCBD", $sformatf(
                    "DATA LENGTH ERROR: addr=0x%04h, expected=%0d beats, actual=%0d beats",
                    txn.addr, exp_txn.wdata.size(), txn.wdata.size()))
                data_fail++;
            end

            // ===== ID 验证 =====
            // 检查：事务 ID 是否匹配？
            if (exp_txn.id !== txn.id) begin
                `uvm_warning("SCBD", $sformatf(
                    "ID MISMATCH: addr=0x%04h, expected id=0x%02h, actual id=0x%02h",
                    txn.addr, exp_txn.id, txn.id))
            end

        end else begin
            // 读事务处理
            slv_rd_cnt++;

            // 读事务的路由验证
            // 从地址计算期望的 Slave ID
            expected_slave = txn.addr[15:12];

            if (expected_slave != actual_slave) begin
                `uvm_error("SCBD", $sformatf(
                    "READ ROUTING ERROR: addr=0x%04h should go to Slave %0d, but went to Slave %0d",
                    txn.addr, expected_slave, actual_slave))
                route_fail++;
            end else begin
                route_pass++;
            end

            // 读数据比对
            if (exp_data.exists(txn.addr)) begin
                if (txn.rdata[0] === exp_data[txn.addr]) begin
                    rd_pass++;
                end else begin
                    `uvm_error("SCBD", $sformatf(
                        "RD DATA FAIL: addr=0x%04h got=0x%08h exp=0x%08h",
                        txn.addr, txn.rdata[0], exp_data[txn.addr]))
                    rd_fail++;
                end
            end
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

        // 检查未处理的期望队列
        for (int i = 0; i < 4; i++) begin
            if (expected_queue[i].size() > 0) begin
                `uvm_error("SCBD", $sformatf(
                    "Slave %0d has %0d unmatched transactions", i, expected_queue[i].size()))
            end
        end

        // 最终结果判定
        if (route_fail > 0 || data_fail > 0 || wr_fail > 0 || rd_fail > 0)
            `uvm_error("SCBD", "FAILURES DETECTED - TEST FAILED")
        else
            `uvm_info("SCBD", "ALL CHECKS PASSED - TEST PASSED", UVM_LOW)
    endfunction
endclass
