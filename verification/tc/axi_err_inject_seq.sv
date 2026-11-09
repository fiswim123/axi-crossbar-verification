//==========================================================================
// Error Injection Sequence
// 功能说明：错误注入测试序列
//
// 测试目的：
//   验证AXI Crossbar在接收到错误响应时的处理能力。
//   在实际系统中，从设备可能因为各种原因返回错误响应(SLVERR/DECERR)，
//   crossbar需要正确地将错误信息传递给主设备，而不能导致系统崩溃。
//
// AXI协议中的错误类型：
//   - SLVERR (Slave Error)：从设备错误，表示从设备无法完成请求
//     例如：访问了从设备的无效寄存器地址
//   - DECERR (Decode Error)：解码错误，表示地址无法路由到任何从设备
//     例如：访问了crossbar地址映射表中不存在的地址
//   - 在读通道中，错误通过RRESP信号传递（2位，00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR）
//   - 在写通道中，错误通过BRESP信号传递
//
// 测试场景：
//   本文件包含两个sequence：
//   1. axi_err_inject_seq：单次错误注入（先写后读同一地址）
//   2. axi_err_multi_seq：多次错误注入（交替读写，随机错误预期）
//==========================================================================

//==========================================================================
// 单次错误注入Sequence
// 向指定地址发送一个写和一个读，预期可能产生错误响应
//==========================================================================
class axi_err_inject_seq extends uvm_sequence #(axi_txn);

    // 工厂注册
    `uvm_object_utils(axi_err_inject_seq)

    // s_addr：目标地址
    // 这个地址可能是：
    // - 一个不存在的地址（触发DECERR解码错误）
    // - 一个故障从设备的地址（触发SLVERR从设备错误）
    bit [15:0] s_addr;

    // s_id：事务ID
    bit [7:0]  s_id;

    // s_expect_err：是否预期产生错误
    // 1 = 预期有错误响应（用于验证错误处理逻辑）
    // 0 = 预期正常响应（正常测试路径）
    // 这个标志会被传递给scoreboard，用于判断测试是否通过
    bit        s_expect_err;

    // 构造函数
    function new(string name = "axi_err_inject_seq");
        super.new(name);
    endfunction

    // body()任务：生成带错误注入的读写激励
    task body();
        axi_txn txn;

        // ==================== 写操作（带错误注入） ====================
        // 创建写事务
        txn = axi_txn::type_id::create("wr_err");

        // 设置为写操作
        txn.kind = axi_txn::WRITE;

        // 设置地址和ID
        txn.addr = s_addr;  // 目标地址（可能是无效地址）
        txn.id = s_id;

        // 单拍写参数
        txn.len = 0; txn.size = 2; txn.burst = 1;

        // 分配写数据缓冲区
        txn.wdata = new[1];
        txn.wstrb = new[1];

        // 写数据：DEAD_BEEF是经典的测试数据模式
        // 这个模式在内存测试中广泛使用，便于在波形中识别
        txn.wdata[0] = 32'hDEAD_BEEF;

        // 全字节写入
        txn.wstrb[0] = 4'hF;

        // 设置错误预期标志
        // driver或monitor会将这个标志与实际的响应比较
        // 如果实际响应与预期不符，scoreboard会报错
        txn.expect_err = s_expect_err;

        // 发送写事务
        start_item(txn); finish_item(txn);

        // ==================== 读操作（带错误注入） ====================
        // 创建读事务
        txn = axi_txn::type_id::create("rd_err");

        // 设置为读操作
        txn.kind = axi_txn::READ;

        // 读同一个地址
        // 如果写时产生了错误，读也应该产生类似的错误
        txn.addr = s_addr;
        txn.id = s_id;

        // 单拍读参数
        txn.len = 0; txn.size = 2; txn.burst = 1;

        // 分配读数据缓冲区
        txn.rdata = new[1];

        // 同样设置错误预期标志
        txn.expect_err = s_expect_err;

        // 发送读事务
        start_item(txn); finish_item(txn);

        // 测试验证点：
        // 1. crossbar是否正确传递从设备的错误响应
        // 2. 错误响应是否与expect_err标志一致
        // 3. 错误事务后，crossbar是否仍能正常工作（不卡死）
        // 4. 错误计数是否正确统计
    endtask
endclass

//==========================================================================
// Multiple Error Injection Sequence
// 功能说明：多次错误注入测试序列
//
// 测试目的：
//   通过多次交替的读写操作，混合正常和错误预期，验证crossbar在
//   持续错误注入下的稳定性和错误恢复能力。
//   实际系统中错误可能是间歇性的，这个测试模拟了这种场景。
//==========================================================================
class axi_err_multi_seq extends uvm_sequence #(axi_txn);

    // 工厂注册
    `uvm_object_utils(axi_err_multi_seq)

    // s_addr：起始地址
    // 多次测试时地址会递增：s_addr, s_addr+4, s_addr+8, ...
    bit [15:0] s_addr;

    // s_id：事务ID
    bit [7:0]  s_id;

    // s_count：测试次数，默认为4
    // 可以通过test或sequence的配置修改这个值，控制测试规模
    int        s_count = 4;

    // 构造函数
    function new(string name = "axi_err_multi_seq");
        super.new(name);
    endfunction

    // body()任务：生成多次交替的读写激励，随机注入错误预期
    task body();
        axi_txn txn;

        // 循环s_count次，默认4次
        for (int i = 0; i < s_count; i++) begin

            // 创建事务对象
            txn = axi_txn::type_id::create($sformatf("txn_%0d", i));

            // 交替选择读或写操作
            // i为偶数时写，i为奇数时读：写0,读1,写2,读3...
            txn.kind = (i % 2 == 0) ? axi_txn::WRITE : axi_txn::READ;

            // 地址递增：每次偏移4字节
            txn.addr = s_addr + i * 4;
            txn.id = s_id;

            // 单拍参数
            txn.len = 0; txn.size = 2; txn.burst = 1;

            // 根据操作类型分配不同的缓冲区
            if (txn.kind == axi_txn::WRITE) begin
                // 写操作：分配写数据和字节选通
                txn.wdata = new[1];
                txn.wstrb = new[1];
                // 写数据：0xCAFE0000 + i，每轮数据不同
                // CAFE是另一种常见的测试模式
                txn.wdata[0] = 32'hCAFE_0000 + i;
                txn.wstrb[0] = 4'hF;  // 全字节有效
            end else begin
                // 读操作：分配读数据缓冲区
                txn.rdata = new[1];
            end

            // 随机决定是否预期错误（50%概率）
            // $urandom_range(0, 1)：生成0或1的随机数
            // 当结果为0时，expect_err=1（预期有错误）
            // 当结果为1时，expect_err=0（预期无错误）
            // 这种随机化的错误注入可以发现更多边界情况
            txn.expect_err = ($urandom_range(0, 1) == 0);

            // 发送事务
            start_item(txn); finish_item(txn);
        end
        // 测试验证点：
        // 1. crossbar在持续错误注入下是否保持稳定
        // 2. 错误事务是否不影响后续正常事务
        // 3. 随机的错误预期是否与实际错误响应匹配
        // 4. 内部状态机是否在错误后正确复位
        // 5. 是否存在错误累积导致的系统退化
    endtask
endclass
