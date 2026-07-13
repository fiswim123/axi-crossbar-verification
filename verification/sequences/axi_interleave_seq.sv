//==========================================================================
// Read/Write Interleave Sequence (T042)
// 功能说明：读写交替(Interleave)测试序列
//
// 测试目的：
//   验证AXI Crossbar在读写操作交替进行时的正确性。
//   读写交替是实际应用中最常见的访问模式，因为CPU通常会
//   先写入数据再读回验证，或对同一地址区域进行混合读写。
//
// 测试场景：
//   对同一个地址，交替执行写操作和读操作，共4轮（4写+4读=8个事务）。
//   每轮先写后读同一地址，验证数据一致性(Coherency)。
//
// AXI协议知识点：
//   - AXI的读和写使用独立的通道，理论上可以同时进行
//   - 读通道：AR(地址) + R(数据)
//   - 写通道：AW(地址) + W(数据) + B(响应)
//   - 当读写同一地址时，存在数据冒险(Data Hazard)：
//     * Read After Write (RAW)：先写后读，需要保证读到写入的数据
//     * Write After Read (WAR)：先读后写
//     * Write After Write (WAW)：连续写同一地址
//   - Crossbar需要正确处理这些冒险，确保数据一致性
//==========================================================================

// 类定义：读写交替测试sequence
class axi_interleave_seq extends uvm_sequence #(axi_txn);

    // 工厂注册
    `uvm_object_utils(axi_interleave_seq)

    // s_addr：目标地址，读写都使用这个地址
    // 读写同一地址可以测试crossbar的数据一致性处理能力
    bit [15:0] s_addr;

    // s_id：事务ID，相同ID确保保序
    bit [7:0]  s_id;

    // 构造函数
    function new(string name = "axi_interleave_seq");
        super.new(name);
    endfunction

    // body()任务：生成交替的读写激励
    task body();
        axi_txn txn;  // 事务句柄

        // 循环4次，每轮包含一个写操作和一个读操作
        for (int i = 0; i < 4; i++) begin

            // ==================== 写操作部分 ====================
            // 创建写事务对象
            txn = axi_txn::type_id::create($sformatf("wr_%0d", i));

            // 设置为写操作
            txn.kind = axi_txn::WRITE;

            // 地址和ID都使用相同值
            txn.addr = s_addr;
            txn.id = s_id;

            // 单拍写操作参数
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 分配写数据和字节选通缓冲区
            txn.wdata = new[1];
            txn.wstrb = new[1];

            // 写数据：0x1EAF0000 + i
            // 1EAF是测试模式，加上循环计数器i使每轮数据不同
            // 这样读回时可以验证是否读到了最新写入的数据
            txn.wdata[0] = 32'h1EAF0000 + i;

            // 全字节写入有效
            txn.wstrb[0] = 4'hF;

            // 发送写事务，等待driver完成驱动
            start_item(txn); finish_item(txn);

            // ==================== 读操作部分 ====================
            // 创建读事务对象
            txn = axi_txn::type_id::create($sformatf("rd_%0d", i));

            // 设置为读操作
            txn.kind = axi_txn::READ;

            // 读同一个地址（RAW冒险场景）
            // 如果crossbar正确处理，应该读到刚才写入的数据
            txn.addr = s_addr;
            txn.id = s_id;

            // 单拍读操作参数
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 分配读数据缓冲区
            txn.rdata = new[1];

            // 发送读事务
            start_item(txn); finish_item(txn);
        end
        // 测试验证点：
        // 1. 读操作是否能读到最新写入的数据（RAW一致性）
        // 2. crossbar是否正确处理读写通道的交叉
        // 3. 相同ID的读写事务是否保持正确的顺序
        // 4. 响应信号是否正确（写响应BVALID，读数据RVALID）
    endtask
endclass
