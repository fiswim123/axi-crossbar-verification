//==========================================================================
// Scoreboard（计分板/比较器）
// UVM验证组件：axi_scoreboard
// 功能：对AXI事务进行数据正确性检查和性能统计。
// 原理：scoreboard采用"写后读"（write-after-read）检查策略：
//       1. 写事务到来时，将写入的地址和数据存储到期望数据表中
//       2. 读事务到来时，将读回的数据与期望数据表中的数据比较
//       3. 如果不匹配则报告错误
//       同时统计延迟等性能指标。
// 继承自 uvm_scoreboard，是UVM的计分板基类。
// 包含性能统计（Performance Stats）功能。
//==========================================================================
class axi_scoreboard extends uvm_scoreboard;
    // 工厂注册宏，使该类可以通过UVM工厂创建和替换
    `uvm_component_utils(axi_scoreboard)

    // uvm_analysis_imp：UVM分析端口的实现（implementation）端
    // 参数：#(axi_txn, axi_scoreboard) - 事务类型 + 实现write回调的类
    // analysis_imp与analysis_port配合使用：
    //   - monitor的ap（analysis_port端）通过connect连接到这里的imp
    //   - 当monitor调用ap.write()时，UVM框架会自动调用scoreboard的write()函数
    // 一个imp可以连接多个port，但通常一个imp只连一个port
    uvm_analysis_imp #(axi_txn, axi_scoreboard) imp;

    // exp_data：期望数据存储表（关联数组）
    // 类型：bit[31:0] 索引 -> bit[31:0] 数据
    // 索引是字节地址（32位），值是该地址期望读到的32位数据
    // 关联数组的key是地址，方便按地址查找
    // 只有写事务响应为OKAY时才会存储期望数据
    bit [31:0] exp_data[bit [31:0]];

    // 通过/失败计数器
    // wr_pass: 写事务成功的次数（bresp=OKAY）
    // wr_fail: 写事务失败的次数（bresp!=OKAY，即从机返回错误）
    // rd_pass: 读事务成功的次数（数据匹配且rresp=OKAY）
    // rd_fail: 读事务失败的次数（数据不匹配或rresp!=OKAY）
    int unsigned wr_pass, wr_fail, rd_pass, rd_fail;

    // ===== 性能跟踪（Performance Tracking）变量 =====

    // wr_lat_sum / rd_lat_sum：写/读延迟累加和
    // 用于计算平均延迟：平均延迟 = 延迟累加和 / 事务总数
    int unsigned wr_lat_sum, rd_lat_sum;

    // wr_cnt / rd_cnt：写/读事务总计数
    int unsigned wr_cnt, rd_cnt;

    // wr_lat_max / rd_lat_max：写/读最大延迟
    // 记录仿真过程中出现的最大延迟值（时钟周期数）
    int unsigned wr_lat_max, rd_lat_max;

    // 构造函数：传递名称和父组件给基类
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase：构建阶段
    // 创建analysis_imp实例，名称为"imp"
    // imp必须在build_phase中创建，以便connect_phase时可以被连接
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    // write：事务接收回调函数
    // 这是UVM analysis_imp机制的核心：当monitor通过ap.write(txn)发送事务时，
    // UVM框架会自动调用所有连接到该port的imp组件的write()函数
    // 参数txn是由monitor采集并广播过来的AXI事务对象
    // 该函数根据事务类型（写/读）分别处理
    function void write(axi_txn txn);

        // ========== 写事务处理 ==========
        if (txn.kind == axi_txn::WRITE) begin
            wr_cnt++;  // 写事务计数加1

            // 延迟统计：如果事务包含延迟信息（wr_latency > 0），则累加
            // wr_latency通常在monitor中通过计算valid到ready的等待周期得到
            if (txn.wr_latency > 0) begin
                wr_lat_sum += txn.wr_latency;  // 累加延迟总和
                // 更新最大延迟
                if (txn.wr_latency > wr_lat_max)
                    wr_lat_max = txn.wr_latency;
            end

            // 检查写响应：bresp == 2'b00 表示OKAY（正常完成）
            // AXI响应编码：2'b00=OKAY, 2'b01=EXOKAY, 2'b10=SLVERR, 2'b11=DECERR
            if (txn.bresp == 2'b00) begin
                // 将写数据存储到期望数据表中
                // 突发传输中每拍数据对应一个地址，地址按字节偏移递增
                // 假设数据宽度为32位（4字节），所以地址步进为 i*4
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;  // 写成功计数加1
            end else begin
                // 写响应非OKAY，记录为写失败
                // 从机可能返回SLVERR（从机错误）或DECERR（地址解码错误）
                wr_fail++;
            end

        // ========== 读事务处理 ==========
        end else begin
            rd_cnt++;  // 读事务计数加1

            // 读延迟统计
            if (txn.rd_latency > 0) begin
                rd_lat_sum += txn.rd_latency;
                if (txn.rd_latency > rd_lat_max)
                    rd_lat_max = txn.rd_latency;
            end

            // 检查读响应：rresp == 2'b00 表示OKAY
            if (txn.rresp == 2'b00) begin
                // 逐拍比较读回的数据与期望数据
                for (int i = 0; i <= txn.len; i++) begin
                    // 计算当前拍的字节地址
                    bit [31:0] key = txn.addr + i * 4;

                    // 检查期望数据表中是否存在该地址的记录
                    // exists()是关联数组的内建方法，判断key是否存在
                    // 如果存在且读回数据与期望数据不匹配，则报告错误
                    if (exp_data.exists(key) && txn.rdata[i] !== exp_data[key]) begin
                        // 使用!==而不是!=，因为需要正确处理x/z值
                        `uvm_error("SCBD", $sformatf("RD DATA FAIL: addr=0x%04h got=0x%08h exp=0x%08h",
                                   key, txn.rdata[i], exp_data[key]))
                        rd_fail++; return;  // 记录失败并提前返回
                    end
                end
                // 所有拍的数据都匹配，记录为读成功
                rd_pass++;
            end else begin
                // 读响应非OKAY，记录为读失败
                rd_fail++;
            end
        end
    endfunction

    // report_phase：UVM报告阶段
    // 在仿真结束时由UVM自动调用，用于打印最终的验证结果统计
    // 这是UVM phase机制的一部分，在run_phase结束后的cleanup阶段执行
    function void report_phase(uvm_phase phase);
        // 打印分隔线和测试结果汇总
        `uvm_info("SCBD", "====================================", UVM_LOW)
        `uvm_info("SCBD", $sformatf("WR: %0d pass / %0d fail", wr_pass, wr_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("RD: %0d pass / %0d fail", rd_pass, rd_fail), UVM_LOW)
        `uvm_info("SCBD", "------------------------------------", UVM_LOW)

        // 打印写延迟统计：平均延迟和最大延迟（单位：时钟周期）
        if (wr_cnt > 0)
            `uvm_info("SCBD", $sformatf("WR Latency: avg=%0d max=%0d cycles", wr_lat_sum/wr_cnt, wr_lat_max), UVM_LOW)

        // 打印读延迟统计
        if (rd_cnt > 0)
            `uvm_info("SCBD", $sformatf("RD Latency: avg=%0d max=%0d cycles", rd_lat_sum/rd_cnt, rd_lat_max), UVM_LOW)

        // 打印事务总数
        `uvm_info("SCBD", $sformatf("Total Transactions: WR=%0d RD=%0d", wr_cnt, rd_cnt), UVM_LOW)
        `uvm_info("SCBD", "====================================", UVM_LOW)

        // 如果存在任何失败，用uvm_error报告最终失败
        // uvm_error会被UVM统计，最终影响仿真结果（PASS/FAIL判定）
        if (wr_fail > 0 || rd_fail > 0)
            `uvm_error("SCBD", "FAILURES DETECTED")
    endfunction
endclass
