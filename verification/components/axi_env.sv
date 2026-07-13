//==========================================================================
// Environment（验证环境）
// UVM验证组件：axi_env
// 功能：顶层验证环境，负责创建、配置和连接所有验证组件。
//       它定义了验证平台的拓扑结构（topology）。
// 原理：env是UVM验证平台的"骨架"，它包含：
//       - 驱动器（driver）：驱动AXI信号
//       - 监视器（monitor）：被动观测总线事务
//       - 序列器（sequencer）：产生事务序列
//       - 计分板（scoreboard）：校验数据正确性
//       - 覆盖率收集器（coverage）：收集功能覆盖率
//       本设计为 4 Master x 4 Slave 的AXI Crossbar，所以有4组驱动器和监视器。
// 继承自 uvm_env，是UVM的验证环境基类。
//==========================================================================
class axi_env extends uvm_env;
    // 工厂注册宏
    `uvm_component_utils(axi_env)

    // ===== 组件句柄声明 =====

    // mst_drv[4]：4个主机驱动器（Master Driver）
    // 每个驱动器负责一个主机端口，将sequence产生的事务转化为AXI信号驱动到DUT
    // 驱动器通过seq_item_port从sequencer获取事务
    axi_mst_drv    mst_drv[4];

    // slv_drv[4]：4个从机驱动器（Slave Driver）
    // 模拟从机（memory/peripheral）的行为，接收DUT发来的事务并返回响应
    // 从机驱动器不需要sequencer，它被动响应主机的请求
    axi_slv_drv    slv_drv[4];

    // mst_mon[4]：4个主机侧监视器（Master-side Monitor）
    // 放置在主机端口侧，观测主机发出的事务
    // 监视器是被动组件，不驱动任何信号
    axi_monitor    mst_mon[4];

    // slv_mon[4]：4个从机侧监视器（Slave-side Monitor）
    // 放置在从机端口侧，观测从机接收到的事务
    // 与主机侧监视器配合，可以验证crossbar的路由是否正确
    axi_monitor    slv_mon[4];

    // sqr[4]：4个序列器（Sequencer）
    // sequencer负责管理和调度sequence（事务序列）
    // driver通过seq_item_port从sequencer获取下一个要驱动的事务
    // 类型参数为axi_txn，表示序列器只处理axi_txn类型的事务
    uvm_sequencer #(axi_txn) sqr[4];

    // scbd：计分板（Scoreboard）- 单实例
    // 整个验证环境共享一个scoreboard，收集所有主机侧监视器的事务进行校验
    axi_scoreboard scbd;

    // cov：覆盖率收集器（Coverage Collector）- 单实例
    // 收集所有主机侧事务的功能覆盖率
    axi_coverage   cov;

    // slv_cfg[4]：从机配置对象数组
    // 每个从机驱动器需要独立的配置，例如：
    //   - 是否注入错误响应（error injection）
    //   - 从机的响应延迟设置
    //   - 内存大小等参数
    axi_slv_cfg    slv_cfg[4];

    // 构造函数
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // build_phase：构建阶段
    // 在此阶段创建所有子组件。UVM的build_phase是从上到下执行的：
    // test -> env -> 各子组件
    // 所有组件都通过工厂（type_id::create）创建，而非直接new()
    // 这样做的好处是支持factory override，可以在test层替换任何组件
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // 循环创建4组主机/从机的驱动器、监视器和序列器
        for (int i = 0; i < 4; i++) begin
            // 创建主机驱动器，名称如"mst_drv0", "mst_drv1"等
            // $sformatf用于格式化字符串，%0d表示不补零的十进制数
            mst_drv[i] = axi_mst_drv::type_id::create($sformatf("mst_drv%0d", i), this);

            // 创建从机驱动器
            slv_drv[i] = axi_slv_drv::type_id::create($sformatf("slv_drv%0d", i), this);

            // 创建主机侧监视器
            mst_mon[i] = axi_monitor::type_id::create($sformatf("mst_mon%0d", i), this);

            // 创建从机侧监视器
            slv_mon[i] = axi_monitor::type_id::create($sformatf("slv_mon%0d", i), this);

            // 创建序列器，类型参数为axi_txn
            sqr[i]     = uvm_sequencer#(axi_txn)::type_id::create($sformatf("sqr%0d", i), this);

            // 创建从机配置对象
            slv_cfg[i] = axi_slv_cfg::type_id::create($sformatf("slv_cfg%0d", i));

            // 通过uvm_config_db将从机配置传递给对应的从机驱动器
            // set()的参数：(上下文, 目标组件路径的相对路径, key, value)
            // 这里将slv_cfg[i]传递给"slv_drv<i>"组件，key为"cfg"
            // 从机驱动器在自己的build_phase中通过get()获取这个配置
            uvm_config_db#(axi_slv_cfg)::set(this, $sformatf("slv_drv%0d", i), "cfg", slv_cfg[i]);
        end

        // 创建scoreboard和coverage（各一个实例，全局共享）
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction

    // connect_phase：连接阶段
    // 在所有组件的build_phase完成后执行，用于建立组件间的通信连接
    // UVM的connect_phase是从下到上执行的：子组件 -> 父组件
    // 此阶段的核心任务是将analysis_port连接到analysis_imp/export
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        for (int i = 0; i < 4; i++) begin
            // 连接驱动器的seq_item_port到序列器的seq_item_export
            // 这是UVM的标准driver-sequencer连接模式：
            //   driver通过seq_item_port.get_next_item()从sequencer获取事务
            //   处理完后通过seq_item_port.item_done()通知sequencer
            mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);

            // 将主机侧监视器的analysis port连接到scoreboard的analysis imp
            // 当monitor广播事务时，scoreboard的write()会被调用
            // 只连接主机侧监视器，不连接从机侧监视器
            // 原因：同一笔事务如果同时从主机侧和从机侧采集，会导致重复计数
            mst_mon[i].ap.connect(scbd.imp);

            // 将主机侧监视器的analysis port连接到coverage的analysis_export
            // uvm_subscriber的analysis_export名称是固定的
            // 同样只连接主机侧监视器
            mst_mon[i].ap.connect(cov.analysis_export);

            // 注释说明：只连接主机侧监视器到scoreboard，避免重复计数
            // 从机侧监视器可用于交叉验证crossbar路由正确性
        end
    endfunction
endclass
