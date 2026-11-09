//=============================================================================
// 工程名称: AXI Crossbar 互联设计
// 文件名称: axicb_round_robin.sv
// 文件功能: 分层优先级轮询仲裁包装器 (Multi-Priority Round-Robin Arbiter)
// 模块描述:
//   本模块实现支持 4 个静态优先级层级 (Priority 0 ~ 3) 的分层轮询仲裁器。
//   在 AXI Crossbar 中，当多个 Master (发起方) 同时请求访问同一个 Slave (目标方) 的
//   AW/AR 通道，或者多个 Slave 向同一个 Master 返回 B/R 响应时，通过本仲裁器裁决。
//
// 核心仲裁原理与规则:
//   1. 静态优先级分层 (Hierarchical Priority):
//      - Priority 3 为最高优先级，Priority 0 为最低优先级 (P3 > P2 > P1 > P0)。
//      - 抢占抑制原则: 若高优先级层存在活跃请求 (例如 p3_active=1)，则完全压制
//        低优先级层 (P2/P1/P0) 的仲裁，且禁止低优先级轮询核心的使能 (en)。
//   2. 层内轮询均衡 (Fair Round-Robin Within Layer):
//      - 处于相同优先级层级的多个请求者，通过底层的 axicb_round_robin_core 进行
//        公平的无饥饿轮询 (Round-Robin) 调度。
//   3. 动态硬件生成 (Generate per Active Priority):
//      - 根据参数 REQx_PRIORITY 静态推导各优先级层是否存在请求者，仅对有请求者的
//        层级实例化底层轮询核心，避免无谓的门电路消耗。
//=============================================================================

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_round_robin

    #(
        //---------------------------------------------------------------------
        // 参数配置
        //---------------------------------------------------------------------
        // 参与仲裁的请求者总数 (通常对应 Master 数量 MST_NB，例如 4)
        parameter REQ_NB = 4,

        // 各请求者的优先级分配 (取值范围 0 ~ 3，3 为最高优先级)
        parameter REQ0_PRIORITY = 0,
        parameter REQ1_PRIORITY = 0,
        parameter REQ2_PRIORITY = 0,
        parameter REQ3_PRIORITY = 0
    )(
        // 全局信号
        input  wire                   aclk,     // 统一工作时钟
        input  wire                   aresetn,  // 全局异步复位，低电平有效
        input  wire                   srst,     // 同步复位，高电平有效

        // 仲裁控制与通道接口
        input  wire                   en,       // 仲裁使能信号 (通常与 downstream ready 或握手事件绑定)
        input  wire  [REQ_NB    -1:0] req,      // 各请求者的请求有效标志向量 (每一位对应一个请求者)
        output logic [REQ_NB    -1:0] grant     // 最终仲裁授权输出 (One-hot 编码，同一时刻至多 1 位有效)
    );

    //-------------------------------------------------------------------------
    // 内部信号定义
    //-------------------------------------------------------------------------
    // 各优先级层级的“活跃且未被高层压制”指示信号
    logic                  p0_active;
    logic                  p1_active;
    logic                  p2_active;
    logic                  p3_active;

    // 按优先级分层过滤后的请求向量 (仅属于该层的请求者保留其 req 位，其余位清零)
    logic [REQ_NB    -1:0] req_p0;
    logic [REQ_NB    -1:0] req_p1;
    logic [REQ_NB    -1:0] req_p2;
    logic [REQ_NB    -1:0] req_p3;

    // 底层各优先级轮询核心输出的授权向量
    logic [REQ_NB    -1:0] grant_p0;
    logic [REQ_NB    -1:0] grant_p1;
    logic [REQ_NB    -1:0] grant_p2;
    logic [REQ_NB    -1:0] grant_p3;

    // 辅助逻辑变量 (记录参数，便于综合器语法推导)
    logic p0 = REQ0_PRIORITY;
    logic p1 = REQ1_PRIORITY;
    logic p2 = REQ2_PRIORITY;
    logic p3 = REQ3_PRIORITY;

    //=========================================================================
    // 1. 请求向量分层映射 (Request Demultiplexing to Priority Layers)
    //=========================================================================
    // 遍历 4 个请求者，根据其参数配置的优先级，分别分流至对应的优先级子请求向量中
    assign req_p0[0] = (REQ0_PRIORITY==0) ? req[0] : 1'b0;
    assign req_p0[1] = (REQ1_PRIORITY==0) ? req[1] : 1'b0;
    assign req_p0[2] = (REQ2_PRIORITY==0) ? req[2] : 1'b0;
    assign req_p0[3] = (REQ3_PRIORITY==0) ? req[3] : 1'b0;

    assign req_p1[0] = (REQ0_PRIORITY==1) ? req[0] : 1'b0;
    assign req_p1[1] = (REQ1_PRIORITY==1) ? req[1] : 1'b0;
    assign req_p1[2] = (REQ2_PRIORITY==1) ? req[2] : 1'b0;
    assign req_p1[3] = (REQ3_PRIORITY==1) ? req[3] : 1'b0;

    assign req_p2[0] = (REQ0_PRIORITY==2) ? req[0] : 1'b0;
    assign req_p2[1] = (REQ1_PRIORITY==2) ? req[1] : 1'b0;
    assign req_p2[2] = (REQ2_PRIORITY==2) ? req[2] : 1'b0;
    assign req_p2[3] = (REQ3_PRIORITY==2) ? req[3] : 1'b0;

    assign req_p3[0] = (REQ0_PRIORITY==3) ? req[0] : 1'b0;
    assign req_p3[1] = (REQ1_PRIORITY==3) ? req[1] : 1'b0;
    assign req_p3[2] = (REQ2_PRIORITY==3) ? req[2] : 1'b0;
    assign req_p3[3] = (REQ3_PRIORITY==3) ? req[3] : 1'b0;

    //=========================================================================
    // 2. 优先级抢占与活跃标志判别 (Strict Priority Suppression Logic)
    //=========================================================================
    // P3 最高: 只要 P3 存在任何请求 (|req_p3 为真)，P3 即被激活
    assign p3_active = |req_p3;

    // P2 其次: P2 有请求且高层 P3 没有激活时，P2 才能激活
    assign p2_active = |req_p2 & ~p3_active;

    // P1 再次: P1 有请求且更高层 P3/P2 均未激活时，P1 激活
    assign p1_active = |req_p1 & ~p2_active;

    // P0 最低: P0 有请求且更高层 P3/P2/P1 均未激活时，P0 激活
    assign p0_active = |req_p0 & ~p1_active;

    //=========================================================================
    // 3. 各优先级轮询核心例化 (Core Instantiation per Priority)
    //=========================================================================

    //-------------------------------------------------------------------------
    // Priority 0 仲裁核心例化: 仅在有请求者属于该优先级时生成
    //-------------------------------------------------------------------------
    generate
    if (REQ0_PRIORITY==0 || REQ1_PRIORITY==0 || REQ2_PRIORITY==0 || REQ3_PRIORITY==0) begin : P0_ON

        axicb_round_robin_core
        #(
            .REQ_NB (REQ_NB)
        )
        rr_p0
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            // 注意: 只有当前层活跃 (p0_active=1) 且外部仲裁使能 en=1 时，底层状态才推进
            .en      (en & p0_active),
            .req     (req_p0),
            .grant   (grant_p0)
        );

    end else begin : P0_OFF
        assign grant_p0 = {REQ_NB{1'b0}}; // 无请求者则常闭输出 0
    end
    endgenerate

    //-------------------------------------------------------------------------
    // Priority 1 仲裁核心例化
    //-------------------------------------------------------------------------
    generate
    if (REQ0_PRIORITY==1 || REQ1_PRIORITY==1 || REQ2_PRIORITY==1 || REQ3_PRIORITY==1) begin : P1_ON

        axicb_round_robin_core
        #(
            .REQ_NB (REQ_NB)
        )
        rr_p1
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            .en      (en & p1_active),
            .req     (req_p1),
            .grant   (grant_p1)
        );

    end else begin : P1_OFF
        assign grant_p1 = {REQ_NB{1'b0}};
    end
    endgenerate

    //-------------------------------------------------------------------------
    // Priority 2 仲裁核心例化
    //-------------------------------------------------------------------------
    generate
    if (REQ0_PRIORITY==2 || REQ1_PRIORITY==2 || REQ2_PRIORITY==2 || REQ3_PRIORITY==2) begin : P2_ON

        axicb_round_robin_core
        #(
            .REQ_NB (REQ_NB)
        )
        rr_p2
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            .en      (en & p2_active),
            .req     (req_p2),
            .grant   (grant_p2)
        );

    end else begin : P2_OFF
        assign grant_p2 = {REQ_NB{1'b0}};
    end
    endgenerate

    //-------------------------------------------------------------------------
    // Priority 3 仲裁核心例化
    //-------------------------------------------------------------------------
    generate
    if (REQ0_PRIORITY==3 || REQ1_PRIORITY==3 || REQ2_PRIORITY==3 || REQ3_PRIORITY==3) begin : P3_ON

        axicb_round_robin_core
        #(
            .REQ_NB (REQ_NB)
        )
        rr_p3
        (
            .aclk    (aclk),
            .aresetn (aresetn),
            .srst    (srst),
            .en      (en & p3_active),
            .req     (req_p3),
            .grant   (grant_p3)
        );

    end else begin : P3_OFF
        assign grant_p3 = {REQ_NB{1'b0}};
    end
    endgenerate

    //=========================================================================
    // 4. 最终授权仲裁选择 (Final Grant Multiplexing)
    //=========================================================================
    // 按照 P3 > P2 > P1 > P0 的严格优先级顺序，依次判断是否有非零授权输出
    assign grant = (|grant_p3) ? grant_p3 :
                   (|grant_p2) ? grant_p2 :
                   (|grant_p1) ? grant_p1 :
                                 grant_p0 ;

endmodule

`resetall
