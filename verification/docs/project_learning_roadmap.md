# AXI Crossbar UVM 项目学习路线与面试指南

> 面向数字 IC 验证初学者。本教程不是对代码注释的简单复述，而是用本项目解释标准 UVM 机制，并指出当前实现与成熟验证平台之间的差距。

## 0. 怎么使用这份文档

这份文档按八个阶段组织。每个阶段都包含五部分：

1. 要掌握的知识；
2. 本项目中的代码入口；
3. 代码运行原理；
4. 当前实现的局限或错误；
5. 动手练习和面试问答。

建议不要一次背完。每完成一个阶段，都做三件事：画出数据流、在波形中找到对应信号、脱离代码口述原理。

### 0.1 项目规格

- 4 个上游 AXI Master 端口；
- 4 个下游 AXI Slave 端口；
- 地址宽度 16 bit，数据宽度 32 bit，ID 宽度 8 bit；
- 地址窗口：`0x0000~0x0FFF`、`0x1000~0x1FFF`、`0x2000~0x2FFF`、`0x3000~0x3FFF`；
- 五个 AXI 通道：AW、W、B、AR、R。

本项目把 DUT 上游端口命名为 `slv0~slv3`，因为从 DUT 视角它们是 slave ports；验证环境把这些接口称为 `mst_if`，因为接口外面连接的是 master BFM。两种命名描述的是不同视角，不矛盾。

### 0.2 平台全景图

```text
axi_crossbar_tb (module 世界)
├── clock/reset
├── mst_if[0..3] ── Master Agent[0..3]
├── DUT
└── slv_if[0..3] ── Slave Agent[0..3]

uvm_test_top (class 世界)
└── env
    ├── mst_agent[0..3]
    │   ├── sequencer
    │   ├── driver
    │   └── monitor ──┬──> scoreboard.mst_imp
    │                 └──> coverage.analysis_export
    ├── slv_agent[0..3]
    │   ├── responder/driver
    │   └── monitor ─────> scoreboard.slv_imp
    ├── scoreboard
    └── coverage
```

### 0.3 一笔事务的主路径

```text
Test.start(sequence)
        ↓
Sequence 创建 axi_txn
        ↓ start_item / finish_item
Sequencer 仲裁
        ↓ get_next_item
Master Driver 把 txn 转成 AW/W/B 或 AR/R 时序
        ↓
DUT 地址译码、仲裁和路由
        ↓
Slave Driver 模拟存储器并返回响应
        ↓
两侧 Monitor 从握手信号重建 txn
        ↓ analysis_port.write
Scoreboard 比较 + Coverage 采样
```

---

## 阶段一：SystemVerilog 验证基础

### 1.1 学习目标

完成本阶段后，应能解释：

- class、object、handle 的区别；
- 静态数组、动态数组、队列、关联数组的用途；
- `rand`、constraint、`randomize with` 的工作方式；
- `task` 和 `function` 的区别；
- `fork/join`、`fork/join_none` 和线程变量生命周期；
- interface、modport、virtual interface 的作用。

### 1.2 从 `axi_txn` 学 class 和 handle

入口：[components/axi_txn.sv](../components/axi_txn.sv)

```systemverilog
class axi_txn extends uvm_sequence_item;
    rand bit [15:0] addr;
    rand bit [7:0]  len;
    rand bit [31:0] wdata[];
    bit [31:0]      rdata[];
endclass
```

`axi_txn txn;` 只声明一个句柄，不会自动创建对象。创建对象需要：

```systemverilog
txn = axi_txn::type_id::create("txn");
```

两个句柄可以指向同一对象：

```systemverilog
axi_txn a, b;
a = axi_txn::type_id::create("a");
b = a;
b.addr = 16'h1000; // a.addr 也变成 0x1000
```

这不是对象复制。需要独立副本时应使用 `clone()`、`copy()` 或显式复制字段。这个知识对 analysis port 很重要：如果发送方在 `write(txn)` 后继续修改同一个对象，接收方队列中保存的也可能随之改变。本项目 monitor 每笔事务都重新创建对象，因此当前路径没有这个问题，但成熟 monitor 通常仍会明确所有权或发送 clone。

### 1.3 三种容器在本项目里的用途

| 类型 | 项目示例 | 适用场景 |
|---|---|---|
| 动态数组 | `wdata[]`、`rdata[]` | burst 长度运行时才能确定 |
| 队列 | scoreboard 的 `mst_wr_txns[$]` | 按时间不断 push/pop 的事务流 |
| 关联数组 | `mem[bit [31:0]]`、`exp_data[bit [31:0]]` | 稀疏地址空间的内存模型 |

动态数组必须先分配：

```systemverilog
txn.wdata = new[txn.len + 1];
```

队列用 `push_back()` 插入，用 `pop_front()` 或 `delete(index)` 删除。关联数组读取前最好使用 `exists(address)` 判断该地址是否有期望值，否则默认值可能掩盖“从未写过”的错误。

### 1.4 约束随机化

[components/axi_txn.sv](../components/axi_txn.sv) 中所有 constraint 默认同时生效：

```systemverilog
constraint c_basic         { ... }
constraint c_boundary_addr { addr inside {...}; }
constraint c_boundary_burst{ len inside {0,1,3,7,15}; }
constraint c_boundary_id   { id inside {...}; }
```

这意味着 `c_boundary_addr` 并不是“只有边界测试才开启”，而是限制了每一次 `randomize()`。如果想让普通随机测试覆盖整个合法地址空间，应在边界测试前后调用：

```systemverilog
txn.c_boundary_addr.constraint_mode(0); // 普通随机
txn.c_boundary_addr.constraint_mode(1); // 专项边界测试
```

或者把不同场景写成派生 transaction。

项目中的 [sequences/axi_concurrent_seq.sv](../sequences/axi_concurrent_seq.sv) 又追加了：

```systemverilog
addr inside {16'h0100, 16'h0200, 16'h0400, 16'h0800};
```

这些地址与默认开启的 `c_boundary_addr` 没有交集，因此随机化会失败。另外四个地址的高 4 bit 都是 0，实际上全部访问 Slave 0，并非注释所说的四个 slave。工程上不能只写 `assert(req.randomize())` 后继续运行；失败应成为明确的测试失败，例如：

```systemverilog
if (!req.randomize() with {...})
    `uvm_fatal("RANDFAIL", "axi_txn randomization failed")
```

### 1.5 并发线程与共享句柄

[tests/axi_multi_master_test.sv](../tests/axi_multi_master_test.sv) 在 `fork` 外声明了一个 `axi_wr_seq seq`，四个线程同时给它赋值。`seq` 是共享句柄，存在竞争：一个线程创建完 m0 后，另一个线程可能把同一变量改成 m1，然后第一个线程再调用 `seq.start()`。

更稳妥的写法是在每个并发块中声明局部句柄：

```systemverilog
fork
    begin
        axi_wr_seq seq0;
        seq0 = axi_wr_seq::type_id::create("m0");
        seq0.start(env.mst_agent[0].sequencer);
    end
    begin
        axi_wr_seq seq1;
        seq1 = axi_wr_seq::type_id::create("m1");
        seq1.start(env.mst_agent[1].sequencer);
    end
join
```

类似地，`axi_concurrent_seq` 的两个线程共享继承自 `uvm_sequence` 的 `req` 句柄，也存在竞争。面试时看到 `fork`，第一反应应是检查共享变量、`automatic` 生命周期和线程结束条件。

### 1.6 interface、modport 与 virtual interface

入口：[infra/axi_if.sv](../infra/axi_if.sv)

- interface 把一组 AXI 信号封装在一起；
- modport 从不同角色规定信号方向；
- virtual interface 是 class 世界保存物理 interface 实例的句柄；
- 当前 driver 声明的是 `virtual axi_if vif`，没有使用 modport 限定方向，因此 class 代码不会得到严格的方向保护；
- 当前 interface 没有 clocking block，driver 和 monitor 都直接在 `posedge` 附近驱动/采样，容易出现 testbench 与 DUT 的仿真竞争。成熟 VIP 通常通过 clocking block 明确 input/output skew。

### 1.7 本阶段练习

1. 画出 `wdata[]` 在 `len=3` 时的数组长度和四个元素。
2. 写一个实验，证明 `b = a` 是句柄赋值而不是深拷贝。
3. 找出项目中所有 `fork`，检查是否共享 sequence、transaction 或循环变量。
4. 临时打印 `req.randomize()` 返回值，验证 `axi_concurrent_seq` 的约束冲突。

### 1.8 面试问答

**问：function 和 task 有什么区别？**

答：function 不能消耗仿真时间，不能包含 `#`、`@` 或阻塞 task；task 可以消耗时间。UVM 的 `build_phase`、`connect_phase`、`check_phase` 是 function phase，`run_phase` 以及 reset/main/shutdown 等 runtime phase 是 task phase。

**问：`fork/join_none` 后局部变量为什么常加 `automatic`？**

答：父线程会继续执行后续循环，如果子线程共享同一个循环变量或句柄，等子线程真正使用它时值可能已经改变。`automatic` 为每次迭代保存独立副本，但对象句柄本身是否共享仍要单独检查。

---

## 阶段二：UVM 平台骨架

### 2.1 学习目标

- 理解 `uvm_object` 与 `uvm_component`；
- 理解 factory、phase、config_db 和 objection；
- 能从 `uvm_test_top` 画出完整组件树；
- 知道 module 世界与 class 世界如何连接。

### 2.2 object 和 component

| 对比 | `uvm_object` | `uvm_component` |
|---|---|---|
| 项目实例 | txn、sequence、slave cfg | test、env、agent、driver、monitor |
| 是否有固定层次 | 否 | 是，有 parent |
| 生命周期 | 按需创建 | 主要由 phase 管理 |
| 构造函数 | `new(string name="...")` | `new(string name, uvm_component parent)` |
| 注册宏 | `uvm_object_utils` | `uvm_component_utils` |

Sequence 也是 object，不在 UVM component topology 中。Sequencer 是 component，两者不要混淆。

### 2.3 testbench top：两个世界的桥

入口：[tb/axi_crossbar_tb.sv](../tb/axi_crossbar_tb.sv)

顶层 module 完成：

1. 生成 100 MHz 时钟和复位；
2. 实例化 4 个 `mst_if` 与 4 个 `slv_if`；
3. 实例化 `axicb_crossbar_top`；
4. 把 interface 放进 `uvm_config_db`；
5. 调用 `run_test("axi_basic_test")`。

命令行 `+UVM_TESTNAME=axi_xxx_test` 用来选择具体 test。`run_test()` 随后建立 `uvm_test_top` 并执行 UVM phases。

### 2.4 package 与编译顺序

入口：[infra/axi_pkg.sv](../infra/axi_pkg.sv)

`axi_pkg` 先 import `uvm_pkg::*`，再按依赖顺序 include：

```text
cfg/txn
  ↓
driver/monitor/scoreboard/coverage
  ↓
agent/env
  ↓
sequence
  ↓
test
```

SystemVerilog 编译器读到一个类型前必须已经知道它的定义，因此 include 顺序不是装饰。更大型项目也可把文件分别编译进同一个 package，但仍需要 file list 管理依赖。

### 2.5 factory 的真实价值

项目统一使用：

```systemverilog
axi_env::type_id::create("env", this);
axi_txn::type_id::create("txn");
```

Factory 根据“请求类型 + 实例路径”决定实际创建的类型。它允许 test 不修改 env 源码，就把基础 driver 或 transaction 替换为派生类。

面试中不要只回答“factory 用来创建对象”。关键是：

> Factory 把调用者与具体实现解耦，支持 type override 和 instance override；前提是类型使用对应 utils 宏注册，并通过 `type_id::create` 创建。

### 2.6 phase 执行过程

本项目最重要的 phases：

```text
build_phase     自顶向下创建组件、读取配置
connect_phase   自底向上连接 TLM 端口
end_of_elaboration / start_of_simulation
run_phase       各 component 的 run_phase 并行执行
extract_phase
check_phase     scoreboard 做最终一致性检查
report_phase    汇总结果和覆盖率
final_phase
```

`run_phase` 不是与 `build_phase` 并行；它是在 build/connect 等结构阶段完成后开始。不同 component 的 `run_phase` 彼此并行。

[tests/axi_basic_test.sv](../tests/axi_basic_test.sv) 使用：

```systemverilog
phase.raise_objection(this);
...
phase.drop_objection(this);
```

Objection 控制 task phase 何时允许结束。它不是等待每笔 AXI 事务的同步机制。忘记 raise 可能导致测试过早结束，忘记 drop 可能导致仿真挂死。

### 2.7 config_db 的设置与查找

顶层设置物理接口：

```systemverilog
uvm_config_db#(virtual axi_if)::set(
    null, "*.mst_agent0", "vif", mst_if[0]);
```

Agent 在自己的 `build_phase` 中 get，然后继续 set 给子组件：

```text
tb set vif → mst_agent0 get vif
                  ├─ set driver.vif
                  └─ set monitor.vif
```

env 也用 config_db 把 `master_id`、`slave_id` 和 `axi_slv_cfg` 传给 agent。类型、字段名和实例路径必须同时匹配。路径写得过宽可能让错误组件拿到配置，写得过窄则 `get()` 失败。

成熟环境通常定义 env config 和 agent config，将 active/passive、vif、地址映射等集中管理，避免散落大量字符串路径。

### 2.8 Agent 的 active/passive 模式

[components/axi_mst_agent.sv](../components/axi_mst_agent.sv) 中 active agent 创建：

- sequencer；
- driver；
- monitor。

Passive agent 只创建 monitor，适合旁路观察真实 master。

当前 `is_active` 是 agent 内部普通变量，未从 config_db 获取，因此外部还不能真正配置 passive 模式。Slave agent 的 responder 没有 sequencer，却继承 `uvm_driver#(axi_txn)`；功能上可以工作，但用 `uvm_component` 或专用 responder 基类更能表达它并不消费 sequence item。

### 2.9 本阶段练习

1. 加 `uvm_top.print_topology()`，把实际 topology 与本文架构图对照。
2. 在 driver 的 `build_phase` 打印 `get_full_name()`，理解 config_db 路径。
3. 写一个派生 transaction，并用 type override 验证 factory 替换。
4. 把一个 master agent 配成 passive，思考哪些组件不应创建。

### 2.10 面试问答

**问：为什么 class 不能直接连接 DUT 端口？**

答：DUT/interface 是静态 elaboration 的 module 世界，UVM component 是运行时 class 对象。顶层 module 实例化真实 interface，再通过 config_db 把 virtual interface 句柄交给 class。

**问：build_phase 为什么常用 factory create，而不是 `new`？**

答：组件用 factory 创建后才能被 test 做类型或实例替换，同时 factory 会维护正确的 UVM component 创建流程和层次。

---

## 阶段三：Transaction、Sequence、Sequencer 与 Driver 握手

### 3.1 学习目标

- 理解 sequence item 表达“做什么”，driver 表达“怎么做”；
- 理解 sequencer 的仲裁职责；
- 掌握 `start_item/finish_item` 和 `get_next_item/item_done`；
- 区分 sequence 并发、总线并发和 outstanding。

### 3.2 transaction 建模

[components/axi_txn.sv](../components/axi_txn.sv) 把读写放在同一个类型中，用 `kind` 区分，并包含请求、响应、性能和来源字段。

优点是 sequence/driver 类型统一；缺点是某些字段只对读或写有意义，约束也更难管理。成熟建模需要至少补齐：

- 每拍 `rresp`，而不是整笔事务只有一个 `rresp`；
- `WLAST/RLAST` 观测结果；
- byte address 计算方法；
- response status 和 aborted/reset 状态；
- 事务开始、各通道握手和结束的时间戳。

### 3.3 一笔写 sequence

[sequences/axi_wr_seq.sv](../sequences/axi_wr_seq.sv) 的核心：

```systemverilog
txn = axi_txn::type_id::create("txn");
txn.kind = axi_txn::WRITE;
txn.addr = s_addr;
...
start_item(txn);
finish_item(txn);
```

标准握手：

```text
sequence.start_item(req)
    ↓ 请求 sequencer grant，可能阻塞
sequence 填充或随机化 req
sequence.finish_item(req)
    ↓ 把 item 交给 sequencer，并等待 driver item_done
driver.get_next_item(req)
driver.drive(req)
driver.item_done()
    ↓ finish_item 返回
```

本项目固定 sequence 在 `start_item` 前已经填完字段，这可以工作。约束随机 sequence 常在获得 grant 后 randomize，减少 item 在等待仲裁期间被修改的风险。

### 3.4 Sequencer 不生成激励

Agent 创建的是通用 `uvm_sequencer#(axi_txn)`。Sequencer 的核心职责是：

- 接收一个或多个 sequence 的 item 请求；
- 按优先级和仲裁策略发放 grant；
- 通过 export 与 driver 的 port 建立拉取式通信。

“Sequencer 产生 transaction”是常见错误回答。真正创建 transaction 的通常是 sequence。

### 3.5 `finish_item` 返回代表什么

当前 [components/axi_mst_drv.sv](../components/axi_mst_drv.sv) 在完整等待 B 或 R 后才调用 `item_done()`。所以本项目中 `finish_item` 返回时，这笔事务的总线响应已经完成。

但这是当前 driver 的实现选择，不是 UVM 对 `finish_item` 的固定承诺。高性能 driver 可以在请求被接受后就 `item_done()`，响应通过 `put_response()`/`get_response()` 或独立 analysis path 返回。

### 3.6 为什么当前 outstanding 不成立

[tests/axi_outstanding_test.sv](../tests/axi_outstanding_test.sv) 并发启动多个 sequence，但 driver 的逻辑是：

```text
get item 0 → AW0 → W0 → 等 B0 → item_done
get item 1 → AW1 → W1 → 等 B1 → item_done
```

因此任意时刻只有一笔未完成请求。多个 sequence 只是在 sequencer 前排队，不等于总线上有多个 outstanding。

真正的写 outstanding 应近似为：

```text
请求线程：get item → 发 AW/W → 保存 pending[id] → item_done
响应线程：收 B → 按 BID 找 pending → 返回 response
```

读 outstanding 同理，AR 发送线程不能等待整笔 R 返回后才取下一笔 item。

### 3.7 多 Master 并发与单 Master outstanding

这两个概念必须分开：

- `axi_multi_master_test` 在四个不同 sequencer/driver 上启动 sequence，确实可能形成四个 master 的物理并发；
- 同一个 sequencer 上并发启动四个 sequence，在当前串行 driver 下只形成仲裁排队；
- AXI outstanding 指同一个接口在前一请求完成前继续发出新请求。

### 3.8 本阶段练习

1. 给 sequence 和 driver 的四个握手点加 transaction ID 日志。
2. 在波形中证明当前同一 master 的第二个 AW 一定晚于第一个 B。
3. 修改 sequence，让它通过 `get_response()` 接收 driver response，理解 request/response 分离。
4. 画出支持 4 笔读 outstanding 所需的 pending 数据结构。

### 3.9 面试问答

**问：`get_next_item/item_done` 与 `get` 有什么区别？**

答：`get_next_item` 取得的 item 在调用 `item_done` 前仍处于 sequencer-driver 握手中，必须配对；`get` 相当于取走请求并立即完成该握手，driver 后续不能再为同一 item 调 `item_done`。实际项目应统一选定模式，避免混用。

**问：如何判断一个测试是否真的产生 outstanding？**

答：看波形或 driver 架构：是否在 B/R 完成前出现新的 AW/AR 握手，并用 ID/队列可靠追踪未完成请求。仅看多个 sequence 被 fork 启动无法证明。

---

## 阶段四：AXI 五通道 Driver 与 Responder

### 4.1 学习目标

- 掌握 VALID/READY 握手；
- 掌握 AXI 写、读通道之间的依赖和独立性；
- 理解 burst、size、strobe、LAST、response 和 ID；
- 理解 backpressure、reset 和并发 driver 架构。

### 4.2 VALID/READY 基本规则

一次传输只在时钟上升沿满足以下条件时发生：

```text
VALID == 1 && READY == 1
```

发送方必须做到：

- 不能等待 READY 后才首次拉高 VALID；
- VALID 拉高但未握手时必须保持 VALID；
- payload 必须在等待期间稳定。

接收方可以自由拉高或拉低 READY，从而施加 backpressure。

### 4.3 当前 Master Driver

入口：[components/axi_mst_drv.sv](../components/axi_mst_drv.sv)

写操作当前严格串行：

```text
AW handshake → 全部 W beats → B handshake
```

读操作当前严格串行：

```text
AR handshake → 全部 R beats
```

作为最小 BFM，这容易理解；作为 AXI4 VIP，它有以下局限：

- AW 和 W 本来是独立通道，当前不能并行；
- 写和读本来可以同时进行，单个 run loop 让它们互斥；
- 不能 outstanding；
- 没有检查 BID/RID 是否匹配请求 ID；
- 没有检查 WLAST/RLAST 是否在正确拍出现；
- 没有 reset 监测，传输中复位时线程可能继续等待握手；
- 没有可配置的 BREADY/RREADY backpressure。

### 4.4 当前 Slave Responder

入口：[components/axi_slv_drv.sv](../components/axi_slv_drv.sv)

它用两个线程并行处理写和读，体现 AXI 读写通道独立：

```systemverilog
fork
    wr_handler();
    rd_handler();
join
```

它用 byte-addressed 关联数组模拟存储器，但写入时始终写 4 byte：

```systemverilog
mem[addr]   = wdata[7:0];
...
mem[addr+3] = wdata[31:24];
addr += 4;
```

这会忽略：

- `WSTRB` 哪些字节有效；
- `AxSIZE` 是 1、2 还是 4 byte；
- FIXED/WRAP burst 的地址规则；
- 窄传输 lane 与地址低位的关系。

因此 `axi_burst_size_seq` 即使通过，也不能证明窄传输正确。

### 4.5 Burst 地址计算

AXI 中每拍字节数：

```text
bytes_per_beat = 1 << AxSIZE
beats          = AxLEN + 1
```

INCR burst 的下一拍地址通常增加 `bytes_per_beat`；不能固定 `+4`。WRAP 还必须在规定的 wrap boundary 内回绕；burst 不能跨越 4 KB 边界。

本设计把 slave 下游基地址去掉。顶层将 `SLVx_KEEP_BASE_ADDR=0`，RTL [../src/axicb_mst_if.sv](../../src/axicb_mst_if.sv) 执行：

```systemverilog
o_awaddr = awaddr - BASE_ADDR;
o_araddr = araddr - BASE_ADDR;
```

例如上游 `0x2004` 路由到 Slave 2 后，下游看到的是局部地址 `0x0004`。

### 4.6 Backpressure 测试审查

[components/axi_slv_cfg.sv](../components/axi_slv_cfg.sv) 只定义了：

- AWREADY backpressure；
- WREADY backpressure；
- ARREADY backpressure。

而 BREADY、RREADY 由 master 驱动，必须在 master agent 配置。当前 [tests/axi_backpressure_test.sv](../tests/axi_backpressure_test.sv) 的“R Channel”和“B Channel”段落没有实际配置 RREADY/BREADY，所谓“All Channel”也只设置了 WREADY。因此测试名称不能替代真实激励和检查。

### 4.7 错误注入测试审查

[tests/axi_error_test.sv](../tests/axi_error_test.sv) 配置的是 `env.slv_cfg[0]`，但 DECERR 和恢复事务访问 `0x1000/0x2000`，分别被路由到 Slave 1/2。对应 responder 不会读取 Slave 0 的配置，所以预期错误可能根本没有注入。

另外，DECERR 一般由 interconnect 对未映射地址产生；让已选中的 slave responder 返回 DECERR 可以测试响应传播，但不能证明 crossbar 的地址 decode error 行为。

### 4.8 Reset 测试审查

顶层 module 持续根据全局 `aresetn` 驱动各 interface 的复位；[tests/axi_reset_test.sv](../tests/axi_reset_test.sv) 又从 class 侧直接给同一 `vif.aresetn` 赋值，形成多过程驱动/调度竞争。更合理的做法是：

- 顶层提供唯一 reset 驱动源；
- test 通过 reset interface 或 reset agent 发请求；
- driver、responder、monitor 在复位到来时清空输出和 pending 状态；
- scoreboard 定义 reset 时是否清空内存模型与未完成事务。

### 4.9 本阶段练习

1. 为单拍写画出 AW/W/B 波形，标注每个握手沿。
2. 把 slave memory model 改成按 WSTRB 更新字节。
3. 增加 `size=0/1/2` 的地址递增函数并为其写单元测试。
4. 给 master config 增加 BREADY/RREADY backpressure。
5. 设计传输中 reset 的退出策略，避免 driver 永久阻塞。

### 4.10 面试问答

**问：VALID 可以依赖 READY 吗？**

答：不可以。源端必须独立声明数据有效，否则双方都等待对方可能死锁；READY 可以依赖 VALID，但为了性能通常可以提前拉高。

**问：AW 与 W 必须谁先发生？**

答：AXI 不规定固定先后，两条通道独立，AW 可以先、W 可以先、也可同周期握手。接收端必须正确关联写地址和写数据。当前项目为了简化固定 AW 后 W，不代表协议要求。

---

## 阶段五：Monitor 与事务重组

### 5.1 学习目标

- 理解 monitor 为什么必须被动；
- 理解 pin-to-transaction 转换；
- 掌握 analysis port 的广播语义；
- 能设计支持 outstanding/乱序返回的 monitor。

### 5.2 当前 Monitor 工作方式

入口：[components/axi_monitor.sv](../components/axi_monitor.sv)

`run_phase` 同时启动 `mon_wr()` 和 `mon_rd()`，因此读写可以并行观察。写 monitor：

```text
等一个 AW → 创建 txn
等 len+1 个 W → 填 wdata/wstrb
等一个 B → 填 bid/bresp
ap.write(txn)
```

读 monitor：

```text
等一个 AR → 创建 txn
等 len+1 个 R → 填 rdata/rid/rresp
ap.write(txn)
```

Monitor 只在 `VALID && READY` 的边沿采样，这是正确的基本原则。它还从 config_db 得到 `source_id`，告诉 scoreboard 事务来自哪个 master/slave 侧端口。

### 5.3 analysis port

`uvm_analysis_port#(axi_txn)` 是非阻塞的一对多广播：

```systemverilog
ap.write(txn);
```

所有已连接 subscriber/imp 的 `write()` 会在同一调用栈中依次执行。`write()` 是 function，接收方不能在里面等待时钟。耗时处理应把事务 clone 后放进 queue 或 `uvm_tlm_analysis_fifo`，再由独立 task 消费。

### 5.4 当前 Monitor 为什么不支持 outstanding

`mon_wr()` 在收到一个 AW 后便停止监听新 AW，直到收齐 W 和 B。若总线上在 B 返回前又握手了 AW2，它会直接漏掉。

支持 outstanding 的典型结构：

```text
AW monitor ──> aw_queue（按 AXI4 W 顺序）
W monitor  ──> 用 WLAST 完成当前写数据包
B monitor  ──> 按 BID 匹配 pending write

AR monitor ──> pending_reads[RID] queue
R monitor  ──> 按 RID 累积数据，RLAST 时完成 transaction
```

同一 ID 的响应必须保持协议要求的顺序；不同 ID 可以乱序。不能只用一个全局当前 transaction。

### 5.5 必须检查 LAST，而不是只相信 LEN

当前 monitor 根据 AWLEN/ARLEN 固定循环若干拍，却没有验证：

- WLAST 是否恰好出现在最后一个 W beat；
- RLAST 是否恰好出现在最后一个 R beat；
- 是否提前 LAST；
- 是否缺少 LAST；
- 每拍 RID/RRESP 是否符合预期。

一种职责划分是：monitor 记录“观察到的 LAST”，protocol checker/SVA 报协议错误；scoreboard 只消费已重建事务。无论如何，错误不能因为 monitor 自己按 LEN 截断而被掩盖。

### 5.6 Master 侧与 Slave 侧双观察

Crossbar 验证需要两类检查：

1. 端到端数据检查：上游请求最终响应是否正确；
2. 路由检查：某笔上游请求是否只出现在正确的下游端口。

因此本项目两侧都放 monitor 是合理的。需要注意下游地址可能是局部地址，ID 也可能经过 crossbar 扩展/掩码，scoreboard 不能直接假设所有字段逐位相等。

### 5.7 本阶段练习

1. 把 AW、W、B 采集拆成三个并行任务。
2. 用队列保存两个 AW，再让 B 延迟返回，确认 monitor 不漏事务。
3. 给读 monitor 增加提前/缺失 RLAST 检查。
4. 比较 analysis imp、subscriber 和 analysis FIFO 的使用场景。

### 5.8 面试问答

**问：Monitor 为什么不能从 driver 接收期望 transaction 后直接转发？**

答：那样只能证明 driver 想发送什么，不能证明 DUT 引脚实际上发生了什么。Monitor 必须独立观察接口握手，才能发现 driver、连接、协议或 DUT 的问题。

**问：analysis port 会不会阻塞？**

答：`write()` 本身是 function，不能消耗仿真时间；但订阅者中复杂的同步计算仍会占用当前调用栈。需要解耦时使用 analysis FIFO，并注意对象 clone。

---

## 阶段六：Scoreboard、Reference Model 与自检闭环

### 6.1 学习目标

- 区分 monitor、predictor/reference model 和 comparator；
- 能建立 byte-accurate memory model；
- 能处理地址转换、ID、顺序和乱序；
- 能定义严格且无 false pass 的通过标准。

### 6.2 当前 Scoreboard 架构

入口：[components/axi_scoreboard.sv](../components/axi_scoreboard.sv)

因为同时接收 master/slave 两类事务，文件用：

```systemverilog
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)
```

生成两个不同的 `write_master()`、`write_slave()` 回调。这是一个 scoreboard 接收同类型多来源事务的常用方法。

当前模型有：

- Master/Slave 写事务队列；
- `exp_data[address]` 期望表；
- 路由、读写和延迟计数器；
- `check_phase` 末尾匹配写事务。

### 6.3 当前 false pass

现有 `sim.log` 同时出现：

```text
No matching Slave txn ...
Unmatched Slave txn ...
RD: 0 pass / 0 fail
ALL CHECKS PASSED - TEST PASSED
```

原因有三类。

第一，读事务分支只增加 `mst_rd_cnt`，没有使用 `rdata` 与 `exp_data` 比较，也没有增加 `rd_pass/rd_fail`。

第二，未匹配事务只调用 `uvm_warning`，没有增加 `route_fail`，最终报告不会失败。

第三，路由匹配直接要求上下游地址相等，但 DUT 在 `KEEP_BASE_ADDR=0` 时会把全局地址转换成局部地址。例如：

```text
Master side: addr = 0x2000
expected slave = 2
Slave  side: addr = 0x0000
```

这本应匹配为同一笔事务。

### 6.4 一个正确的 reference model 应预测什么

对写请求：

1. 根据全局地址预测目标 slave；
2. 预测下游局部地址；
3. 根据 burst/size 计算每拍地址；
4. 仅按 WSTRB 更新有效字节；
5. 如果 response 为 OKAY，提交内存模型；错误写是否修改内存必须按规格定义；
6. 检查 B response 和 BID。

对读请求：

1. 从 reference memory 取得期望字节；
2. 根据 size 和 lane 拼成期望 RDATA；
3. 每拍比较 RDATA/RRESP/RID；
4. 最后一拍检查 RLAST；
5. 未初始化地址要有明确策略，例如返回 0、X 或跳过比较，不能含糊。

### 6.5 路由比较键

当前只用“地址 + 第一拍数据”查找，很容易在重复地址、重复数据或并发时误配。更好的比较键包括：

- 来源 master；
- 请求 ID；
- 目标 slave；
- 规范化后的地址；
- burst 属性；
- 完整数据和 strobe；
- 同 ID 内的序号。

若 DUT 修改 ID，需要显式建模 ID 映射，而不是硬比较原始 ID。

### 6.6 In-order 与 out-of-order scoreboard

简单 in-order 场景可以用两个 `uvm_tlm_analysis_fifo`：每次从 expected/actual 各取一笔比较。

支持乱序时不能只按到达顺序比较，应按 ID 等 key 保存 pending queues：

```text
expected[id].push_back(txn)
actual response id 到达
    → 从 expected[id] 取该 ID 最早一笔
    → 比较并删除
```

仿真结束时所有 pending queue 必须为空，否则代表请求丢失或响应丢失。

### 6.7 通过标准必须严格

最终 PASS 至少要求：

- `UVM_ERROR == 0` 且 `UVM_FATAL == 0`；
- assertion failure 为 0；
- 所有期望事务均匹配；
- 没有意外的 actual 事务；
- 所有 pending queue 清空；
- 读写比较计数符合 test 预期，不能出现 `0 pass / 0 fail` 的空通过；
- test 未超时；
- 必需覆盖目标达到门限。

### 6.8 本阶段练习

1. 修复下游局部地址归一化，使 basic test 四条路由全部匹配。
2. 按 byte 和 WSTRB 重写 reference memory。
3. 给读事务增加逐 beat 比较并维护 `rd_pass/rd_fail`。
4. 把所有 unmatched warning 升级为计数失败。
5. 故意篡改一拍 RDATA，证明测试必然 FAIL。

### 6.9 面试问答

**问：Scoreboard 的期望值应该来自哪里？**

答：应由规格驱动的独立 reference model 根据输入事务预测，不能直接读取 DUT 内部实现。Crossbar 项目至少要独立预测地址 decode、地址转换、数据内容、响应和顺序规则。

**问：为什么不能只检查 response 是 OKAY？**

答：错误路由、数据损坏、事务丢失、重复响应都可能仍返回 OKAY。必须同时检查数量、身份、路径、数据和协议属性。

---

## 阶段七：Functional Coverage 与 SVA

### 7.1 学习目标

- 区分代码覆盖率、功能覆盖率和断言覆盖率；
- 能从 verification plan 推导 coverpoints/cross；
- 能写基本 AXI 时序断言；
- 理解覆盖率高不等于功能正确。

### 7.2 三种覆盖率

| 类型 | 回答的问题 | 示例 |
|---|---|---|
| 代码覆盖 | RTL 哪些结构执行过 | line、branch、condition、FSM、toggle |
| 功能覆盖 | 验证计划场景是否发生过 | master × slave、read/write × burst length |
| 断言覆盖 | 协议属性是否被触发/满足 | VALID 等待 READY、LAST 位置 |

Coverage 只说明“发生过”，scoreboard/assertion 才说明“发生得正确”。

### 7.3 当前 Coverage Model

入口：[components/axi_coverage.sv](../components/axi_coverage.sv)

已有 coverpoints：

- `kind`；
- 地址高位对应的 slave；
- ID 高 4 bit 对应的 master；
- burst length 分类；
- size；
- response；
- master × slave 等交叉覆盖。

需要改进：

- Monitor 已提供 `source_id`，`cp_master` 却从 ID 高位推断 master，耦合了当前 ID mask 约定；
- `cp_resp` 只有 OKAY bin，没有 SLVERR、DECERR；
- 没有 FIXED/INCR/WRAP burst 覆盖；
- 没有 backpressure 等待周期覆盖；
- 没有 outstanding 深度、仲裁竞争、reset 中断覆盖；
- 没有非法地址、4 KB 边界和 crossing-window burst 覆盖；
- coverage 只连接 master monitor，适合端到端场景覆盖，但无法直接证明实际下游路由覆盖。

Covergroup 最好用显式采样参数，减少成员句柄被并发 write 改写的风险：

```systemverilog
covergroup cg with function sample(axi_txn t);
    cp_kind: coverpoint t.kind;
endgroup
```

### 7.4 当前 SVA

入口：[infra/axi_if.sv](../infra/axi_if.sv)

已有检查：

- VALID 在等待 READY 时保持；
- WLAST 必须伴随 WVALID；
- RLAST 必须伴随 RVALID。

现有稳定性属性只检查 VALID 本身，没有检查 payload。完整属性还应覆盖类似：

```systemverilog
AWVALID && !AWREADY |=> AWVALID && $stable({AWADDR, AWID, AWLEN, ...})
WVALID  && !WREADY  |=> WVALID  && $stable({WDATA, WSTRB, WLAST})
```

还应考虑：

- reset 期间或释放后 VALID 的规则；
- WLAST/RLAST 与 LEN 的拍数对应；
- response 只能在对应请求后发生；
- BID/RID 合法；
- burst size 合法且不跨 4 KB；
- X/Z 检查；
- 对 liveness 属性设置合理上界，避免无界等待。

### 7.5 为什么日志里 SVA 失败但 UVM 仍报 PASS

当前 assertion action block 使用 `$error`。现有 `sim.log` 有多次：

```text
[SVA] RLAST without RVALID
```

但 UVM summary 仍显示 `UVM_ERROR : 0`。Simulator assertion failure 与 UVM report server 是不同统计通道。回归脚本必须同时读取仿真器断言状态，或者让 action block 调用统一的 UVM reporting，并配置仿真器 assertion failure 影响退出码。

### 7.6 覆盖收敛流程

```text
verification plan
      ↓ 映射
coverpoint / assertion / test
      ↓ 回归
coverage hole 分析
      ↓
判断是激励未产生、checker 未观察、不可达还是规格排除
      ↓
增加约束/sequence/cross 或合理 exclusion
```

不能为了数字好看而删除困难 bins。每个 exclusion 都应该有规格依据和评审记录。

### 7.7 本阶段练习

1. 给 response 增加 OKAY/EXOKAY/SLVERR/DECERR bins。
2. 把 master coverage 从 `id[7:4]` 改为 `source_id`。
3. 增加 AW payload 稳定性断言，并故意让 driver 违规验证其有效性。
4. 增加 `outstanding_depth` 覆盖点。
5. 将 verification plan 每一条映射到 test、checker 和 coverage，找出只有 test 名称但没有检查的项目。

### 7.8 面试问答

**问：功能覆盖率 100% 是否代表验证完成？**

答：不代表。它只说明定义的 bins 被命中；可能 bins 定义不完整，也可能场景发生了但结果错误。完成标准还需要 scoreboard、assertion、代码覆盖、bug 状态和 verification plan closure。

**问：SVA 与 scoreboard 如何分工？**

答：SVA 擅长局部、周期精确的协议属性，如稳定性和握手顺序；scoreboard 擅长跨长时间、跨接口的端到端数据、路由和顺序比较。两者互补。

---

## 阶段八：Test、回归、Debug 与面试表达

### 8.1 学习目标

- 能把 verification plan 落到 test/checker/coverage；
- 能运行可复现回归并自动判定结果；
- 能从日志和波形定位问题；
- 能诚实、有层次地介绍项目。

### 8.2 Test 应负责什么

Test 主要负责：

- 创建/配置 env；
- 选择 agent active/passive；
- 配置错误率、延迟、backpressure 等场景；
- 启动一个或多个 sequence/virtual sequence；
- 管理 objection 和测试结束条件。

Test 不应该直接承担 pin-level 驱动，也不应直接深入 `env.mst_agent[0].driver.vif` 操作复位。更好的做法是通过配置对象、virtual sequencer 和专用 reset sequence 控制。

### 8.3 Base Test 与 Virtual Sequence

[tests/axi_base_test.sv](../tests/axi_base_test.sv) 当前只创建 env。项目中的具体 test 直接访问四个 master sequencer。

当多接口场景增多时，应增加 virtual sequencer 保存各子 sequencer 句柄，再由 virtual sequence 协调：

```text
virtual_sequence
├── 在 mst_sqr[0] 启动 seq0
├── 在 mst_sqr[1] 启动 seq1
├── 配置 slave response
└── 协调 reset/并发/结束
```

Virtual sequence 不产生 pin-level item，它负责场景级调度。

### 8.4 当前 Makefile 与回归风险

入口：[Makefile](../Makefile)

当前支持 VCS/Xcelium 和多个 test target，但需要注意：

- VCS `-cm` 的 `func` 选项在现有日志中被报告为非法；SystemVerilog functional coverage 与代码覆盖选项不是同一个概念；
- 每个 test 重新 compile，回归时间不必要地增加；
- 所有 test 使用同名 `sim.log`，后一次会覆盖前一次；
- coverage database 的 merge、test name 和 pass/fail 汇总需要更明确；
- regression 顺序执行且遇到某些日志级错误时未必停止；
- README、verification plan 与单次日志中的覆盖数字不一致，不能未经数据库核验就对外声称结果。

可靠回归至少输出：

```text
test name | seed | exit code | UVM_ERROR | UVM_FATAL |
assertion failures | timeout | scoreboard status | coverage db
```

### 8.5 Seed 与可复现性

约束随机验证必须保存 seed。发现 bug 后，应能用：

```text
test name + seed + RTL version + TB version + simulator options
```

完全重现。修复后先跑原 seed，再做多 seed regression。只说“随机跑了很多次没问题”不具备工程证据。

### 8.6 推荐 Debug 顺序

遇到失败时按层次缩小范围：

1. Test 是否真的启动了目标 sequence；
2. randomize 是否成功，item 字段是否正确；
3. sequencer-driver 是否完成握手；
4. 上游 AW/W/AR 是否握手；
5. DUT 是否选到正确 slave；
6. 下游地址是否按配置转换；
7. B/R 是否返回，ID/LAST/RESP 是否正确；
8. monitor 是否完整重建；
9. reference model 预测是否正确；
10. comparator 是否使用了正确匹配键。

优先看第一处异常，不要从最终一串连锁错误倒推。

### 8.7 本项目推荐改造顺序

不要一开始就重写全部 VIP。按风险从高到低：

1. 修复 scoreboard 的地址归一化、读比较和 unmatched false pass；
2. 让 assertion failure 进入统一测试结果；
3. 修复 shared handle 和随机约束冲突；
4. 修复 WSTRB/size/burst memory model；
5. 修复 error/backpressure/reset tests，使配置真正作用于目标接口；
6. 拆分 monitor 通道，支持多笔 pending；
7. 重构 driver，支持独立读写和 outstanding；
8. 增加 virtual sequencer、配置对象和自动 regression report；
9. 重新收集并审核 coverage，而不是沿用旧数字。

### 8.8 面试中的项目介绍模板

可以用 1~2 分钟这样介绍：

> 我搭建并审查了一个 4×4 AXI4 Crossbar UVM 验证环境。平台包含四组 active master agents、四组 reactive slave agents、两侧 monitors、reference scoreboard、functional coverage 和接口 SVA。激励覆盖基础读写、地址路由、多 master 竞争、burst、错误响应、backpressure、reset 和 outstanding 等场景。
>
> 在深入分析时，我发现原始 AI 生成版本存在 false pass：scoreboard 没有比较读数据，未匹配路由只报 warning，而且忽略了 DUT 去除 slave base address 的行为；所谓 outstanding driver 也会等待每笔 response 后才取下一笔 item。我通过波形、日志和源码定位这些问题，并规划用 byte-accurate reference memory、规范化地址、pending queues、按 ID 匹配以及统一 assertion/UVM 回归判定来修复。这让我理解了 UVM 组件名称齐全并不等于验证闭环成立。

这段介绍的价值在于同时讲清：DUT、平台架构、验证内容、发现的问题和改进思路。不要声称当前尚未实测完成的修复和覆盖数字。

### 8.9 高频追问清单

1. 为什么 master agent 需要 sequencer，而 slave responder 可以没有？
2. `start_item/finish_item` 与 `get_next_item/item_done` 如何配对？
3. 多 sequence 并发为什么不一定形成 outstanding？
4. 如何按 ID 处理不同 ID 乱序、同 ID 保序？
5. AW 和 W 是否必须按顺序出现？
6. 如何计算 INCR/WRAP burst 地址？
7. WSTRB 如何更新 byte-addressed memory model？
8. 下游地址去掉 base 后，scoreboard 如何匹配上下游事务？
9. analysis port、analysis imp、subscriber、analysis FIFO 有何区别？
10. assertion 报错为什么可能没进入 UVM error count？
11. coverage 100% 为什么仍可能漏 bug？
12. reset 到来时 driver、monitor、scoreboard 应分别做什么？

### 8.10 阶段验收

达到以下标准后，可以认为你已经从“会运行 UVM”进入“能解释和评审 UVM”：

- 不看代码画出完整 UVM topology 和 transaction flow；
- 用波形解释一笔 AXI burst 的五通道握手；
- 能指出当前项目至少五个 false pass/协议建模问题；
- 能设计支持 outstanding 的 driver/monitor 数据结构；
- 能从 verification plan 推导 checker 和 coverage；
- 能用 test + seed 重现失败并定位第一处异常；
- 面试介绍中明确区分“已经实现并验证”和“计划改进”。

---

## 附录 A：建议阅读顺序

第一次阅读：

1. [tb/axi_crossbar_tb.sv](../tb/axi_crossbar_tb.sv)
2. [infra/axi_pkg.sv](../infra/axi_pkg.sv)
3. [tests/axi_base_test.sv](../tests/axi_base_test.sv)
4. [components/axi_env.sv](../components/axi_env.sv)
5. [components/axi_mst_agent.sv](../components/axi_mst_agent.sv)
6. [components/axi_txn.sv](../components/axi_txn.sv)
7. [sequences/axi_wr_seq.sv](../sequences/axi_wr_seq.sv)
8. [components/axi_mst_drv.sv](../components/axi_mst_drv.sv)
9. [components/axi_slv_drv.sv](../components/axi_slv_drv.sv)
10. [components/axi_monitor.sv](../components/axi_monitor.sv)
11. [components/axi_scoreboard.sv](../components/axi_scoreboard.sv)
12. [components/axi_coverage.sv](../components/axi_coverage.sv)

第二次阅读按一笔写事务横向追踪；第三次阅读按 reset、backpressure、outstanding 等场景纵向追踪。

## 附录 B：每阶段产出物

| 阶段 | 应产出的东西 |
|---|---|
| 1 | SV 容器/并发/随机化小实验 |
| 2 | UVM topology 图、phase 和 config_db 路径图 |
| 3 | sequence-driver 握手时序图 |
| 4 | AXI 五通道波形与 driver 改造设计 |
| 5 | 支持 pending/outstanding 的 monitor 结构图 |
| 6 | 可故障注入验证的 reference scoreboard |
| 7 | verification plan 到 coverage/assertion 映射表 |
| 8 | 自动回归报告和两分钟项目介绍 |

## 附录 C：学习原则

每看到一个测试名称，都问三遍：

1. 激励真的产生了吗？
2. 检查器真的检查了吗？
3. 故意制造错误时，它真的会失败吗？

只有三个答案都是“是”，这个验证点才形成闭环。
