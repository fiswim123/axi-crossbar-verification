//==========================================================================
// Environment（验证环境）- 标准UVM架构版本
//==========================================================================
// 【文件功能说明】
// 本文件实现了 AXI Crossbar 的顶层验证环境，采用标准 UVM 架构。
// 与简化版本不同，标准架构使用 Agent 来封装 driver、sequencer、monitor，
// 使代码结构更清晰、更符合 UVM 最佳实践。
//
// 【标准UVM架构优势】
// 1. 层次清晰：Agent 封装了相关组件，env 只管理 agent
// 2. 可复用性：Agent 可以在不同 testbench 中复用
// 3. 灵活性：可以通过 is_active 配置切换 active/passive 模式
// 4. 易维护：修改 agent 内部不影响 env 的结构
//
// 【架构图】
//   ┌─────────────────────────────────────────────────────────────┐
//   │                    axi_env (顶层环境)                         │
//   ├─────────────────────────────────────────────────────────────┤
//   │  ┌─────────────────────────────────────────────────────┐   │
//   │  │ Master Agent[0..3] (Active)                          │   │
//   │  │  ├── driver: 驱动写/读事务到 DUT                      │   │
//   │  │  ├── sequencer: 调度 sequence 产生的事务              │   │
//   │  │  └── monitor: 观察主机侧总线事务                      │   │
//   │  └─────────────────────────────────────────────────────┘   │
//   │  ┌─────────────────────────────────────────────────────┐   │
//   │  │ Slave Agent[0..3] (Active)                           │   │
//   │  │  ├── driver: 响应 DUT 的请求，模拟存储器              │   │
//   │  │  └── monitor: 观察从机侧总线事务                      │   │
//   │  └─────────────────────────────────────────────────────┘   │
//   │  ┌─────────────────────────────────────────────────────┐   │
//   │  │ Global Components                                    │   │
//   │  │  ├── scoreboard: 数据正确性校验                      │   │
//   │  │  └── coverage: 功能覆盖率收集                        │   │
//   │  └─────────────────────────────────────────────────────┘   │
//   └─────────────────────────────────────────────────────────────┘
//
// 【与简化版本的对比】
// 简化版本：
//   axi_env
//   ├── mst_drv[4]
//   ├── slv_drv[4]
//   ├── mst_mon[4]
//   ├── slv_mon[4]
//   ├── sqr[4]
//   ├── scbd
//   └── cov
//
// 标准版本：
//   axi_env
//   ├── mst_agent[4] (包含 driver + sequencer + monitor)
//   ├── slv_agent[4] (包含 driver + monitor)
//   ├── scbd
//   └── cov
//==========================================================================

class axi_env extends uvm_env;
    // 工厂注册宏
    `uvm_component_utils(axi_env)

    // ===== 组件句柄声明 =====

    // mst_agent[4]: 4个主机代理（Master Agent）
    // 每个 agent 封装了一个主机端口的完整验证组件：
    //   - driver: 驱动写/读事务到 DUT
    //   - sequencer: 调度 sequence 产生的事务
    //   - monitor: 观察主机侧总线事务
    axi_mst_agent mst_agent[4];

    // slv_agent[4]: 4个从机代理（Slave Agent）
    // 每个 agent 封装了一个从机端口的验证组件：
    //   - driver: 响应 DUT 的请求，模拟存储器行为
    //   - monitor: 观察从机侧总线事务
    axi_slv_agent slv_agent[4];

    // scbd: 计分板（Scoreboard）- 单实例
    // 整个验证环境共享一个 scoreboard，收集所有主机侧监视器的事务进行校验
    axi_scoreboard scbd;

    // cov: 覆盖率收集器（Coverage Collector）- 单实例
    // 收集所有主机侧事务的功能覆盖率
    axi_coverage cov;

    // slv_cfg[4]: 从机配置对象数组
    // 每个从机驱动器需要独立的配置，例如：
    //   - 是否注入错误响应（error injection）
    //   - 从机的响应延迟设置
    //   - 内存大小等参数
    axi_slv_cfg slv_cfg[4];

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // ================================================================
    // 【build_phase - 构建阶段】
    // ================================================================
    // 在此阶段创建所有子组件。UVM的build_phase是从上到下执行的：
    // test -> env -> agent -> driver/sequencer/monitor
    // 所有组件都通过工厂（type_id::create）创建，而非直接new()
    // 这样做的好处是支持factory override，可以在test层替换任何组件
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 循环创建4组主机/从机的 agent
        for (int i = 0; i < 4; i++) begin
            // 设置 master_id（用于路由验证）
            uvm_config_db#(int)::set(
                this,
                $sformatf("mst_agent%0d", i),
                "master_id",
                i
            );

            // 创建主机代理
            // Agent 内部会自动创建 driver、sequencer、monitor
            mst_agent[i] = axi_mst_agent::type_id::create(
                $sformatf("mst_agent%0d", i), this
            );

            // 创建从机配置对象
            slv_cfg[i] = axi_slv_cfg::type_id::create(
                $sformatf("slv_cfg%0d", i)
            );

            // 通过 config_db 将从机配置传递给对应的从机代理
            // Agent 会进一步传递给内部的 driver
            uvm_config_db#(axi_slv_cfg)::set(
                this,
                $sformatf("slv_agent%0d", i),
                "cfg",
                slv_cfg[i]
            );

            // 设置 slave_id（用于路由验证）
            uvm_config_db#(int)::set(
                this,
                $sformatf("slv_agent%0d", i),
                "slave_id",
                i
            );

            // 创建从机代理
            // Agent 内部会自动创建 driver、monitor
            slv_agent[i] = axi_slv_agent::type_id::create(
                $sformatf("slv_agent%0d", i), this
            );
        end

        // 创建 scoreboard 和 coverage（各一个实例，全局共享）
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction

    // ================================================================
    // 【connect_phase - 连接阶段】
    // ================================================================
    // 在所有组件的build_phase完成后执行，用于建立组件间的通信连接
    // UVM的connect_phase是从下到上执行的：子组件 -> 父组件
    // 此阶段的核心任务是将analysis_port连接到analysis_imp/export
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        for (int i = 0; i < 4; i++) begin
            // 将主机侧监视器的analysis port连接到scoreboard的analysis imp
            // 当monitor广播事务时，scoreboard的write()会被调用
            mst_agent[i].monitor.ap.connect(scbd.mst_imp);

            // 将从机侧监视器的analysis port连接到scoreboard
            // 用于路由验证：检查事务是否到达正确的Slave
            slv_agent[i].monitor.ap.connect(scbd.slv_imp);

            // 将主机侧监视器的analysis port连接到coverage的analysis_export
            // uvm_subscriber的analysis_export名称是固定的
            mst_agent[i].monitor.ap.connect(cov.analysis_export);
        end
    endfunction

endclass
