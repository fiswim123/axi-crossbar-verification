//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_scfifo_regfile.sv
// 文件功能: 同步 FIFO 存储体 - 寄存器堆实现方式 (Register-File Storage)
// 模块描述:
//   本模块为同步 FIFO 控制器 (axicb_scfifo) 提供基于 D 触发器寄存器堆实现的物理存储体。
//   与 RAM 实现方式相比，寄存器堆存储体的特点包括:
//   1. 具备全阵列复位能力 (Fully-Resettable Register Array):
//      - 包含异步复位 (aresetn) 和同步复位 (srst)。
//      - 复位时通过循环 (for loop) 将存储体内的每个寄存器清零，确保复位后内容确定。
//      - 缺点: 消耗触发器资源较多，不适合深度很大的 FIFO (通常用于深度 2/4/8 等浅层队列)。
//   2. 读数据模式可配置 (参数 FFD_EN):
//      - FFD_EN = 0: 组合读 (异步读)，读地址一变立即输出数据。
//      - FFD_EN = 1: 寄存读 (同步读)，读出数据寄存打一拍输出。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_scfifo_regfile

    #(
        //---------------------------------------------------------------------
        // 参数配置
        //---------------------------------------------------------------------
        // 地址总线位宽，对应 FIFO 深度为 2**ADDR_WIDTH
        parameter ADDR_WIDTH = 8,
        // 数据总线位宽 (单位: bit)
        parameter DATA_WIDTH = 8,
        // 读出口寄存器使能: 0=组合输出, 1=触发器打拍输出
        parameter FFD_EN     = 0
    )(
        // 全局信号
        input  wire                   aclk,      // 统一工作时钟
        input  wire                   aresetn,   // 异步复位信号，低电平有效
        input  wire                   srst,      // 同步复位信号，高电平有效

        // 写端口 (Write Port)
        input  wire                   wr_en,     // 写使能，高电平有效
        input  wire  [ADDR_WIDTH-1:0] addr_in,   // 写入条目索引
        input  wire  [DATA_WIDTH-1:0] data_in,   // 写入数据负载

        // 读端口 (Read Port)
        input  wire  [ADDR_WIDTH-1:0] addr_out,  // 读出条目索引
        output logic [DATA_WIDTH-1:0] data_out   // 读出数据负载
    );

    // 计算内部寄存器堆的总深度: 2^ADDR_WIDTH 个条目
    localparam DEPTH = 2**ADDR_WIDTH;

    // 定义寄存器阵列: 由 DEPTH 个宽度为 DATA_WIDTH 的寄存器构成
    logic [DATA_WIDTH-1:0] ram [DEPTH-1:0];

    //-------------------------------------------------------------------------
    // 写入与复位进程
    //-------------------------------------------------------------------------
    always @ (posedge aclk or negedge aresetn) begin
        // 异步复位: 遍历清空每个存储单元
        if (!aresetn) begin
            for (int i=0; i<DEPTH; i++)
                ram[i] <= '0;
        // 同步复位: 遍历清空每个存储单元
        end else if (srst) begin
            for (int i=0; i<DEPTH; i++)
                ram[i] <= '0;
        // 正常工作模式下的同步写操作
        end else if (wr_en) begin
            ram[addr_in] <= data_in; // 在指定索引写入输入数据
        end
    end

    //-------------------------------------------------------------------------
    // 读出逻辑
    //-------------------------------------------------------------------------
    generate if (FFD_EN==1) begin: WITH_FFD
        // 模式 1: 寄存输出 (打一拍)
        always @ (posedge aclk) begin
            data_out <= ram[addr_out];
        end
    end else begin: NO_FFD
        // 模式 2: 纯组合逻辑输出 (零延迟)
        assign data_out = ram[addr_out];
    end
    endgenerate

endmodule

`resetall
