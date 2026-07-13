//==========================================================================
// Performance Test Sequence — 性能测试序列
//==========================================================================
// 【测试目的】
//   测量AXI Crossbar的性能指标，包括：
//   1. 延迟(Latency) — 从发出请求到收到响应的时间
//   2. 带宽(Bandwidth) — 单位时间内传输的数据量
//
// 【性能测试方法】
//   本序列通过以下方式收集性能数据：
//   - 顺序单拍写/读：测量延迟(latency)
//   - 突发写/读：     测量带宽(bandwidth)
//
//   性能数据通过UVM的analysis port和monitor收集，
//   或者通过scoreboard中的计数器统计。
//
// 【AXI性能相关知识】
//   - 突发传输比单拍传输效率高，因为地址只发一次
//   - Outstanding可以进一步提高带宽(掩盖延迟)
//   - Crossbar的性能取决于：
//     a) 内部FIFO深度
//     b) 仲裁算法效率
//     c) 数据通路宽度
//     d) 时钟频率
//==========================================================================
class axi_perf_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_perf_seq)

    // s_addr: 基地址
    bit [15:0] s_addr;

    // s_id: 事务ID
    bit [7:0]  s_id;

    // s_count: 顺序传输的次数(用于延迟测试)
    // 默认10次
    int        s_count = 10;

    // 构造函数
    function new(string name = "axi_perf_seq");
        super.new(name);
    endfunction

    // body()任务：产生四种类型的性能测试激励
    task body();
        axi_txn txn;

        // ============================================================
        // 阶段1：顺序写(Sequential Writes) — 测量写延迟
        // ============================================================
        // 发送s_count个单拍写请求，每个访问不同地址
        // 通过记录每个请求的发出时间和响应时间，可以计算平均写延迟
        // 【延迟 = 响应时间 - 请求发出时间】
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("pw_%0d", i));
            txn.kind = axi_txn::WRITE;

            // 每次地址递增4字节(32位对齐)
            txn.addr = s_addr + i * 4;
            txn.id = s_id;

            // 单拍传输：len=0, size=2(4字节), burst=1(INCR)
            txn.len = 0; txn.size = 2; txn.burst = 1;

            txn.wdata = new[1]; txn.wstrb = new[1];
            txn.wdata[0] = 32'hA500_0000 + i; // 带有计数的数据模式
            txn.wstrb[0] = 4'hF;

            start_item(txn); finish_item(txn);
        end

        // ============================================================
        // 阶段2：顺序读(Sequential Reads) — 测量读延迟
        // ============================================================
        // 发送s_count个单拍读请求
        // 读延迟通常比写延迟高，因为需要经过更多流水线阶段
        // 【读延迟 = 读数据返回时间 - 读地址发出时间】
        for (int i = 0; i < s_count; i++) begin
            txn = axi_txn::type_id::create($sformatf("pr_%0d", i));
            txn.kind = axi_txn::READ;

            // 读取相同地址
            txn.addr = s_addr + i * 4;
            txn.id = s_id;
            txn.len = 0; txn.size = 2; txn.burst = 1;

            txn.rdata = new[1];

            start_item(txn); finish_item(txn);
        end

        // ============================================================
        // 阶段3：突发写(Burst Writes) — 测量写带宽
        // ============================================================
        // 发送4个16拍burst写请求
        // 【带宽计算】
        //   每次burst传输 = 16拍 × 4字节/拍 = 64字节
        //   总传输量 = 4次 × 64字节 = 256字节
        //   带宽 = 总传输量 / 总时间
        //
        // 【为什么burst能提高带宽】
        //   单拍传输：每次需要发送地址(AW通道) + 数据(W通道) + 等待响应(B通道)
        //   Burst传输：只发一次地址，然后连续发16拍数据，最后等一次响应
        //   地址通道的利用率大幅降低，数据通道接近满负荷
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("bw_%0d", i));
            txn.kind = axi_txn::WRITE;
            txn.addr = s_addr; // 每次burst从相同基地址开始
            txn.id = s_id;

            // 16拍burst传输
            // len=15:  实际拍数 = 15+1 = 16拍
            // size=2:  每拍4字节
            // burst=1: INCR模式(地址递增)
            // 总传输量 = 16 × 4 = 64字节
            txn.len = 15; txn.size = 2; txn.burst = 1;

            // 分配16个元素的数据数组
            txn.wdata = new[16]; txn.wstrb = new[16];

            // 填充16拍数据
            for (int j = 0; j < 16; j++) begin
                // 数据包含burst编号(i)和拍编号(j)，便于验证
                txn.wdata[j] = 32'h8A00_0000 + i * 16 + j;
                txn.wstrb[j] = 4'hF;
            end

            start_item(txn); finish_item(txn);
        end

        // ============================================================
        // 阶段4：突发读(Burst Reads) — 测量读带宽
        // ============================================================
        // 发送4个16拍burst读请求
        // 与突发写对称，测量读方向的带宽
        for (int i = 0; i < 4; i++) begin
            txn = axi_txn::type_id::create($sformatf("br_%0d", i));
            txn.kind = axi_txn::READ;
            txn.addr = s_addr;
            txn.id = s_id;

            // 同样的16拍burst参数
            txn.len = 15; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区
            txn.rdata = new[16];

            start_item(txn); finish_item(txn);
        end

        // 【性能分析】
        // monitor会记录每个事务的时间戳，scoreboard或checker会计算：
        // 1. 平均写延迟 = 写响应时间总和 / 写请求数量
        // 2. 平均读延迟 = 读数据时间总和 / 读请求数量
        // 3. 写带宽 = 总写数据量 / 写传输时间
        // 4. 读带宽 = 总读数据量 / 读传输时间
        // 这些指标会记录在最终的test report中
    endtask
endclass
