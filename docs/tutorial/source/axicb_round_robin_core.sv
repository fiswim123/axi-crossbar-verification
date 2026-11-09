//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_round_robin_core.sv
// 文件功能: 非阻塞无饥饿轮询仲裁核心 (Non-blocking Round-Robin Arbiter Core)
// 模块描述:
//   本模块实现参数化 (支持 2 到 32 路请求者) 的单周期轮询仲裁器核心。
//   在 AXI 总线写/读地址仲裁、多路返回响应仲裁中，提供公平、无饥饿的调度服务。
//
// 核心工作机制 (动态历史掩码算法 Mask-based Round-Robin):
//   1. 掩码机制 (Mask Tracking):
//      - 内部维护一个与请求位宽相同的历史掩码 mask。
//      - mask 记录了“在上一轮获胜的请求者之后，哪些请求者在本轮具备优先权”。
//      - 例如 4 路请求:
//        若请求者 0 刚获得授权 (grant=4'b0001)，则下一拍更新 mask = 4'b1110。
//        这表示请求者 1, 2, 3 在下一次仲裁中排在请求者 0 前面，避免请求者 0 连续独占。
//   2. 两阶段优先级扫描 (Two-Stage Priority Search):
//      - 阶段 2.1: 计算 masked = mask & req。
//        如果 masked 非零 (|masked == 1)，说明有处于高优先级窗口内的请求者在排队，
//        从最低有效位 (LSB) 开始查找并授权最先匹配的请求者。
//      - 阶段 2.2: 若 masked 为零 (|masked == 0)，说明高优先级窗口内无请求，
//        则发生“回绕 (Wrap-around)”，直接从原始未掩码的 req 向量中从 LSB 向 MSB 查找。
//   3. 仲裁授权保持与使能控制 (en 与 grant_r/grant_c):
//      - en 信号通常与下游握手事件 (例如 valid & ready) 绑定。
//      - 当 en=1 且产生有效授权时，动态更新 mask 历史状态，输出组合授权 grant_c。
//      - 当下游背压导致 en=0 时，仲裁状态冻结，输出上一拍寄存的 grant_r，
//        确保在握手阻塞期间，授权目标绝不发生跳变，维持 AXI 协议稳定性。
//   4. 展开结构说明:
//      - 为了确保逻辑综合出的延迟最短、完全没有循环依赖，源码针对 REQ_NB=2 到 32
//        通过 generate 块分别展开了硬编码的优先编码器与掩码生成逻辑。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_round_robin_core

    #(
        //---------------------------------------------------------------------
        // 参数配置
        //---------------------------------------------------------------------
        // 参与本核心仲裁的请求者数量 (支持 2 ~ 32)
        parameter REQ_NB = 4
    )(
        // 全局控制信号
        input  wire                   aclk,     // 统一工作时钟
        input  wire                   aresetn,  // 全局异步复位，低电平有效
        input  wire                   srst,     // 同步复位，高电平有效

        // 仲裁控制信号
        input  wire                   en,       // 仲裁推进使能 (仅在一次事务完成或接受时置 1)
        input  wire  [REQ_NB    -1:0] req,      // 各通道请求信号 (位 i 为 1 表示请求者 i 有请求)
        output logic [REQ_NB    -1:0] grant     // 最终仲裁授权 (One-hot 编码，位 i 为 1 表示请求者 i 获胜)
    );

    //-------------------------------------------------------------------------
    // 内部连线与状态寄存器
    //-------------------------------------------------------------------------
    logic [REQ_NB    -1:0] mask;     // 历史轮询掩码: 标记当前轮次中哪些索引拥有更高轮换优先级
    logic [REQ_NB    -1:0] masked;   // 掩码过滤后的请求: masked = mask & req
    logic [REQ_NB    -1:0] grant_r;  // 寄存的仲裁结果: 在 en=0 (反压/等待) 期间保持输出稳定
    logic [REQ_NB    -1:0] grant_c;  // 当前时钟周期的实时组合仲裁结果
    generate

    if (REQ_NB==2) begin : GRANT_2

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 2'd1;
            else if (masked[1]) grant_c = 2'd2;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 2'd1;
            else if (req[1]) grant_c = 2'd2;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_2

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 2'b10;
                else if (grant[1]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==3) begin : GRANT_3

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 3'd1;
            else if (masked[1]) grant_c = 3'd2;
            else if (masked[2]) grant_c = 3'd4;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 3'd1;
            else if (req[1]) grant_c = 3'd2;
            else if (req[2]) grant_c = 3'd4;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_3

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 3'b110;
                else if (grant[1]) mask <= 3'b100;
                else if (grant[2]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==4) begin : GRANT_4

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 4'd1;
            else if (masked[1]) grant_c = 4'd2;
            else if (masked[2]) grant_c = 4'd4;
            else if (masked[3]) grant_c = 4'd8;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 4'd1;
            else if (req[1]) grant_c = 4'd2;
            else if (req[2]) grant_c = 4'd4;
            else if (req[3]) grant_c = 4'd8;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_4

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 4'b1110;
                else if (grant[1]) mask <= 4'b1100;
                else if (grant[2]) mask <= 4'b1000;
                else if (grant[3]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==5) begin : GRANT_5

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 5'd1;
            else if (masked[1]) grant_c = 5'd2;
            else if (masked[2]) grant_c = 5'd4;
            else if (masked[3]) grant_c = 5'd8;
            else if (masked[4]) grant_c = 5'd16;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 5'd1;
            else if (req[1]) grant_c = 5'd2;
            else if (req[2]) grant_c = 5'd4;
            else if (req[3]) grant_c = 5'd8;
            else if (req[4]) grant_c = 5'd16;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_5

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 5'b11110;
                else if (grant[1]) mask <= 5'b11100;
                else if (grant[2]) mask <= 5'b11000;
                else if (grant[3]) mask <= 5'b10000;
                else if (grant[4]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==6) begin : GRANT_6

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 6'd1;
            else if (masked[1]) grant_c = 6'd2;
            else if (masked[2]) grant_c = 6'd4;
            else if (masked[3]) grant_c = 6'd8;
            else if (masked[4]) grant_c = 6'd16;
            else if (masked[5]) grant_c = 6'd32;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 6'd1;
            else if (req[1]) grant_c = 6'd2;
            else if (req[2]) grant_c = 6'd4;
            else if (req[3]) grant_c = 6'd8;
            else if (req[4]) grant_c = 6'd16;
            else if (req[5]) grant_c = 6'd32;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_6

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 6'b111110;
                else if (grant[1]) mask <= 6'b111100;
                else if (grant[2]) mask <= 6'b111000;
                else if (grant[3]) mask <= 6'b110000;
                else if (grant[4]) mask <= 6'b100000;
                else if (grant[5]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==7) begin : GRANT_7

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 7'd1;
            else if (masked[1]) grant_c = 7'd2;
            else if (masked[2]) grant_c = 7'd4;
            else if (masked[3]) grant_c = 7'd8;
            else if (masked[4]) grant_c = 7'd16;
            else if (masked[5]) grant_c = 7'd32;
            else if (masked[6]) grant_c = 7'd64;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 7'd1;
            else if (req[1]) grant_c = 7'd2;
            else if (req[2]) grant_c = 7'd4;
            else if (req[3]) grant_c = 7'd8;
            else if (req[4]) grant_c = 7'd16;
            else if (req[5]) grant_c = 7'd32;
            else if (req[6]) grant_c = 7'd64;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_7

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 7'b1111110;
                else if (grant[1]) mask <= 7'b1111100;
                else if (grant[2]) mask <= 7'b1111000;
                else if (grant[3]) mask <= 7'b1110000;
                else if (grant[4]) mask <= 7'b1100000;
                else if (grant[5]) mask <= 7'b1000000;
                else if (grant[6]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==8) begin : GRANT_8

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 8'd1;
            else if (masked[1]) grant_c = 8'd2;
            else if (masked[2]) grant_c = 8'd4;
            else if (masked[3]) grant_c = 8'd8;
            else if (masked[4]) grant_c = 8'd16;
            else if (masked[5]) grant_c = 8'd32;
            else if (masked[6]) grant_c = 8'd64;
            else if (masked[7]) grant_c = 8'd128;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 8'd1;
            else if (req[1]) grant_c = 8'd2;
            else if (req[2]) grant_c = 8'd4;
            else if (req[3]) grant_c = 8'd8;
            else if (req[4]) grant_c = 8'd16;
            else if (req[5]) grant_c = 8'd32;
            else if (req[6]) grant_c = 8'd64;
            else if (req[7]) grant_c = 8'd128;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_8

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 8'b11111110;
                else if (grant[1]) mask <= 8'b11111100;
                else if (grant[2]) mask <= 8'b11111000;
                else if (grant[3]) mask <= 8'b11110000;
                else if (grant[4]) mask <= 8'b11100000;
                else if (grant[5]) mask <= 8'b11000000;
                else if (grant[6]) mask <= 8'b10000000;
                else if (grant[7]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==9) begin : GRANT_9

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 9'd1;
            else if (masked[1]) grant_c = 9'd2;
            else if (masked[2]) grant_c = 9'd4;
            else if (masked[3]) grant_c = 9'd8;
            else if (masked[4]) grant_c = 9'd16;
            else if (masked[5]) grant_c = 9'd32;
            else if (masked[6]) grant_c = 9'd64;
            else if (masked[7]) grant_c = 9'd128;
            else if (masked[8]) grant_c = 9'd256;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 9'd1;
            else if (req[1]) grant_c = 9'd2;
            else if (req[2]) grant_c = 9'd4;
            else if (req[3]) grant_c = 9'd8;
            else if (req[4]) grant_c = 9'd16;
            else if (req[5]) grant_c = 9'd32;
            else if (req[6]) grant_c = 9'd64;
            else if (req[7]) grant_c = 9'd128;
            else if (req[8]) grant_c = 9'd256;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_9

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 9'b111111110;
                else if (grant[1]) mask <= 9'b111111100;
                else if (grant[2]) mask <= 9'b111111000;
                else if (grant[3]) mask <= 9'b111110000;
                else if (grant[4]) mask <= 9'b111100000;
                else if (grant[5]) mask <= 9'b111000000;
                else if (grant[6]) mask <= 9'b110000000;
                else if (grant[7]) mask <= 9'b100000000;
                else if (grant[8]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==10) begin : GRANT_10

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 10'd1;
            else if (masked[1]) grant_c = 10'd2;
            else if (masked[2]) grant_c = 10'd4;
            else if (masked[3]) grant_c = 10'd8;
            else if (masked[4]) grant_c = 10'd16;
            else if (masked[5]) grant_c = 10'd32;
            else if (masked[6]) grant_c = 10'd64;
            else if (masked[7]) grant_c = 10'd128;
            else if (masked[8]) grant_c = 10'd256;
            else if (masked[9]) grant_c = 10'd512;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 10'd1;
            else if (req[1]) grant_c = 10'd2;
            else if (req[2]) grant_c = 10'd4;
            else if (req[3]) grant_c = 10'd8;
            else if (req[4]) grant_c = 10'd16;
            else if (req[5]) grant_c = 10'd32;
            else if (req[6]) grant_c = 10'd64;
            else if (req[7]) grant_c = 10'd128;
            else if (req[8]) grant_c = 10'd256;
            else if (req[9]) grant_c = 10'd512;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_10

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 10'b1111111110;
                else if (grant[1]) mask <= 10'b1111111100;
                else if (grant[2]) mask <= 10'b1111111000;
                else if (grant[3]) mask <= 10'b1111110000;
                else if (grant[4]) mask <= 10'b1111100000;
                else if (grant[5]) mask <= 10'b1111000000;
                else if (grant[6]) mask <= 10'b1110000000;
                else if (grant[7]) mask <= 10'b1100000000;
                else if (grant[8]) mask <= 10'b1000000000;
                else if (grant[9]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==11) begin : GRANT_11

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 11'd1;
            else if (masked[1]) grant_c = 11'd2;
            else if (masked[2]) grant_c = 11'd4;
            else if (masked[3]) grant_c = 11'd8;
            else if (masked[4]) grant_c = 11'd16;
            else if (masked[5]) grant_c = 11'd32;
            else if (masked[6]) grant_c = 11'd64;
            else if (masked[7]) grant_c = 11'd128;
            else if (masked[8]) grant_c = 11'd256;
            else if (masked[9]) grant_c = 11'd512;
            else if (masked[10]) grant_c = 11'd1024;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 11'd1;
            else if (req[1]) grant_c = 11'd2;
            else if (req[2]) grant_c = 11'd4;
            else if (req[3]) grant_c = 11'd8;
            else if (req[4]) grant_c = 11'd16;
            else if (req[5]) grant_c = 11'd32;
            else if (req[6]) grant_c = 11'd64;
            else if (req[7]) grant_c = 11'd128;
            else if (req[8]) grant_c = 11'd256;
            else if (req[9]) grant_c = 11'd512;
            else if (req[10]) grant_c = 11'd1024;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_11

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 11'b11111111110;
                else if (grant[1]) mask <= 11'b11111111100;
                else if (grant[2]) mask <= 11'b11111111000;
                else if (grant[3]) mask <= 11'b11111110000;
                else if (grant[4]) mask <= 11'b11111100000;
                else if (grant[5]) mask <= 11'b11111000000;
                else if (grant[6]) mask <= 11'b11110000000;
                else if (grant[7]) mask <= 11'b11100000000;
                else if (grant[8]) mask <= 11'b11000000000;
                else if (grant[9]) mask <= 11'b10000000000;
                else if (grant[10]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==12) begin : GRANT_12

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 12'd1;
            else if (masked[1]) grant_c = 12'd2;
            else if (masked[2]) grant_c = 12'd4;
            else if (masked[3]) grant_c = 12'd8;
            else if (masked[4]) grant_c = 12'd16;
            else if (masked[5]) grant_c = 12'd32;
            else if (masked[6]) grant_c = 12'd64;
            else if (masked[7]) grant_c = 12'd128;
            else if (masked[8]) grant_c = 12'd256;
            else if (masked[9]) grant_c = 12'd512;
            else if (masked[10]) grant_c = 12'd1024;
            else if (masked[11]) grant_c = 12'd2048;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 12'd1;
            else if (req[1]) grant_c = 12'd2;
            else if (req[2]) grant_c = 12'd4;
            else if (req[3]) grant_c = 12'd8;
            else if (req[4]) grant_c = 12'd16;
            else if (req[5]) grant_c = 12'd32;
            else if (req[6]) grant_c = 12'd64;
            else if (req[7]) grant_c = 12'd128;
            else if (req[8]) grant_c = 12'd256;
            else if (req[9]) grant_c = 12'd512;
            else if (req[10]) grant_c = 12'd1024;
            else if (req[11]) grant_c = 12'd2048;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_12

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 12'b111111111110;
                else if (grant[1]) mask <= 12'b111111111100;
                else if (grant[2]) mask <= 12'b111111111000;
                else if (grant[3]) mask <= 12'b111111110000;
                else if (grant[4]) mask <= 12'b111111100000;
                else if (grant[5]) mask <= 12'b111111000000;
                else if (grant[6]) mask <= 12'b111110000000;
                else if (grant[7]) mask <= 12'b111100000000;
                else if (grant[8]) mask <= 12'b111000000000;
                else if (grant[9]) mask <= 12'b110000000000;
                else if (grant[10]) mask <= 12'b100000000000;
                else if (grant[11]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==13) begin : GRANT_13

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 13'd1;
            else if (masked[1]) grant_c = 13'd2;
            else if (masked[2]) grant_c = 13'd4;
            else if (masked[3]) grant_c = 13'd8;
            else if (masked[4]) grant_c = 13'd16;
            else if (masked[5]) grant_c = 13'd32;
            else if (masked[6]) grant_c = 13'd64;
            else if (masked[7]) grant_c = 13'd128;
            else if (masked[8]) grant_c = 13'd256;
            else if (masked[9]) grant_c = 13'd512;
            else if (masked[10]) grant_c = 13'd1024;
            else if (masked[11]) grant_c = 13'd2048;
            else if (masked[12]) grant_c = 13'd4096;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 13'd1;
            else if (req[1]) grant_c = 13'd2;
            else if (req[2]) grant_c = 13'd4;
            else if (req[3]) grant_c = 13'd8;
            else if (req[4]) grant_c = 13'd16;
            else if (req[5]) grant_c = 13'd32;
            else if (req[6]) grant_c = 13'd64;
            else if (req[7]) grant_c = 13'd128;
            else if (req[8]) grant_c = 13'd256;
            else if (req[9]) grant_c = 13'd512;
            else if (req[10]) grant_c = 13'd1024;
            else if (req[11]) grant_c = 13'd2048;
            else if (req[12]) grant_c = 13'd4096;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_13

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 13'b1111111111110;
                else if (grant[1]) mask <= 13'b1111111111100;
                else if (grant[2]) mask <= 13'b1111111111000;
                else if (grant[3]) mask <= 13'b1111111110000;
                else if (grant[4]) mask <= 13'b1111111100000;
                else if (grant[5]) mask <= 13'b1111111000000;
                else if (grant[6]) mask <= 13'b1111110000000;
                else if (grant[7]) mask <= 13'b1111100000000;
                else if (grant[8]) mask <= 13'b1111000000000;
                else if (grant[9]) mask <= 13'b1110000000000;
                else if (grant[10]) mask <= 13'b1100000000000;
                else if (grant[11]) mask <= 13'b1000000000000;
                else if (grant[12]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==14) begin : GRANT_14

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 14'd1;
            else if (masked[1]) grant_c = 14'd2;
            else if (masked[2]) grant_c = 14'd4;
            else if (masked[3]) grant_c = 14'd8;
            else if (masked[4]) grant_c = 14'd16;
            else if (masked[5]) grant_c = 14'd32;
            else if (masked[6]) grant_c = 14'd64;
            else if (masked[7]) grant_c = 14'd128;
            else if (masked[8]) grant_c = 14'd256;
            else if (masked[9]) grant_c = 14'd512;
            else if (masked[10]) grant_c = 14'd1024;
            else if (masked[11]) grant_c = 14'd2048;
            else if (masked[12]) grant_c = 14'd4096;
            else if (masked[13]) grant_c = 14'd8192;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 14'd1;
            else if (req[1]) grant_c = 14'd2;
            else if (req[2]) grant_c = 14'd4;
            else if (req[3]) grant_c = 14'd8;
            else if (req[4]) grant_c = 14'd16;
            else if (req[5]) grant_c = 14'd32;
            else if (req[6]) grant_c = 14'd64;
            else if (req[7]) grant_c = 14'd128;
            else if (req[8]) grant_c = 14'd256;
            else if (req[9]) grant_c = 14'd512;
            else if (req[10]) grant_c = 14'd1024;
            else if (req[11]) grant_c = 14'd2048;
            else if (req[12]) grant_c = 14'd4096;
            else if (req[13]) grant_c = 14'd8192;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_14

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 14'b11111111111110;
                else if (grant[1]) mask <= 14'b11111111111100;
                else if (grant[2]) mask <= 14'b11111111111000;
                else if (grant[3]) mask <= 14'b11111111110000;
                else if (grant[4]) mask <= 14'b11111111100000;
                else if (grant[5]) mask <= 14'b11111111000000;
                else if (grant[6]) mask <= 14'b11111110000000;
                else if (grant[7]) mask <= 14'b11111100000000;
                else if (grant[8]) mask <= 14'b11111000000000;
                else if (grant[9]) mask <= 14'b11110000000000;
                else if (grant[10]) mask <= 14'b11100000000000;
                else if (grant[11]) mask <= 14'b11000000000000;
                else if (grant[12]) mask <= 14'b10000000000000;
                else if (grant[13]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==15) begin : GRANT_15

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 15'd1;
            else if (masked[1]) grant_c = 15'd2;
            else if (masked[2]) grant_c = 15'd4;
            else if (masked[3]) grant_c = 15'd8;
            else if (masked[4]) grant_c = 15'd16;
            else if (masked[5]) grant_c = 15'd32;
            else if (masked[6]) grant_c = 15'd64;
            else if (masked[7]) grant_c = 15'd128;
            else if (masked[8]) grant_c = 15'd256;
            else if (masked[9]) grant_c = 15'd512;
            else if (masked[10]) grant_c = 15'd1024;
            else if (masked[11]) grant_c = 15'd2048;
            else if (masked[12]) grant_c = 15'd4096;
            else if (masked[13]) grant_c = 15'd8192;
            else if (masked[14]) grant_c = 15'd16384;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 15'd1;
            else if (req[1]) grant_c = 15'd2;
            else if (req[2]) grant_c = 15'd4;
            else if (req[3]) grant_c = 15'd8;
            else if (req[4]) grant_c = 15'd16;
            else if (req[5]) grant_c = 15'd32;
            else if (req[6]) grant_c = 15'd64;
            else if (req[7]) grant_c = 15'd128;
            else if (req[8]) grant_c = 15'd256;
            else if (req[9]) grant_c = 15'd512;
            else if (req[10]) grant_c = 15'd1024;
            else if (req[11]) grant_c = 15'd2048;
            else if (req[12]) grant_c = 15'd4096;
            else if (req[13]) grant_c = 15'd8192;
            else if (req[14]) grant_c = 15'd16384;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_15

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 15'b111111111111110;
                else if (grant[1]) mask <= 15'b111111111111100;
                else if (grant[2]) mask <= 15'b111111111111000;
                else if (grant[3]) mask <= 15'b111111111110000;
                else if (grant[4]) mask <= 15'b111111111100000;
                else if (grant[5]) mask <= 15'b111111111000000;
                else if (grant[6]) mask <= 15'b111111110000000;
                else if (grant[7]) mask <= 15'b111111100000000;
                else if (grant[8]) mask <= 15'b111111000000000;
                else if (grant[9]) mask <= 15'b111110000000000;
                else if (grant[10]) mask <= 15'b111100000000000;
                else if (grant[11]) mask <= 15'b111000000000000;
                else if (grant[12]) mask <= 15'b110000000000000;
                else if (grant[13]) mask <= 15'b100000000000000;
                else if (grant[14]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==16) begin : GRANT_16

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 16'd1;
            else if (masked[1]) grant_c = 16'd2;
            else if (masked[2]) grant_c = 16'd4;
            else if (masked[3]) grant_c = 16'd8;
            else if (masked[4]) grant_c = 16'd16;
            else if (masked[5]) grant_c = 16'd32;
            else if (masked[6]) grant_c = 16'd64;
            else if (masked[7]) grant_c = 16'd128;
            else if (masked[8]) grant_c = 16'd256;
            else if (masked[9]) grant_c = 16'd512;
            else if (masked[10]) grant_c = 16'd1024;
            else if (masked[11]) grant_c = 16'd2048;
            else if (masked[12]) grant_c = 16'd4096;
            else if (masked[13]) grant_c = 16'd8192;
            else if (masked[14]) grant_c = 16'd16384;
            else if (masked[15]) grant_c = 16'd32768;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 16'd1;
            else if (req[1]) grant_c = 16'd2;
            else if (req[2]) grant_c = 16'd4;
            else if (req[3]) grant_c = 16'd8;
            else if (req[4]) grant_c = 16'd16;
            else if (req[5]) grant_c = 16'd32;
            else if (req[6]) grant_c = 16'd64;
            else if (req[7]) grant_c = 16'd128;
            else if (req[8]) grant_c = 16'd256;
            else if (req[9]) grant_c = 16'd512;
            else if (req[10]) grant_c = 16'd1024;
            else if (req[11]) grant_c = 16'd2048;
            else if (req[12]) grant_c = 16'd4096;
            else if (req[13]) grant_c = 16'd8192;
            else if (req[14]) grant_c = 16'd16384;
            else if (req[15]) grant_c = 16'd32768;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_16

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 16'b1111111111111110;
                else if (grant[1]) mask <= 16'b1111111111111100;
                else if (grant[2]) mask <= 16'b1111111111111000;
                else if (grant[3]) mask <= 16'b1111111111110000;
                else if (grant[4]) mask <= 16'b1111111111100000;
                else if (grant[5]) mask <= 16'b1111111111000000;
                else if (grant[6]) mask <= 16'b1111111110000000;
                else if (grant[7]) mask <= 16'b1111111100000000;
                else if (grant[8]) mask <= 16'b1111111000000000;
                else if (grant[9]) mask <= 16'b1111110000000000;
                else if (grant[10]) mask <= 16'b1111100000000000;
                else if (grant[11]) mask <= 16'b1111000000000000;
                else if (grant[12]) mask <= 16'b1110000000000000;
                else if (grant[13]) mask <= 16'b1100000000000000;
                else if (grant[14]) mask <= 16'b1000000000000000;
                else if (grant[15]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==17) begin : GRANT_17

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 17'd1;
            else if (masked[1]) grant_c = 17'd2;
            else if (masked[2]) grant_c = 17'd4;
            else if (masked[3]) grant_c = 17'd8;
            else if (masked[4]) grant_c = 17'd16;
            else if (masked[5]) grant_c = 17'd32;
            else if (masked[6]) grant_c = 17'd64;
            else if (masked[7]) grant_c = 17'd128;
            else if (masked[8]) grant_c = 17'd256;
            else if (masked[9]) grant_c = 17'd512;
            else if (masked[10]) grant_c = 17'd1024;
            else if (masked[11]) grant_c = 17'd2048;
            else if (masked[12]) grant_c = 17'd4096;
            else if (masked[13]) grant_c = 17'd8192;
            else if (masked[14]) grant_c = 17'd16384;
            else if (masked[15]) grant_c = 17'd32768;
            else if (masked[16]) grant_c = 17'd65536;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 17'd1;
            else if (req[1]) grant_c = 17'd2;
            else if (req[2]) grant_c = 17'd4;
            else if (req[3]) grant_c = 17'd8;
            else if (req[4]) grant_c = 17'd16;
            else if (req[5]) grant_c = 17'd32;
            else if (req[6]) grant_c = 17'd64;
            else if (req[7]) grant_c = 17'd128;
            else if (req[8]) grant_c = 17'd256;
            else if (req[9]) grant_c = 17'd512;
            else if (req[10]) grant_c = 17'd1024;
            else if (req[11]) grant_c = 17'd2048;
            else if (req[12]) grant_c = 17'd4096;
            else if (req[13]) grant_c = 17'd8192;
            else if (req[14]) grant_c = 17'd16384;
            else if (req[15]) grant_c = 17'd32768;
            else if (req[16]) grant_c = 17'd65536;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_17

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 17'b11111111111111110;
                else if (grant[1]) mask <= 17'b11111111111111100;
                else if (grant[2]) mask <= 17'b11111111111111000;
                else if (grant[3]) mask <= 17'b11111111111110000;
                else if (grant[4]) mask <= 17'b11111111111100000;
                else if (grant[5]) mask <= 17'b11111111111000000;
                else if (grant[6]) mask <= 17'b11111111110000000;
                else if (grant[7]) mask <= 17'b11111111100000000;
                else if (grant[8]) mask <= 17'b11111111000000000;
                else if (grant[9]) mask <= 17'b11111110000000000;
                else if (grant[10]) mask <= 17'b11111100000000000;
                else if (grant[11]) mask <= 17'b11111000000000000;
                else if (grant[12]) mask <= 17'b11110000000000000;
                else if (grant[13]) mask <= 17'b11100000000000000;
                else if (grant[14]) mask <= 17'b11000000000000000;
                else if (grant[15]) mask <= 17'b10000000000000000;
                else if (grant[16]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==18) begin : GRANT_18

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 18'd1;
            else if (masked[1]) grant_c = 18'd2;
            else if (masked[2]) grant_c = 18'd4;
            else if (masked[3]) grant_c = 18'd8;
            else if (masked[4]) grant_c = 18'd16;
            else if (masked[5]) grant_c = 18'd32;
            else if (masked[6]) grant_c = 18'd64;
            else if (masked[7]) grant_c = 18'd128;
            else if (masked[8]) grant_c = 18'd256;
            else if (masked[9]) grant_c = 18'd512;
            else if (masked[10]) grant_c = 18'd1024;
            else if (masked[11]) grant_c = 18'd2048;
            else if (masked[12]) grant_c = 18'd4096;
            else if (masked[13]) grant_c = 18'd8192;
            else if (masked[14]) grant_c = 18'd16384;
            else if (masked[15]) grant_c = 18'd32768;
            else if (masked[16]) grant_c = 18'd65536;
            else if (masked[17]) grant_c = 18'd131072;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 18'd1;
            else if (req[1]) grant_c = 18'd2;
            else if (req[2]) grant_c = 18'd4;
            else if (req[3]) grant_c = 18'd8;
            else if (req[4]) grant_c = 18'd16;
            else if (req[5]) grant_c = 18'd32;
            else if (req[6]) grant_c = 18'd64;
            else if (req[7]) grant_c = 18'd128;
            else if (req[8]) grant_c = 18'd256;
            else if (req[9]) grant_c = 18'd512;
            else if (req[10]) grant_c = 18'd1024;
            else if (req[11]) grant_c = 18'd2048;
            else if (req[12]) grant_c = 18'd4096;
            else if (req[13]) grant_c = 18'd8192;
            else if (req[14]) grant_c = 18'd16384;
            else if (req[15]) grant_c = 18'd32768;
            else if (req[16]) grant_c = 18'd65536;
            else if (req[17]) grant_c = 18'd131072;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_18

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 18'b111111111111111110;
                else if (grant[1]) mask <= 18'b111111111111111100;
                else if (grant[2]) mask <= 18'b111111111111111000;
                else if (grant[3]) mask <= 18'b111111111111110000;
                else if (grant[4]) mask <= 18'b111111111111100000;
                else if (grant[5]) mask <= 18'b111111111111000000;
                else if (grant[6]) mask <= 18'b111111111110000000;
                else if (grant[7]) mask <= 18'b111111111100000000;
                else if (grant[8]) mask <= 18'b111111111000000000;
                else if (grant[9]) mask <= 18'b111111110000000000;
                else if (grant[10]) mask <= 18'b111111100000000000;
                else if (grant[11]) mask <= 18'b111111000000000000;
                else if (grant[12]) mask <= 18'b111110000000000000;
                else if (grant[13]) mask <= 18'b111100000000000000;
                else if (grant[14]) mask <= 18'b111000000000000000;
                else if (grant[15]) mask <= 18'b110000000000000000;
                else if (grant[16]) mask <= 18'b100000000000000000;
                else if (grant[17]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==19) begin : GRANT_19

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 19'd1;
            else if (masked[1]) grant_c = 19'd2;
            else if (masked[2]) grant_c = 19'd4;
            else if (masked[3]) grant_c = 19'd8;
            else if (masked[4]) grant_c = 19'd16;
            else if (masked[5]) grant_c = 19'd32;
            else if (masked[6]) grant_c = 19'd64;
            else if (masked[7]) grant_c = 19'd128;
            else if (masked[8]) grant_c = 19'd256;
            else if (masked[9]) grant_c = 19'd512;
            else if (masked[10]) grant_c = 19'd1024;
            else if (masked[11]) grant_c = 19'd2048;
            else if (masked[12]) grant_c = 19'd4096;
            else if (masked[13]) grant_c = 19'd8192;
            else if (masked[14]) grant_c = 19'd16384;
            else if (masked[15]) grant_c = 19'd32768;
            else if (masked[16]) grant_c = 19'd65536;
            else if (masked[17]) grant_c = 19'd131072;
            else if (masked[18]) grant_c = 19'd262144;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 19'd1;
            else if (req[1]) grant_c = 19'd2;
            else if (req[2]) grant_c = 19'd4;
            else if (req[3]) grant_c = 19'd8;
            else if (req[4]) grant_c = 19'd16;
            else if (req[5]) grant_c = 19'd32;
            else if (req[6]) grant_c = 19'd64;
            else if (req[7]) grant_c = 19'd128;
            else if (req[8]) grant_c = 19'd256;
            else if (req[9]) grant_c = 19'd512;
            else if (req[10]) grant_c = 19'd1024;
            else if (req[11]) grant_c = 19'd2048;
            else if (req[12]) grant_c = 19'd4096;
            else if (req[13]) grant_c = 19'd8192;
            else if (req[14]) grant_c = 19'd16384;
            else if (req[15]) grant_c = 19'd32768;
            else if (req[16]) grant_c = 19'd65536;
            else if (req[17]) grant_c = 19'd131072;
            else if (req[18]) grant_c = 19'd262144;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_19

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 19'b1111111111111111110;
                else if (grant[1]) mask <= 19'b1111111111111111100;
                else if (grant[2]) mask <= 19'b1111111111111111000;
                else if (grant[3]) mask <= 19'b1111111111111110000;
                else if (grant[4]) mask <= 19'b1111111111111100000;
                else if (grant[5]) mask <= 19'b1111111111111000000;
                else if (grant[6]) mask <= 19'b1111111111110000000;
                else if (grant[7]) mask <= 19'b1111111111100000000;
                else if (grant[8]) mask <= 19'b1111111111000000000;
                else if (grant[9]) mask <= 19'b1111111110000000000;
                else if (grant[10]) mask <= 19'b1111111100000000000;
                else if (grant[11]) mask <= 19'b1111111000000000000;
                else if (grant[12]) mask <= 19'b1111110000000000000;
                else if (grant[13]) mask <= 19'b1111100000000000000;
                else if (grant[14]) mask <= 19'b1111000000000000000;
                else if (grant[15]) mask <= 19'b1110000000000000000;
                else if (grant[16]) mask <= 19'b1100000000000000000;
                else if (grant[17]) mask <= 19'b1000000000000000000;
                else if (grant[18]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==20) begin : GRANT_20

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 20'd1;
            else if (masked[1]) grant_c = 20'd2;
            else if (masked[2]) grant_c = 20'd4;
            else if (masked[3]) grant_c = 20'd8;
            else if (masked[4]) grant_c = 20'd16;
            else if (masked[5]) grant_c = 20'd32;
            else if (masked[6]) grant_c = 20'd64;
            else if (masked[7]) grant_c = 20'd128;
            else if (masked[8]) grant_c = 20'd256;
            else if (masked[9]) grant_c = 20'd512;
            else if (masked[10]) grant_c = 20'd1024;
            else if (masked[11]) grant_c = 20'd2048;
            else if (masked[12]) grant_c = 20'd4096;
            else if (masked[13]) grant_c = 20'd8192;
            else if (masked[14]) grant_c = 20'd16384;
            else if (masked[15]) grant_c = 20'd32768;
            else if (masked[16]) grant_c = 20'd65536;
            else if (masked[17]) grant_c = 20'd131072;
            else if (masked[18]) grant_c = 20'd262144;
            else if (masked[19]) grant_c = 20'd524288;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 20'd1;
            else if (req[1]) grant_c = 20'd2;
            else if (req[2]) grant_c = 20'd4;
            else if (req[3]) grant_c = 20'd8;
            else if (req[4]) grant_c = 20'd16;
            else if (req[5]) grant_c = 20'd32;
            else if (req[6]) grant_c = 20'd64;
            else if (req[7]) grant_c = 20'd128;
            else if (req[8]) grant_c = 20'd256;
            else if (req[9]) grant_c = 20'd512;
            else if (req[10]) grant_c = 20'd1024;
            else if (req[11]) grant_c = 20'd2048;
            else if (req[12]) grant_c = 20'd4096;
            else if (req[13]) grant_c = 20'd8192;
            else if (req[14]) grant_c = 20'd16384;
            else if (req[15]) grant_c = 20'd32768;
            else if (req[16]) grant_c = 20'd65536;
            else if (req[17]) grant_c = 20'd131072;
            else if (req[18]) grant_c = 20'd262144;
            else if (req[19]) grant_c = 20'd524288;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_20

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 20'b11111111111111111110;
                else if (grant[1]) mask <= 20'b11111111111111111100;
                else if (grant[2]) mask <= 20'b11111111111111111000;
                else if (grant[3]) mask <= 20'b11111111111111110000;
                else if (grant[4]) mask <= 20'b11111111111111100000;
                else if (grant[5]) mask <= 20'b11111111111111000000;
                else if (grant[6]) mask <= 20'b11111111111110000000;
                else if (grant[7]) mask <= 20'b11111111111100000000;
                else if (grant[8]) mask <= 20'b11111111111000000000;
                else if (grant[9]) mask <= 20'b11111111110000000000;
                else if (grant[10]) mask <= 20'b11111111100000000000;
                else if (grant[11]) mask <= 20'b11111111000000000000;
                else if (grant[12]) mask <= 20'b11111110000000000000;
                else if (grant[13]) mask <= 20'b11111100000000000000;
                else if (grant[14]) mask <= 20'b11111000000000000000;
                else if (grant[15]) mask <= 20'b11110000000000000000;
                else if (grant[16]) mask <= 20'b11100000000000000000;
                else if (grant[17]) mask <= 20'b11000000000000000000;
                else if (grant[18]) mask <= 20'b10000000000000000000;
                else if (grant[19]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==21) begin : GRANT_21

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 21'd1;
            else if (masked[1]) grant_c = 21'd2;
            else if (masked[2]) grant_c = 21'd4;
            else if (masked[3]) grant_c = 21'd8;
            else if (masked[4]) grant_c = 21'd16;
            else if (masked[5]) grant_c = 21'd32;
            else if (masked[6]) grant_c = 21'd64;
            else if (masked[7]) grant_c = 21'd128;
            else if (masked[8]) grant_c = 21'd256;
            else if (masked[9]) grant_c = 21'd512;
            else if (masked[10]) grant_c = 21'd1024;
            else if (masked[11]) grant_c = 21'd2048;
            else if (masked[12]) grant_c = 21'd4096;
            else if (masked[13]) grant_c = 21'd8192;
            else if (masked[14]) grant_c = 21'd16384;
            else if (masked[15]) grant_c = 21'd32768;
            else if (masked[16]) grant_c = 21'd65536;
            else if (masked[17]) grant_c = 21'd131072;
            else if (masked[18]) grant_c = 21'd262144;
            else if (masked[19]) grant_c = 21'd524288;
            else if (masked[20]) grant_c = 21'd1048576;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 21'd1;
            else if (req[1]) grant_c = 21'd2;
            else if (req[2]) grant_c = 21'd4;
            else if (req[3]) grant_c = 21'd8;
            else if (req[4]) grant_c = 21'd16;
            else if (req[5]) grant_c = 21'd32;
            else if (req[6]) grant_c = 21'd64;
            else if (req[7]) grant_c = 21'd128;
            else if (req[8]) grant_c = 21'd256;
            else if (req[9]) grant_c = 21'd512;
            else if (req[10]) grant_c = 21'd1024;
            else if (req[11]) grant_c = 21'd2048;
            else if (req[12]) grant_c = 21'd4096;
            else if (req[13]) grant_c = 21'd8192;
            else if (req[14]) grant_c = 21'd16384;
            else if (req[15]) grant_c = 21'd32768;
            else if (req[16]) grant_c = 21'd65536;
            else if (req[17]) grant_c = 21'd131072;
            else if (req[18]) grant_c = 21'd262144;
            else if (req[19]) grant_c = 21'd524288;
            else if (req[20]) grant_c = 21'd1048576;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_21

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 21'b111111111111111111110;
                else if (grant[1]) mask <= 21'b111111111111111111100;
                else if (grant[2]) mask <= 21'b111111111111111111000;
                else if (grant[3]) mask <= 21'b111111111111111110000;
                else if (grant[4]) mask <= 21'b111111111111111100000;
                else if (grant[5]) mask <= 21'b111111111111111000000;
                else if (grant[6]) mask <= 21'b111111111111110000000;
                else if (grant[7]) mask <= 21'b111111111111100000000;
                else if (grant[8]) mask <= 21'b111111111111000000000;
                else if (grant[9]) mask <= 21'b111111111110000000000;
                else if (grant[10]) mask <= 21'b111111111100000000000;
                else if (grant[11]) mask <= 21'b111111111000000000000;
                else if (grant[12]) mask <= 21'b111111110000000000000;
                else if (grant[13]) mask <= 21'b111111100000000000000;
                else if (grant[14]) mask <= 21'b111111000000000000000;
                else if (grant[15]) mask <= 21'b111110000000000000000;
                else if (grant[16]) mask <= 21'b111100000000000000000;
                else if (grant[17]) mask <= 21'b111000000000000000000;
                else if (grant[18]) mask <= 21'b110000000000000000000;
                else if (grant[19]) mask <= 21'b100000000000000000000;
                else if (grant[20]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==22) begin : GRANT_22

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 22'd1;
            else if (masked[1]) grant_c = 22'd2;
            else if (masked[2]) grant_c = 22'd4;
            else if (masked[3]) grant_c = 22'd8;
            else if (masked[4]) grant_c = 22'd16;
            else if (masked[5]) grant_c = 22'd32;
            else if (masked[6]) grant_c = 22'd64;
            else if (masked[7]) grant_c = 22'd128;
            else if (masked[8]) grant_c = 22'd256;
            else if (masked[9]) grant_c = 22'd512;
            else if (masked[10]) grant_c = 22'd1024;
            else if (masked[11]) grant_c = 22'd2048;
            else if (masked[12]) grant_c = 22'd4096;
            else if (masked[13]) grant_c = 22'd8192;
            else if (masked[14]) grant_c = 22'd16384;
            else if (masked[15]) grant_c = 22'd32768;
            else if (masked[16]) grant_c = 22'd65536;
            else if (masked[17]) grant_c = 22'd131072;
            else if (masked[18]) grant_c = 22'd262144;
            else if (masked[19]) grant_c = 22'd524288;
            else if (masked[20]) grant_c = 22'd1048576;
            else if (masked[21]) grant_c = 22'd2097152;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 22'd1;
            else if (req[1]) grant_c = 22'd2;
            else if (req[2]) grant_c = 22'd4;
            else if (req[3]) grant_c = 22'd8;
            else if (req[4]) grant_c = 22'd16;
            else if (req[5]) grant_c = 22'd32;
            else if (req[6]) grant_c = 22'd64;
            else if (req[7]) grant_c = 22'd128;
            else if (req[8]) grant_c = 22'd256;
            else if (req[9]) grant_c = 22'd512;
            else if (req[10]) grant_c = 22'd1024;
            else if (req[11]) grant_c = 22'd2048;
            else if (req[12]) grant_c = 22'd4096;
            else if (req[13]) grant_c = 22'd8192;
            else if (req[14]) grant_c = 22'd16384;
            else if (req[15]) grant_c = 22'd32768;
            else if (req[16]) grant_c = 22'd65536;
            else if (req[17]) grant_c = 22'd131072;
            else if (req[18]) grant_c = 22'd262144;
            else if (req[19]) grant_c = 22'd524288;
            else if (req[20]) grant_c = 22'd1048576;
            else if (req[21]) grant_c = 22'd2097152;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_22

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 22'b1111111111111111111110;
                else if (grant[1]) mask <= 22'b1111111111111111111100;
                else if (grant[2]) mask <= 22'b1111111111111111111000;
                else if (grant[3]) mask <= 22'b1111111111111111110000;
                else if (grant[4]) mask <= 22'b1111111111111111100000;
                else if (grant[5]) mask <= 22'b1111111111111111000000;
                else if (grant[6]) mask <= 22'b1111111111111110000000;
                else if (grant[7]) mask <= 22'b1111111111111100000000;
                else if (grant[8]) mask <= 22'b1111111111111000000000;
                else if (grant[9]) mask <= 22'b1111111111110000000000;
                else if (grant[10]) mask <= 22'b1111111111100000000000;
                else if (grant[11]) mask <= 22'b1111111111000000000000;
                else if (grant[12]) mask <= 22'b1111111110000000000000;
                else if (grant[13]) mask <= 22'b1111111100000000000000;
                else if (grant[14]) mask <= 22'b1111111000000000000000;
                else if (grant[15]) mask <= 22'b1111110000000000000000;
                else if (grant[16]) mask <= 22'b1111100000000000000000;
                else if (grant[17]) mask <= 22'b1111000000000000000000;
                else if (grant[18]) mask <= 22'b1110000000000000000000;
                else if (grant[19]) mask <= 22'b1100000000000000000000;
                else if (grant[20]) mask <= 22'b1000000000000000000000;
                else if (grant[21]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==23) begin : GRANT_23

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 23'd1;
            else if (masked[1]) grant_c = 23'd2;
            else if (masked[2]) grant_c = 23'd4;
            else if (masked[3]) grant_c = 23'd8;
            else if (masked[4]) grant_c = 23'd16;
            else if (masked[5]) grant_c = 23'd32;
            else if (masked[6]) grant_c = 23'd64;
            else if (masked[7]) grant_c = 23'd128;
            else if (masked[8]) grant_c = 23'd256;
            else if (masked[9]) grant_c = 23'd512;
            else if (masked[10]) grant_c = 23'd1024;
            else if (masked[11]) grant_c = 23'd2048;
            else if (masked[12]) grant_c = 23'd4096;
            else if (masked[13]) grant_c = 23'd8192;
            else if (masked[14]) grant_c = 23'd16384;
            else if (masked[15]) grant_c = 23'd32768;
            else if (masked[16]) grant_c = 23'd65536;
            else if (masked[17]) grant_c = 23'd131072;
            else if (masked[18]) grant_c = 23'd262144;
            else if (masked[19]) grant_c = 23'd524288;
            else if (masked[20]) grant_c = 23'd1048576;
            else if (masked[21]) grant_c = 23'd2097152;
            else if (masked[22]) grant_c = 23'd4194304;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 23'd1;
            else if (req[1]) grant_c = 23'd2;
            else if (req[2]) grant_c = 23'd4;
            else if (req[3]) grant_c = 23'd8;
            else if (req[4]) grant_c = 23'd16;
            else if (req[5]) grant_c = 23'd32;
            else if (req[6]) grant_c = 23'd64;
            else if (req[7]) grant_c = 23'd128;
            else if (req[8]) grant_c = 23'd256;
            else if (req[9]) grant_c = 23'd512;
            else if (req[10]) grant_c = 23'd1024;
            else if (req[11]) grant_c = 23'd2048;
            else if (req[12]) grant_c = 23'd4096;
            else if (req[13]) grant_c = 23'd8192;
            else if (req[14]) grant_c = 23'd16384;
            else if (req[15]) grant_c = 23'd32768;
            else if (req[16]) grant_c = 23'd65536;
            else if (req[17]) grant_c = 23'd131072;
            else if (req[18]) grant_c = 23'd262144;
            else if (req[19]) grant_c = 23'd524288;
            else if (req[20]) grant_c = 23'd1048576;
            else if (req[21]) grant_c = 23'd2097152;
            else if (req[22]) grant_c = 23'd4194304;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_23

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 23'b11111111111111111111110;
                else if (grant[1]) mask <= 23'b11111111111111111111100;
                else if (grant[2]) mask <= 23'b11111111111111111111000;
                else if (grant[3]) mask <= 23'b11111111111111111110000;
                else if (grant[4]) mask <= 23'b11111111111111111100000;
                else if (grant[5]) mask <= 23'b11111111111111111000000;
                else if (grant[6]) mask <= 23'b11111111111111110000000;
                else if (grant[7]) mask <= 23'b11111111111111100000000;
                else if (grant[8]) mask <= 23'b11111111111111000000000;
                else if (grant[9]) mask <= 23'b11111111111110000000000;
                else if (grant[10]) mask <= 23'b11111111111100000000000;
                else if (grant[11]) mask <= 23'b11111111111000000000000;
                else if (grant[12]) mask <= 23'b11111111110000000000000;
                else if (grant[13]) mask <= 23'b11111111100000000000000;
                else if (grant[14]) mask <= 23'b11111111000000000000000;
                else if (grant[15]) mask <= 23'b11111110000000000000000;
                else if (grant[16]) mask <= 23'b11111100000000000000000;
                else if (grant[17]) mask <= 23'b11111000000000000000000;
                else if (grant[18]) mask <= 23'b11110000000000000000000;
                else if (grant[19]) mask <= 23'b11100000000000000000000;
                else if (grant[20]) mask <= 23'b11000000000000000000000;
                else if (grant[21]) mask <= 23'b10000000000000000000000;
                else if (grant[22]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==24) begin : GRANT_24

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 24'd1;
            else if (masked[1]) grant_c = 24'd2;
            else if (masked[2]) grant_c = 24'd4;
            else if (masked[3]) grant_c = 24'd8;
            else if (masked[4]) grant_c = 24'd16;
            else if (masked[5]) grant_c = 24'd32;
            else if (masked[6]) grant_c = 24'd64;
            else if (masked[7]) grant_c = 24'd128;
            else if (masked[8]) grant_c = 24'd256;
            else if (masked[9]) grant_c = 24'd512;
            else if (masked[10]) grant_c = 24'd1024;
            else if (masked[11]) grant_c = 24'd2048;
            else if (masked[12]) grant_c = 24'd4096;
            else if (masked[13]) grant_c = 24'd8192;
            else if (masked[14]) grant_c = 24'd16384;
            else if (masked[15]) grant_c = 24'd32768;
            else if (masked[16]) grant_c = 24'd65536;
            else if (masked[17]) grant_c = 24'd131072;
            else if (masked[18]) grant_c = 24'd262144;
            else if (masked[19]) grant_c = 24'd524288;
            else if (masked[20]) grant_c = 24'd1048576;
            else if (masked[21]) grant_c = 24'd2097152;
            else if (masked[22]) grant_c = 24'd4194304;
            else if (masked[23]) grant_c = 24'd8388608;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 24'd1;
            else if (req[1]) grant_c = 24'd2;
            else if (req[2]) grant_c = 24'd4;
            else if (req[3]) grant_c = 24'd8;
            else if (req[4]) grant_c = 24'd16;
            else if (req[5]) grant_c = 24'd32;
            else if (req[6]) grant_c = 24'd64;
            else if (req[7]) grant_c = 24'd128;
            else if (req[8]) grant_c = 24'd256;
            else if (req[9]) grant_c = 24'd512;
            else if (req[10]) grant_c = 24'd1024;
            else if (req[11]) grant_c = 24'd2048;
            else if (req[12]) grant_c = 24'd4096;
            else if (req[13]) grant_c = 24'd8192;
            else if (req[14]) grant_c = 24'd16384;
            else if (req[15]) grant_c = 24'd32768;
            else if (req[16]) grant_c = 24'd65536;
            else if (req[17]) grant_c = 24'd131072;
            else if (req[18]) grant_c = 24'd262144;
            else if (req[19]) grant_c = 24'd524288;
            else if (req[20]) grant_c = 24'd1048576;
            else if (req[21]) grant_c = 24'd2097152;
            else if (req[22]) grant_c = 24'd4194304;
            else if (req[23]) grant_c = 24'd8388608;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_24

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 24'b111111111111111111111110;
                else if (grant[1]) mask <= 24'b111111111111111111111100;
                else if (grant[2]) mask <= 24'b111111111111111111111000;
                else if (grant[3]) mask <= 24'b111111111111111111110000;
                else if (grant[4]) mask <= 24'b111111111111111111100000;
                else if (grant[5]) mask <= 24'b111111111111111111000000;
                else if (grant[6]) mask <= 24'b111111111111111110000000;
                else if (grant[7]) mask <= 24'b111111111111111100000000;
                else if (grant[8]) mask <= 24'b111111111111111000000000;
                else if (grant[9]) mask <= 24'b111111111111110000000000;
                else if (grant[10]) mask <= 24'b111111111111100000000000;
                else if (grant[11]) mask <= 24'b111111111111000000000000;
                else if (grant[12]) mask <= 24'b111111111110000000000000;
                else if (grant[13]) mask <= 24'b111111111100000000000000;
                else if (grant[14]) mask <= 24'b111111111000000000000000;
                else if (grant[15]) mask <= 24'b111111110000000000000000;
                else if (grant[16]) mask <= 24'b111111100000000000000000;
                else if (grant[17]) mask <= 24'b111111000000000000000000;
                else if (grant[18]) mask <= 24'b111110000000000000000000;
                else if (grant[19]) mask <= 24'b111100000000000000000000;
                else if (grant[20]) mask <= 24'b111000000000000000000000;
                else if (grant[21]) mask <= 24'b110000000000000000000000;
                else if (grant[22]) mask <= 24'b100000000000000000000000;
                else if (grant[23]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==25) begin : GRANT_25

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 25'd1;
            else if (masked[1]) grant_c = 25'd2;
            else if (masked[2]) grant_c = 25'd4;
            else if (masked[3]) grant_c = 25'd8;
            else if (masked[4]) grant_c = 25'd16;
            else if (masked[5]) grant_c = 25'd32;
            else if (masked[6]) grant_c = 25'd64;
            else if (masked[7]) grant_c = 25'd128;
            else if (masked[8]) grant_c = 25'd256;
            else if (masked[9]) grant_c = 25'd512;
            else if (masked[10]) grant_c = 25'd1024;
            else if (masked[11]) grant_c = 25'd2048;
            else if (masked[12]) grant_c = 25'd4096;
            else if (masked[13]) grant_c = 25'd8192;
            else if (masked[14]) grant_c = 25'd16384;
            else if (masked[15]) grant_c = 25'd32768;
            else if (masked[16]) grant_c = 25'd65536;
            else if (masked[17]) grant_c = 25'd131072;
            else if (masked[18]) grant_c = 25'd262144;
            else if (masked[19]) grant_c = 25'd524288;
            else if (masked[20]) grant_c = 25'd1048576;
            else if (masked[21]) grant_c = 25'd2097152;
            else if (masked[22]) grant_c = 25'd4194304;
            else if (masked[23]) grant_c = 25'd8388608;
            else if (masked[24]) grant_c = 25'd16777216;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 25'd1;
            else if (req[1]) grant_c = 25'd2;
            else if (req[2]) grant_c = 25'd4;
            else if (req[3]) grant_c = 25'd8;
            else if (req[4]) grant_c = 25'd16;
            else if (req[5]) grant_c = 25'd32;
            else if (req[6]) grant_c = 25'd64;
            else if (req[7]) grant_c = 25'd128;
            else if (req[8]) grant_c = 25'd256;
            else if (req[9]) grant_c = 25'd512;
            else if (req[10]) grant_c = 25'd1024;
            else if (req[11]) grant_c = 25'd2048;
            else if (req[12]) grant_c = 25'd4096;
            else if (req[13]) grant_c = 25'd8192;
            else if (req[14]) grant_c = 25'd16384;
            else if (req[15]) grant_c = 25'd32768;
            else if (req[16]) grant_c = 25'd65536;
            else if (req[17]) grant_c = 25'd131072;
            else if (req[18]) grant_c = 25'd262144;
            else if (req[19]) grant_c = 25'd524288;
            else if (req[20]) grant_c = 25'd1048576;
            else if (req[21]) grant_c = 25'd2097152;
            else if (req[22]) grant_c = 25'd4194304;
            else if (req[23]) grant_c = 25'd8388608;
            else if (req[24]) grant_c = 25'd16777216;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_25

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 25'b1111111111111111111111110;
                else if (grant[1]) mask <= 25'b1111111111111111111111100;
                else if (grant[2]) mask <= 25'b1111111111111111111111000;
                else if (grant[3]) mask <= 25'b1111111111111111111110000;
                else if (grant[4]) mask <= 25'b1111111111111111111100000;
                else if (grant[5]) mask <= 25'b1111111111111111111000000;
                else if (grant[6]) mask <= 25'b1111111111111111110000000;
                else if (grant[7]) mask <= 25'b1111111111111111100000000;
                else if (grant[8]) mask <= 25'b1111111111111111000000000;
                else if (grant[9]) mask <= 25'b1111111111111110000000000;
                else if (grant[10]) mask <= 25'b1111111111111100000000000;
                else if (grant[11]) mask <= 25'b1111111111111000000000000;
                else if (grant[12]) mask <= 25'b1111111111110000000000000;
                else if (grant[13]) mask <= 25'b1111111111100000000000000;
                else if (grant[14]) mask <= 25'b1111111111000000000000000;
                else if (grant[15]) mask <= 25'b1111111110000000000000000;
                else if (grant[16]) mask <= 25'b1111111100000000000000000;
                else if (grant[17]) mask <= 25'b1111111000000000000000000;
                else if (grant[18]) mask <= 25'b1111110000000000000000000;
                else if (grant[19]) mask <= 25'b1111100000000000000000000;
                else if (grant[20]) mask <= 25'b1111000000000000000000000;
                else if (grant[21]) mask <= 25'b1110000000000000000000000;
                else if (grant[22]) mask <= 25'b1100000000000000000000000;
                else if (grant[23]) mask <= 25'b1000000000000000000000000;
                else if (grant[24]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==26) begin : GRANT_26

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 26'd1;
            else if (masked[1]) grant_c = 26'd2;
            else if (masked[2]) grant_c = 26'd4;
            else if (masked[3]) grant_c = 26'd8;
            else if (masked[4]) grant_c = 26'd16;
            else if (masked[5]) grant_c = 26'd32;
            else if (masked[6]) grant_c = 26'd64;
            else if (masked[7]) grant_c = 26'd128;
            else if (masked[8]) grant_c = 26'd256;
            else if (masked[9]) grant_c = 26'd512;
            else if (masked[10]) grant_c = 26'd1024;
            else if (masked[11]) grant_c = 26'd2048;
            else if (masked[12]) grant_c = 26'd4096;
            else if (masked[13]) grant_c = 26'd8192;
            else if (masked[14]) grant_c = 26'd16384;
            else if (masked[15]) grant_c = 26'd32768;
            else if (masked[16]) grant_c = 26'd65536;
            else if (masked[17]) grant_c = 26'd131072;
            else if (masked[18]) grant_c = 26'd262144;
            else if (masked[19]) grant_c = 26'd524288;
            else if (masked[20]) grant_c = 26'd1048576;
            else if (masked[21]) grant_c = 26'd2097152;
            else if (masked[22]) grant_c = 26'd4194304;
            else if (masked[23]) grant_c = 26'd8388608;
            else if (masked[24]) grant_c = 26'd16777216;
            else if (masked[25]) grant_c = 26'd33554432;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 26'd1;
            else if (req[1]) grant_c = 26'd2;
            else if (req[2]) grant_c = 26'd4;
            else if (req[3]) grant_c = 26'd8;
            else if (req[4]) grant_c = 26'd16;
            else if (req[5]) grant_c = 26'd32;
            else if (req[6]) grant_c = 26'd64;
            else if (req[7]) grant_c = 26'd128;
            else if (req[8]) grant_c = 26'd256;
            else if (req[9]) grant_c = 26'd512;
            else if (req[10]) grant_c = 26'd1024;
            else if (req[11]) grant_c = 26'd2048;
            else if (req[12]) grant_c = 26'd4096;
            else if (req[13]) grant_c = 26'd8192;
            else if (req[14]) grant_c = 26'd16384;
            else if (req[15]) grant_c = 26'd32768;
            else if (req[16]) grant_c = 26'd65536;
            else if (req[17]) grant_c = 26'd131072;
            else if (req[18]) grant_c = 26'd262144;
            else if (req[19]) grant_c = 26'd524288;
            else if (req[20]) grant_c = 26'd1048576;
            else if (req[21]) grant_c = 26'd2097152;
            else if (req[22]) grant_c = 26'd4194304;
            else if (req[23]) grant_c = 26'd8388608;
            else if (req[24]) grant_c = 26'd16777216;
            else if (req[25]) grant_c = 26'd33554432;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_26

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 26'b11111111111111111111111110;
                else if (grant[1]) mask <= 26'b11111111111111111111111100;
                else if (grant[2]) mask <= 26'b11111111111111111111111000;
                else if (grant[3]) mask <= 26'b11111111111111111111110000;
                else if (grant[4]) mask <= 26'b11111111111111111111100000;
                else if (grant[5]) mask <= 26'b11111111111111111111000000;
                else if (grant[6]) mask <= 26'b11111111111111111110000000;
                else if (grant[7]) mask <= 26'b11111111111111111100000000;
                else if (grant[8]) mask <= 26'b11111111111111111000000000;
                else if (grant[9]) mask <= 26'b11111111111111110000000000;
                else if (grant[10]) mask <= 26'b11111111111111100000000000;
                else if (grant[11]) mask <= 26'b11111111111111000000000000;
                else if (grant[12]) mask <= 26'b11111111111110000000000000;
                else if (grant[13]) mask <= 26'b11111111111100000000000000;
                else if (grant[14]) mask <= 26'b11111111111000000000000000;
                else if (grant[15]) mask <= 26'b11111111110000000000000000;
                else if (grant[16]) mask <= 26'b11111111100000000000000000;
                else if (grant[17]) mask <= 26'b11111111000000000000000000;
                else if (grant[18]) mask <= 26'b11111110000000000000000000;
                else if (grant[19]) mask <= 26'b11111100000000000000000000;
                else if (grant[20]) mask <= 26'b11111000000000000000000000;
                else if (grant[21]) mask <= 26'b11110000000000000000000000;
                else if (grant[22]) mask <= 26'b11100000000000000000000000;
                else if (grant[23]) mask <= 26'b11000000000000000000000000;
                else if (grant[24]) mask <= 26'b10000000000000000000000000;
                else if (grant[25]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==27) begin : GRANT_27

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 27'd1;
            else if (masked[1]) grant_c = 27'd2;
            else if (masked[2]) grant_c = 27'd4;
            else if (masked[3]) grant_c = 27'd8;
            else if (masked[4]) grant_c = 27'd16;
            else if (masked[5]) grant_c = 27'd32;
            else if (masked[6]) grant_c = 27'd64;
            else if (masked[7]) grant_c = 27'd128;
            else if (masked[8]) grant_c = 27'd256;
            else if (masked[9]) grant_c = 27'd512;
            else if (masked[10]) grant_c = 27'd1024;
            else if (masked[11]) grant_c = 27'd2048;
            else if (masked[12]) grant_c = 27'd4096;
            else if (masked[13]) grant_c = 27'd8192;
            else if (masked[14]) grant_c = 27'd16384;
            else if (masked[15]) grant_c = 27'd32768;
            else if (masked[16]) grant_c = 27'd65536;
            else if (masked[17]) grant_c = 27'd131072;
            else if (masked[18]) grant_c = 27'd262144;
            else if (masked[19]) grant_c = 27'd524288;
            else if (masked[20]) grant_c = 27'd1048576;
            else if (masked[21]) grant_c = 27'd2097152;
            else if (masked[22]) grant_c = 27'd4194304;
            else if (masked[23]) grant_c = 27'd8388608;
            else if (masked[24]) grant_c = 27'd16777216;
            else if (masked[25]) grant_c = 27'd33554432;
            else if (masked[26]) grant_c = 27'd67108864;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 27'd1;
            else if (req[1]) grant_c = 27'd2;
            else if (req[2]) grant_c = 27'd4;
            else if (req[3]) grant_c = 27'd8;
            else if (req[4]) grant_c = 27'd16;
            else if (req[5]) grant_c = 27'd32;
            else if (req[6]) grant_c = 27'd64;
            else if (req[7]) grant_c = 27'd128;
            else if (req[8]) grant_c = 27'd256;
            else if (req[9]) grant_c = 27'd512;
            else if (req[10]) grant_c = 27'd1024;
            else if (req[11]) grant_c = 27'd2048;
            else if (req[12]) grant_c = 27'd4096;
            else if (req[13]) grant_c = 27'd8192;
            else if (req[14]) grant_c = 27'd16384;
            else if (req[15]) grant_c = 27'd32768;
            else if (req[16]) grant_c = 27'd65536;
            else if (req[17]) grant_c = 27'd131072;
            else if (req[18]) grant_c = 27'd262144;
            else if (req[19]) grant_c = 27'd524288;
            else if (req[20]) grant_c = 27'd1048576;
            else if (req[21]) grant_c = 27'd2097152;
            else if (req[22]) grant_c = 27'd4194304;
            else if (req[23]) grant_c = 27'd8388608;
            else if (req[24]) grant_c = 27'd16777216;
            else if (req[25]) grant_c = 27'd33554432;
            else if (req[26]) grant_c = 27'd67108864;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_27

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 27'b111111111111111111111111110;
                else if (grant[1]) mask <= 27'b111111111111111111111111100;
                else if (grant[2]) mask <= 27'b111111111111111111111111000;
                else if (grant[3]) mask <= 27'b111111111111111111111110000;
                else if (grant[4]) mask <= 27'b111111111111111111111100000;
                else if (grant[5]) mask <= 27'b111111111111111111111000000;
                else if (grant[6]) mask <= 27'b111111111111111111110000000;
                else if (grant[7]) mask <= 27'b111111111111111111100000000;
                else if (grant[8]) mask <= 27'b111111111111111111000000000;
                else if (grant[9]) mask <= 27'b111111111111111110000000000;
                else if (grant[10]) mask <= 27'b111111111111111100000000000;
                else if (grant[11]) mask <= 27'b111111111111111000000000000;
                else if (grant[12]) mask <= 27'b111111111111110000000000000;
                else if (grant[13]) mask <= 27'b111111111111100000000000000;
                else if (grant[14]) mask <= 27'b111111111111000000000000000;
                else if (grant[15]) mask <= 27'b111111111110000000000000000;
                else if (grant[16]) mask <= 27'b111111111100000000000000000;
                else if (grant[17]) mask <= 27'b111111111000000000000000000;
                else if (grant[18]) mask <= 27'b111111110000000000000000000;
                else if (grant[19]) mask <= 27'b111111100000000000000000000;
                else if (grant[20]) mask <= 27'b111111000000000000000000000;
                else if (grant[21]) mask <= 27'b111110000000000000000000000;
                else if (grant[22]) mask <= 27'b111100000000000000000000000;
                else if (grant[23]) mask <= 27'b111000000000000000000000000;
                else if (grant[24]) mask <= 27'b110000000000000000000000000;
                else if (grant[25]) mask <= 27'b100000000000000000000000000;
                else if (grant[26]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==28) begin : GRANT_28

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 28'd1;
            else if (masked[1]) grant_c = 28'd2;
            else if (masked[2]) grant_c = 28'd4;
            else if (masked[3]) grant_c = 28'd8;
            else if (masked[4]) grant_c = 28'd16;
            else if (masked[5]) grant_c = 28'd32;
            else if (masked[6]) grant_c = 28'd64;
            else if (masked[7]) grant_c = 28'd128;
            else if (masked[8]) grant_c = 28'd256;
            else if (masked[9]) grant_c = 28'd512;
            else if (masked[10]) grant_c = 28'd1024;
            else if (masked[11]) grant_c = 28'd2048;
            else if (masked[12]) grant_c = 28'd4096;
            else if (masked[13]) grant_c = 28'd8192;
            else if (masked[14]) grant_c = 28'd16384;
            else if (masked[15]) grant_c = 28'd32768;
            else if (masked[16]) grant_c = 28'd65536;
            else if (masked[17]) grant_c = 28'd131072;
            else if (masked[18]) grant_c = 28'd262144;
            else if (masked[19]) grant_c = 28'd524288;
            else if (masked[20]) grant_c = 28'd1048576;
            else if (masked[21]) grant_c = 28'd2097152;
            else if (masked[22]) grant_c = 28'd4194304;
            else if (masked[23]) grant_c = 28'd8388608;
            else if (masked[24]) grant_c = 28'd16777216;
            else if (masked[25]) grant_c = 28'd33554432;
            else if (masked[26]) grant_c = 28'd67108864;
            else if (masked[27]) grant_c = 28'd134217728;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 28'd1;
            else if (req[1]) grant_c = 28'd2;
            else if (req[2]) grant_c = 28'd4;
            else if (req[3]) grant_c = 28'd8;
            else if (req[4]) grant_c = 28'd16;
            else if (req[5]) grant_c = 28'd32;
            else if (req[6]) grant_c = 28'd64;
            else if (req[7]) grant_c = 28'd128;
            else if (req[8]) grant_c = 28'd256;
            else if (req[9]) grant_c = 28'd512;
            else if (req[10]) grant_c = 28'd1024;
            else if (req[11]) grant_c = 28'd2048;
            else if (req[12]) grant_c = 28'd4096;
            else if (req[13]) grant_c = 28'd8192;
            else if (req[14]) grant_c = 28'd16384;
            else if (req[15]) grant_c = 28'd32768;
            else if (req[16]) grant_c = 28'd65536;
            else if (req[17]) grant_c = 28'd131072;
            else if (req[18]) grant_c = 28'd262144;
            else if (req[19]) grant_c = 28'd524288;
            else if (req[20]) grant_c = 28'd1048576;
            else if (req[21]) grant_c = 28'd2097152;
            else if (req[22]) grant_c = 28'd4194304;
            else if (req[23]) grant_c = 28'd8388608;
            else if (req[24]) grant_c = 28'd16777216;
            else if (req[25]) grant_c = 28'd33554432;
            else if (req[26]) grant_c = 28'd67108864;
            else if (req[27]) grant_c = 28'd134217728;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_28

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 28'b1111111111111111111111111110;
                else if (grant[1]) mask <= 28'b1111111111111111111111111100;
                else if (grant[2]) mask <= 28'b1111111111111111111111111000;
                else if (grant[3]) mask <= 28'b1111111111111111111111110000;
                else if (grant[4]) mask <= 28'b1111111111111111111111100000;
                else if (grant[5]) mask <= 28'b1111111111111111111111000000;
                else if (grant[6]) mask <= 28'b1111111111111111111110000000;
                else if (grant[7]) mask <= 28'b1111111111111111111100000000;
                else if (grant[8]) mask <= 28'b1111111111111111111000000000;
                else if (grant[9]) mask <= 28'b1111111111111111110000000000;
                else if (grant[10]) mask <= 28'b1111111111111111100000000000;
                else if (grant[11]) mask <= 28'b1111111111111111000000000000;
                else if (grant[12]) mask <= 28'b1111111111111110000000000000;
                else if (grant[13]) mask <= 28'b1111111111111100000000000000;
                else if (grant[14]) mask <= 28'b1111111111111000000000000000;
                else if (grant[15]) mask <= 28'b1111111111110000000000000000;
                else if (grant[16]) mask <= 28'b1111111111100000000000000000;
                else if (grant[17]) mask <= 28'b1111111111000000000000000000;
                else if (grant[18]) mask <= 28'b1111111110000000000000000000;
                else if (grant[19]) mask <= 28'b1111111100000000000000000000;
                else if (grant[20]) mask <= 28'b1111111000000000000000000000;
                else if (grant[21]) mask <= 28'b1111110000000000000000000000;
                else if (grant[22]) mask <= 28'b1111100000000000000000000000;
                else if (grant[23]) mask <= 28'b1111000000000000000000000000;
                else if (grant[24]) mask <= 28'b1110000000000000000000000000;
                else if (grant[25]) mask <= 28'b1100000000000000000000000000;
                else if (grant[26]) mask <= 28'b1000000000000000000000000000;
                else if (grant[27]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==29) begin : GRANT_29

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 29'd1;
            else if (masked[1]) grant_c = 29'd2;
            else if (masked[2]) grant_c = 29'd4;
            else if (masked[3]) grant_c = 29'd8;
            else if (masked[4]) grant_c = 29'd16;
            else if (masked[5]) grant_c = 29'd32;
            else if (masked[6]) grant_c = 29'd64;
            else if (masked[7]) grant_c = 29'd128;
            else if (masked[8]) grant_c = 29'd256;
            else if (masked[9]) grant_c = 29'd512;
            else if (masked[10]) grant_c = 29'd1024;
            else if (masked[11]) grant_c = 29'd2048;
            else if (masked[12]) grant_c = 29'd4096;
            else if (masked[13]) grant_c = 29'd8192;
            else if (masked[14]) grant_c = 29'd16384;
            else if (masked[15]) grant_c = 29'd32768;
            else if (masked[16]) grant_c = 29'd65536;
            else if (masked[17]) grant_c = 29'd131072;
            else if (masked[18]) grant_c = 29'd262144;
            else if (masked[19]) grant_c = 29'd524288;
            else if (masked[20]) grant_c = 29'd1048576;
            else if (masked[21]) grant_c = 29'd2097152;
            else if (masked[22]) grant_c = 29'd4194304;
            else if (masked[23]) grant_c = 29'd8388608;
            else if (masked[24]) grant_c = 29'd16777216;
            else if (masked[25]) grant_c = 29'd33554432;
            else if (masked[26]) grant_c = 29'd67108864;
            else if (masked[27]) grant_c = 29'd134217728;
            else if (masked[28]) grant_c = 29'd268435456;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 29'd1;
            else if (req[1]) grant_c = 29'd2;
            else if (req[2]) grant_c = 29'd4;
            else if (req[3]) grant_c = 29'd8;
            else if (req[4]) grant_c = 29'd16;
            else if (req[5]) grant_c = 29'd32;
            else if (req[6]) grant_c = 29'd64;
            else if (req[7]) grant_c = 29'd128;
            else if (req[8]) grant_c = 29'd256;
            else if (req[9]) grant_c = 29'd512;
            else if (req[10]) grant_c = 29'd1024;
            else if (req[11]) grant_c = 29'd2048;
            else if (req[12]) grant_c = 29'd4096;
            else if (req[13]) grant_c = 29'd8192;
            else if (req[14]) grant_c = 29'd16384;
            else if (req[15]) grant_c = 29'd32768;
            else if (req[16]) grant_c = 29'd65536;
            else if (req[17]) grant_c = 29'd131072;
            else if (req[18]) grant_c = 29'd262144;
            else if (req[19]) grant_c = 29'd524288;
            else if (req[20]) grant_c = 29'd1048576;
            else if (req[21]) grant_c = 29'd2097152;
            else if (req[22]) grant_c = 29'd4194304;
            else if (req[23]) grant_c = 29'd8388608;
            else if (req[24]) grant_c = 29'd16777216;
            else if (req[25]) grant_c = 29'd33554432;
            else if (req[26]) grant_c = 29'd67108864;
            else if (req[27]) grant_c = 29'd134217728;
            else if (req[28]) grant_c = 29'd268435456;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_29

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 29'b11111111111111111111111111110;
                else if (grant[1]) mask <= 29'b11111111111111111111111111100;
                else if (grant[2]) mask <= 29'b11111111111111111111111111000;
                else if (grant[3]) mask <= 29'b11111111111111111111111110000;
                else if (grant[4]) mask <= 29'b11111111111111111111111100000;
                else if (grant[5]) mask <= 29'b11111111111111111111111000000;
                else if (grant[6]) mask <= 29'b11111111111111111111110000000;
                else if (grant[7]) mask <= 29'b11111111111111111111100000000;
                else if (grant[8]) mask <= 29'b11111111111111111111000000000;
                else if (grant[9]) mask <= 29'b11111111111111111110000000000;
                else if (grant[10]) mask <= 29'b11111111111111111100000000000;
                else if (grant[11]) mask <= 29'b11111111111111111000000000000;
                else if (grant[12]) mask <= 29'b11111111111111110000000000000;
                else if (grant[13]) mask <= 29'b11111111111111100000000000000;
                else if (grant[14]) mask <= 29'b11111111111111000000000000000;
                else if (grant[15]) mask <= 29'b11111111111110000000000000000;
                else if (grant[16]) mask <= 29'b11111111111100000000000000000;
                else if (grant[17]) mask <= 29'b11111111111000000000000000000;
                else if (grant[18]) mask <= 29'b11111111110000000000000000000;
                else if (grant[19]) mask <= 29'b11111111100000000000000000000;
                else if (grant[20]) mask <= 29'b11111111000000000000000000000;
                else if (grant[21]) mask <= 29'b11111110000000000000000000000;
                else if (grant[22]) mask <= 29'b11111100000000000000000000000;
                else if (grant[23]) mask <= 29'b11111000000000000000000000000;
                else if (grant[24]) mask <= 29'b11110000000000000000000000000;
                else if (grant[25]) mask <= 29'b11100000000000000000000000000;
                else if (grant[26]) mask <= 29'b11000000000000000000000000000;
                else if (grant[27]) mask <= 29'b10000000000000000000000000000;
                else if (grant[28]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==30) begin : GRANT_30

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 30'd1;
            else if (masked[1]) grant_c = 30'd2;
            else if (masked[2]) grant_c = 30'd4;
            else if (masked[3]) grant_c = 30'd8;
            else if (masked[4]) grant_c = 30'd16;
            else if (masked[5]) grant_c = 30'd32;
            else if (masked[6]) grant_c = 30'd64;
            else if (masked[7]) grant_c = 30'd128;
            else if (masked[8]) grant_c = 30'd256;
            else if (masked[9]) grant_c = 30'd512;
            else if (masked[10]) grant_c = 30'd1024;
            else if (masked[11]) grant_c = 30'd2048;
            else if (masked[12]) grant_c = 30'd4096;
            else if (masked[13]) grant_c = 30'd8192;
            else if (masked[14]) grant_c = 30'd16384;
            else if (masked[15]) grant_c = 30'd32768;
            else if (masked[16]) grant_c = 30'd65536;
            else if (masked[17]) grant_c = 30'd131072;
            else if (masked[18]) grant_c = 30'd262144;
            else if (masked[19]) grant_c = 30'd524288;
            else if (masked[20]) grant_c = 30'd1048576;
            else if (masked[21]) grant_c = 30'd2097152;
            else if (masked[22]) grant_c = 30'd4194304;
            else if (masked[23]) grant_c = 30'd8388608;
            else if (masked[24]) grant_c = 30'd16777216;
            else if (masked[25]) grant_c = 30'd33554432;
            else if (masked[26]) grant_c = 30'd67108864;
            else if (masked[27]) grant_c = 30'd134217728;
            else if (masked[28]) grant_c = 30'd268435456;
            else if (masked[29]) grant_c = 30'd536870912;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 30'd1;
            else if (req[1]) grant_c = 30'd2;
            else if (req[2]) grant_c = 30'd4;
            else if (req[3]) grant_c = 30'd8;
            else if (req[4]) grant_c = 30'd16;
            else if (req[5]) grant_c = 30'd32;
            else if (req[6]) grant_c = 30'd64;
            else if (req[7]) grant_c = 30'd128;
            else if (req[8]) grant_c = 30'd256;
            else if (req[9]) grant_c = 30'd512;
            else if (req[10]) grant_c = 30'd1024;
            else if (req[11]) grant_c = 30'd2048;
            else if (req[12]) grant_c = 30'd4096;
            else if (req[13]) grant_c = 30'd8192;
            else if (req[14]) grant_c = 30'd16384;
            else if (req[15]) grant_c = 30'd32768;
            else if (req[16]) grant_c = 30'd65536;
            else if (req[17]) grant_c = 30'd131072;
            else if (req[18]) grant_c = 30'd262144;
            else if (req[19]) grant_c = 30'd524288;
            else if (req[20]) grant_c = 30'd1048576;
            else if (req[21]) grant_c = 30'd2097152;
            else if (req[22]) grant_c = 30'd4194304;
            else if (req[23]) grant_c = 30'd8388608;
            else if (req[24]) grant_c = 30'd16777216;
            else if (req[25]) grant_c = 30'd33554432;
            else if (req[26]) grant_c = 30'd67108864;
            else if (req[27]) grant_c = 30'd134217728;
            else if (req[28]) grant_c = 30'd268435456;
            else if (req[29]) grant_c = 30'd536870912;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_30

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 30'b111111111111111111111111111110;
                else if (grant[1]) mask <= 30'b111111111111111111111111111100;
                else if (grant[2]) mask <= 30'b111111111111111111111111111000;
                else if (grant[3]) mask <= 30'b111111111111111111111111110000;
                else if (grant[4]) mask <= 30'b111111111111111111111111100000;
                else if (grant[5]) mask <= 30'b111111111111111111111111000000;
                else if (grant[6]) mask <= 30'b111111111111111111111110000000;
                else if (grant[7]) mask <= 30'b111111111111111111111100000000;
                else if (grant[8]) mask <= 30'b111111111111111111111000000000;
                else if (grant[9]) mask <= 30'b111111111111111111110000000000;
                else if (grant[10]) mask <= 30'b111111111111111111100000000000;
                else if (grant[11]) mask <= 30'b111111111111111111000000000000;
                else if (grant[12]) mask <= 30'b111111111111111110000000000000;
                else if (grant[13]) mask <= 30'b111111111111111100000000000000;
                else if (grant[14]) mask <= 30'b111111111111111000000000000000;
                else if (grant[15]) mask <= 30'b111111111111110000000000000000;
                else if (grant[16]) mask <= 30'b111111111111100000000000000000;
                else if (grant[17]) mask <= 30'b111111111111000000000000000000;
                else if (grant[18]) mask <= 30'b111111111110000000000000000000;
                else if (grant[19]) mask <= 30'b111111111100000000000000000000;
                else if (grant[20]) mask <= 30'b111111111000000000000000000000;
                else if (grant[21]) mask <= 30'b111111110000000000000000000000;
                else if (grant[22]) mask <= 30'b111111100000000000000000000000;
                else if (grant[23]) mask <= 30'b111111000000000000000000000000;
                else if (grant[24]) mask <= 30'b111110000000000000000000000000;
                else if (grant[25]) mask <= 30'b111100000000000000000000000000;
                else if (grant[26]) mask <= 30'b111000000000000000000000000000;
                else if (grant[27]) mask <= 30'b110000000000000000000000000000;
                else if (grant[28]) mask <= 30'b100000000000000000000000000000;
                else if (grant[29]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==31) begin : GRANT_31

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 31'd1;
            else if (masked[1]) grant_c = 31'd2;
            else if (masked[2]) grant_c = 31'd4;
            else if (masked[3]) grant_c = 31'd8;
            else if (masked[4]) grant_c = 31'd16;
            else if (masked[5]) grant_c = 31'd32;
            else if (masked[6]) grant_c = 31'd64;
            else if (masked[7]) grant_c = 31'd128;
            else if (masked[8]) grant_c = 31'd256;
            else if (masked[9]) grant_c = 31'd512;
            else if (masked[10]) grant_c = 31'd1024;
            else if (masked[11]) grant_c = 31'd2048;
            else if (masked[12]) grant_c = 31'd4096;
            else if (masked[13]) grant_c = 31'd8192;
            else if (masked[14]) grant_c = 31'd16384;
            else if (masked[15]) grant_c = 31'd32768;
            else if (masked[16]) grant_c = 31'd65536;
            else if (masked[17]) grant_c = 31'd131072;
            else if (masked[18]) grant_c = 31'd262144;
            else if (masked[19]) grant_c = 31'd524288;
            else if (masked[20]) grant_c = 31'd1048576;
            else if (masked[21]) grant_c = 31'd2097152;
            else if (masked[22]) grant_c = 31'd4194304;
            else if (masked[23]) grant_c = 31'd8388608;
            else if (masked[24]) grant_c = 31'd16777216;
            else if (masked[25]) grant_c = 31'd33554432;
            else if (masked[26]) grant_c = 31'd67108864;
            else if (masked[27]) grant_c = 31'd134217728;
            else if (masked[28]) grant_c = 31'd268435456;
            else if (masked[29]) grant_c = 31'd536870912;
            else if (masked[30]) grant_c = 31'd1073741824;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 31'd1;
            else if (req[1]) grant_c = 31'd2;
            else if (req[2]) grant_c = 31'd4;
            else if (req[3]) grant_c = 31'd8;
            else if (req[4]) grant_c = 31'd16;
            else if (req[5]) grant_c = 31'd32;
            else if (req[6]) grant_c = 31'd64;
            else if (req[7]) grant_c = 31'd128;
            else if (req[8]) grant_c = 31'd256;
            else if (req[9]) grant_c = 31'd512;
            else if (req[10]) grant_c = 31'd1024;
            else if (req[11]) grant_c = 31'd2048;
            else if (req[12]) grant_c = 31'd4096;
            else if (req[13]) grant_c = 31'd8192;
            else if (req[14]) grant_c = 31'd16384;
            else if (req[15]) grant_c = 31'd32768;
            else if (req[16]) grant_c = 31'd65536;
            else if (req[17]) grant_c = 31'd131072;
            else if (req[18]) grant_c = 31'd262144;
            else if (req[19]) grant_c = 31'd524288;
            else if (req[20]) grant_c = 31'd1048576;
            else if (req[21]) grant_c = 31'd2097152;
            else if (req[22]) grant_c = 31'd4194304;
            else if (req[23]) grant_c = 31'd8388608;
            else if (req[24]) grant_c = 31'd16777216;
            else if (req[25]) grant_c = 31'd33554432;
            else if (req[26]) grant_c = 31'd67108864;
            else if (req[27]) grant_c = 31'd134217728;
            else if (req[28]) grant_c = 31'd268435456;
            else if (req[29]) grant_c = 31'd536870912;
            else if (req[30]) grant_c = 31'd1073741824;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_31

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 31'b1111111111111111111111111111110;
                else if (grant[1]) mask <= 31'b1111111111111111111111111111100;
                else if (grant[2]) mask <= 31'b1111111111111111111111111111000;
                else if (grant[3]) mask <= 31'b1111111111111111111111111110000;
                else if (grant[4]) mask <= 31'b1111111111111111111111111100000;
                else if (grant[5]) mask <= 31'b1111111111111111111111111000000;
                else if (grant[6]) mask <= 31'b1111111111111111111111110000000;
                else if (grant[7]) mask <= 31'b1111111111111111111111100000000;
                else if (grant[8]) mask <= 31'b1111111111111111111111000000000;
                else if (grant[9]) mask <= 31'b1111111111111111111110000000000;
                else if (grant[10]) mask <= 31'b1111111111111111111100000000000;
                else if (grant[11]) mask <= 31'b1111111111111111111000000000000;
                else if (grant[12]) mask <= 31'b1111111111111111110000000000000;
                else if (grant[13]) mask <= 31'b1111111111111111100000000000000;
                else if (grant[14]) mask <= 31'b1111111111111111000000000000000;
                else if (grant[15]) mask <= 31'b1111111111111110000000000000000;
                else if (grant[16]) mask <= 31'b1111111111111100000000000000000;
                else if (grant[17]) mask <= 31'b1111111111111000000000000000000;
                else if (grant[18]) mask <= 31'b1111111111110000000000000000000;
                else if (grant[19]) mask <= 31'b1111111111100000000000000000000;
                else if (grant[20]) mask <= 31'b1111111111000000000000000000000;
                else if (grant[21]) mask <= 31'b1111111110000000000000000000000;
                else if (grant[22]) mask <= 31'b1111111100000000000000000000000;
                else if (grant[23]) mask <= 31'b1111111000000000000000000000000;
                else if (grant[24]) mask <= 31'b1111110000000000000000000000000;
                else if (grant[25]) mask <= 31'b1111100000000000000000000000000;
                else if (grant[26]) mask <= 31'b1111000000000000000000000000000;
                else if (grant[27]) mask <= 31'b1110000000000000000000000000000;
                else if (grant[28]) mask <= 31'b1100000000000000000000000000000;
                else if (grant[29]) mask <= 31'b1000000000000000000000000000000;
                else if (grant[30]) mask <= '1;
            end
        end
    end

    end

    if (REQ_NB==32) begin : GRANT_32

    // Compute the requester granted based on mask state
    always @ (*) begin

        // 1. Applies the mask and init the granted output
        masked = mask & req;

        // 2. Zeroes the grants once found a first activated one

        // 2.1 handles first the reqs which fall into the mask
        if (|masked) begin
            if      (masked[0]) grant_c = 32'd1;
            else if (masked[1]) grant_c = 32'd2;
            else if (masked[2]) grant_c = 32'd4;
            else if (masked[3]) grant_c = 32'd8;
            else if (masked[4]) grant_c = 32'd16;
            else if (masked[5]) grant_c = 32'd32;
            else if (masked[6]) grant_c = 32'd64;
            else if (masked[7]) grant_c = 32'd128;
            else if (masked[8]) grant_c = 32'd256;
            else if (masked[9]) grant_c = 32'd512;
            else if (masked[10]) grant_c = 32'd1024;
            else if (masked[11]) grant_c = 32'd2048;
            else if (masked[12]) grant_c = 32'd4096;
            else if (masked[13]) grant_c = 32'd8192;
            else if (masked[14]) grant_c = 32'd16384;
            else if (masked[15]) grant_c = 32'd32768;
            else if (masked[16]) grant_c = 32'd65536;
            else if (masked[17]) grant_c = 32'd131072;
            else if (masked[18]) grant_c = 32'd262144;
            else if (masked[19]) grant_c = 32'd524288;
            else if (masked[20]) grant_c = 32'd1048576;
            else if (masked[21]) grant_c = 32'd2097152;
            else if (masked[22]) grant_c = 32'd4194304;
            else if (masked[23]) grant_c = 32'd8388608;
            else if (masked[24]) grant_c = 32'd16777216;
            else if (masked[25]) grant_c = 32'd33554432;
            else if (masked[26]) grant_c = 32'd67108864;
            else if (masked[27]) grant_c = 32'd134217728;
            else if (masked[28]) grant_c = 32'd268435456;
            else if (masked[29]) grant_c = 32'd536870912;
            else if (masked[30]) grant_c = 32'd1073741824;
            else if (masked[31]) grant_c = 32'd2147483648;
            else                grant_c = '0;

        // 2.2 if the mask doesn't match the reqs, uses the unmasked ones
        end else begin
            if      (req[0]) grant_c = 32'd1;
            else if (req[1]) grant_c = 32'd2;
            else if (req[2]) grant_c = 32'd4;
            else if (req[3]) grant_c = 32'd8;
            else if (req[4]) grant_c = 32'd16;
            else if (req[5]) grant_c = 32'd32;
            else if (req[6]) grant_c = 32'd64;
            else if (req[7]) grant_c = 32'd128;
            else if (req[8]) grant_c = 32'd256;
            else if (req[9]) grant_c = 32'd512;
            else if (req[10]) grant_c = 32'd1024;
            else if (req[11]) grant_c = 32'd2048;
            else if (req[12]) grant_c = 32'd4096;
            else if (req[13]) grant_c = 32'd8192;
            else if (req[14]) grant_c = 32'd16384;
            else if (req[15]) grant_c = 32'd32768;
            else if (req[16]) grant_c = 32'd65536;
            else if (req[17]) grant_c = 32'd131072;
            else if (req[18]) grant_c = 32'd262144;
            else if (req[19]) grant_c = 32'd524288;
            else if (req[20]) grant_c = 32'd1048576;
            else if (req[21]) grant_c = 32'd2097152;
            else if (req[22]) grant_c = 32'd4194304;
            else if (req[23]) grant_c = 32'd8388608;
            else if (req[24]) grant_c = 32'd16777216;
            else if (req[25]) grant_c = 32'd33554432;
            else if (req[26]) grant_c = 32'd67108864;
            else if (req[27]) grant_c = 32'd134217728;
            else if (req[28]) grant_c = 32'd268435456;
            else if (req[29]) grant_c = 32'd536870912;
            else if (req[30]) grant_c = 32'd1073741824;
            else if (req[31]) grant_c = 32'd2147483648;
            else             grant_c = '0;
        end
    end

    // Generate the next mask
    always @ (posedge aclk or negedge aresetn) begin : MASK_32

        if (!aresetn) begin
            mask <= '0;
        end else if (srst) begin
            mask <= '0;
        end else begin
            if (en && |grant) begin
                if      (grant[0]) mask <= 32'b11111111111111111111111111111110;
                else if (grant[1]) mask <= 32'b11111111111111111111111111111100;
                else if (grant[2]) mask <= 32'b11111111111111111111111111111000;
                else if (grant[3]) mask <= 32'b11111111111111111111111111110000;
                else if (grant[4]) mask <= 32'b11111111111111111111111111100000;
                else if (grant[5]) mask <= 32'b11111111111111111111111111000000;
                else if (grant[6]) mask <= 32'b11111111111111111111111110000000;
                else if (grant[7]) mask <= 32'b11111111111111111111111100000000;
                else if (grant[8]) mask <= 32'b11111111111111111111111000000000;
                else if (grant[9]) mask <= 32'b11111111111111111111110000000000;
                else if (grant[10]) mask <= 32'b11111111111111111111100000000000;
                else if (grant[11]) mask <= 32'b11111111111111111111000000000000;
                else if (grant[12]) mask <= 32'b11111111111111111110000000000000;
                else if (grant[13]) mask <= 32'b11111111111111111100000000000000;
                else if (grant[14]) mask <= 32'b11111111111111111000000000000000;
                else if (grant[15]) mask <= 32'b11111111111111110000000000000000;
                else if (grant[16]) mask <= 32'b11111111111111100000000000000000;
                else if (grant[17]) mask <= 32'b11111111111111000000000000000000;
                else if (grant[18]) mask <= 32'b11111111111110000000000000000000;
                else if (grant[19]) mask <= 32'b11111111111100000000000000000000;
                else if (grant[20]) mask <= 32'b11111111111000000000000000000000;
                else if (grant[21]) mask <= 32'b11111111110000000000000000000000;
                else if (grant[22]) mask <= 32'b11111111100000000000000000000000;
                else if (grant[23]) mask <= 32'b11111111000000000000000000000000;
                else if (grant[24]) mask <= 32'b11111110000000000000000000000000;
                else if (grant[25]) mask <= 32'b11111100000000000000000000000000;
                else if (grant[26]) mask <= 32'b11111000000000000000000000000000;
                else if (grant[27]) mask <= 32'b11110000000000000000000000000000;
                else if (grant[28]) mask <= 32'b11100000000000000000000000000000;
                else if (grant[29]) mask <= 32'b11000000000000000000000000000000;
                else if (grant[30]) mask <= 32'b10000000000000000000000000000000;
                else if (grant[31]) mask <= '1;
            end
        end
    end

    end

    endgenerate

    //=========================================================================
    // 仲裁结果输出与状态保持逻辑 (Grant Latching & Output Mux)
    //=========================================================================

    //-------------------------------------------------------------------------
    // 寄存当前授权: 仅在使能 en=1 时捕获新的组合仲裁 grant_c
    // 当下游发生背压导致 en=0 时，保持之前已锁定的 grant_r 不变
    //-------------------------------------------------------------------------
    always @ (posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            grant_r <= '0;
        end else if (srst) begin
            grant_r <= '0;
        end else begin
            if (en) begin
                grant_r <= grant_c; // 捕获当前仲裁结果
            end
        end
    end

    //-------------------------------------------------------------------------
    // 最终授权多路选择:
    // - en=1: 输出当前周期的实时组合仲裁 grant_c (零周期延迟)
    // - en=0: 输出锁存的 grant_r，确保背压期间授权信号恒定不变
    //-------------------------------------------------------------------------
    always @ (*) begin
        if (en)
            grant = grant_c;
        else
            grant = grant_r;
    end

endmodule

`resetall
