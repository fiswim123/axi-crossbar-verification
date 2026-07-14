//==========================================================================
// Slave Agent - 从设备代理
//==========================================================================
// 【文件功能说明】
// 本文件实现了 AXI Slave Agent，它是 UVM 标准架构中的核心组件。
// Slave Agent 模拟从设备（如 SRAM、外设）的行为，响应 DUT 的请求。
//
// 【与 Master Agent 的区别】
// Master Agent (Active):
//   - 包含 driver + sequencer + monitor
//   - 主动产生激励，驱动到 DUT
//
// Slave Agent (通常为 Active):
//   - 包含 driver + monitor
//   - 被动响应 DUT 的请求
//   - 通常不需要 sequencer，因为 slave 是响应型设备
//
// 【Slave Driver 的特殊性】
// 与 Master Driver 不同，Slave Driver 不从 sequencer 获取事务：
//   - Master Driver: 主动获取事务 → 驱动信号
//   - Slave Driver: 被动监听请求 → 响应信号
//
// 因此 Slave Agent 通常不需要 sequencer，但可以保留 monitor 用于：
//   1. 观察 DUT 发出的请求
//   2. 收集从设备侧的覆盖率
//   3. 协议检查
//
// 【配置对象】
// Slave Agent 使用 axi_slv_cfg 配置对象来控制：
//   - 错误注入概率
//   - 背压（backpressure）行为
//   - 响应延迟
//   - 存储器大小等参数
//==========================================================================

class axi_slv_agent extends uvm_agent;
    // 【工厂注册】注册到 UVM 工厂
    `uvm_component_utils(axi_slv_agent)

    // ===== 组件句柄声明 =====

    // driver: 从设备驱动器
    // 被动响应 DUT 的请求，模拟存储器行为
    axi_slv_drv driver;

    // monitor: 监视器
    // 观察从设备侧的总线事务
    axi_monitor monitor;

    // ===== 配置对象 =====

    // cfg: 从设备配置对象
    // 控制错误注入、背压、延迟等行为
    axi_slv_cfg cfg;

    // is_active: 控制 agent 是 active 还是 passive 模式
    // Slave Agent 默认为 UVM_ACTIVE，因为它需要 driver 来响应请求
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // vif: 虚拟接口，指向 DUT 的 AXI 接口
    virtual axi_if vif;

    // ================================================================
    // 【构造函数】
    // ================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // ================================================================
    // 【build_phase - 构建阶段】
    // ================================================================
    // 在 build_phase 中创建子组件，并获取配置参数
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 从 config_db 获取虚拟接口
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))

        // 从 config_db 获取配置对象
        // 配置对象在 env 中创建并通过 config_db 传递
        if (!uvm_config_db#(axi_slv_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", $sformatf("No cfg for %s", get_full_name()))

        // 将虚拟接口和配置传递给子组件
        uvm_config_db#(virtual axi_if)::set(this, "driver", "vif", vif);
        uvm_config_db#(virtual axi_if)::set(this, "monitor", "vif", vif);
        uvm_config_db#(axi_slv_cfg)::set(this, "driver", "cfg", cfg);

        // 创建 monitor (active 和 passive 模式都需要)
        monitor = axi_monitor::type_id::create("monitor", this);

        // 根据 is_active 配置创建 driver
        if (is_active == UVM_ACTIVE) begin
            // Active 模式：创建 driver
            // Slave Driver 不需要 sequencer，因为它被动响应
            driver = axi_slv_drv::type_id::create("driver", this);
        end
    endfunction

    // ================================================================
    // 【connect_phase - 连接阶段】
    // ================================================================
    // Slave Agent 通常不需要在 connect_phase 中建立连接
    // 因为 Slave Driver 不连接 sequencer
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Slave Driver 是被动响应型，不需要连接 sequencer
        // 如果需要，可以在这里建立其他连接
    endfunction

endclass
