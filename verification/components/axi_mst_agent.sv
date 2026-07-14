//==========================================================================
// Master Agent - 主设备代理
//==========================================================================
// 【文件功能说明】
// 本文件实现了 AXI Master Agent，它是 UVM 标准架构中的核心组件。
// Agent 的作用是将相关的 driver、sequencer、monitor 封装在一起，
// 形成一个可复用的验证组件单元。
//
// 【UVM 标准架构知识点】
// UVM Agent 是验证环境的基本构建块，分为两种类型：
//   1. Active Agent: 包含 driver + sequencer + monitor
//      - 主动驱动接口信号
//      - 用于产生激励
//   2. Passive Agent: 只包含 monitor
//      - 只观察，不驱动
//      - 用于覆盖率收集和协议检查
//
// 本项目中的 Master Agent 是 Active Agent，因为它需要：
//   - 从 sequencer 获取事务
//   - 通过 driver 驱动信号到 DUT
//   - 通过 monitor 观察实际的总线行为
//
// 【Agent 的优势】
// 1. 可复用性：同一个 agent 可以在不同 testbench 中使用
// 2. 封装性：隐藏内部实现细节，外部只需配置接口
// 3. 灵活性：可以通过 is_active 配置切换 active/passive 模式
// 4. 标准化：符合 UVM 的最佳实践
//
// 【数据流】
// Sequence → Sequencer → Driver → DUT
//                 ↓
//              Monitor → Scoreboard/Coverage
//==========================================================================

class axi_mst_agent extends uvm_agent;
    // 【工厂注册】注册到 UVM 工厂
    `uvm_component_utils(axi_mst_agent)

    // ===== 组件句柄声明 =====

    // driver: 主设备驱动器
    // 负责将 sequence_item 转换为实际的 AXI 信号
    axi_mst_drv driver;

    // sequencer: 序列器
    // 负责管理和调度 sequence，为 driver 提供事务
    uvm_sequencer #(axi_txn) sequencer;

    // monitor: 监视器
    // 被动观察总线事务，用于覆盖率收集和协议检查
    axi_monitor monitor;

    // ===== 配置对象 =====

    // is_active: 控制 agent 是 active 还是 passive 模式
    // UVM_ACTIVE: 包含 driver + sequencer + monitor
    // UVM_PASSIVE: 只包含 monitor
    // 默认为 UVM_ACTIVE，可通过 config_db 在 test 层配置
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // vif: 虚拟接口，指向 DUT 的 AXI 接口
    virtual axi_if vif;

    // master_id: 标识这个 Agent 是哪个 Master（0~3）
    // 在 env 创建时通过 config_db 设置
    // 用于 Monitor 的来源标识，支持路由验证
    int master_id = 0;

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
        // Agent 的所有子组件共享同一个接口
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))

        // 从 config_db 获取 master_id（用于路由验证）
        uvm_config_db#(int)::get(this, "", "master_id", master_id);

        // 将虚拟接口传递给子组件
        // 使用相对路径 "" 表示从当前位置开始查找
        uvm_config_db#(virtual axi_if)::set(this, "driver", "vif", vif);
        uvm_config_db#(virtual axi_if)::set(this, "monitor", "vif", vif);

        // 设置 Monitor 的来源标识（用于路由验证）
        // Master Monitor: is_slave=0, source_id=master_id
        uvm_config_db#(int)::set(this, "monitor", "source_id", master_id);
        uvm_config_db#(bit)::set(this, "monitor", "is_slave", 0);

        // 创建 monitor (active 和 passive 模式都需要)
        monitor = axi_monitor::type_id::create("monitor", this);

        // 根据 is_active 配置创建 driver 和 sequencer
        if (is_active == UVM_ACTIVE) begin
            // Active 模式：创建 driver 和 sequencer
            driver    = axi_mst_drv::type_id::create("driver", this);
            sequencer = uvm_sequencer#(axi_txn)::type_id::create("sequencer", this);
        end
    endfunction

    // ================================================================
    // 【connect_phase - 连接阶段】
    // ================================================================
    // 在 connect_phase 中建立 driver 和 sequencer 之间的连接
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // 只有在 active 模式下才需要连接 driver 和 sequencer
        if (is_active == UVM_ACTIVE) begin
            // 连接 driver 的 seq_item_port 到 sequencer 的 seq_item_export
            // 这是 UVM 的标准 driver-sequencer 连接模式：
            //   driver 通过 seq_item_port.get_next_item() 从 sequencer 获取事务
            //   处理完后通过 seq_item_port.item_done() 通知 sequencer
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass
