//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_pipeline.sv
// 文件功能: 通用握手流水线缓冲器 (Pipeline Register Slice)
// 模块描述:
//   本模块实现带 valid/ready 握手协议的通用流水线寄存器切片。
//   在 AXI 总线互联中，物理布线长、跨越模块多时会导致较差的时序收敛。
//   通过在通道（AW/W/B/AR/R）中插入流水线寄存器，可以切断长时序路径，提升工作频率。
//
// 工作模式 (通过参数 NB_PIPELINE 控制):
//   1. NB_PIPELINE = 0 : 纯组合直通 (Zero-stage/Pass-through)
//      - 延迟为 0，无任何触发器开销。
//      - 缺点: valid 和 ready 信号均为纯组合逻辑贯通，前后级时序路径直接耦合。
//   2. NB_PIPELINE = 1 : 单级流水线缓冲 (One-stage Pipeline)
//      - 前向数据通路 (valid 和 data) 经过 D 触发器打一拍，切断前向时序路径。
//      - 反向流控 (ready) 基于内部缓冲区满状态驱动: full = o_valid & ~o_ready。
//        当本级已缓存有效数据且下游未接收时，拉低 i_ready 阻止上游压入新数据。
//   3. NB_PIPELINE > 1 : 多级流水线串联 (N-stage Pipeline)
//      - 采用递归 generate 结构，由 1 级切片级联 (NB_PIPELINE-1) 级切片构成。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_pipeline

    #(
        //---------------------------------------------------------------------
        // 参数配置
        //---------------------------------------------------------------------
        // 数据总线位宽 (单位: bit)
        parameter DATA_BUS_W = 8,
        // 流水线级数: 0=直通, 1=单级寄存, >1=多级级联
        parameter NB_PIPELINE = 1
    )(
        // 全局信号
        input  wire                       aclk,     // 模块主时钟
        input  wire                       aresetn,  // 全局异步复位信号，低电平有效
        input  wire                       srst,     // 同步复位信号，高电平有效

        // 上游接口 (面向数据生产者 Producer)
        input  wire                       i_valid,  // 上游输入数据有效指示
        output logic                      i_ready,  // 向上传播的就绪指示 (1 表示本级可接收新数据)
        input  wire  [DATA_BUS_W    -1:0] i_data,   // 上游输入的有效载荷数据

        // 下游接口 (面向数据消费者 Consumer)
        output logic                      o_valid,  // 向下游输出数据有效指示
        input  wire                       o_ready,  // 下游消费者就绪指示 (1 表示下游准备好接收)
        output logic [DATA_BUS_W    -1:0] o_data    // 向下游输出的有效载荷数据
    );

    //=========================================================================
    // 流水线生成逻辑 (根据级数生成对应硬件结构)
    //=========================================================================
    generate

    //-------------------------------------------------------------------------
    // 情况 1: 0 级流水线 (纯组合直通)
    //-------------------------------------------------------------------------
    if (NB_PIPELINE==0) begin: NO_PIPELINE

        // 输入输出信号直接短接，不消耗任何触发器资源
        assign o_valid = i_valid;
        assign o_data  = i_data;
        // 反向 ready 信号也直接传递，下游的背压直接无延迟传导到上游
        assign i_ready = o_ready;

    //-------------------------------------------------------------------------
    // 情况 2: 1 级流水线 (单级寄存切片)
    //-------------------------------------------------------------------------
    end else if (NB_PIPELINE==1) begin: ONE_STAGE_PIPELINE

        // 内部满标志: 当本地已暂存有效数据且下游尚未接收时，状态为满 (full=1)
        logic full;

        // 流水线寄存器进程: 寄存 o_valid 与 o_data
        always @ (posedge aclk or negedge aresetn) begin
            // 异步复位清零
            if (~aresetn) begin
                o_valid <= 1'b0;
                o_data  <= {DATA_BUS_W{1'b0}};
            // 同步复位清零
            end else if (srst) begin
                o_valid <= 1'b0;
                o_data  <= {DATA_BUS_W{1'b0}};
            // 非满状态下更新输出寄存器:
            // 1. 如果当前为空 (o_valid=0)，可以直接吸纳上游输入 (即使 i_valid=0 也会更新为 0)。
            // 2. 如果当前有有效数据但下游同时准备好消费 (o_valid=1 && o_ready=1)，
            //    旧数据被消耗的同时，本拍正好无缝载入新数据。
            end else if (~full) begin
                o_valid <= i_valid;
                o_data  <= i_data;
            end
            // 若 full==1，则保持 o_valid 与 o_data 不变，锁定当前未被消费的数据
        end

        // 满条件判定:
        // 当前寄存器中已有有效数据 (o_valid == 1)，但下游未准备好接收 (o_ready == 0)。
        // 此时寄存器处于暂存闭锁状态，不能写入新数据，否则会覆盖未被消费的内容。
        assign full = (o_valid & ~o_ready);

        // 向生产者反馈的就绪信号:
        // 只要本地寄存器没有满 (!full)，就允许上游写入新数据。
        assign i_ready = !full;

    //-------------------------------------------------------------------------
    // 情况 3: N 级流水线 (N > 1，递归例化结构)
    //-------------------------------------------------------------------------
    end else begin: N_STAGE_PIPELINE

        // 连接当前第 1 级切片与后续 (N-1) 级切片的内部握手总线
        logic                      pipe_valid;
        logic                      pipe_ready;
        logic [DATA_BUS_W    -1:0] pipe_data;

        // 递归基底: 实例化第 1 级流水线
        axicb_pipeline
        #(
            .DATA_BUS_W  (DATA_BUS_W),
            .NB_PIPELINE (1)            // 构造 1 级硬件切片
        )
        pipe_n
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            // 连接上游输入端口
            .i_valid (i_valid),
            .i_ready (i_ready),
            .i_data  (i_data),
            // 输出连接到中间内部连线
            .o_valid (pipe_valid),
            .o_ready (pipe_ready),
            .o_data  (pipe_data)
        );

        // 递归展开: 实例化剩余的 (NB_PIPELINE - 1) 级流水线
        axicb_pipeline
        #(
            .DATA_BUS_W  (DATA_BUS_W),
            .NB_PIPELINE (NB_PIPELINE-1) // 递归级数减 1
        )
        pipe_n_m1
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            // 输入连接中间内部连线
            .i_valid (pipe_valid),
            .i_ready (pipe_ready),
            .i_data  (pipe_data),
            // 输出连接到下游输出端口
            .o_valid (o_valid),
            .o_ready (o_ready),
            .o_data  (o_data)
        );

    end
    endgenerate

endmodule

`resetall
