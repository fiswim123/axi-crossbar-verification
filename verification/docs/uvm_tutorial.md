# AXI Crossbar UVM 验证平台 — 代码阅读指南

> 本文档是为 IC 验证初学者编写的代码阅读路线图。
> 按照推荐顺序阅读，每一步都会告诉你：**看哪个文件、看哪些行、理解什么概念**。

---

## 零、背景知识：先搞懂我们在干什么

### 0.1 DUT 是什么

我们要验证的是一个 **4×4 AXI Crossbar**，简单说就是一个"信号路由器"：

```
Master 0 ──┐                    ┌── Slave 0 (0x0000~0x0FFF)
Master 1 ──┼── AXI Crossbar ──┼── Slave 1 (0x1000~0x1FFF)
Master 2 ──┼    (路由器)        ├── Slave 2 (0x2000~0x2FFF)
Master 3 ──┘                    └── Slave 3 (0x3000~0x3FFF)
```

- **Master**：发起读写请求的一方（比如 CPU）
- **Slave**：响应读写的一方（比如内存）
- **Crossbar**：根据地址把请求路由到正确的 Slave

### 0.2 验证的目标

验证 = 确认 DUT 行为正确。具体来说：

| 目标 | 测试场景 | 对应 Test |
|------|---------|----------|
| 路由正确 | 写 Slave 0，能从 Slave 0 读回来 | axi_routing_test |
| 并发正确 | 4 个 Master 同时访问不同 Slave | axi_multi_master_test |
| 协议正确 | Burst 传输不丢数据 | axi_burst_size_test |
| 异常处理 | Slave 返回错误，DUT 不卡死 | axi_err_slverr_test |
| 鲁棒性 | 中途复位，DUT 能恢复 | axi_reset_recovery_test |

### 0.3 为什么用 UVM

不用 UVM，你也可以直接写个 `initial begin ... end` 去驱动信号。但：

| | 直接写 | UVM |
|---|---|---|
| 换个项目能复用吗 | ❌ | ✅ |
| 能随机生成激励吗 | ❌ | ✅ |
| 能自动收集覆盖率吗 | ❌ | ✅ |
| 面试官认可吗 | ❌ | ✅ |

**UVM 就是一套"验证框架"**，规定了谁干什么、怎么配合。你只要按规矩填代码就行。

### 0.4 UVM 的核心思想

```
                Test
                  │  "我要测什么"
                  ▼
              Sequence
                  │  "生成什么激励"
                  ▼
             Sequencer  ←→  Driver  "把激励变成信号"
                              │
                              ▼
                          Interface  →  DUT
                              ▲
                              │
                           Monitor    "旁观采集"
                              │
                              ▼
       Scoreboard  ←────────┘ "比对对不对"
       Coverage   ←────────┘ "采了多少"
```

**记住这个图，后面每一步都是在填这个图里的格子。**

---

## 一、平台全景架构图

下图展示 UVM 验证平台的组件关系和数据流向。**箭头表示数据流方向**。

### 1.1 组件层次图

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        axi_crossbar_tb.sv  (Testbench 顶层 - module)            │
│   职责: 生成时钟/复位, 例化接口(mst_if/slv_if), 例化DUT, config_db传vif         │
│                                                                                 │
│      ┌─────────────────── DUT (axicb_crossbar_top) ───────────────────┐        │
│      │                    4 Master × 4 Slave Crossbar                 │        │
│      └────────────────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────────┘
        │ mst_if[0..3]                        │ slv_if[0..3]
        ▼                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           axi_env.sv  (顶层验证环境)                             │
│                                                                                 │
│  ┌──────────────────────────────┐    ┌──────────────────────────────┐           │
│  │  axi_mst_agent.sv ×4        │    │  axi_slv_agent.sv ×4         │           │
│  │  (Master Agent, Active)      │    │  (Slave Agent, Active)       │           │
│  │                              │    │                              │           │
│  │  ┌────────────────────────┐  │    │  ┌────────────────────────┐  │           │
│  │  │  axi_mst_drv.sv        │  │    │  │  axi_slv_drv.sv        │  │           │
│  │  │  (Master Driver)       │  │    │  │  (Slave Driver)        │  │           │
│  │  │  从sequencer获取txn,   │  │    │  │  被动响应DUT请求,      │  │           │
│  │  │  驱动AXI信号到DUT      │  │    │  │  模拟存储器行为        │  │           │
│  │  └────────────────────────┘  │    │  └────────────────────────┘  │           │
│  │                              │    │                              │           │
│  │  ┌────────────────────────┐  │    │  ┌────────────────────────┐  │           │
│  │  │  uvm_sequencer#(txn)   │  │    │  │  axi_monitor.sv        │  │           │
│  │  │  (内置Sequencer)       │  │    │  │  (Monitor)             │  │           │
│  │  │  调度sequence产生的txn │  │    │  │  被动观察总线事务,     │  │           │
│  │  └────────────────────────┘  │    │  │  广播给scoreboard      │  │           │
│  │                              │    │  └────────────────────────┘  │           │
│  │  ┌────────────────────────┐  │    └──────────────────────────────┘           │
│  │  │  axi_monitor.sv        │  │                                              │
│  │  │  (Monitor)             │  │                                              │
│  │  │  观察主机侧总线事务    │  │                                              │
│  │  └────────────────────────┘  │                                              │
│  └──────────────────────────────┘                                              │
│                                                                                 │
│  ┌──────────────────────────┐    ┌──────────────────────────┐                  │
│  │  axi_scoreboard.sv       │    │  axi_coverage.sv         │                  │
│  │  (Scoreboard 记分板)     │    │  (Coverage 覆盖率)       │                  │
│  └──────────────────────────┘    └──────────────────────────┘                  │
│                                                                                 │
│  ┌──────────────────────────┐                                                  │
│  │  axi_slv_cfg.sv          │  ← Slave 配置对象 (错误注入/背压/延迟)           │
│  └──────────────────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 数据流图（核心！）

```
    tests/                         sequences/              axi_txn.sv
    ┌──────────┐                   ┌──────────┐          ┌─────────────────┐
    │axi_basic │    ① Test 创建     │axi_wr_seq│          │ class axi_txn   │
    │_test.sv  │──────Sequence────→│axi_rd_seq│←─────────│  kind, addr     │
    │          │    设置参数        │ ...      │ 被引用   │  len, size      │
    │start()   │                   │ body()   │          │  wdata[], wstrb[]│
    └──────────┘                   └────┬─────┘          └─────────────────┘
                                                  │
                                     ② Sequence.body() 创建 txn
                                        填充字段 (kind, addr, wdata)
                                                  │
              ┌───────────────────────────────────┼──────────────────────────┐
              │                    Master Agent (主动驱动)                     │
              │                    axi_mst_agent.sv                           │
              │                                                               │
              │   ┌───────────┐      ┌───────────┐      ┌───────────┐       │
              │   │ Sequencer │      │  Driver   │      │  Monitor  │       │
              │   │ (内置)    │←─────│(axi_mst_ │      │(axi_moni │       │
              │   │           │      │ drv.sv)   │      │ tor.sv)   │       │
              │   │ ③ 调度txn │─────→│           │      │           │       │
              │   └───────────┘      └─────┬─────┘      └─────┬─────┘       │
              │                            │                  │              │
              └────────────────────────────┼──────────────────┼──────────────┘
                                           │                  │
                        ④ Driver 把 txn    │                  │ ⑧ Master Monitor
                           拆成信号:       │                  │    观测主机侧
                           addr→awaddr     │                  │    还原成 txn
                           wdata→wdata     │                  │
                                           ▼                  │
              ┌───────────────────────────────────────────────┼──────────────┐
              │                        DUT                    │              │
              │                   axicb_crossbar_top.sv       │              │
              │                                               │              │
              │   ⑤ 根据 awaddr 高位判断路由                   │              │
              │      0x0000~0x0FFF → Slave 0                  │              │
              │      0x1000~0x1FFF → Slave 1                  │              │
              │      0x2000~0x2FFF → Slave 2                  │              │
              │      0x3000~0x3FFF → Slave 3                  │              │
              └───────────────────────────┬───────────────────┼──────────────┘
                                          │                   │
                                          │ ⑥ DUT 输出信号    │
                                          │    到 Slave Agent │
                                          ▼                   │
              ┌───────────────────────────────────────────────┼──────────────┐
              │                    Slave Agent (被动响应)       │              │
              │                    axi_slv_agent.sv            │              │
              │                                               │              │
              │   ┌───────────────────┐   ┌───────────────┐  │              │
              │   │   Slave Driver    │   │ Slave Monitor │  │              │
              │   │   (axi_slv_drv.sv)│   │(axi_monitor.sv)│  │              │
              │   │                   │   │               │  │              │
              │   │ ⑥a 被动监听请求   │   │ ⑦ 观测从机侧  │  │              │
              │   │ ⑥b 从mem[]读写    │   │   还原成 txn  │  │              │
              │   │ ⑥c 返回响应       │   │   ap.write()  │  │              │
              │   │    bresp/rdata    │   └───────┬───────┘  │              │
              │   └───────────────────┘           │          │              │
              └───────────────────────────────────┼──────────┼──────────────┘
                                                  │          │
                                                  │          │
                              ⑨ Monitor.ap.write(txn) 广播   │
                                                  │          │
                                          ┌───────┴──────────┘
                                          │
                                    ┌─────┴─────┐
                                    ▼           ▼
                              ┌───────────┐  ┌───────────┐
                              │Scoreboard │  │ Coverage  │
                              │(axi_score │  │(axi_cover │
                              │ board.sv) │  │ age.sv)   │
                              │           │  │           │
                              │ ⑩ 比对    │  │ ⑪ 采样    │
                              │   期望值   │  │   覆盖率  │
                              │   vs实际值 │  │           │
                              └───────────┘  └───────────┘
```

**数据流方向**：
```
Test → Sequence → Sequencer → Driver → DUT → Slave Agent
                                    ↑                    │
                                    │         Slave Driver 响应
                                    │         Slave Monitor 观测
                                    │              │
                                    │              ▼
                                    │      Scoreboard + Coverage
                                    │
                              Master Monitor 也观测并广播
```

### 1.3 数据流总结

**一句话总结**：

> Test 启动 Sequence → Sequence 创建 txn → Sequencer 调度给 Driver → Driver 驱动信号到 DUT → DUT 路由到 Slave Driver 响应 → Monitor 观测并广播 → Scoreboard 比对 + Coverage 采样。

**完整流程**：

```
阶段    谁在工作              做了什么                         对应文件
──────────────────────────────────────────────────────────────────────────
 1      Testbench Top         生成时钟/复位, 例化DUT和接口      axi_crossbar_tb.sv
                               config_db传vif, run_test()

 2      Test                  build_phase: 创建env             axi_basic_test.sv
                               run_phase: raise_objection
                               创建sequence, 设置参数
                               seq.start(sequencer)

 3      Sequence              body(): 创建txn, 填充字段         axi_wr_seq.sv
                               start_item → finish_item

 4      Sequencer             调度txn给driver                  uvm_sequencer(内置)

 5      Master Driver         get_next_item(txn)               axi_mst_drv.sv
                               驱动信号: awaddr, wdata...
                               等待握手: awready, wready
                               采样响应: bresp
                               item_done()

 6      DUT                   根据地址路由到正确的Slave          axicb_crossbar_top.sv

 7      Slave Driver          被动监听DUT请求                   axi_slv_drv.sv
                               从mem[]读/写数据
                               返回bresp/rdata

 8      Master Monitor        观测主机侧信号, 还原成txn         axi_monitor.sv
                               ap.write(txn) 广播

 9      Slave Monitor         观测从机侧信号, 还原成txn         axi_monitor.sv
                               ap.write(txn) 广播

10      Scoreboard            收到txn: 写事务存期望表           axi_scoreboard.sv
                               读事务比对期望值
                               统计pass/fail

11      Coverage              收到txn: 采样覆盖率点             axi_coverage.sv
                               (kind, slave, master, len, size)

12      Test                  drop_objection, 仿真结束          axi_basic_test.sv
                               report_phase打印结果
──────────────────────────────────────────────────────────────────────────
```

---

## 二、推荐阅读顺序

按照从**底层到顶层**、从**数据到控制**的顺序，分 7 步阅读：

```
        ┌─ 第1步 ─┐    ┌─ 第2步 ─┐    ┌─ 第3步 ─┐
        │axi_if.sv│───→│axi_txn.sv│───→│axi_mst_ │
        │ 接口定义 │    │ 事务定义  │    │drv.sv   │
        └─────────┘    └─────────┘    │Master   │
                                      │Driver   │
                                      └────┬────┘
                                           │
        ┌─ 第5步 ─┐    ┌─ 第4步 ─┐         │
        │axi_slv_ │←───│axi_moni │←────────┘
        │cfg.sv   │    │tor.sv   │
        │Slave配置 │    │ Monitor │
        └────┬────┘    └────┬────┘
             │              │
             ▼              │
        ┌─ 第6步 ─┐         │
        │axi_slv_ │         │
        │drv.sv   │         │
        │Slave    │         │
        │Driver   │         │
        └─────────┘         │
                            ▼
                       ┌─ 第7步 ─┐
                       │axi_env.sv│
                       │ 顶层环境  │
                       └─────────┘
```

---

## 三、分步阅读详解

---

### 第 1 步：axi_if.sv — AXI 接口定义

| 项目 | 内容 |
|------|------|
| 文件 | `infra/axi_if.sv` |
| 角色 | 定义"插座"——所有信号的集合 |
| 阅读时间 | 15 分钟 |
| 前置知识 | 无 |

#### 这个文件做了什么？

`axi_if.sv` 定义了 AXI 总线的**所有信号线**，就像一个标准化的"插座"。芯片（DUT）和验证组件（Driver/Monitor）都通过这个"插座"连接。

#### 逐段阅读指引

**第 33-58 行 — 参数和端口声明**

```systemverilog
interface axi_if #(
    parameter AXI_ADDR_W = 16,   // 地址位宽：16位 → 可寻址 64KB
    parameter AXI_ID_W   = 8,    // ID位宽：8位 → 支持256个事务ID
    parameter AXI_DATA_W = 32    // 数据位宽：32位 → 每次传4字节
)(
    input logic aclk              // 时钟信号，由外部驱动
);
```

**你要理解的**：
- `parameter` 让接口可配置，同一个接口定义可以适配不同位宽的设计
- `aclk` 是唯一的输入端口，其他信号都在接口内部声明

---

**第 75-215 行 — 5 个通道的信号声明**

AXI 协议有 5 个独立的"车道"（通道），每个通道负责不同的任务：

| 通道 | 前缀 | 方向 | 作用 | 关键信号 |
|------|------|------|------|---------|
| Write Address | AW | Master→Slave | 发送写地址 | awvalid, awready, awaddr, awlen |
| Write Data | W | Master→Slave | 发送写数据 | wvalid, wready, wdata, wlast |
| Write Response | B | Slave→Master | 返回写响应 | bvalid, bready, bresp |
| Read Address | AR | Master→Slave | 发送读地址 | arvalid, arready, araddr, arlen |
| Read Data | R | Slave→Master | 返回读数据 | rvalid, rready, rdata, rlast |

**你要理解的**：
- 每个通道都有 `valid` 和 `ready` 信号（握手信号对）
- 写操作需要 3 个通道（AW+W+B），读操作需要 2 个通道（AR+R）

---

**第 250-295 行 — Modport 定义**

```systemverilog
modport master (
    input  aclk, aresetn,
    output awvalid, awaddr, ...    // Master 驱动这些信号
    input  awready, ...            // Master 接收这些信号
);
modport slave (
    input  aclk, aresetn,
    input  awvalid, awaddr, ...    // Slave 接收这些信号（方向相反！）
    output awready, ...            // Slave 驱动这些信号
);
```

**你要理解的**：
- 同一个接口，Master 看到的信号方向和 Slave **完全相反**
- 就像同一个插座，插头的"输入"和"输出"是反的

---

**第 350-383 行 — SVA 断言**

```systemverilog
assert property (sig_stable(awvalid, awready)) else $error("[SVA] AWVALID unstable");
```

**你要理解的**：
- 断言是"自动检查员"，在仿真过程中实时检测协议违规
- 这个断言检查：valid 一旦拉高，在 ready 拉高之前不能撤销

---

### 第 2 步：axi_txn.sv — 事务（数据包）定义

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_txn.sv` |
| 角色 | 定义"快递单"——一次读/写操作的完整描述 |
| 阅读时间 | 20 分钟 |
| 前置知识 | 第 1 步（理解 5 个通道和握手） |

#### 这个文件做了什么？

`axi_txn.sv` 定义了一个"数据包"类，描述一次完整的 AXI 读或写操作的所有信息。Driver 发送的就是这种数据包，Monitor 采集的也是这种数据包。

#### 逐段阅读指引

**第 19 行 — 类定义**

```systemverilog
class axi_txn extends uvm_sequence_item;
```

**你要理解的**：
- `uvm_sequence_item` 是 UVM 的"事务基类"，所有事务都继承它
- 继承它之后，你的类就能被 Sequencer 调度、被 Driver 处理

---

**第 23-43 行 — 随机变量（"快递单"的各个字段）**

```systemverilog
typedef enum {READ, WRITE} kind_e;   // 读或写

rand kind_e     kind;      // 事务类型
rand bit [15:0] addr;      // 目标地址（16位，64KB空间）
rand bit [7:0]  id;        // 事务ID（用于乱序和识别）
rand bit [7:0]  len;       // 突发长度 = len+1 拍
rand bit [2:0]  size;      // 每拍字节数 = 2^size
rand bit [1:0]  burst;     // 突发类型（FIXED/INCR/WRAP）
rand bit [31:0] wdata[];   // 写数据数组（动态数组）
rand bit [3:0]  wstrb[];   // 写选通（控制哪些字节有效）
```

**你要理解的**：
- `rand` 关键字表示这些变量在 `randomize()` 时会被**自动随机化**
- 这是 UVM 验证的核心思想：自动生成各种合法的测试数据
- 动态数组 `wdata[]` 和 `wstrb[]` 的大小等于 `len+1`

**生活类比**：
```
addr  = 收件地址
id    = 快递单号
len   = 包裹数量（3表示4个包裹）
size  = 每个包裹大小（2表示4字节）
wdata = 包裹内容
wstrb = 哪些包裹有效
```

---

**第 45-60 行 — 非随机变量（响应信息）**

```systemverilog
bit [7:0]  bid, rid;       // 响应ID（应与请求ID匹配）
bit [1:0]  bresp, rresp;   // 响应码（OKAY/SLVERR/DECERR）
bit [31:0] rdata[];        // 读数据（由Driver从总线采样后填入）
```

**你要理解的**：
- 这些变量**不参与随机化**，它们是从 DUT 返回的响应信息
- Driver 采样总线信号后，把值存到这些变量里

---

**第 67-74 行 — 约束块**

```systemverilog
constraint c_basic {
    size inside {[0:2]};         // 只能是0、1、2（对应1/2/4字节）
    len  inside {[0:15]};        // 只能是0~15（对应1~16拍）
    burst == 2'b01;              // 固定用INCR模式（地址递增）
    addr[1:0] == 2'b00;          // 地址必须4字节对齐
    wdata.size() == len + 1;     // 数据数组大小 = 突发长度
    wstrb.size() == len + 1;     // 选通数组大小 = 突发长度
}
```

**你要理解的**：
- 约束块限制随机化的范围，确保生成**合法**的测试数据
- 就像告诉系统"地址必须对齐、长度不能超限"
- 不同的约束块（c_boundary_addr 等）用于不同的测试场景

---

**第 117-128 行 — UVM 工厂注册**

```systemverilog
`uvm_object_utils_begin(axi_txn)
    `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(addr,  UVM_ALL_ON)
    ...
`uvm_object_utils_end
```

**你要理解的**：
- 这些宏把每个字段注册到 UVM 系统
- 注册后，UVM 自动帮你实现 `print()`、`copy()`、`compare()` 等方法
- 你不需要手写这些通用功能

---

### 第 3 步：axi_mst_drv.sv — Master 驱动器

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_mst_drv.sv` |
| 角色 | "快递员"——把 Transaction 变成真实信号发给 DUT |
| 阅读时间 | 25 分钟 |
| 前置知识 | 第 1、2 步 |

#### 这个文件做了什么？

Master Driver 是"主动型"组件：从 Sequencer 获取 Transaction，然后按照 AXI 协议的时序要求，把数据包转换成真实信号驱动到 DUT。

#### 逐段阅读指引

**第 32 行 — 类定义**

```systemverilog
class axi_mst_drv extends uvm_driver #(axi_txn);
```

**你要理解的**：
- `uvm_driver#(axi_txn)` 表示这个 Driver 只处理 `axi_txn` 类型的事务
- `#(axi_txn)` 是参数化，让 `seq_item_port` 自动知道要获取什么类型的数据

---

**第 45 行 — 虚拟接口**

```systemverilog
virtual axi_if vif;
```

**你要理解的**：
- `virtual interface` 是指向真实接口的"指针"
- UVM 组件（class）不能直接访问接口（module），必须通过 vif 间接操作
- vif 通过 `config_db` 机制从 testbench 传递过来

---

**第 67-78 行 — build_phase（准备工作）**

```systemverilog
function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
endfunction
```

**你要理解的**：
- `build_phase` 是 UVM 生命周期的第一个阶段，用于获取配置和创建子组件
- `config_db::get` 从全局配置数据库获取虚拟接口
- 如果获取失败，`uvm_fatal` 会终止仿真并报错

---

**第 91-114 行 — run_phase 主循环（核心！）**

```systemverilog
task run_phase(uvm_phase phase);
    // 信号初始化
    vif.awvalid <= 0; vif.wvalid <= 0; ...

    forever begin
        axi_txn txn;
        seq_item_port.get_next_item(txn);     // ① 从Sequencer获取事务
        if (txn.kind == axi_txn::WRITE)
            drive_wr(txn);                    // ② 驱动写操作
        else
            drive_rd(txn);                    // ② 驱动读操作
        seq_item_port.item_done();            // ③ 通知Sequencer：完成了
    end
endtask
```

**你要理解的**：
- `forever` 循环：Driver 永远在工作，不断获取事务并驱动
- `get_next_item()`：阻塞调用，没有事务时会等待
- `item_done()`：告诉 Sequencer "这个事务我处理完了，给我下一个"

**整个循环就是**：等事务 → 驱动信号 → 标记完成 → 等事务 → ...

---

**第 123-164 行 — drive_wr 写操作（重点！）**

```
阶段1: AW通道（写地址）     阶段2: W通道（写数据）      阶段3: B通道（写响应）
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│ awvalid <= 1      │     │ for i = 0 to len: │     │ bready <= 1       │
│ awaddr <= txn.addr│     │   wvalid <= 1     │     │ 等待 bvalid=1     │
│ awlen  <= txn.len │     │   wdata <= data[i]│     │ 采样 bresp        │
│ ...               │     │   wlast <= (末拍) │     │ bready <= 0       │
│ 等待 awready=1    │     │   等待 wready=1   │     │                   │
│ awvalid <= 0      │     │ wvalid <= 0       │     │                   │
└───────────────────┘     └───────────────────┘     └───────────────────┘
```

**逐行翻译**：

```systemverilog
// 阶段1: 发送写地址
@(posedge vif.aclk);           // 等时钟上升沿（同步）
vif.awvalid <= 1;               // 举手说"我有地址要给你"
vif.awaddr <= txn.addr;         // 把地址放上去
vif.awlen <= txn.len;           // 告诉对方"我要传len+1拍数据"
do @(posedge vif.aclk); while (!vif.awready);  // 等对方举手
vif.awvalid <= 0;               // 对方接住了，放下手

// 阶段2: 逐拍发送写数据
for (int i = 0; i <= txn.len; i++) begin
    vif.wvalid <= 1;            // 举手说"我有数据"
    vif.wdata <= txn.wdata[i];  // 把第i拍数据放上去
    vif.wlast <= (i == txn.len);// 最后一拍时说"这是最后一个"
    do @(posedge vif.aclk); while (!vif.wready);  // 等对方接住
end

// 阶段3: 接收写响应
vif.bready <= 1;                // 说"我准备好接收响应了"
do @(posedge vif.aclk); while (!vif.bvalid);  // 等对方给出响应
txn.bresp = vif.bresp;         // 采样响应码
vif.bready <= 0;               // 完成
```

**关键模式**：`do @(posedge aclk); while (!ready);` — 这是 AXI 握手的标准写法。

---

**第 172-203 行 — drive_rd 读操作**

读操作比写操作简单，只有 2 个阶段：

```
阶段1: AR通道（读地址）      阶段2: R通道（读数据）
┌───────────────────┐     ┌───────────────────┐
│ arvalid <= 1      │     │ for i = 0 to len: │
│ araddr <= txn.addr│     │   等待 rvalid=1   │
│ ...               │     │   采样 rdata[i]   │
│ 等待 arready=1    │     │ rready <= 0       │
│ arvalid <= 0      │     │                   │
└───────────────────┘     └───────────────────┘
```

**注意**：读操作的 `rready` 在循环开始前就拉高了（第 173 行），表示"我一直准备好接收"。

---

### 第 4 步：axi_monitor.sv — 监视器

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_monitor.sv` |
| 角色 | "监控摄像头"——被动观察总线，还原成 Transaction |
| 阅读时间 | 20 分钟 |
| 前置知识 | 第 1、2、3 步 |

#### 这个文件做了什么？

Monitor 是"被动型"组件：**不驱动任何信号**，只观察总线上的握手，把观察到的信号还原成 Transaction 对象，然后广播出去。

#### 逐段阅读指引

**第 24 行 — 分析端口**

```systemverilog
uvm_analysis_port #(axi_txn) ap;
```

**你要理解的**：
- `analysis_port` 是 UVM 的"广播喇叭"
- Monitor 观察到一个完整事务后，调用 `ap.write(txn)` 广播出去
- Scoreboard 和 Coverage 都连接到这个"喇叭"上接收数据

---

**第 59-64 行 — run_phase**

```systemverilog
task run_phase(uvm_phase phase);
    fork
        mon_wr();   // 监视写通道（AW + W + B）
        mon_rd();   // 监视读通道（AR + R）
    join
endtask
```

**你要理解的**：
- AXI 的读和写是**独立的通道**，可以同时发生
- 所以 Monitor 用 `fork...join` 同时监视两个方向

---

**第 72-123 行 — mon_wr 写通道监视**

```systemverilog
task mon_wr();
    forever begin
        // 阶段1: 等待AW通道握手
        @(posedge vif.aclk iff (vif.awvalid && vif.awready));
        txn = axi_txn::type_id::create("wr_txn");
        txn.kind = axi_txn::WRITE;
        txn.addr = vif.awaddr;    // 采样地址
        txn.len = vif.awlen;      // 采样突发长度

        // 阶段2: 逐拍采样W通道数据
        for (int i = 0; i <= txn.len; i++) begin
            @(posedge vif.aclk iff (vif.wvalid && vif.wready));
            txn.wdata[i] = vif.wdata;   // 采样数据
        end

        // 阶段3: 等待B通道响应
        @(posedge vif.aclk iff (vif.bvalid && vif.bready));
        txn.bresp = vif.bresp;          // 采样响应码

        ap.write(txn);                   // 广播出去！
    end
endtask
```

**对比 Driver 和 Monitor**：

| 对比项 | Driver (axi_mst_drv) | Monitor (axi_monitor) |
|--------|---------------------|----------------------|
| 信号操作 | `vif.awvalid <= 1`（驱动） | `vif.awvalid && vif.awready`（观察） |
| 数据方向 | 把 txn 写到总线 | 从总线读到 txn |
| 握手等待 | `while (!ready)` | `iff (valid && ready)` |
| 结果 | 信号变化 | 调用 `ap.write(txn)` |

---

### 第 5 步：axi_slv_cfg.sv — Slave 配置对象

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_slv_cfg.sv` |
| 角色 | 控制 Slave Driver 的行为参数 |
| 阅读时间 | 10 分钟 |
| 前置知识 | 无 |

#### 这个文件做了什么？

`axi_slv_cfg` 是一个"配置单"，告诉 Slave Driver 怎么工作：要不要注入错误？要不要模拟背压？延迟多少？

#### 逐段阅读指引

**第 30-38 行 — 错误注入参数**

```systemverilog
int unsigned err_pct = 0;       // 错误概率 (0~100%)
bit [1:0]    err_resp = 2'b10;  // 错误类型 (SLVERR/DECERR)
```

**你要理解的**：
- `err_pct=0` 表示不注入错误（默认行为）
- `err_pct=30` 表示约 30% 的事务会返回错误响应
- 用于测试 DUT 对错误响应的处理能力

---

**第 55-60 行 — 背压参数**

```systemverilog
int unsigned bp_awready_pct = 0;   // AW通道背压概率
int unsigned bp_wready_pct = 0;    // W通道背压概率
int unsigned bp_arready_pct = 0;   // AR通道背压概率
```

**你要理解的**：
- 背压 = Slave 通过拉低 `ready` 信号说"我还没准备好"
- `bp_wready_pct=80` 表示 80% 的时间 W 通道的 ready 为低
- 用于测试 DUT 在拥塞情况下的行为

---

**第 75-88 行 — 辅助函数**

```systemverilog
function int get_delay();
    return $urandom_range(delay_min, delay_max);  // 返回随机延迟
endfunction

function bit should_error();
    return ($urandom_range(0, 99) < err_pct);     // 按概率决定
endfunction
```

**你要理解的**：
- 这些函数封装了随机决策逻辑
- Slave Driver 调用这些函数来决定"这个事务要不要注入错误"

---

### 第 6 步：axi_slv_drv.sv — Slave 驱动器

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_slv_drv.sv` |
| 角色 | "模拟厨房"——被动响应 DUT 的读写请求 |
| 阅读时间 | 25 分钟 |
| 前置知识 | 第 3、4、5 步 |

#### 这个文件做了什么？

Slave Driver 是"被动响应型"组件：**不从 Sequencer 获取事务**，而是监听 DUT 发出的请求，然后响应。它内部有一个存储器模型（`mem[]`），写入的数据会被保存，读取时返回保存的值。

#### 与 Master Driver 的本质区别

| 对比项 | Master Driver | Slave Driver |
|--------|--------------|-------------|
| 工作模式 | 主动：获取事务→驱动信号 | 被动：监听请求→响应信号 |
| 需要 Sequencer？ | ✅ 是 | ❌ 否 |
| 需要 Sequence？ | ✅ 是 | ❌ 否 |
| 数据来源 | Sequence 产生的 txn | DUT 发出的信号 |
| 存储器模型 | 无 | 有（`mem[]`） |

---

**第 45 行 — 存储器模型**

```systemverilog
bit [7:0] mem[bit [31:0]];
```

**你要理解的**：
- 这是一个**关联数组**，索引是 32 位地址，值是 8 位数据（1 字节）
- 不需要预先分配空间，只在实际写入时创建条目
- 写入时按字节存储，读取时按字节拼接

---

**第 81-96 行 — run_phase**

```systemverilog
task run_phase(uvm_phase phase);
    vif.awready <= 0; vif.wready <= 0; ...  // 初始化

    fork
        wr_handler();   // 处理写请求（AW+W+B）
        rd_handler();   // 处理读请求（AR+R）
    join
endtask
```

**你要理解的**：
- 和 Monitor 一样，用 `fork...join` 同时处理读和写
- 因为 AXI 的读和写是独立的，DUT 可能同时发起读和写请求

---

**第 105-176 行 — wr_handler 写处理**

```systemverilog
task wr_handler();
    forever begin
        // 阶段1: AW通道 — 接收写地址
        while (!(vif.awvalid && vif.awready)) begin
            vif.awready <= !cfg.should_bp(0);  // 按概率施加背压
            @(posedge vif.aclk);
        end
        awaddr = vif.awaddr;                    // 采样地址
        inject_err = cfg.should_error();        // 决定是否注入错误

        // 阶段2: W通道 — 接收写数据并存入mem
        for (int i = 0; i < awlen + 1; i++) begin
            // 等待握手...
            if (!inject_err) begin
                mem[wr_addr]     = vif.wdata[7:0];    // 存字节0
                mem[wr_addr + 1] = vif.wdata[15:8];   // 存字节1
                mem[wr_addr + 2] = vif.wdata[23:16];  // 存字节2
                mem[wr_addr + 3] = vif.wdata[31:24];  // 存字节3
            end
            wr_addr += 4;                              // 地址递增4字节
        end

        // 阶段3: B通道 — 发送写响应
        vif.bresp <= inject_err ? cfg.err_resp : 2'b00;  // 正常或错误
        vif.bvalid <= 1;
        // 等待 bready...
    end
endtask
```

**关键逻辑**：
- 背压：通过 `cfg.should_bp()` 按概率拉低 ready
- 错误注入：通过 `cfg.should_error()` 按概率决定不写入数据 + 返回错误响应
- 存储器写入：32 位数据拆成 4 个字节存入 `mem[]`

---

**第 184-242 行 — rd_handler 读处理**

```systemverilog
task rd_handler();
    forever begin
        // 阶段1: AR通道 — 接收读地址
        // ...握手 + 采样地址...

        // 阶段2: R通道 — 从mem读取数据并返回
        for (int i = 0; i < blen; i++) begin
            vif.rdata <= inject_err ? 32'hDEAD_BEEF :    // 错误时返回标记值
                         {mem[araddr+3], mem[araddr+2],
                          mem[araddr+1], mem[araddr]};     // 从小端序拼接
            vif.rresp <= inject_err ? cfg.err_resp : 2'b00;
            vif.rlast <= (i == blen - 1);                  // 最后一拍
            // 等待 rready...
        end
    end
endtask
```

**关键逻辑**：
- 存储器读取：从小端序拼接 `{byte3, byte2, byte1, byte0}` = 32 位数据
- 错误注入时返回 `0xDEAD_BEEF`（一个明显的标记值）

---

### 第 7 步：axi_env.sv — 顶层环境

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_env.sv` |
| 角色 | "总指挥"——创建和连接所有组件 |
| 阅读时间 | 20 分钟 |
| 前置知识 | 第 1~6 步 |

#### 这个文件做了什么？

`axi_env.sv` 是验证平台的"骨架"，负责：
1. 创建所有 Agent（每个 Agent 内含 Driver + Sequencer + Monitor）
2. 创建 Scoreboard 和 Coverage
3. 把 Monitor 的"广播喇叭"连接到 Scoreboard 和 Coverage

#### 逐段阅读指引

**第 15-60 行 — 组件句柄声明**

```systemverilog
class axi_env extends uvm_env;
    axi_mst_agent mst_agent[4];       // 4个Master Agent
    axi_slv_agent slv_agent[4];       // 4个Slave Agent
    axi_scoreboard scbd;              // 1个Scoreboard
    axi_coverage   cov;               // 1个Coverage
    axi_slv_cfg    slv_cfg[4];        // 4个Slave配置
```

**你要理解的**：
- 4 个 Master Agent 对应 DUT 的 4 个 Slave 端口（DUT 的 Slave 接收外部 Master 的请求）
- 4 个 Slave Agent 对应 DUT 的 4 个 Master 端口（DUT 的 Master 向外部 Slave 发请求）
- Scoreboard 和 Coverage 各只有 1 个，全局共享

---

**第 72-106 行 — build_phase（创建组件）**

```systemverilog
function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    for (int i = 0; i < 4; i++) begin
        // 创建Master Agent
        mst_agent[i] = axi_mst_agent::type_id::create(
            $sformatf("mst_agent%0d", i), this);

        // 创建Slave配置并通过config_db传递
        slv_cfg[i] = axi_slv_cfg::type_id::create(...);
        uvm_config_db#(axi_slv_cfg)::set(this,
            $sformatf("slv_agent%0d", i), "cfg", slv_cfg[i]);

        // 创建Slave Agent
        slv_agent[i] = axi_slv_agent::type_id::create(
            $sformatf("slv_agent%0d", i), this);
    end

    // 创建Scoreboard和Coverage
    scbd = axi_scoreboard::type_id::create("scbd", this);
    cov  = axi_coverage::type_id::create("cov", this);
endfunction
```

**你要理解的**：
- 所有组件都通过 `type_id::create` 工厂方法创建（而非 `new`）
- 工厂创建的好处：可以在 test 层用 factory override 替换任何组件
- `config_db::set` 把配置参数"放到"数据库，子组件通过 `config_db::get` 获取

---

**第 112-136 行 — connect_phase（连接组件）**

```systemverilog
function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    for (int i = 0; i < 4; i++) begin
        // 把Master Monitor的广播连接到Scoreboard
        mst_agent[i].monitor.ap.connect(scbd.imp);

        // 把Master Monitor的广播连接到Coverage
        mst_agent[i].monitor.ap.connect(cov.analysis_export);
    end
endfunction
```

**你要理解的**：
- `connect_phase` 在所有 `build_phase` 完成后执行
- `ap.connect(imp)` 把 Monitor 的"广播喇叭"接到 Scoreboard 的"接收器"上
- 连接后，Monitor 每次调用 `ap.write(txn)`，Scoreboard 和 Coverage 都会收到

---

### 第 8 步：axi_mst_agent.sv / axi_slv_agent.sv — Agent 代理

| 项目 | 内容 |
|------|------|
| 文件 | `components/axi_mst_agent.sv` 和 `components/axi_slv_agent.sv` |
| 角色 | "快递站"——把 Driver + Sequencer + Monitor 封装在一起 |
| 阅读时间 | 15 分钟 |
| 前置知识 | 第 3、4 步 |

#### 为什么需要 Agent？

假设没有 Agent，`axi_env.sv` 要手动管理所有细节：

```
没有 Agent 时 env 要做的事：
├── 创建 mst_drv[4]
├── 创建 sqr[4]
├── 创建 mst_mon[4]
├── 创建 slv_drv[4]
├── 创建 slv_mon[4]
├── 传递 vif 给每个 driver 和 monitor（8次 config_db::set）
├── 连接每个 driver 到 sequencer（4次 connect）
└── 总共 ~20 行重复代码

有了 Agent 之后 env 要做的事：
├── 创建 mst_agent[4]     ← 一行搞定
├── 创建 slv_agent[4]     ← 一行搞定
└── Agent 内部自动完成创建+连接+传参
```

#### axi_mst_agent.sv 逐段解析

**第 35-62 行 — 组件句柄声明**

```systemverilog
class axi_mst_agent extends uvm_agent;
    axi_mst_drv driver;                    // Master Driver
    uvm_sequencer #(axi_txn) sequencer;    // Sequencer（UVM内置）
    axi_monitor monitor;                   // Monitor
    uvm_active_passive_enum is_active = UVM_ACTIVE;  // Active模式
    virtual axi_if vif;                    // 虚拟接口
```

**你要理解的**：
- Agent 内部包含 3 个子组件：Driver + Sequencer + Monitor
- `is_active = UVM_ACTIVE` 表示"主动模式"（包含 Driver）
- 如果设为 `UVM_PASSIVE`，只创建 Monitor（用于纯观察场景）

---

**第 75-97 行 — build_phase（创建子组件 + 传参）**

```systemverilog
function void build_phase(uvm_phase phase);
    // 1. 从 config_db 获取接口
    uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif);

    // 2. 把接口传递给 driver 和 monitor
    uvm_config_db#(virtual axi_if)::set(this, "driver", "vif", vif);
    uvm_config_db#(virtual axi_if)::set(this, "monitor", "vif", vif);

    // 3. 创建子组件
    monitor = axi_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
        driver    = axi_mst_drv::type_id::create("driver", this);
        sequencer = uvm_sequencer#(axi_txn)::type_id::create("sequencer", this);
    end
endfunction
```

**你要理解的**：
- Agent 是"中间层"：从 env 获取 vif，再传给自己的子组件
- 只有 Active 模式才创建 Driver 和 Sequencer

---

**第 103-114 行 — connect_phase（连接 Driver-Sequencer）**

```systemverilog
function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
    end
endfunction
```

**你要理解的**：
- 这是 UVM 的标准连接模式
- `seq_item_port` 是 Driver 的"取货口"
- `seq_item_export` 是 Sequencer 的"出货口"
- 连接后，Driver 就能从 Sequencer 获取事务了

---

#### axi_slv_agent.sv 与 Master Agent 的区别

| 对比项 | Master Agent | Slave Agent |
|--------|-------------|-------------|
| Driver | axi_mst_drv（主动驱动） | axi_slv_drv（被动响应） |
| Sequencer | ✅ 有 | ❌ 无（不需要） |
| Monitor | ✅ 有 | ✅ 有 |
| 原因 | Master 需要主动产生事务 | Slave 只被动响应 DUT 请求 |

---

### 第 9 步：sequences/ — 测试序列

| 项目 | 内容 |
|------|------|
| 文件 | `sequences/axi_wr_seq.sv`（以写序列为例） |
| 角色 | "订单模板"——定义测试场景，产生 Transaction |
| 阅读时间 | 15 分钟 |
| 前置知识 | 第 2 步（axi_txn） |

#### Sequence 的工作原理

```
Test 调用 seq.start(sequencer)
  │
  ▼
sequencer 调度 sequence 的 body()
  │
  ▼
body() 内部：
  │  创建 txn
  │  填充字段
  │  start_item(txn)   ← 请求 sequencer 许可
  │  finish_item(txn)  ← 发送给 driver，等 driver 完成
  │
  ▼
body() 返回 → sequence 执行完毕
```

#### axi_wr_seq.sv 逐段解析

**第 13-29 行 — 类定义和参数**

```systemverilog
class axi_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_seq)

    bit [15:0] s_addr;   // 目标地址（由 test 设置）
    bit [31:0] s_data;   // 写入数据（由 test 设置）
    bit [7:0]  s_id;     // 事务ID（由 test 设置）
```

**你要理解的**：
- Sequence 继承 `uvm_sequence#(axi_txn)`，指定产生什么类型的事务
- `s_addr`、`s_data`、`s_id` 是"参数"，由 Test 在 `start()` 之前设置
- 这样同一个 Sequence 可以通过不同参数测试不同场景

---

**第 40-75 — body() 核心逻辑**

```systemverilog
task body();
    // 第1步: 创建事务
    axi_txn txn = axi_txn::type_id::create("txn");

    // 第2步: 填充字段
    txn.kind = axi_txn::WRITE;
    txn.addr = s_addr;      // 从参数获取
    txn.id   = s_id;        // 从参数获取
    txn.len  = 0;           // 单拍传输
    txn.size = 2;           // 每拍4字节
    txn.wdata = new[1];     // 1拍数据
    txn.wdata[0] = s_data;  // 从参数获取
    txn.wstrb = new[1];
    txn.wstrb[0] = 4'hF;   // 4字节全部有效

    // 第3步: 发送给 sequencer → driver
    start_item(txn);        // 向 sequencer 申请许可（可能阻塞）
    finish_item(txn);       // 发送给 driver，等 driver 完成（阻塞）
endtask
```

**`start_item` 和 `finish_item` 的含义**：

```
start_item(txn):
  → 告诉 sequencer "我有一个事务要发"
  → 如果 sequencer 正忙（被其他 sequence 占用），会阻塞等待
  → 类比：快递员问调度员"我现在能发这个包裹吗？"

finish_item(txn):
  → 把 txn 实际交给 driver
  → driver 调用 get_next_item() 获取 txn
  → driver 驱动信号到 DUT
  → driver 调用 item_done()
  → finish_item() 才返回
  → 类比：把包裹交给快递员，等他送完回来报告
```

---

#### 常见 Sequence 类型一览

| Sequence | body() 中的关键区别 | 测试场景 |
|----------|-------------------|---------|
| `axi_wr_seq` | kind=WRITE, len=0, 单拍写 | 基本写功能 |
| `axi_rd_seq` | kind=READ, len=0, 单拍读 | 基本读功能 |
| `axi_burst_wr_seq` | len>0, wdata 有多个元素 | 突发写传输 |
| `axi_burst_rd_seq` | len>0, rdata 有多个元素 | 突发读传输 |
| `axi_random_seq` | 所有字段随机化，不设固定值 | 随机激励 |
| `axi_boundary_seq` | 使用 `c_boundary_addr` 约束 | 边界地址 |
| `axi_concurrent_seq` | fork...join 同时启动读写 | 并发场景 |
| `axi_err_inject_seq` | 配合 slv_cfg 的错误注入 | 错误处理 |

---

### 第 10 步：tests/ — 测试用例

| 项目 | 内容 |
|------|------|
| 文件 | `tests/axi_base_test.sv` + `tests/axi_basic_test.sv` |
| 角色 | "测试计划"——配置环境、启动 Sequence、控制仿真 |
| 阅读时间 | 20 分钟 |
| 前置知识 | 第 7、8、9 步 |

#### Test 的职责

```
Test 做三件事：
  1. build_phase: 创建 env（验证环境）
  2. run_phase:   创建 sequence → 配置参数 → start(sequencer)
  3. 控制仿真：   raise_objection / drop_objection
```

#### axi_base_test.sv — 基类（所有 Test 的模板）

```systemverilog
class axi_base_test extends uvm_test;
    `uvm_component_utils(axi_base_test)
    axi_env env;    // 验证环境句柄

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);  // 创建环境
    endfunction
endclass
```

**你要理解的**：
- `axi_base_test` 只做一件事：创建 `env`
- 所有具体 Test 都继承它，只需要写 `run_phase`

---

#### axi_basic_test.sv — 具体测试（以基本读写为例）

**第 41-121 行 — run_phase 完整流程**

```systemverilog
task run_phase(uvm_phase phase);
    axi_wr_seq wr_seq;
    axi_rd_seq rd_seq;

    // ① 阻止仿真结束
    phase.raise_objection(this);

    // ② 等待复位释放 + 稳定
    @(posedge env.mst_agent[0].driver.vif.aresetn);
    repeat(5) @(posedge env.mst_agent[0].driver.vif.aclk);

    // ③ 写测试：向4个Slave各写一笔
    for (int s = 0; s < 4; s++) begin
        wr_seq = axi_wr_seq::type_id::create($sformatf("wr_seq%0d", s));
        wr_seq.s_addr = s * 16'h1000;      // Slave 0/1/2/3 的基地址
        wr_seq.s_data = 32'hDEAD0000 + s;  // 区分不同Slave的数据
        wr_seq.s_id   = 8'h10;             // 事务ID
        wr_seq.start(env.mst_agent[0].sequencer);  // 启动！
    end

    #200;  // 等待写操作完成

    // ④ 读测试：从4个Slave各读一笔
    for (int s = 0; s < 4; s++) begin
        rd_seq = axi_rd_seq::type_id::create($sformatf("rd_seq%0d", s));
        rd_seq.s_addr = s * 16'h1000;
        rd_seq.s_id   = 8'h10;
        rd_seq.start(env.mst_agent[0].sequencer);  // 启动！
    end

    #200;

    // ⑤ 允许仿真结束
    phase.drop_objection(this);
endtask
```

**逐行翻译**：

| 行 | 代码 | 做了什么 |
|----|------|---------|
| ① | `raise_objection(this)` | 告诉 UVM："我还有工作，别停仿真" |
| ② | `@(posedge vif.aresetn)` | 等复位信号变高（复位释放） |
| ③ | `wr_seq.start(sequencer)` | 把写序列交给 sequencer，等它执行完 |
| ④ | `rd_seq.start(sequencer)` | 把读序列交给 sequencer，等它执行完 |
| ⑤ | `drop_objection(this)` | 告诉 UVM："我做完了，可以停了" |

---

#### Test → Sequence → Driver 的完整调用链

```
axi_basic_test.run_phase()
  │
  │  wr_seq.start(env.mst_agent[0].sequencer)
  │    │
  │    ▼
  │  axi_wr_seq.body()
  │    │  txn = axi_txn::type_id::create("txn")
  │    │  txn.kind = WRITE, txn.addr = 0x0000, ...
  │    │
  │    │  start_item(txn)      ← 向 sequencer 申请许可
  │    │    │
  │    │    ▼
  │    │  sequencer 调度给 driver
  │    │    │
  │    │    ▼
  │    │  driver.get_next_item(txn)   ← driver 拿到 txn
  │    │  driver.drive_wr(txn)        ← 驱动 AW+W+B 信号
  │    │  driver.item_done()          ← 通知完成
  │    │
  │    │  finish_item(txn) 返回       ← driver 完成，sequence 继续
  │    │
  │    ▼
  │  body() 返回                     ← sequence 执行完毕
  │
  │  wr_seq.start() 返回             ← 回到 test
  │
  │  drop_objection(this)            ← 允许仿真结束
  ▼
仿真结束
```

---

#### 不同 Test 的区别

| Test | 测试目的 | Sequence 组合 |
|------|---------|--------------|
| `axi_basic_test` | 基本读写 | wr_seq + rd_seq |
| `axi_random_test` | 随机激励 | axi_random_seq |
| `axi_routing_test` | 地址路由 | axi_full_routing_seq |
| `axi_boundary_addr_test` | 边界地址 | axi_boundary_seq |
| `axi_bp_wready_test` | W通道反压 | wr_seq + 配置 slv_cfg.bp_wready_pct |
| `axi_err_slverr_test` | 从机错误 | wr_seq + 配置 slv_cfg.err_pct |
| `axi_multi_master_test` | 多主机并发 | fork...join 同时启动多个 sequence |
| `axi_reset_wr_test` | 写通道复位 | wr_seq + 中途复位 |

---

## 四、三者联动：Test + Sequence + Agent 的完整关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        Test 层                                    │
│  axi_basic_test.sv                                               │
│    │  build_phase: 创建 env                                      │
│    │  run_phase:                                                  │
│    │    创建 sequence, 设置参数                                   │
│    │    seq.start(env.mst_agent[0].sequencer)                     │
│    └──────────────────────────────────────────────────────┐      │
│                                                           │      │
├───────────────────────────────────────────────────────────┼──────┤
│                        Sequence 层                        │      │
│  axi_wr_seq.sv                                            │      │
│    │  body():                                              │      │
│    │    创建 axi_txn                                       │      │
│    │    填充字段 (kind, addr, len, size, wdata)            │      │
│    │    start_item(txn) → finish_item(txn)                 │      │
│    └───────────────────────────────────────────┐          │      │
│                                                │          │      │
├────────────────────────────────────────────────┼──────────┼──────┤
│                        Agent 层                │          │      │
│  axi_mst_agent.sv                              │          │      │
│    │  内部包含:                                 │          │      │
│    │    sequencer ←────────────────────────────┘          │      │
│    │      │  调度 txn 给 driver                           │      │
│    │    driver ←──────────────────────────────────────────┘      │
│    │      │  get_next_item(txn)                                  │
│    │      │  drive_wr(txn) → 驱动信号到 DUT                      │
│    │      │  item_done()                                         │
│    │    monitor                                                  │
│    │      │  观察 DUT 信号                                       │
│    │      │  ap.write(txn) → 广播给 scoreboard/coverage          │
│    └─────────────────────────────────────────────────────        │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│                        检查层                                      │
│  axi_scoreboard.sv  ← 收到 txn, 路由验证 + 数据比对              │
│                      双端口: mst_imp + slv_imp                    │
│                      check_phase 延迟匹配                         │
│  axi_coverage.sv    ← 收到 txn, 更新覆盖率                       │
└───────────────────────────────────────────────────────────────────┘
```

---

## 五、目录结构说明

```
verification/
├── infra/                ← 基础设施（接口 + Package）
│   ├── axi_if.sv         ← AXI 接口定义（信号集合）
│   └── axi_pkg.sv        ← Package（打包所有组件）
│
├── components/           ← UVM 组件
│   ├── axi_txn.sv        ← Transaction（数据包）
│   ├── axi_mst_drv.sv    ← Master Driver（主动驱动）
│   ├── axi_slv_drv.sv    ← Slave Driver（被动响应）
│   ├── axi_monitor.sv    ← Monitor（被动观察）
│   ├── axi_mst_agent.sv  ← Master Agent（封装 drv+sqr+mon）
│   ├── axi_slv_agent.sv  ← Slave Agent（封装 drv+mon）
│   ├── axi_scoreboard.sv ← Scoreboard（路由验证 + 数据校验）
│   ├── axi_coverage.sv   ← Coverage（覆盖率）
│   ├── axi_slv_cfg.sv    ← Slave 配置对象
│   └── axi_env.sv        ← Environment（顶层环境）
│
├── sequences/            ← 测试序列（定义测试场景）
│   ├── axi_wr_seq.sv     ← 单次写
│   ├── axi_rd_seq.sv     ← 单次读
│   └── ...（共15个）
│
├── tests/                ← 测试用例（配置环境+启动序列）
│   ├── axi_base_test.sv  ← 基类（创建env）
│   ├── axi_basic_test.sv ← 基本读写
│   └── ...（共17个，已合并同类测试）
│
└── tb/                   ← Testbench 顶层
    └── axi_crossbar_tb.sv ← 时钟/复位/DUT例化/config_db/run_test()
```

**命名说明**：
- `infra/`（原 `env/`）：基础设施文件，不是 UVM Environment
- `components/axi_env.sv`：才是真正的 UVM Environment 类
- 两者名字相似但含义不同，已通过文件夹区分

### 路由验证机制

本项目实现了**双端 Scoreboard**，用于验证 AXI Crossbar 的路由正确性：

```
Master Monitor ──→ mst_imp ──→ write_master()
                                    │
                                    ▼
                               记录期望路由
                                    │
Slave Monitor  ──→ slv_imp ──→ write_slave()
                                    │
                                    ▼
                               检查实际路由
```

**验证策略**：
1. Master Monitor 观测"进入 DUT"的事务，记录期望的 Slave ID
2. Slave Monitor 观测"离开 DUT"的事务，获取实际的 Slave ID
3. 在 `check_phase` 中比对：事务是否到达正确的 Slave？

**关键代码**：
```systemverilog
// axi_scoreboard.sv
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_master #(axi_txn, axi_scoreboard) mst_imp;
    uvm_analysis_imp_slave #(axi_txn, axi_scoreboard) slv_imp;

    // check_phase: 仿真结束时进行路由验证
    function void check_phase(uvm_phase phase);
        // 比对 Master 事务和 Slave 事务
        foreach (mst_wr_txns[i]) begin
            int expected_slave = mst_wr_txns[i].addr[15:12];
            // 在 Slave 事务中查找匹配...
        end
    endfunction
endclass
```

---

## 六、辅助文件速查表

### Package 和 Testbench Top

| 文件 | 角色 | 核心内容 |
|------|------|---------|
| `infra/axi_pkg.sv` | Package | 把所有组件用 `include` 打包在一起；`import axi_pkg::*` 后可使用所有类 |
| `tb/axi_crossbar_tb.sv` | Testbench Top | 生成时钟/复位；例化接口和 DUT；通过 `config_db` 传递 vif；调用 `run_test()` 启动 UVM |

### Sequence 文件（了解即可，不需要精读）

| 文件 | 测试场景 | 关键实现 |
|------|---------|---------|
| `axi_wr_seq.sv` | 单次写事务 | body() 中创建 txn → 设置字段 → start_item/finish_item |
| `axi_rd_seq.sv` | 单次读事务 | 同上，kind=READ |
| `axi_burst_wr_seq.sv` | 多拍突发写 | len>0，wdata 数组有多个元素 |
| `axi_burst_rd_seq.sv` | 多拍突发读 | len>0，rdata 数组有多个元素 |
| `axi_burst_size_seq.sv` | 不同 burst size | size 随机化为 0/1/2 |
| `axi_random_seq.sv` | 完全随机事务 | 所有字段随机化，不设固定值 |
| `axi_boundary_seq.sv` | 边界地址测试 | 使用 `c_boundary_addr` 约束 |
| `axi_backpressure_seq.sv` | 背压测试 | 配合 Slave 配置的背压参数 |
| `axi_err_inject_seq.sv` | 错误注入测试 | 配合 Slave 配置的错误注入参数 |
| `axi_concurrent_seq.sv` | 并发读写 | fork...join 同时启动读写 sequence |
| `axi_interleave_seq.sv` | 读写交替 | 交替启动读和写 |
| `axi_full_routing_seq.sv` | 全路由覆盖 | 遍历所有 Master→Slave 组合 |
| `axi_outstanding_read_seq.sv` | Outstanding 读 | 连续发起多个读请求不等响应 |
| `axi_perf_seq.sv` | 性能测试 | 高吞吐量场景 |
| `axi_same_slave_seq.sv` | 同一 Slave 竞争 | 多个 Master 同时访问同一 Slave |

### Test 文件（共 17 个，已合并同类测试）

**合并策略**：将测试场景相似的 Test 合并为一个，减少文件数量，提高可维护性。

| 文件 | 测试目的 | 合并说明 |
|------|---------|---------|
| `axi_base_test.sv` | 所有 test 的基类，build_phase 中创建 env | - |
| `axi_basic_test.sv` | 基本读写功能：写4个Slave → 读回来 → Scoreboard比较 | 验证路由正确性 |
| `axi_routing_test.sv` | 地址路由正确性 | 验证路由正确性 |
| `axi_full_routing_test.sv` | 全路由覆盖（所有 Master→Slave 组合） | 验证路由正确性 |
| `axi_boundary_test.sv` | 边界条件测试 | 合并：边界地址 + 最大突发长度 + 最大 Outstanding |
| `axi_backpressure_test.sv` | 反压测试 | 合并：W/R/B 通道反压 + 全通道反压 |
| `axi_error_test.sv` | 错误处理测试 | 合并：SLVERR + DECERR + 错误恢复 |
| `axi_outstanding_test.sv` | Outstanding 事务测试 | 合并：写 Outstanding + 读 Outstanding |
| `axi_perf_test.sv` | 性能测试 | 合并：延迟测试 + 带宽测试 |
| `axi_reset_test.sv` | 复位测试 | 合并：写通道复位 + 读通道复位 + 复位恢复 |
| `axi_burst_size_test.sv` | 不同 burst size | - |
| `axi_interleave_test.sv` | 读写交织 | - |
| `axi_multi_master_test.sv` | 多主机并发 | - |
| `axi_protocol_test.sv` | 协议合规测试 | - |
| `axi_random_test.sv` | 随机激励测试 | - |
| `axi_random_concurrent_test.sv` | 随机并发测试 | - |
| `axi_same_slave_test.sv` | 同一 Slave 竞争 | - |

---

## 七、UVM 核心概念与文件对应关系

```
UVM 概念              对应文件               类比
─────────────────────────────────────────────────────
Transaction           axi_txn.sv            快递单
Sequencer             uvm_sequencer (内置)   调度员
Sequence              sequences/*.sv         订单列表
Driver                axi_mst_drv.sv         快递员
Monitor               axi_monitor.sv         监控摄像头
Agent                 axi_mst_agent.sv       快递站 (包含调度员+快递员+摄像头)
Scoreboard            axi_scoreboard.sv      对账本
Coverage              axi_coverage.sv        检查清单
Environment           axi_env.sv             总指挥部
Test                  tests/*.sv             测试计划
Config DB             config_db 机制          内部通知系统
Factory               type_id::create        工厂生产线
```

---

## 八、一条写操作的完整旅程

以 "Master 0 往地址 0x1000 写入 4 拍数据" 为例：

```
步骤  谁在工作            做了什么                    对应文件
──────────────────────────────────────────────────────────────────
 1    Test               创建 sequence, 启动          axi_basic_test.sv
 2    Sequence           产生 1 个 axi_txn            axi_wr_seq.sv
      (axi_wr_seq)       kind=WRITE, addr=0x1000
                         len=3, wdata[0..3]=...
 3    Sequencer          收到 txn, 调度给 driver       uvm_sequencer (内置)
 4    Master Driver      收到 txn, 开始驱动信号        axi_mst_drv.sv
      (axi_mst_drv)
 4a                     AW 通道: awvalid=1            第 127-141 行
                         awaddr=0x1000, awlen=3
                         等待 awready=1
 4b                     W 通道: 逐拍发送 wdata         第 146-153 行
                         wdata[0]→wdata[1]→...
                         最后一拍 wlast=1
 4c                     B 通道: 等待响应               第 157-163 行
                         bready=1, 等 bvalid=1
                         采样 bresp
 5    Slave Driver       被动响应 DUT 的请求           axi_slv_drv.sv
      (axi_slv_drv)      收到写地址 → 收到写数据
                         写入 mem[] → 返回 bresp
 6    Monitor            观察到完整写事务              axi_monitor.sv
      (axi_monitor)      还原成 axi_txn 对象
                         通过 ap 广播出去
 7    Scoreboard         收到 txn, 记录到期望队列      axi_scoreboard.sv
 8    Coverage           收到 txn, 更新覆盖率         axi_coverage.sv
──────────────────────────────────────────────────────────────────
```

---

## 九、Testbench Top — 最顶层模块

| 项目 | 内容 |
|------|------|
| 文件 | `tb/axi_crossbar_tb.sv` |
| 角色 | 连接 UVM 世界和 DUT 世界的桥梁 |
| 阅读时间 | 15 分钟 |

### 这个文件做了什么？

Testbench Top 是一个普通的 `module`（不是 UVM 组件），它做 5 件事：

```
1. 产生时钟和复位
2. 例化 Interface（mst_if[4] + slv_if[4]）
3. 例化 DUT，把 Interface 连到 DUT 端口
4. 通过 config_db 把 Interface 传给 UVM 组件
5. 调用 run_test() 启动 UVM
```

### 关键代码解析

**时钟和复位生成**：

```systemverilog
logic aclk = 0;
logic aresetn = 0;
always #5 aclk = ~aclk;              // 100MHz（周期10ns）
initial begin #100; aresetn = 1; end  // 100ns后释放复位
```

**config_db 传递接口**：

```systemverilog
// 把 mst_if[0] 传给名字匹配 "*.mst_drv0" 的组件
uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv0", "vif", mst_if[0]);
//                                    │      │            │      │
//                                 全局    路径匹配      key    值
```

**启动 UVM**：

```systemverilog
run_test("axi_basic_test");  // 创建并运行指定的 Test
```

### 为什么需要 Testbench Top？

UVM 组件是 `class`，不能直接例化 `interface`（module）。Testbench Top 是 `module`，可以例化 interface 和 DUT，然后通过 `config_db` 把 interface 的"指针"（virtual interface）传给 UVM 组件。

---

## 十、Package — 把所有文件串起来

| 项目 | 内容 |
|------|------|
| 文件 | `infra/axi_pkg.sv` |
| 角色 | 把所有 UVM 组件打包在一起 |
| 阅读时间 | 5 分钟 |

### 这个文件做了什么？

`axi_pkg.sv` 用 `include` 把所有组件文件"粘贴"到一个 package 里。Testbench Top 只需 `import axi_pkg::*` 就能使用所有类。

```systemverilog
package axi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // 组件（按依赖顺序）
    `include "components/axi_slv_cfg.sv"    // 先编译：配置类
    `include "components/axi_txn.sv"        // 先编译：事务类
    `include "components/axi_mst_drv.sv"    // 依赖 txn
    `include "components/axi_slv_drv.sv"    // 依赖 txn, cfg
    `include "components/axi_monitor.sv"    // 依赖 txn
    `include "components/axi_scoreboard.sv" // 依赖 txn
    `include "components/axi_coverage.sv"   // 依赖 txn
    `include "components/axi_env.sv"        // 依赖以上所有

    // 序列
    `include "sequences/axi_wr_seq.sv"
    // ... 其他序列 ...

    // 测试
    `include "tests/axi_base_test.sv"
    `include "tests/axi_basic_test.sv"
    // ... 其他测试 ...
endpackage
```

### 编译顺序很重要

```
1. infra/axi_if.sv         ← Interface 先编译（package 里的类需要 virtual interface 类型）
2. infra/axi_pkg.sv        ← Package 编译（include 所有类）
3. tb/axi_crossbar_tb.sv   ← Testbench Top 编译（import package）
```

`include 的顺序 = 编译顺序`。后面的文件可以引用前面的类，反之不行。

---

## 十一、Makefile — 一键编译运行

| 项目 | 内容 |
|------|------|
| 文件 | `Makefile` |
| 角色 | 自动化编译和仿真 |
| 阅读时间 | 10 分钟 |

### 常用命令

```bash
# 编译
make compile SIM=vcs

# 运行单个测试
make sim SIM=vcs UVM_TEST=axi_basic_test

# 运行回归测试（所有测试）
make regression SIM=vcs

# 清理编译产物
make clean
```

### Makefile 结构

```makefile
# RTL 文件
SRC_FILES = ../src/axicb_crossbar_top.sv ...

# TB 文件（注意顺序：interface → package → module）
TB_FILES = \
    infra/axi_if.sv \
    infra/axi_pkg.sv \
    tb/axi_crossbar_tb.sv

# 编译选项
VCS_OPTS = -sverilog -full64 \
           +incdir+components +incdir+sequences +incdir+tests \
           -ntb_opts uvm-1.2 -timescale=1ns/1ps

# 仿真命令
sim: compile
    ./simv +UVM_TESTNAME=$(UVM_TEST) -l sim.log
```

### 运行和调试

**看仿真结果**：

```
UVM_INFO ... [SCBD] WR: 4 pass / 0 fail     ← Scoreboard：写事务全对
UVM_INFO ... [SCBD] RD: 4 pass / 0 fail     ← Scoreboard：读事务全对
UVM_INFO ... [COV] Coverage: 56.7%           ← 覆盖率
UVM_ERROR : 0                                ← 0 个错误
UVM_FATAL : 0                                ← 0 个致命错误
```

**常见错误排查**：

| 错误信息 | 原因 | 解决方法 |
|---------|------|---------|
| `NOVIF` | config_db 没传 vif | 检查 testbench top 的 `set()` 和 driver 的 `get()` 路径是否匹配 |
| `TIMEOUT` | objection 没放下 | 检查 `drop_objection()` 有没有漏 |
| `SCBD DATA MISMATCH` | 数据不对 | 检查 DUT 或 test 逻辑 |
| 编译报 `class not found` | include 顺序错 | 确保 `axi_txn.sv` 在 `axi_mst_drv.sv` 之前 |

---

## 十二、快速入门：30 分钟版

如果你时间有限，只看这 4 个文件的核心行：

| 顺序 | 文件 | 只看这些行 | 理解什么 |
|------|------|-----------|---------|
| 1 | axi_if.sv | 第 33-58 行 | 接口参数和端口 |
| 2 | axi_txn.sv | 第 19-74 行 | Transaction 的字段和约束 |
| 3 | axi_mst_drv.sv | 第 91-114 行 | Driver 的主循环 |
| 4 | axi_env.sv | 第 72-106 行 | 所有组件怎么创建的 |

---

## 十三、常见问题

**Q: 为什么没有独立的 sequencer 文件？**
A: 本项目直接使用 UVM 内置的 `uvm_sequencer#(axi_txn)`，没有特殊需求就不需要自定义。详见 `axi_mst_agent.sv` 第 47 行。

**Q: Agent 和 Environment 的区别是什么？**
A: Agent 封装一个端口的所有组件 (driver+sequencer+monitor)，Environment 是顶层，包含所有 Agent + scoreboard + coverage。

**Q: Sequence 和 Test 的区别是什么？**
A: Sequence 定义"测什么场景"，Test 定义"用哪些 sequence、怎么配置环境"。

**Q: 为什么 Slave Driver 不需要 Sequencer？**
A: 因为 Slave 是被动响应型——DUT 发请求，Slave 被动应答，不需要主动产生事务。

**Q: config_db 是什么？**
A: UVM 的全局配置数据库。Testbench Top 用 `set()` 把接口"放进去"，Driver/Monitor 用 `get()` 从里面"取出来"。就像一个内部公告板。

**Q: factory 是什么？**
A: UVM 的工厂机制。所有组件通过 `type_id::create()` 创建（而非 `new`），好处是可以在 test 层用 `set_type_override` 替换任何组件，无需修改代码。

**Q: 为什么 test 里要 `@(posedge vif.aresetn)`？**
A: 等复位释放。复位期间信号都是 0，不能发事务。等 `aresetn` 从 0 变 1，再等几个时钟周期，DUT 就稳定了。

**Q: `fork/join` 和 `fork/join_none` 的区别？**
A:
- `fork/join`：等所有子线程全部完成才继续（用于 Monitor、Slave Driver）
- `fork/join_none`：不等，立刻继续（子线程后台运行，用于并发测试）

**Q: 怎么加一个新的测试？**
A: 5 步：
1. 在 `sequences/` 下写一个新 sequence
2. 在 `tests/` 下写一个新 test，继承 `axi_base_test`
3. 在 `infra/axi_pkg.sv` 里 include 新文件
4. 在 `Makefile` 里加一个 target
5. `make compile && make sim UVM_TEST=你的test名`

**Q: 怎么提高覆盖率？**
A: 看覆盖率报告里哪些 bin 没覆盖到，然后：
- 加新的 sequence 刺激那个场景
- 在 test 里配置 sequence 的参数
- 用 `constraint_mode(0)` 关闭某些约束，让随机范围更大

**Q: `infra/` 和 `components/axi_env.sv` 有什么关系？**
A: 没有直接关系。`infra/` 放基础设施（接口+Package），`components/axi_env.sv` 是 UVM Environment 类。只是名字碰巧相似。
