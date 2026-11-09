//==========================================================================
// Same Slave Contention Sequence (T041)
// 功能说明：同一从设备竞争访问测试序列
//
// 测试目的：
//   验证当多个主设备同时访问同一个从设备(Slave)时，crossbar的仲裁机制。
//   这是crossbar设计中最关键的场景之一，因为多个主设备到同一个从设备的
//   通路会产生资源竞争(Contention)，需要仲裁器(Arbiter)来决定谁先访问。
//
// 测试场景：
//   向同一个从设备地址连续发送4个写请求，所有请求目标地址相同。
//   这模拟了多个主设备或同一主设备的多个outstanding事务竞争同一从设备的情况。
//
// AXI协议知识点：
//   - AXI的写操作涉及三个通道：写地址(AW)、写数据(W)、写响应(B)
//   - Crossbar内部的仲裁器根据ID或轮询(Round-Robin)策略决定优先级
//   - 写操作的ID保序特性：相同AWID的写事务必须按发出顺序完成
//   - wstrb(Write Strobe)信号用于指定哪些字节有效，实现字节级别的写使能
//==========================================================================

// 类定义：同一从设备竞争访问的sequence
// 继承自uvm_sequence，参数化为axi_txn类型
class axi_same_slave_seq extends uvm_sequence #(axi_txn);

    // 工厂注册宏，允许通过工厂创建和重载该类
    `uvm_object_utils(axi_same_slave_seq)

    // s_addr：目标从设备的地址
    // 所有写请求都发往这个相同的地址，制造竞争条件
    // 在crossbar验证中，这个地址通常映射到某个特定的slave端口
    bit [15:0] s_addr;

    // s_id：事务ID
    // 用于标识事务来源，crossbar可能根据ID进行仲裁
    // 如果是不同主设备发起，ID通常不同
    bit [7:0]  s_id;

    // 构造函数
    function new(string name = "axi_same_slave_seq");
        super.new(name);
    endfunction

    // body()任务：sequence主体，生成竞争访问激励
    task body();
        axi_txn txn;  // 事务句柄

        // 循环4次，发送4个写请求到同一地址
        for (int i = 0; i < 4; i++) begin

            // 通过工厂创建事务对象，名称如 "txn_0", "txn_1" 等
            txn = axi_txn::type_id::create($sformatf("txn_%0d", i));

            // 设置为写操作
            txn.kind = axi_txn::WRITE;

            // 关键点：所有事务的地址相同(s_addr)，制造同一从设备的竞争
            // 地址相同意味着crossbar会将这些请求路由到同一个slave端口
            txn.addr = s_addr;
            txn.id = s_id;  // 使用相同的事务ID

            // AXI事务参数：
            // len=0：突发长度为1（单拍传输）
            // size=2：每拍4字节（32位）
            // burst=1：INCR突发类型
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 写数据相关的字段设置
            txn.wdata = new[1];  // 分配写数据缓冲区（1个32位数据）
            txn.wstrb = new[1];  // 分配写字节选通缓冲区

            // 写数据内容：32'hC0DE0000 + s_id
            // C0DE是"CODE"的十六进制，常用于测试模式(pattern)
            // 加上s_id可以区分不同来源的写数据，便于验证时检查
            txn.wdata[0] = 32'hC0DE0000 + s_id;

            // wstrb = 4'hF = 4'b1111，表示4个字节全部有效
            // wstrb每一位对应一个字节：bit[0]对应byte[0]，bit[3]对应byte[3]
            // 4'hF表示所有4字节都写入（全写）
            txn.wstrb[0] = 4'hF;

            // 发送事务：start_item等待sequencer授权，finish_item完成发送
            // driver接收到后会驱动AW、W、B三个通道的信号
            start_item(txn); finish_item(txn);
        end
        // 测试验证点：
        // 1. crossbar是否正确将所有请求路由到目标slave
        // 2. 仲裁器是否正确处理竞争（按ID优先级或轮询）
        // 3. 写响应(B channel)是否正确返回给请求方
        // 4. 所有写操作是否都正确完成，数据是否完整
    endtask
endclass
