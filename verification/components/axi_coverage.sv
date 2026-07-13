//==========================================================================
// Coverage（覆盖率收集器）
// UVM验证组件：axi_coverage
// 功能：收集AXI事务的功能覆盖率（functional coverage），衡量验证的完备性。
// 原理：通过SystemVerilog的covergroup机制定义覆盖点（coverpoint）和
//       交叉覆盖（cross），在每次收到事务时采样。
//       覆盖率是验证的核心指标之一：当所有覆盖率bin都被命中时，
//       说明验证计划中的各种场景组合都已经被测试到。
// 继承自 uvm_subscriber，这是UVM专用于订阅analysis port的基类。
// uvm_subscriber 内建了 analysis_export 和 write() 接口。
//==========================================================================
class axi_coverage extends uvm_subscriber #(axi_txn);
    // 工厂注册宏
    `uvm_component_utils(axi_coverage)

    // txn：事务句柄，用于在write()和covergroup之间传递数据
    // covergroup的采样表达式可以直接引用这个变量
    axi_txn txn;

    // ===== covergroup：定义覆盖率模型 =====
    // covergroup是SystemVerilog的覆盖率收集容器
    // 内部包含coverpoint（覆盖点）和cross（交叉覆盖）
    // 每个coverpoint定义了需要观测的信号/变量及其合法值域（bins）
    covergroup cg;

        // cp_kind：事务类型覆盖点
        // 覆盖读和写两种操作类型，确保两种事务都被测试到
        // bins rd = {0}: 当txn.kind==0时命中读操作bin
        // bins wr = {1}: 当txn.kind==1时命中写操作bin
        cp_kind: coverpoint txn.kind {
            bins rd = {0}; bins wr = {1};
        }

        // cp_slave：目标从机覆盖点
        // AXI Crossbar有4个从机（slave 0~3），通过地址的高4位[15:12]选择
        // 确保每个从机都被访问到（地址路由正确性验证）
        cp_slave: coverpoint txn.addr[15:12] {
            bins s0 = {0}; bins s1 = {1}; bins s2 = {2}; bins s3 = {3};
        }

        // cp_master：发起主机覆盖点
        // AXI Crossbar有4个主机（master 0~3），通过事务ID的高位[7:4]标识
        // ID编码：1=master0, 2=master1, 3=master2, 4=master3
        // 确保每个主机都发起过事务
        cp_master: coverpoint txn.id[7:4] {
            bins m0 = {1}; bins m1 = {2}; bins m2 = {3}; bins m3 = {4};
        }

        // cp_len：突发长度覆盖点
        // AXI突发长度（burst length）= len + 1 拍
        // 将长度分为4个区间，覆盖单拍、短突发、中等突发、长突发
        // bins single = {0}: 单拍传输（len=0, 即1拍）
        // bins short = {[1:3]}: 短突发（2~4拍）
        // bins med = {[4:7]}: 中等突发（5~8拍）
        // bins long_b = {[8:15]}: 长突发（9~16拍）
        cp_len: coverpoint txn.len {
            bins single = {0}; bins short = {[1:3]};
            bins med    = {[4:7]}; bins long_b = {[8:15]};
        }

        // cp_size：数据宽度覆盖点
        // AXI的size参数表示每拍传输的字节数 = 2^size
        // bins b1 = {0}: 1字节（8位）传输
        // bins b2 = {1}: 2字节（16位）传输
        // bins b4 = {2}: 4字节（32位）传输
        cp_size: coverpoint txn.size {
            bins b1 = {0}; bins b2 = {1}; bins b4 = {2};
        }

        // cp_resp：响应覆盖点
        // 根据事务类型选择对应的响应信号：写事务用bresp，读事务用rresp
        // 使用三目运算符 ?: 根据txn.kind选择
        // bins okay = {0}: 覆盖正常响应（2'b00=OKAY）
        cp_resp: coverpoint (txn.kind ? txn.bresp : txn.rresp) {
            bins okay = {0};
        }

        // ===== 交叉覆盖（Cross Coverage） =====
        // cross覆盖多个覆盖点的组合，用于发现单一覆盖点无法检测的交互问题
        // 例如：主机A是否访问过从机B？读操作是否使用过长突发？

        // cx_routing：路由交叉覆盖
        // 主机 x 从机 的组合，验证所有 (master, slave) 路由路径都被测试
        // 4x4 crossbar应有 4*4=16 种路由组合
        cx_routing:   cross cp_master, cp_slave;

        // cx_kind_len：事务类型与突发长度的交叉
        // 验证读/写操作分别覆盖了不同长度的突发
        cx_kind_len:  cross cp_kind, cp_len;

        // cx_kind_size：事务类型与数据宽度的交叉
        // 验证读/写操作分别使用了不同大小的数据宽度
        cx_kind_size: cross cp_kind, cp_size;

        // cx_kind_slave：事务类型与目标从机的交叉
        // 验证每个从机都分别执行过读和写操作
        cx_kind_slave: cross cp_kind, cp_slave;
    endgroup

    // 构造函数
    // 注意：covergroup必须在构造函数中实例化（new()）
    // covergroup的new()会在构造时注册该covergroup到覆盖率数据库
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg = new();  // 实例化covergroup，开始跟踪覆盖率
    endfunction

    // write：事务接收回调函数
    // 继承自 uvm_subscriber，当analysis port广播事务时被自动调用
    // 步骤：
    //   1. 将接收到的事务赋值给成员变量txn（供covergroup采样表达式使用）
    //   2. 调用cg.sample()触发覆盖率采样
    //      sample()会计算所有coverpoint和cross的当前值并更新覆盖率统计
    function void write(axi_txn t);
        txn = t;      // 更新事务引用
        cg.sample();  // 触发覆盖率采样
    endfunction

    // report_phase：报告阶段
    // 在仿真结束时打印总覆盖率百分比
    // cg.get_coverage()返回所有coverpoint和cross的综合覆盖率（0~100%）
    // 覆盖率 = 已命中的bins数 / 总bins数 * 100%
    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Coverage: %.1f%%", cg.get_coverage()), UVM_LOW)
    endfunction
endclass
