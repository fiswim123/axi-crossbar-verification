# SystemVerilog & UVM 语法详解 — 基于 AXI Crossbar 项目的逐行教学

> 本文档逐行解释项目中用到的每个 SV/UVM 语法，配合实际代码片段。遇到不懂的语法直接搜对应章节。

---

## 目录

- [第一章：数据类型](#第一章数据类型)
- [第二章：过程块与并发](#第二章过程块与并发)
- [第三章：面向对象（class）](#第三章面向对象class)
- [第四章：Interface](#第四章interface)
- [第五章：约束随机](#第五章约束随机)
- [第六章：UVM 基础组件](#第六章uvm-基础组件)
- [第七章：UVM Sequence 机制](#第七章uvm-sequence-机制)
- [第八章：UVM TLM 端口](#第八章uvm-tlm-端口)
- [第九章：UVM Factory](#第九章uvm-factory)
- [第十章：UVM Phase](#第十章uvm-phase)
- [第十一章：UVM Config_db](#第十一章uvm-config_db)
- [第十二章：覆盖率](#第十二章覆盖率)
- [第十三章：SVA 断言](#第十三章sva-断言)
- [第十四章：常用系统函数](#第十四章常用系统函数)

---

## 第一章：数据类型

### 1.1 logic — 四态逻辑

```systemverilog
logic aclk = 0;
logic aresetn = 0;
logic awvalid, awready;
logic [15:0] awaddr;      // 16-bit 宽
logic [7:0]  awlen;       // 8-bit 宽
```

**`logic` 是什么？**

四态逻辑类型，值可以是 `0`、`1`、`x`（不确定）、`z`（高阻）。替代 Verilog 的 `reg` 和 `wire`。

| 类型 | 值 | 用途 |
|------|-----|------|
| `logic` | 0/1/x/z | 通用信号 |
| `bit` | 0/1 | 只有两态，仿真更快 |
| `wire` | 0/1/x/z | 多驱动（连续赋值） |

**`[15:0]` 是什么？**

位宽声明。`[15:0]` 表示 16 位，`[7:0]` 表示 8 位，`[2:0]` 表示 3 位。

---

### 1.2 bit — 两态逻辑

```systemverilog
bit [31:0] rdata;
bit [7:0]  bid;
bit [1:0]  bresp;
bit expect_err = 0;
```

**`bit` 和 `logic` 的区别？**

| | `logic` | `bit` |
|---|---|---|
| 值 | 0/1/x/z | 0/1 |
| 仿真速度 | 较慢 | 较快 |
| 用途 | 硬件信号 | 软件变量 |

`bit` 没有 x 和 z，仿真器不需要处理不确定态，所以更快。在 class 里用 `bit`，在 interface/module 里用 `logic`。

---

### 1.3 动态数组 — `[]`

```systemverilog
rand bit [31:0] wdata[];     // 动态数组：大小运行时确定
rand bit [3:0]  wstrb[];

// 使用前必须 new
txn.wdata = new[1];          // 分配 1 个元素
txn.wdata = new[txn.len + 1]; // 分配 len+1 个元素
```

**动态数组 vs 静态数组：**

```systemverilog
bit [31:0] fixed_arr[4];     // 静态：编译时固定 4 个元素
bit [31:0] dyn_arr[];        // 动态：运行时用 new[] 分配
```

**为什么用动态数组？**

因为 burst 长度不固定（len 可以是 0~15），数据数组大小要根据 len 动态分配。

---

### 1.4 关联数组 — `[key_type]`

```systemverilog
bit [7:0] mem[bit [31:0]];   // 关联数组：地址 → 数据
bit [31:0] exp_data[bit [31:0]]; // Scoreboard 的期望数据表
```

**关联数组是什么？**

像 C++ 的 `std::map`，按任意 key 访问，不需要连续分配内存。

```systemverilog
mem[32'h0000] = 8'hAA;       // 写入地址 0x0000
mem[32'h1000] = 8'hBB;       // 写入地址 0x1000

if (mem.exists(32'h0000))    // 检查地址是否存在
    data = mem[32'h0000];    // 读取
```

**为什么 Slave Driver 用关联数组做内存？**

地址空间 64KB，如果用静态数组要分配 64K 个元素。关联数组只存实际被写入的地址，节省内存。

---

### 1.5 枚举 — `typedef enum`

```systemverilog
typedef enum {READ, WRITE} kind_e;
rand kind_e kind;
```

**枚举是什么？**

给常量起名字。`READ = 0`，`WRITE = 1`。代码里用 `kind == axi_txn::WRITE` 比 `kind == 1` 可读性好。

**`::` 是什么作用域？**

`axi_txn::WRITE` 表示 `WRITE` 这个枚举值定义在 `axi_txn` 类里面。

---

### 1.6 参数化 — `parameter`

```systemverilog
interface axi_if #(
    parameter AXI_ADDR_W = 16,
    parameter AXI_ID_W   = 8,
    parameter AXI_DATA_W = 32
)
```

**`parameter` 是什么？**

编译时常量，例化时可以覆盖。类似 C++ 的 `#define` 但更安全。

```systemverilog
axi_if #(.AXI_ADDR_W(32)) my_if (.aclk(clk));  // 覆盖为 32-bit
```

---

## 第二章：过程块与并发

### 2.1 always — 时序逻辑

```systemverilog
always #5 aclk = ~aclk;     // 每 5ns 翻转 → 100MHz
```

**`#5` 是什么？**

延迟 5 个时间单位。`timescale 1ns/1ps` 下就是 5ns。

**`~` 是什么？**

按位取反。`~0 = 1`，`~1 = 0`。

---

### 2.2 initial — 初始化块

```systemverilog
initial begin
    #100;
    aresetn = 1;
    srst = 0;
end
```

**`initial` 是什么？**

仿真开始时执行一次的代码块。用于初始化信号、产生激励。

**`begin...end` 是什么？**

相当于 C 的 `{...}`，把多条语句组合成一个块。

---

### 2.3 forever — 无限循环

```systemverilog
forever begin
    axi_txn txn;
    seq_item_port.get_next_item(txn);  // 阻塞等待
    drive_wr(txn);
    seq_item_port.item_done();
end
```

**`forever` 是什么？**

无限循环，相当于 `while(1)`。Driver 的主循环必须是 `forever`，因为它要一直接收事务。

---

### 2.4 fork/join — 并行块

```systemverilog
// 4 个 master 并行写
fork
    begin seq.start(env.sqr[0]); end
    begin seq.start(env.sqr[1]); end
    begin seq.start(env.sqr[2]); end
    begin seq.start(env.sqr[3]); end
join   // 等全部完成才继续
```

**`fork/join` vs `fork/join_none` vs `fork/join_any`：**

| 类型 | 含义 |
|------|------|
| `fork/join` | 等**所有**子线程完成 |
| `fork/join_any` | 等**任意一个**完成 |
| `fork/join_none` | **不等**，立即继续 |

---

### 2.5 repeat — 重复执行

```systemverilog
repeat(5) @(posedge vif.aclk);  // 等 5 个时钟上升沿
```

**`@(posedge vif.aclk)` 是什么？**

等待 `aclk` 的上升沿（从 0 变 1 的瞬间）。

**`@(posedge vif.aclk iff (vif.awvalid && vif.awready))` 是什么？**

带条件的时钟边沿等待——只在 `awvalid && awready` 都为 1 的那个上升沿才继续。用于 AXI 握手采样。

---

### 2.6 非阻塞赋值 — `<=`

```systemverilog
vif.awvalid <= 1;     // 非阻塞：在时钟沿生效
vif.awaddr  <= addr;
```

**`<=` 和 `=` 的区别？**

| | `=`（阻塞） | `<=`（非阻塞） |
|---|---|---|
| 执行 | 立即生效 | 等时钟沿统一生效 |
| 用途 | 软件逻辑（class） | 硬件信号驱动（interface） |
| 顺序 | 有先后 | 同时生效 |

Driver 驱动信号用 `<=`，读取信号用 `=`。

---

### 2.7 do-while 循环

```systemverilog
do @(posedge vif.aclk); while (!vif.awready);
```

**这是什么？**

先执行一次 `@(posedge vif.aclk)`（等一个时钟），然后检查 `awready`。如果 ready 还没来，继续等。直到 ready=1 才退出。

等价于：
```systemverilog
@(posedge vif.aclk);
while (!vif.awready) begin
    @(posedge vif.aclk);
end
```

---

## 第三章：面向对象（class）

### 3.1 class 定义与继承

```systemverilog
class axi_base_test extends uvm_test;
    axi_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

class axi_basic_test extends axi_base_test;
    // 继承了 axi_base_test 的 env
endclass
```

**`extends` 是什么？**

继承。`axi_basic_test` 继承 `axi_base_test`，自动拥有 `env` 变量。

**`super.new()` 是什么？**

调用父类的构造函数。UVM 组件的 `new` 需要两个参数：名字和父组件。

---

### 3.2 `new` 构造函数

```systemverilog
function new(string name = "axi_txn");
    super.new(name);
endfunction
```

**为什么 `new` 有两个参数（uvm_component）或一个参数（uvm_object）？**

- `uvm_component`（Driver/Test/Env）：`new(name, parent)` — 有层次关系
- `uvm_object`（Transaction/Sequence）：`new(name)` — 无层次关系

---

### 3.3 虚方法 — `virtual`

```systemverilog
virtual axi_if vif;     // virtual interface
```

**`virtual` 是什么？**

"虚拟"的意思。在 SV 里有两种用法：

1. **Virtual interface**：interface 的指针，可以在 class 里使用
2. **Virtual function**：可被子类重写的函数（多态）

---

### 3.4 自动变量 — `automatic`

```systemverilog
fork
    automatic axi_wr_seq s = seq;  // 每次循环独立拷贝
    s.start(env.sqr[0]);
join_none
```

**`automatic` 是什么？**

让变量在每次调用/循环时独立分配，不共享。在 `fork/join_none` 循环里必须用，否则所有线程共享同一个变量。

---

## 第四章：Interface

### 4.1 Interface 定义

```systemverilog
interface axi_if #(
    parameter AXI_ADDR_W = 16
)(
    input logic aclk       // 端口：时钟从外面接进来
);

    logic aresetn = 0;     // 内部信号：可被 test 驱动
    logic awvalid, awready;
    logic [AXI_ADDR_W-1:0] awaddr;

endinterface
```

**Interface 和 Module 的区别？**

| | Module | Interface |
|---|---|---|
| 用途 | 实现硬件逻辑 | 打包信号 |
| 例化 | `module_name u0(...)` | `if_name u0(...)` |
| 内部 | 可以有 always/assign | 可以有 modport/SVA |
| 参数化 | `#(parameter)` | `#(parameter)` |

---

### 4.2 Modport — 信号方向

```systemverilog
modport master (
    input  aclk, aresetn, awready,
    output awvalid, awaddr, awlen
);

modport slave (
    input  aclk, aresetn, awvalid, awaddr, awlen,
    output awready
);
```

**Modport 是什么？**

同一个 interface，从不同角度看信号方向不同。Master 看 `awvalid` 是 output，Slave 看 `awvalid` 是 input。

---

### 4.3 Virtual Interface 使用

```systemverilog
// Driver 里
virtual axi_if vif;                    // 声明
uvm_config_db#(virtual axi_if)::get(   // 从 config_db 获取
    this, "", "vif", vif);
vif.awvalid <= 1;                      // 通过 vif 驱动信号
```

**为什么需要 virtual interface？**

UVM 组件是 `class`，不能直接例化 `interface`。`virtual interface` 是 interface 的指针，让 class 能访问 interface 里的信号。

---

## 第五章：约束随机

### 5.1 rand — 随机变量

```systemverilog
rand kind_e     kind;
rand bit [15:0] addr;
rand bit [7:0]  id;
rand bit [31:0] wdata[];
```

**`rand` 是什么？**

标记变量可以被随机化。调用 `randomize()` 时，solver 会按 constraint 生成随机值。

**没有 `rand` 的字段呢？**

不会被随机化，保持原值。

---

### 5.2 constraint — 约束

```systemverilog
constraint c_basic {
    size inside {[0:2]};        // size 取值范围 0~2
    len  inside {[0:15]};       // len 取值范围 0~15
    burst == 2'b01;             // burst 固定为 INCR
    addr[1:0] == 2'b00;         // 地址 4 字节对齐
    wdata.size() == len + 1;    // 数组大小 = burst 长度
    wstrb.size() == len + 1;
}
```

**`inside` 是什么？**

范围约束。`inside {[0:2]}` 表示值在 0、1、2 之间随机。

**`wdata.size()` 是什么？**

动态数组的大小约束。`wdata.size() == len + 1` 表示数组元素个数等于 burst 长度。

**怎么调用随机化？**

```systemverilog
axi_txn txn = new();
txn.randomize();        // 所有 rand 字段按 constraint 随机
// 或
txn.randomize() with { addr inside {16'h0000, 16'h1000}; };  // 内联约束
```

---

## 第六章：UVM 基础组件

### 6.1 `uvm_component_utils — 注册到工厂

```systemverilog
class axi_mst_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_mst_drv)
endclass
```

**`` `uvm_component_utils `` 是什么？**

宏，把类注册到 UVM 工厂。注册后才能用 `type_id::create()` 创建实例。

**为什么用 factory 而不用 `new`？**

Factory 允许在 test 里用一行代码替换组件类型，不用改 env：

```systemverilog
axi_mst_drv::type_id::set_type_override(my_fast_drv::get_type());
```

---

### 6.2 `uvm_field_* — 字段自动化

```systemverilog
`uvm_object_utils_begin(axi_txn)
    `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(addr,  UVM_ALL_ON)
    `uvm_field_array_int(wdata, UVM_ALL_ON)
`uvm_object_utils_end
```

**这些宏是做什么的？**

让 UVM 内置方法自动处理这些字段：

| 方法 | 功能 |
|------|------|
| `print()` | 自动打印所有字段 |
| `compare()` | 自动比对两个对象 |
| `copy()` | 自动拷贝 |
| `clone()` | 自动深拷贝 |

`UVM_ALL_ON` 表示所有操作都开启（print/compare/copy/...）。

---

### 6.3 `uvm_info / `uvm_error / `uvm_fatal

```systemverilog
`uvm_info("TEST", $sformatf("SLV%0d PASS", s), UVM_LOW)
`uvm_error("SCBD", "DATA MISMATCH")
`uvm_fatal("NOVIF", "No vif")
```

**三个宏的区别？**

| 宏 | 严重性 | 效果 |
|---|---|---|
| `uvm_info` | 信息 | 只打印日志 |
| `uvm_error` | 错误 | 打印 + 计数，仿真继续 |
| `uvm_fatal` | 致命 | 打印 + 立即终止仿真 |

**参数：** `(ID字符串, 消息字符串, 冗余级别)`

`UVM_LOW` / `UVM_MEDIUM` / `UVM_HIGH` 控制消息是否显示，由 `+UVM_VERBOSITY` 控制。

---

### 6.4 `$sformatf` — 格式化字符串

```systemverilog
$sformatf("SLV%0d PASS: 0x%08h", s, rdata)
```

**格式符：**

| 符号 | 含义 | 例子 |
|------|------|------|
| `%0d` | 十进制（无前导零） | `%0d` → `4` |
| `%04h` | 十六进制（4位，前导零） | `%04h` → `0010` |
| `%08h` | 十六进制（8位） | `%08h` → `DEAD0000` |
| `%b` | 二进制 | `%b` → `1010` |
| `%s` | 字符串 | `%s` → `hello` |

---

## 第七章：UVM Sequence 机制

### 7.1 uvm_sequence 定义

```systemverilog
class axi_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_seq)
    bit [15:0] s_addr;       // 由 test 配置
    bit [31:0] s_data;

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.addr = s_addr;
        start_item(txn);
        finish_item(txn);
    endtask
endclass
```

**`uvm_sequence #(axi_txn)` 是什么？**

泛型参数化。`#(axi_txn)` 表示这个 sequence 产生 `axi_txn` 类型的事务。

**`body()` 是什么？**

Sequence 的主任务，`start()` 被调用时执行。

---

### 7.2 start_item / finish_item

```systemverilog
start_item(txn);       // 阻塞等待 sequencer 授权
// 可以在这里修改 txn 字段
finish_item(txn);      // 把 txn 发给 driver，等 driver 完成
```

**握手过程：**

```
Sequence          Sequencer          Driver
   │                  │                 │
   ├──start_item()──→ │                 │
   │  (阻塞)          │                 │
   │ ←─ 授权 ─────────┤                 │
   │                  │                 │
   ├──finish_item()──→│──get_next_item()→│
   │                  │                 ├── 驱动
   │                  │ ←─item_done()───┤
   │ ←─ 完成 ─────────┤                 │
```

---

### 7.3 seq.start(sequencer) — 启动 sequence

```systemverilog
wr_seq.start(env.sqr[0]);  // 从 sequencer 0 启动
```

**`start()` 做了什么？**

1. 把 sequence 挂到 sequencer 上
2. 调用 sequence 的 `body()` 任务
3. `body()` 里的 `start_item/finish_item` 通过 sequencer 和 driver 握手

---

## 第八章：UVM TLM 端口

### 8.1 seq_item_port — Driver 拉取事务

```systemverilog
// Driver 里
seq_item_port.get_next_item(txn);   // 从 sequencer 拉一个事务
seq_item_port.item_done();          // 通知完成
```

**`seq_item_port` 是什么？**

`uvm_driver` 内置的 TLM 端口，连接到 sequencer 的 `seq_item_export`。

---

### 8.2 uvm_analysis_port — Monitor 广播事务

```systemverilog
// Monitor 里
uvm_analysis_port #(axi_txn) ap;   // 声明
ap = new("ap", this);               // 创建
ap.write(txn);                      // 广播
```

**`analysis_port` 和普通 `port` 的区别？**

| | 普通 port | analysis_port |
|---|---|---|
| 连接数 | 1 对 1 | 1 对多 |
| 阻塞 | 是 | 否 |
| 用途 | Driver ↔ Sequencer | Monitor → Scoreboard/Coverage |

---

### 8.3 uvm_analysis_imp — 接收端

```systemverilog
// Scoreboard 里
uvm_analysis_imp #(axi_txn, axi_scoreboard) imp;  // 声明
imp = new("imp", this);                             // 创建

function void write(axi_txn txn);                   // 收到事务时被调用
    // 比对逻辑
endfunction
```

**`write()` 是什么时候被调用的？**

Monitor 的 `ap.write(txn)` 触发时，所有连接的 `imp` 的 `write()` 都会被调用。

---

### 8.4 connect_phase — 连接端口

```systemverilog
function void connect_phase(uvm_phase phase);
    // Driver ← Sequencer
    mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);
    // Monitor → Scoreboard
    mst_mon[i].ap.connect(scbd.imp);
    // Monitor → Coverage
    mst_mon[i].ap.connect(cov.analysis_export);
endfunction
```

**`.connect()` 是什么？**

把两个 TLM 端口连起来。连接后，一端的 `write()`/`get()` 会触发另一端。

---

## 第九章：UVM Factory

### 9.1 type_id::create — 通过工厂创建

```systemverilog
env = axi_env::type_id::create("env", this);
seq = axi_wr_seq::type_id::create("seq");
txn = axi_txn::type_id::create("txn");
```

**为什么不用 `new`？**

`create()` 通过工厂创建，允许在运行时替换类型：

```systemverilog
// 在 test 里：用 my_env 替换 axi_env
axi_env::type_id::set_type_override(my_env::get_type());
// 之后所有 axi_env::type_id::create() 都会创建 my_env
```

---

### 9.2 set_type_override — 类型替换

```systemverilog
axi_wr_seq::type_id::set_type_override(my_wr_seq::get_type());
```

**效果：** 之后所有 `axi_wr_seq::type_id::create()` 实际创建的是 `my_wr_seq` 对象。Test 代码不用改。

---

## 第十章：UVM Phase

### 10.1 Phase 执行顺序

```
build_phase        → 创建组件（自顶向下）
connect_phase      → 连接端口（自底向上）
end_of_elaboration → 最终调整
run_phase          → 主仿真（消耗时间）
extract_phase      → 提取数据
check_phase        → 检查结果
report_phase       → 打印报告
```

**自顶向下 vs 自底向上？**

- `build_phase`：先创建 env，再创建 env 里的 driver/monitor
- `connect_phase`：先连接 driver/monitor，再连接 env 的端口

---

### 10.2 raise_objection / drop_objection

```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this);   // "我还没做完"
    // ... 仿真 ...
    phase.drop_objection(this);    // "我做完了"
endtask
```

**如果不 drop 会怎样？**

仿真永远不会结束，直到超时。

**如果不在 run_phase 里 raise 会怎样？**

run_phase 立即结束，sequence 没机会执行。

---

## 第十一章：UVM Config_db

### 11.1 set — 存入

```systemverilog
uvm_config_db#(virtual axi_if)::set(
    null,                    // context：null 表示全局
    "*.mst_drv0",            // inst_name：路径匹配
    "vif",                   // field_name：key
    mst_if[0]                // value：要传的值
);
```

### 11.2 get — 取出

```systemverilog
uvm_config_db#(virtual axi_if)::get(
    this,                    // context：当前组件
    "",                      // inst_name：空表示自己
    "vif",                   // field_name：和 set 的 key 对应
    vif                      // 变量：接收取出的值
);
```

**路径匹配规则：**

| set 的 inst_name | 匹配 |
|---|---|
| `"*.mst_drv0"` | `uvm_test_top.env.mst_drv0` ✓ |
| `"env.*"` | `env.mst_drv0`、`env.slv_drv0` ... |
| `"*"` | 所有组件 |

---

## 第十二章：覆盖率

### 12.1 covergroup — 覆盖组

```systemverilog
covergroup cg;
    cp_kind: coverpoint txn.kind {
        bins rd = {0};
        bins wr = {1};
    }

    cp_slave: coverpoint txn.addr[15:12] {
        bins s0 = {0};
        bins s1 = {1};
        bins s2 = {2};
        bins s3 = {3};
    }

    cx_routing: cross cp_master, cp_slave;
endgroup
```

**`coverpoint` 是什么？**

单维度覆盖。记录某个变量/表达式取了哪些值。

**`bins` 是什么？**

覆盖仓。每个 bin 是一个目标值或范围。全部 bin 被采到 = 100%。

**`cross` 是什么？**

交叉覆盖。两个 coverpoint 的所有组合。

```
cp_master: 4 bins (MST0~3)
cp_slave:  4 bins (SLV0~3)
cx_routing = cross → 4×4 = 16 bins
```

---

### 12.2 cg.sample() — 采样

```systemverilog
function void write(axi_txn t);
    txn = t;         // 把事务赋给覆盖组的采样变量
    cg.sample();     // 采样所有 coverpoint 和 cross
endfunction
```

**`cg` 里的 `txn` 从哪来？**

`axi_coverage` 类里声明了 `axi_txn txn;`，covergroup 里的 `txn.kind`、`txn.addr` 等直接引用这个成员变量。

---

## 第十三章：SVA 断言

### 13.1 property — 属性定义

```systemverilog
property sig_stable(sig, ready);
    @(posedge aclk) disable iff (!aresetn)
    sig && !ready |=> sig;
endproperty
```

**`disable iff (!aresetn)` 是什么？**

复位期间不检查。`aresetn=0` 时属性被禁用。

**`|=>` 是什么？**

"下一个时钟周期蕴含"。意思是：如果当前拍 `sig=1 && ready=0`，那么下一拍 `sig` 必须还是 1。

---

### 13.2 assert — 断言检查

```systemverilog
assert property (sig_stable(awvalid, awready))
    else $error("[SVA] AWVALID unstable");
```

**`assert property` 是什么？**

检查属性是否成立。不成立时执行 `else` 后面的语句。

---

## 第十四章：常用系统函数

### 14.1 `$urandom_range` — 随机范围

```systemverilog
$urandom_range(0, 99)    // 返回 0~99 的随机整数
$urandom_range(0, 99) < 30   // 30% 概率为真
```

### 14.2 `$sformatf` — 格式化

```systemverilog
$sformatf("addr=0x%04h data=0x%08h", addr, data)
// → "addr=0x1000 data=0xDEAD0000"
```

### 14.3 `$display` / `$finish`

```systemverilog
$display("Hello %0d", 42);   // 打印
$finish;                      // 结束仿真
```

### 14.4 `$dumpfile` / `$dumpvars`

```systemverilog
$dumpfile("wave.vcd");        // 波形文件名
$dumpvars(0, top_module);     // 转储所有信号
```

### 14.6 `type_id::create` — 工厂创建

```systemverilog
axi_txn::type_id::create("txn")
// 等价于 new("txn") 但支持 factory override
```

### 14.7 `get_full_name()` — 完整路径

```systemverilog
get_full_name()
// → "uvm_test_top.env.mst_drv0"
```

### 14.8 `new[]` — 动态数组分配

```systemverilog
txn.wdata = new[txn.len + 1];   // 分配 len+1 个元素
```
