//==========================================================================
// Full Routing Sequence — 全路由覆盖测试序列
//==========================================================================
// 【测试目的】
//   确保AXI Crossbar的所有路由路径(route)都被测试到。
//
// 【什么是路由(Routing)】
//   AXI Crossbar的核心功能是将多个Master的请求路由到正确的Slave。
//   路由依据是请求的地址(addr)：
//   - Crossbar内部有地址解码器(address decoder)
//   - 根据地址范围判断该请求应该发往哪个Slave
//   - 例如：addr 0x0000-0x0FFF → Slave0, 0x1000-0x1FFF → Slave1, ...
//
// 【本序列的背景】
//   从注释中可以看到，之前的测试已经覆盖了部分路由路径：
//   已覆盖: MST0→SLV0/1/2/3, MST1→SLV0, MST2→SLV1, MST3→SLV3
//   待覆盖: MST1→SLV1/2/3, MST2→SLV0/2/3, MST3→SLV0/1/2
//
//   本sequence是一个通用的路由测试sequence，在test层通过
//   设置不同的s_id(代表不同master)和s_addr(路由到不同slave)
//   来组合出所有缺失的路由路径。
//
// 【为什么路由覆盖很重要】
//   - Crossbar内部可能有多个独立的数据通路
//   - 不同的MST→SLV路径可能使用不同的仲裁逻辑
//   - 某些路径可能存在竞争条件(race condition)
//   - 地址解码逻辑可能在某些边界条件下出错
//
// 【使用方式】
//   在test中，为每个需要测试的MST→SLV组合创建一个实例：
//   例如测试MST1→SLV1:
//     seq.s_id   = 8'h01;  // Master 1
//     seq.s_addr = 16'h1000;  // Slave 1的地址
//   例如测试MST2→SLV3:
//     seq.s_id   = 8'h02;  // Master 2
//     seq.s_addr = 16'h3000;  // Slave 3的地址
//==========================================================================
class axi_full_routing_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_full_routing_seq)

    // s_id: 事务ID，代表发起请求的Master编号
    // 在test层设置：MST0=0x00, MST1=0x01, MST2=0x02, MST3=0x03
    bit [7:0]  s_id;

    // s_addr: 目标地址，决定路由到哪个Slave
    // 在test层设置：SLV0=0x0000, SLV1=0x1000, SLV2=0x2000, SLV3=0x3000
    bit [15:0] s_addr;

    // 构造函数
    function new(string name = "axi_full_routing_seq");
        super.new(name);
    endfunction

    // body()任务：产生一次写操作来测试路由
    // 只需要一次写操作即可验证路由功能：
    // 如果写操作成功到达正确的Slave并返回正确响应，
    // 说明该MST→SLV的路由路径工作正常
    task body();
        // 创建一个AXI事务对象
        // 注意：这里直接用create创建了一个txn，而不是声明后再create
        axi_txn txn = axi_txn::type_id::create("txn");

        // 设置为写操作
        // 写操作比读操作更适合路由测试，因为：
        // 1. 写操作可以在一次请求中完成(地址+数据)
        // 2. 写响应(B通道)可以确认请求是否被正确处理
        txn.kind  = axi_txn::WRITE;

        // 设置路由地址(由test层配置)
        // Crossbar会根据此地址决定发往哪个Slave
        txn.addr  = s_addr;

        // 设置事务ID(由test层配置)
        txn.id    = s_id;

        // 单拍传输参数
        // len=0:  1拍(最简单的传输形式)
        // size=2: 4字节(32位)
        // burst=1: INCR模式
        txn.len   = 0;
        txn.size  = 2;

        // 注意：burst字段没有显式设置，默认值为0或由txn类定义
        // 这里不影响功能，因为len=0时burst类型无关紧要

        // 分配写数据缓冲区
        txn.wdata = new[1];
        txn.wstrb = new[1];

        // 写入特殊数据模式 0xC0DE_0000
        // C0DE 类似 "CODE"，便于在波形中识别这是路由测试的数据
        txn.wdata[0] = 32'hC0DE_0000;
        txn.wstrb[0] = 4'hF; // 所有字节有效

        // 发送事务并等待完成
        // 如果路由正确，此事务会被Crossbar转发到正确的Slave
        // Slave返回写响应(B通道)，完成整个写流程
        start_item(txn);
        finish_item(txn);

        // 【验证方式】
        // 1. scoreboard会检查写响应是否成功(OKAY响应)
        // 2. monitor会记录事务的源Master和目标Slave信息
        // 3. 如果路由错误，事务会发往错误的Slave，
        //    可能导致地址解码错误或超时
    endtask
endclass
