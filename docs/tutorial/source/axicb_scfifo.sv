//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_scfifo.sv
// 文件功能: 同步单时钟 FIFO 控制器 (Single-Clock FIFO Controller)
// 模块描述:
//   本模块实现具备高灵活性、支持旁路低延迟特性的单时钟同步先进先出队列 (FIFO)。
//   用于跨接口缓冲突发数据、暂存握手属性或匹配速率不平衡的上下游。
//
// 核心机制与特性:
//   1. 扩展位指针机制 (Extended Bit Pointer):
//      - 读写指针位宽为 (ADDR_WIDTH + 1)，最高位为折返翻转位 (Wrap-around bit)。
//      - 判空 (empty): wrptr == rdptr，表明指针完全相等，处于空状态。
//      - 判满 (full) : (wrptr - rdptr) == 2^ADDR_WIDTH，即低位相同、最高位相反。
//   2. 刷新清空控制 (flush):
//      - 支持同步 flush 信号，使读写指针同时复位归零，实现单周期逻辑排空。
//   3. 旁路直通模式 (Pass-Thru Mode):
//      - 由参数 PASS_THRU 控制。在 FIFO 处于空状态 (empty) 且下游持续拉高 pull 索取数据时，
//        新来的输入流 (data_in) 绕过 RAM 存储体，直接以纯组合逻辑直达 data_out 输出。
//      - 优势: 将数据从写入到读出的延迟由 1 个周期降至 0 周期。
//      - 注意事项: 形成了从输入到输出的纯组合路径，调用处需注意避免组合环路。
//   4. 物理后端可选 (参数 BLOCK):
//      - "RAM"    : 例化推断 RAM 存储体 (axicb_scfifo_ram)，节约寄存器面积。
//      - "REGFILE": 例化触发器堆 (axicb_scfifo_regfile)，带全存储单元复位。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_scfifo

    #(
        //---------------------------------------------------------------------
        // 参数配置
        //---------------------------------------------------------------------
        // 存储体类型选择: "RAM" (推断式 RAM) 或 "REGFILE" (寄存器阵列)
        parameter BLOCK      = "RAM",
        // 旁路直通使能: 1=使能空队列下的零延迟直通, 0=关闭 (纯排队存储)
        parameter PASS_THRU  = 0,
        // 地址总线位宽，FIFO 深度 Depth = 2**ADDR_WIDTH
        parameter ADDR_WIDTH = 8,
        // 数据总线位宽 (单位: bit)
        parameter DATA_WIDTH = 8
    )(
        // 全局控制信号
        input  wire                   aclk,      // 统一工作时钟
        input  wire                   aresetn,   // 异步全局复位，低电平有效
        input  wire                   srst,      // 同步复位，高电平有效
        input  wire                   flush,     // 同步刷新清空信号 (将读写指针清零)

        // 数据写入端口 (Push 接口)
        input  wire  [DATA_WIDTH-1:0] data_in,   // 写入数据流有效载荷
        input  wire                   push,      // 写使能请求信号
        output logic                  full,      // FIFO 满状态标志 (1 表示已满，禁止写入)

        // 数据读出端口 (Pull 接口)
        output logic [DATA_WIDTH-1:0] data_out,  // 读出数据流有效载荷
        input  wire                   pull,      // 读使能请求信号
        output logic                  empty      // FIFO 空状态标志 (1 表示已空，无有效数据)
    );

    //-------------------------------------------------------------------------
    // 内部连线与寄存器声明
    //-------------------------------------------------------------------------
    logic                  wr_en;       // 实际传递给物理存储体的写使能
    logic [ADDR_WIDTH  :0] wrptr;       // 写指针: 位宽为 ADDR_WIDTH+1 (多出 1 位用于判空满)
    logic [ADDR_WIDTH  :0] rdptr;       // 读指针: 位宽为 ADDR_WIDTH+1
    logic                  empty_flag;  // 内部寄存队列判空标志
    logic                  full_flag;   // 内部寄存队列判满标志
    logic                  pass_thru;   // 处于直通传输状态的条件指示
    logic [DATA_WIDTH-1:0] data_fifo;   // 从底层存储体中读取的暂存数据

    //=========================================================================
    // 1. 写指针管理逻辑 (Write Pointer Management)
    //=========================================================================
    always @ (posedge aclk or negedge aresetn) begin
        // 异步复位: 写指针清零
        if (aresetn == 1'b0) begin
            wrptr <= {(ADDR_WIDTH+1){1'b0}};
        // 同步复位或刷新: 写指针清零，丢弃所有排队条目
        end else if (srst || flush) begin
            wrptr <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            // 写入递增条件:
            // 必须满足: 上游发起 push、当前未满 (!full_flag)、且未处于旁路直通模式 (!pass_thru)。
            // [设计重点]: 如果当前处于 pass_thru，数据同拍直接流向下游，不入队，因此写指针不递增。
            if (push == 1'b1 && full_flag == 1'b0 && pass_thru == 1'b0) begin
                wrptr <= wrptr + 1'b1;
            end
        end
    end

    //=========================================================================
    // 2. 读指针管理逻辑 (Read Pointer Management)
    //=========================================================================
    always @ (posedge aclk or negedge aresetn) begin
        // 异步复位: 读指针清零
        if (aresetn == 1'b0) begin
            rdptr <= {(ADDR_WIDTH+1){1'b0}};
        // 同步复位或刷新: 读指针清零
        end else if (srst || flush) begin
            rdptr <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            // 读出递增条件:
            // 必须满足: 下游发起 pull、且当前内部 FIFO 非空 (!empty_flag)。
            // 只有真正从内部存储体中弹出一个有效条目时，读指针才递增 1。
            if (pull == 1'b1 && empty_flag == 1'b0) begin
                rdptr <= rdptr + 1'b1;
            end
        end
    end

    //=========================================================================
    // 3. 空满状态标志生成 (Full & Empty Detection)
    //=========================================================================
    // 判空: 读写指针完全一致 (包括最高回绕位相同)
    assign empty_flag = (wrptr == rdptr) ? 1'b1 : 1'b0;

    // 判满: 指针差值刚好等于深度 (最高位不同，其余低位相同，即差值为 100...0)
    assign full_flag  = ((wrptr - rdptr) == {1'b1, {ADDR_WIDTH{1'b0}}}) ? 1'b1 : 1'b0;

    //=========================================================================
    // 4. 底层物理存储体例化 (Internal Storage Block)
    //=========================================================================
    // 实际进入底层存储体的写使能: 只有当 push 且非满且未旁路时，才执行物理写入
    assign wr_en = push & ~full & ~pass_thru;

    generate
    if (BLOCK == "RAM") begin : RAM_BLOCK
        // 分支 A: 例化 RAM 存储体 (适用于大深度、节约资源)
        axicb_scfifo_ram
        #(
            .ADDR_WIDTH (ADDR_WIDTH),
            .DATA_WIDTH (DATA_WIDTH),
            .FFD_EN     (0)           // 采用零周期组合读，保证 pull 当拍数据就绪
        )
        fifo_ram
        (
            .aclk     (aclk),
            .wr_en    (wr_en),
            .addr_in  (wrptr[ADDR_WIDTH-1:0]), // 截取低位作为物理寻址
            .data_in  (data_in),
            .addr_out (rdptr[ADDR_WIDTH-1:0]),
            .data_out (data_fifo)
        );

    end else begin : REGFILE_BLOCK
        // 分支 B: 例化触发器堆存储体 (支持全复位、适用于小深度关键控制队列)
        axicb_scfifo_regfile
        #(
            .ADDR_WIDTH (ADDR_WIDTH),
            .DATA_WIDTH (DATA_WIDTH),
            .FFD_EN     (0)           // 采用零周期组合读
        )
        fifo_regfile
        (
            .aclk     (aclk),
            .aresetn  (aresetn),
            .srst     (srst),
            .wr_en    (wr_en),
            .addr_in  (wrptr[ADDR_WIDTH-1:0]),
            .data_in  (data_in),
            .addr_out (rdptr[ADDR_WIDTH-1:0]),
            .data_out (data_fifo)
        );

    end
    endgenerate

    //=========================================================================
    // 5. 旁路直通模式管理 (Pass-Thru Mode Management)
    //=========================================================================
    generate
    if (PASS_THRU) begin : PASS_THRU_MODE
        // 当使能 PASS_THRU:
        // 如果当前内部队列为空 (empty_flag=1)，且下游正在 pull 请求数据，
        // 则触发 pass_thru 状态。
        assign pass_thru = pull & empty_flag;

        // 输出多路选择:
        // 在直通状态下，将输入端口 data_in 纯组合逻辑直通给 data_out；
        // 否则输出底层存储体中的读出数据 data_fifo。
        assign data_out  = (pass_thru) ? data_in : data_fifo;

        // 对外 empty 状态:
        // 如果处于直通状态，是否有数据取决于上游当前是否有 push 写入；
        // 若没有处于直通状态，则返回真实的内部寄存队列判空结果 empty_flag。
        assign empty     = (pass_thru) ? ~push : empty_flag;

        // 对外 full 状态: 直接等于内部 full_flag
        assign full      = full_flag;

    end else begin : STORE_MODE
        // 当关闭 PASS_THRU:
        // 纯排队存储模式，绝不旁路
        assign pass_thru = 1'b0;
        assign data_out  = data_fifo;
        assign empty     = empty_flag;
        assign full      = full_flag;

    end
    endgenerate

endmodule

`resetall
