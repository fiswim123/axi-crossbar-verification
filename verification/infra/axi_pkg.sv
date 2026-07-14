`timescale 1ns/1ps
// ============================================================================
// 时间精度声明：`timescale 仿真时间单位 / 仿真时间精度
//   - 1ns：仿真中所有延时的默认单位为纳秒
//   - 1ps：仿真器能分辨的最小时间步进为皮秒
//   例如 #10 表示延时 10ns；仿真器内部以 1ps 精度推进仿真时间
// ============================================================================

// ============================================================================
// package 是 SystemVerilog 的命名空间机制，用于将相关的类型、类、常量、
// 函数等封装在一起，避免命名冲突。在 UVM 验证环境中，我们通常把整个验证
// 平台的所有组件（driver、monitor、scoreboard 等）定义在同一个 package 中，
// 这样在顶层 testbench 中只需 import 一个 package 即可使用所有组件。
//
// package 名称 "axi_pkg" 暗示这是与 AXI 协议相关的验证组件集合。
// ============================================================================
package axi_pkg;

    // ========================================================================
    // 第一步：导入 UVM 基础库
    // ========================================================================
    // import uvm_pkg::* 将 UVM 库中的所有类（如 uvm_driver、uvm_monitor、
    // uvm_test、uvm_env、uvm_sequence 等）和方法导入到当前 package 作用域。
    // 这样后续定义的组件就可以直接继承 UVM 基类，无需每次都写 uvm_pkg::uvm_driver。
    import uvm_pkg::*;

    // uvm_macros.svh 文件包含了 UVM 的各种宏定义，例如：
    //   - `uvm_info(MSG_ID, MSG, VERBOSITY)   ：打印信息日志
    //   - `uvm_warning(MSG_ID, MSG)            ：打印警告
    //   - `uvm_error(MSG_ID, MSG)              ：打印错误
    //   - `uvm_fatal(MSG_ID, MSG)              ：打印致命错误并终止仿真
    //   - `uvm_field_int / `uvm_field_object 等：UVM 自动化宏（自动实现 copy/print/compare）
    //
    // 为什么用 `include 而不是 import？
    // 因为 uvm_macros.svh 是一个头文件（.svh = SystemVerilog Header），
    // 它通过预处理指令 `include 在编译前被文本替换粘贴到当前位置。
    // 宏不是类/包成员，不能通过 import 导入，只能通过 `include 引入。
    `include "uvm_macros.svh"

    // ========================================================================
    // 第二步：用 `include 引入验证平台的所有组件文件
    // ========================================================================
    //
    // `include 是 SystemVerilog 的预处理指令，作用类似 C 语言的 #include：
    // 编译器在编译之前，会把指定文件的全部内容原样替换到 `include 所在的位置。
    //
    // 为什么要分文件组织？
    //   1. 可读性：每个文件只定义一两个类，便于查找和阅读
    //   2. 可维护性：修改某个组件只需改动对应文件
    //   3. 团队协作：不同成员可以并行修改不同文件，减少代码冲突
    //   4. 复用性：组件文件可以在其他项目中被复用
    //
    // include 的顺序很重要！后面 include 的文件可能依赖前面 include 的类。
    // 例如 axi_env.sv 中会用到 axi_scoreboard 等组件，所以 axi_env.sv 必须
    // 在它们之后被 include。类似地，测试用例（tests/）依赖组件和序列，
    // 所以 tests/ 目录的文件必须放在最后。
    //
    // 下面将所有文件按功能分为三大类：Components（组件）、Sequences（序列）、Tests（测试）
    // ========================================================================

    //==========================================================================
    // Components（验证平台组件）
    //==========================================================================
    // 这些是构成 UVM 验证平台（environment）的核心组件：
    //
    // axi_slv_cfg.sv     - 从设备（slave）配置类，存储 slave 的地址范围、
    //                       ID 宽度等参数，用于配置验证环境中的 slave agent
    //
    // axi_txn.sv         - AXI 事务（transaction）类，继承自 uvm_sequence_item，
    //                       描述一次 AXI 读/写操作的所有信号信息：
    //                       地址、数据、ID、burst 类型、burst 长度等
    //
    // axi_mst_drv.sv     - 主设备驱动器（master driver），继承自 uvm_driver，
    //                       负责将 master 端的 AXI 事务转化为引脚级信号激励，
    //                       驱动 DUT 的 master 端口
    //
    // axi_slv_drv.sv     - 从设备驱动器（slave driver），继承自 uvm_driver，
    //                       模拟 slave 行为，接收 DUT 发来的读/写请求并返回响应
    //
    // axi_monitor.sv     - 监控器（monitor），继承自 uvm_monitor，
    //                       被动观测 DUT 的引脚信号，将观测到的事务信息
    //                       发送给 scoreboard 和 coverage 组件
    //
    // axi_scoreboard.sv  - 记分板（scoreboard），用于比对 master 端发出的
    //                       事务与 slave 端实际收到的事务是否一致，
    //                       检测数据丢失、地址路由错误等 bug
    //
    // axi_coverage.sv    - 功能覆盖率收集器，记录各种测试场景（如不同 burst
    //                       类型、不同地址范围、不同 ID 值）是否被覆盖到，
    //                       帮助评估验证完备性
    //
    // axi_env.sv         - 验证环境（environment），继承自 uvm_env，
    //                       顶层容器，负责创建并连接上述所有组件：
    //                       agent(mst_drv+slv_drv+monitor)、scoreboard、coverage
    `include "components/axi_slv_cfg.sv"
    `include "components/axi_txn.sv"
    `include "components/axi_mst_drv.sv"
    `include "components/axi_slv_drv.sv"
    `include "components/axi_monitor.sv"
    `include "components/axi_scoreboard.sv"
    `include "components/axi_coverage.sv"
    `include "components/axi_mst_agent.sv"
    `include "components/axi_slv_agent.sv"
    `include "components/axi_env.sv"

    //==========================================================================
    // Sequences（测试序列）
    //==========================================================================
    // sequence 继承自 uvm_sequence，定义了发送给 driver 的激励模式。
    // 每个 sequence 包含若干 sequence_item（事务），按特定规则生成并发送给 driver。
    // 不同的 sequence 模拟不同的测试场景。
    //
    // 基础读写序列：
    //   axi_wr_seq.sv              - 单次写事务序列
    //   axi_rd_seq.sv              - 单次读事务序列
    //
    // Burst 传输相关序列：
    //   axi_burst_wr_seq.sv        - 突发写序列（连续发送多个写数据 beat）
    //   axi_burst_rd_seq.sv        - 突发读序列（连续发起多个读请求）
    //   axi_burst_size_seq.sv      - 不同 burst size 的测试序列
    //
    // 高级特性测试序列：
    //   axi_outstanding_read_seq.sv - 未完成读（outstanding read）序列，
    //                                  测试 DUT 在前一笔读未返回时能否发起新读
    //   axi_same_slave_seq.sv      - 连续访问同一 slave 的序列
    //   axi_interleave_seq.sv      - 交织传输序列，测试写数据通道的 interleaving
    //   axi_concurrent_seq.sv      - 并发序列，同时发起读写操作
    //
    // 异常/边界测试序列：
    //   axi_err_inject_seq.sv      - 错误注入序列，模拟 slave 返回错误响应
    //   axi_boundary_seq.sv        - 地址边界序列，测试地址空间边界的读写
    //   axi_backpressure_seq.sv    - 反压序列，模拟下游 ready 信号延迟拉高
    //
    // 随机/性能测试序列：
    //   axi_random_seq.sv          - 随机序列，随机化事务参数进行全面测试
    //   axi_perf_seq.sv            - 性能测试序列，测试吞吐量和延迟
    //   axi_full_routing_seq.sv    - 全路由测试序列，覆盖所有地址到所有 slave 的路由
    `include "sequences/axi_wr_seq.sv"
    `include "sequences/axi_rd_seq.sv"
    `include "sequences/axi_burst_wr_seq.sv"
    `include "sequences/axi_burst_rd_seq.sv"
    `include "sequences/axi_burst_size_seq.sv"
    `include "sequences/axi_outstanding_read_seq.sv"
    `include "sequences/axi_same_slave_seq.sv"
    `include "sequences/axi_interleave_seq.sv"
    `include "sequences/axi_concurrent_seq.sv"
    `include "sequences/axi_err_inject_seq.sv"
    `include "sequences/axi_boundary_seq.sv"
    `include "sequences/axi_backpressure_seq.sv"
    `include "sequences/axi_random_seq.sv"
    `include "sequences/axi_perf_seq.sv"
    `include "sequences/axi_full_routing_seq.sv"

    //==========================================================================
    // Tests（测试用例）
    //==========================================================================
    // 测试用例继承自 uvm_test，每个 test 代表一个独立的验证场景。
    // test 负责：
    //   1. 创建并配置 environment
    //   2. 启动一个或多个 sequence
    //   3. 设置仿真结束条件（如 drain time）
    // 在运行仿真时，通过 +UVM_TESTNAME=<test_name> 指定要运行哪个 test。
    //
    // axi_base_test.sv            - 基础测试类，封装公共的 build/connect/run 逻辑，
    //                                 其他所有 test 继承自它，避免代码重复
    //
    // 基础功能测试：
    //   axi_basic_test.sv          - 基本读写功能测试
    //   axi_routing_test.sv        - 地址路由功能测试（验证地址正确分发到对应 slave）
    //   axi_protocol_test.sv       - AXI 协议合规性测试
    //
    // 特性测试：
    //   axi_burst_size_test.sv     - 不同 burst size 测试
    //   axi_outstanding_test.sv    - Outstanding 事务测试
    //   axi_outstanding_read_test.sv - 读 outstanding 专项测试
    //   axi_multi_master_test.sv   - 多 master 并发测试
    //   axi_same_slave_test.sv     - 同一 slave 连续访问测试
    //   axi_interleave_test.sv     - 写数据交织测试
    //
    // 错误注入测试：
    //   axi_err_slverr_test.sv     - slave 错误响应（SLVERR）测试
    //   axi_err_decerr_test.sv     - 解码错误（DECERR）测试
    //   axi_err_recovery_test.sv   - 错误恢复测试
    //
    // 地址边界测试：
    //   axi_boundary_addr_test.sv  - 边界地址测试
    //   axi_boundary_burst_test.sv - 边界 burst 测试
    //   axi_boundary_ostd_test.sv  - 边界 outstanding 测试
    //
    // 反压测试：
    //   axi_bp_wready_test.sv      - 写数据通道 WREADY 反压测试
    //   axi_bp_bready_test.sv      - 写响应通道 BREADY 反压测试
    //   axi_bp_rready_test.sv      - 读数据通道 RREADY 反压测试
    //   axi_bp_all_test.sv         - 全通道反压测试
    //
    // 随机测试：
    //   axi_random_test.sv         - 随机参数测试
    //   axi_random_concurrent_test.sv - 随机并发测试
    //
    // 性能测试：
    //   axi_perf_latency_test.sv   - 延迟性能测试
    //   axi_perf_bandwidth_test.sv - 带宽性能测试
    //
    // 复位测试：
    //   axi_reset_wr_test.sv       - 写通道复位测试
    //   axi_reset_rd_test.sv       - 读通道复位测试
    //   axi_reset_recovery_test.sv - 复位恢复测试
    //
    // 全路由测试：
    //   axi_full_routing_test.sv   - 全路由覆盖测试
    `include "tests/axi_base_test.sv"
    `include "tests/axi_basic_test.sv"
    `include "tests/axi_routing_test.sv"
    `include "tests/axi_protocol_test.sv"
    `include "tests/axi_burst_size_test.sv"
    `include "tests/axi_outstanding_test.sv"
    `include "tests/axi_outstanding_read_test.sv"
    `include "tests/axi_multi_master_test.sv"
    `include "tests/axi_same_slave_test.sv"
    `include "tests/axi_interleave_test.sv"
    `include "tests/axi_err_slverr_test.sv"
    `include "tests/axi_err_decerr_test.sv"
    `include "tests/axi_err_recovery_test.sv"
    `include "tests/axi_boundary_addr_test.sv"
    `include "tests/axi_boundary_burst_test.sv"
    `include "tests/axi_boundary_ostd_test.sv"
    `include "tests/axi_bp_wready_test.sv"
    `include "tests/axi_bp_bready_test.sv"
    `include "tests/axi_bp_rready_test.sv"
    `include "tests/axi_bp_all_test.sv"
    `include "tests/axi_random_test.sv"
    `include "tests/axi_random_concurrent_test.sv"
    `include "tests/axi_perf_latency_test.sv"
    `include "tests/axi_perf_bandwidth_test.sv"
    `include "tests/axi_reset_wr_test.sv"
    `include "tests/axi_reset_rd_test.sv"
    `include "tests/axi_reset_recovery_test.sv"
    `include "tests/axi_full_routing_test.sv"

// ============================================================================
// package 的结束标记。所有被 include 进来的类和宏，都归属于 axi_pkg 这个命名空间。
// 在其他模块中使用时，需要先 import axi_pkg::* 才能访问其中的类。
// 例如在顶层 testbench 中：
//   import axi_pkg::*;
//   然后就可以直接引用 axi_base_test 等类名了。
// ============================================================================
endpackage
