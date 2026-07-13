//==========================================================================
// Transaction - AXI 事务类 (AXI Transaction Class)
//==========================================================================
// 【文件功能说明】
// 本文件定义了 AXI 协议的事务(transaction)类，是 UVM 验证环境中最基本的数据对象。
// 每一个 AXI 读操作或写操作都由一个 axi_txn 对象来描述。
//
// 【UVM 知识点】
// uvm_sequence_item 是 UVM 中所有事务类的基类。sequence_item 由 sequence 产生，
// 经过 sequencer 传递给 driver，driver 将其转换为实际的信号级激励驱动到 DUT。
// 这种 "sequence -> sequencer -> driver" 的数据流是 UVM 验证方法学的核心架构。
//
// 【AXI 协议知识点】
// AXI (Advanced eXtensible Interface) 是 ARM AMBA 总线家族中的高性能接口协议。
// AXI 支持突发传输(burst transfer)，一次地址可以传输多个数据。
// AXI 有 5 个独立通道：AW(写地址)、W(写数据)、B(写响应)、AR(读地址)、R(读数据)。
// 各通道独立工作，通过握手信号(valid/ready)实现数据传输。
//==========================================================================
class axi_txn extends uvm_sequence_item;

    // 【枚举类型】定义事务类型：读(READ)或写(WRITE)
    // typedef 用于定义类型别名，enum 用于定义枚举
    typedef enum {READ, WRITE} kind_e;

    // 【随机变量】以下变量使用 rand 关键字声明，表示它们在 randomize() 时会被随机化
    // 这是 UVM 验证的核心思想：通过随机化生成各种合法的测试激励

    rand kind_e     kind;     // 事务类型：读或写
    rand bit [15:0] addr;     // AXI 地址信号 (16位，覆盖 64KB 地址空间)
    rand bit [7:0]  id;       // AXI ID 信号 (8位，用于乱序处理和事务识别)
                              // AXI 协议允许不同 ID 的事务乱序完成，提高总线效率
    rand bit [7:0]  len;      // AXI AxLEN：突发长度 = len + 1 (0表示1拍，15表示16拍)
                              // AXI3 协议：AxLEN 范围 0~15，对应突发长度 1~16
    rand bit [2:0]  size;     // AXI AxSIZE：每拍字节数 = 2^size (0=1字节, 1=2字节, 2=4字节)
                              // 我们的设计使用 32位数据总线，所以 size 最大为2 (4字节)
    rand bit [1:0]  burst;    // AXI AxBURST：突发类型
                              // 2'b00 = FIXED (固定地址，用于FIFO访问)
                              // 2'b01 = INCR (递增地址，最常用的突发类型)
                              // 2'b10 = WRAP (回环地址，用于Cache行填充)
    rand bit [31:0] wdata[];  // 写数据数组 (动态数组，32位宽)
                              // size() == len + 1，即每个数据拍对应一个数据
    rand bit [3:0]  wstrb[];  // 写选通信号数组 (4位，每位控制1字节是否有效)
                              // 例如 4'b1111 表示全部4字节有效，4'b0001 表示仅最低字节有效

    // 【非随机变量】以下变量不参与随机化，用于保存从 DUT 返回的响应信息
    bit [7:0]  bid, rid;      // 写响应ID / 读响应ID，应与请求的 id 匹配
    bit [1:0]  bresp, rresp;  // 写响应码 / 读响应码
                              // 2'b00 = OKAY (成功)
                              // 2'b10 = SLVERR (从设备错误)
                              // 2'b11 = DECERR (解码错误，地址无效)
    bit [31:0] rdata[];       // 读数据动态数组，由 driver 从总线上采样后填入

    // 【性能追踪】用于计算写操作的延迟
    time aw_time, w_time, b_time;    // 写操作时间戳：AW握手时刻、W完成时刻、B握手时刻
    time ar_time, r_time;            // 读操作时间戳：AR握手时刻、R完成时刻
    int  wr_latency, rd_latency;     // 计算得到的延迟值 (单位：时钟周期数)

    // 【错误注入标志】供 scoreboard (记分板) 使用
    // 当 slave driver 注入错误响应时，scoreboard 需要知道该事务是否应被预期为错误
    bit expect_err = 0;

    // ================================================================
    // 【约束块】c_basic - 基本约束
    // ================================================================
    // SystemVerilog 的 constraint 块用于限制随机变量的取值范围。
    // randomize() 时，求解器会在满足所有约束的前提下为变量赋值。
    constraint c_basic {
        size inside {[0:2]};         // size 取值 0, 1, 2 (对应 1, 2, 4 字节)
        len  inside {[0:15]};        // len 取值 0~15 (对应 1~16 拍突发)
        burst == 2'b01;              // 固定使用 INCR (递增) 突发类型
        addr[1:0] == 2'b00;          // 地址必须 4 字节对齐 (低2位为0)
        wdata.size() == len + 1;     // 写数据数组大小 = 突发长度
        wstrb.size() == len + 1;     // 写选通数组大小 = 突发长度
    }

    // ================================================================
    // 【约束块】c_boundary_addr - 边界地址测试约束
    // ================================================================
    // 用于产生关键边界地址值，验证 crossbar 在地址边界处的路由是否正确。
    // 这些地址对应 crossbar 各 slave 端口的地址范围边界：
    //   0x0000~0x0FFF -> Slave 0
    //   0x1000~0x1FFF -> Slave 1
    //   0x2000~0x2FFF -> Slave 2
    //   0x3000~0x3FFF -> Slave 3
    constraint c_boundary_addr {
        addr inside {16'h0000, 16'h0004, 16'h0FFC, 16'h1000,
                     16'h1FFC, 16'h2000, 16'h2FFC, 16'h3000,
                     16'h3FFC};
    }

    // ================================================================
    // 【约束块】c_boundary_burst - 边界突发长度测试约束
    // ================================================================
    // 选择典型的突发长度值进行测试
    constraint c_boundary_burst {
        len inside {0, 1, 3, 7, 15};  // 对应 1, 2, 4, 8, 16 拍突发
    }

    // ================================================================
    // 【约束块】c_boundary_id - 边界ID测试约束
    // ================================================================
    // 选择边界ID值，测试 crossbar 的 ID 路由和乱序处理能力
    constraint c_boundary_id {
        id inside {8'h00, 8'h0F, 8'h10, 8'h1F, 8'hFF};
    }

    // ================================================================
    // 【UVM 工厂注册宏】
    // ================================================================
    // `uvm_object_utils_begin/end 宏将 axi_txn 类注册到 UVM 工厂(factory)中。
    // 工厂机制是 UVM 的核心设计模式，允许在不修改代码的情况下替换组件类型。
    //
    // `uvm_field_enum  - 注册枚举类型字段，使 UVM 自动实现 print/copy/compare 等方法
    // `uvm_field_int   - 注册整数类型字段
    // `uvm_field_array_int - 注册动态数组字段
    // UVM_ALL_ON 表示对该字段启用所有自动化操作 (print, copy, compare, pack, unpack)
    `uvm_object_utils_begin(axi_txn)
        `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(id,    UVM_ALL_ON)
        `uvm_field_int(len,   UVM_ALL_ON)
        `uvm_field_int(size,  UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_array_int(wdata, UVM_ALL_ON)
        `uvm_field_array_int(wstrb, UVM_ALL_ON)
        `uvm_field_int(bresp, UVM_ALL_ON)
        `uvm_field_int(rresp, UVM_ALL_ON)
    `uvm_object_utils_end

    // ================================================================
    // 【构造函数】
    // ================================================================
    // 所有 UVM 组件和对象都需要一个 new() 构造函数。
    // uvm_sequence_item 的构造函数需要一个 string 类型的 name 参数，
    // 用于在 UVM 层次结构中标识该对象。
    function new(string name = "axi_txn");
        super.new(name);  // 调用父类构造函数
    endfunction

    // ================================================================
    // 【函数】calc_wr_latency - 计算写延迟
    // ================================================================
    // 计算从 AW 通道握手到 B 通道响应的总时间，单位为纳秒(ns)。
    // 延迟 = B响应时刻 - AW请求时刻
    // 用于性能分析和覆盖率收集。
    function int calc_wr_latency();
        if (aw_time > 0 && b_time > 0)
            return (b_time - aw_time) / 1000; // 将时间单位转换为 ns
        return 0;
    endfunction

    // ================================================================
    // 【函数】calc_rd_latency - 计算读延迟
    // ================================================================
    // 计算从 AR 通道握手到 R 通道响应的总时间，单位为纳秒(ns)。
    // 延迟 = R响应时刻 - AR请求时刻
    function int calc_rd_latency();
        if (ar_time > 0 && r_time > 0)
            return (r_time - ar_time) / 1000; // 将时间单位转换为 ns
        return 0;
    endfunction
endclass
