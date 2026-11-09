///////////////////////////////////////////////////////////////////////////////
//
// AXI Crossbar UVM 测试顶层 (Testbench Top)
//
///////////////////////////////////////////////////////////////////////////////
// 【文件功能说明】
// 这是整个 UVM 验证环境的最顶层模块，负责：
//   1. 生成时钟和复位信号
//   2. 例化 AXI 接口（Interface）
//   3. 例化 DUT（Design Under Test，被测设计）
//   4. 将接口通过 config_db 传递给 UVM 组件
//   5. 启动 UVM 测试
//   6. 配置超时和波形转储
//
// 【UVM 知识点】
// testbench top 不是 UVM 组件，而是普通的 SystemVerilog module。
// 它是连接 UVM 世界和 DUT 的桥梁：
//   - UVM 世界：class-based，面向对象，不直接操作信号
//   - DUT 世界：module-based，通过端口连接信号
//   - Interface 是连接两者的纽带：UVM 通过 virtual interface 驱动/采样信号
//
// 【验证环境架构图】
//   +--------------------------------------------------+
//   |                Testbench Top (本文件)              |
//   |  +----------+    +----------+    +----------+    |
//   |  | mst_if[0]|    | mst_if[1]|    | mst_if[2]|... |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |       |               |               |           |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |  |  DUT      |    |          |    |          |    |
//   |  | (Crossbar)|    |          |    |          |    |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |       |               |               |           |
//   |  +----+-----+    +----+-----+    +----+-----+    |
//   |  | slv_if[0]|    | slv_if[1]|    | slv_if[2]|... |
//   |  +----------+    +----------+    +----------+    |
//   +--------------------------------------------------+
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module harness;

    // 【导入 UVM 包】
    // import uvm_pkg::* 导入所有 UVM 类和方法
    // import axi_pkg::* 导入我们自定义的验证组件包
    import uvm_pkg::*;
    import axi_pkg::*;
    `include "uvm_macros.svh"  // 包含 UVM 宏定义（如 `uvm_component_utils 等）

    // 【参数定义】
    // 这些参数必须与 DUT 的参数保持一致
    // 使用 parameter 而非硬编码，方便修改和复用
    parameter AXI_ADDR_W = 16;  // 地址位宽：16位，可寻址 64KB 空间
    parameter AXI_ID_W   = 8;   // ID 位宽：8位，支持 256 个不同的事务 ID
    parameter AXI_DATA_W = 32;  // 数据位宽：32位，每次传输 4 字节

    //--------------------------------------------------------------------------
    // 时钟与复位生成 (Clock & Reset Generation)
    //--------------------------------------------------------------------------
    // 【时钟生成】
    // aclk 初始值为 0，每 5ns 翻转一次 → 时钟周期 = 10ns → 频率 = 100MHz
    // always #5 是 SystemVerilog 的周期性行为块
    logic aclk = 0;

    // 【复位信号】
    // aresetn: AXI 标准复位信号，低电平有效（active low）
    //   - 初始为 0（复位状态）
    //   - 100ns 后拉高为 1（释放复位）
    // srst: 同步复位信号，高电平有效
    //   - 初始为 1（复位状态）
    //   - 100ns 后拉低为 0（释放复位）
    logic aresetn = 0;
    logic srst = 1;
    always #5 aclk = ~aclk;              // 时钟翻转
    initial begin #100; aresetn = 1; srst = 0; end  // 100ns 后释放复位

    //--------------------------------------------------------------------------
    // AXI 接口例化 (Interface Instantiation)
    //--------------------------------------------------------------------------
    // 【Master 接口数组】
    // mst_if[4]: 4 个 Master 接口，连接 DUT 的 Slave 端口
    //   - 每个 Master 接口对应一个 Master Agent（driver + monitor）
    //   - Master Agent 通过这些接口发送读写请求
    //
    // 【Slave 接口数组】
    // slv_if[4]: 4 个 Slave 接口，连接 DUT 的 Master 端口
    //   - 每个 Slave 接口对应一个 Slave Agent（driver + monitor）
    //   - Slave Agent 通过这些接口模拟从设备行为（接收请求、返回响应）
    //
    // 【命名约定说明】
    // DUT 端口命名：slv0, slv1, slv2, slv3 → DUT 的 Slave 端口（连接外部 Master）
    //               mst0, mst1, mst2, mst3 → DUT 的 Master 端口（连接外部 Slave）
    // 这是因为 Crossbar 的 Slave 端口接收来自 Master 的请求，
    // 而 Master 端口将请求转发给下游 Slave 设备
    axi_if #(.AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W))
        mst_if[4] (.aclk(aclk));  // Master 接口，连接 DUT 的 Slave 端口

    axi_if #(.AXI_ADDR_W(AXI_ADDR_W), .AXI_ID_W(AXI_ID_W), .AXI_DATA_W(AXI_DATA_W))
        slv_if[4] (.aclk(aclk));  // Slave 接口，连接 DUT 的 Master 端口

    // 【复位信号同步驱动】
    // 使用 generate 块为每个接口的 aresetn 信号同步驱动
    // 这样 test 可以通过 vif 覆盖复位信号（用于 reset 测试）
    // always @(posedge aclk) 确保复位信号在时钟上升沿更新，避免亚稳态
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_rst
            always @(posedge aclk) mst_if[i].aresetn <= aresetn;
            always @(posedge aclk) slv_if[i].aresetn <= aresetn;
        end
    endgenerate

    `include "top/dut_connect.svh"

    //--------------------------------------------------------------------------
    // UVM config_db 配置 (UVM Configuration Database)
    //--------------------------------------------------------------------------
    // 【config_db 说明】
    // uvm_config_db 是 UVM 的配置数据库机制，用于在组件之间传递配置信息。
    // 这里使用它将 virtual interface 传递给 UVM 组件：
    //   - set() 函数：将数据存入 config_db
    //   - 参数1 (null)：使用全局数据库（非特定组件）
    //   - 参数2 ("*.mst_drv0")：通配符路径，匹配所有层次下的 mst_drv0 组件
    //   - 参数3 ("vif")：配置项名称
    //   - 参数4 (mst_if[0])：配置项值（virtual interface）
    //
    // 【Virtual Interface 说明】
    // virtual interface 是 SystemVerilog 中指向 interface 实例的指针
    // UVM 组件（class）不能直接例化或访问 interface（module），
    // 但可以通过 virtual interface 间接驱动/采样接口信号
    // 这是连接 UVM 世界和 DUT 世界的桥梁
    initial begin
        // 将 mst_if[0] 传递给 Master Agent 0（内部的 driver 和 monitor）
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_agent0", "vif", mst_if[0]);
        // 将 slv_if[0] 传递给 Slave Agent 0（内部的 driver 和 monitor）
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_agent0", "vif", slv_if[0]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_agent1", "vif", mst_if[1]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_agent1", "vif", slv_if[1]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_agent2", "vif", mst_if[2]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_agent2", "vif", slv_if[2]);

        uvm_config_db#(virtual axi_if)::set(null, "*.mst_agent3", "vif", mst_if[3]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_agent3", "vif", slv_if[3]);

        // 【启动 UVM 测试】
        // run_test() 是 UVM 的入口函数，它会：
        //   1. 根据 +UVM_TESTNAME 命令行参数创建测试实例
        //   2. 默认测试由 sim/Makefile 的 UVM_TEST 变量提供
        //   3. 执行 UVM 的 phase 机制（build → connect → run → check → report）
        run_test();
    end

    //--------------------------------------------------------------------------
    // 超时机制 (Timeout Mechanism)
    //--------------------------------------------------------------------------
    // 【超时说明】
    // 如果仿真运行超过 50ms（50,000,000ns）仍未结束，强制终止
    // 这是为了防止测试卡死导致仿真无限运行
    // uvm_fatal 会打印错误信息并终止仿真
    initial begin
        #50000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end

    //--------------------------------------------------------------------------
    // 波形转储 (Waveform Dump)
    //--------------------------------------------------------------------------
    // 【波形说明】
    // $dumpfile: 指定波形文件名（VCD 格式）
    // $dumpvars: 指定要记录的信号范围
    //   - 0: 记录所有层次的信号
    //   - harness: 从 testbench 顶层开始记录
    // 生成的 .vcd 文件可以用 GTKWave 等工具查看
    initial begin
        if ($test$plusargs("DUMP_FSDB")) begin
            $fsdbDumpfile("harness.fsdb");
            $fsdbDumpvars(0, harness);
        end
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("harness.vcd");
            $dumpvars(0, harness);
        end
    end

endmodule
