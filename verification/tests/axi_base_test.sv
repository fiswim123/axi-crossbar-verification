//==========================================================================
// Base Test — 所有 test 的基类
//==========================================================================
//
// 【文件作用】
//   定义所有测试用例的基类 axi_base_test。
//   所有具体的测试（如 axi_basic_test、axi_routing_test 等）都继承自这个基类。
//   基类负责创建验证环境（env），子类只需要专注于定义测试行为（run_phase）。
//
// 【UVM 知识点】
//   - uvm_test 是 UVM 验证平台的顶层组件，是仿真入口
//   - UVM 的 factory 机制允许通过类名动态创建对象（type_id::create）
//   - build_phase 是 UVM 组件的构建阶段，自顶向下依次调用
//
//==========================================================================

// 【类定义】axi_base_test 继承自 uvm_test
// uvm_test 是 UVM 测试用例的基类，所有测试都必须继承它
// 在仿真时通过 +UVM_TESTNAME=axi_xxx_test 指定运行哪个测试
class axi_base_test extends uvm_test;

    // 【工厂注册】将 axi_base_test 注册到 UVM 工厂
    // 这样 UVM 就能通过类名字符串来动态创建该类的实例
    // 例如：在命令行指定 +UVM_TESTNAME=axi_basic_test 时，工厂会创建对应的测试对象
    `uvm_component_utils(axi_base_test)

    // 【成员变量】验证环境句柄
    // axi_env 是顶层验证环境，包含所有验证组件（driver、monitor、scoreboard 等）
    // 在 build_phase 中创建，子类通过 env 访问所有验证组件
    axi_env env;

    // 【构造函数】
    // name: 组件实例名称（UVM 树中的节点名）
    // parent: 父组件句柄（对于 test，通常为 null，因为 test 是顶层）
    function new(string name, uvm_component parent);
        super.new(name, parent);  // 调用父类 uvm_test 的构造函数
    endfunction

    // 【构建阶段】build_phase
    // UVM 组件生命周期的第一个阶段，负责创建子组件
    // 调用顺序：自顶向下（先父后子）
    // 所有 type_id::create() 调用都应该放在这里
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);  // 必须先调用父类的 build_phase

        // 【创建验证环境】通过工厂机制创建 axi_env 实例
        // type_id::create 是 UVM 工厂的标准创建方式
        // 第一个参数 "env" 是实例名，第二个参数 this 表示当前组件是父组件
        env = axi_env::type_id::create("env", this);
    endfunction
endclass
