# 从零读懂 UVM 验证环境：axi_basic_test 完整执行流程

> 跟着 `axi_basic_test` 的执行顺序，一步步看代码。遇到每个语法都会解释，不会跳过任何细节。

---

## 第 0 步：仿真器启动，找到入口

你在终端敲：

```bash
make sim SIM=vcs UVM_TEST=axi_basic_test
```

VCS 编译完成后执行 `./simv`，仿真器从 testbench top 开始运行。

---

## 第 1 步：Testbench Top — 仿真器的第一个 module

文件：[tb/axi_crossbar_tb.sv](verification/tb/axi_crossbar_tb.sv)

```systemverilog
module axi_crossbar_tb;
```

仿真器找最外层的 `module`，这就是入口。名字必须和文件名一致。

### 1.1 import 和 include

```systemverilog
    import uvm_pkg::*;
    import axi_pkg::*;
    `include "uvm_macros.svh"
```

**`import uvm_pkg::*` 是什么？**

把 UVM 库里的所有类（`uvm_test`、`uvm_driver`、`uvm_sequence` 等）导入当前作用域。不写这行，后面用 `uvm_test` 会报"找不到"。

`::*` 表示导入包里所有东西。类似 C++ 的 `using namespace std;`。

**`import axi_pkg::*` 是什么？**

导入我们自己定义的包（包含 `axi_txn`、`axi_mst_drv`、`axi_basic_test` 等所有类）。

**`` `include "uvm_macros.svh"`` 是什么？**

`` `include `` 是预处理指令，把文件内容原地插入。类似 C 的 `#include`。

`uvm_macros.svh` 里定义了 `` `uvm_info ``、`` `uvm_error ``、`` `uvm_fatal `` 等宏。不 include 这个文件，这些宏都用不了。

**为什么 `import` 了还要 `include`？**

`import` 导入的是 `class`、`function`、`task`。`` `include `` 导入的是 `` `define `` 宏。两者机制不同，都需要。

---

### 1.2 参数定义

```systemverilog
    parameter AXI_ADDR_W = 16;
    parameter AXI_ID_W   = 8;
    parameter AXI_DATA_W = 32;
```

**`parameter` 是什么？**

编译时常量。`AXI_ADDR_W = 16` 表示地址宽度 16 位。整个 module 里都能用，但不能在运行时修改。

---

### 1.3 时钟和复位

```systemverilog
    logic aclk = 0;
    logic aresetn = 0;
    logic srst = 1;
    always #5 aclk = ~aclk;
    initial begin #100; aresetn = 1; srst = 0; end
```

**`logic aclk = 0` 是什么？**

声明一个信号，初始值为 0。`logic` 是四态逻辑（0/1/x/z），替代 Verilog 的 `reg` 和 `wire`。

**`always #5 aclk = ~aclk` 是什么？**

`always`：永远执行的块。
`#5`：延迟 5 个时间单位（timescale 是 1ns/1ps，所以是 5ns）。
`~aclk`：按位取反，0 变 1，1 变 0。

效果：每 5ns 翻转一次 → 10ns 一个周期 → 100MHz 时钟。

**`initial begin ... end` 是什么？**

`initial`：仿真开始时执行一次的块。
`begin...end`：把多条语句组合成一个块，相当于 C 的 `{...}`。

**`#100; aresetn = 1` 是什么？**

等 100ns，然后把 `aresetn` 拉高（释放复位）。前 100ns DUT 处于复位状态。

---

### 1.4 例化 Interface

```systemverilog
    axi_if #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .AXI_ID_W(AXI_ID_W),
        .AXI_DATA_W(AXI_DATA_W)
    ) mst_if[4] (.aclk(aclk));
```

**`axi_if #(...)` 是什么？**

例化 interface。`#(...)` 里传参数，覆盖 interface 定义时的默认值。

**`mst_if[4]` 是什么？**

创建 4 个 interface 实例的数组。`mst_if[0]`、`mst_if[1]`、`mst_if[2]`、`mst_if[3]`。

**`(.aclk(aclk))` 是什么？**

端口连接。把 interface 的 `aclk` 端口连到 module 里的 `aclk` 信号。

---

### 1.5 同步 aresetn 到 Interface

```systemverilog
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_rst
            always @(posedge aclk) mst_if[i].aresetn <= aresetn;
            always @(posedge aclk) slv_if[i].aresetn <= aresetn;
        end
    endgenerate
```

**`generate...endgenerate` 是什么？**

编译时循环，展开成多个 `always` 块。`genvar i` 是循环变量（只能在 generate 里用）。

**`begin : gen_rst` 的 `: gen_rst` 是什么？**

给这个 begin 块起名字。generate 循环里的 begin 块必须命名。

**`mst_if[i].aresetn <= aresetn` 是什么？**

在每个时钟上升沿，把顶层的 `aresetn` 同步到每个 interface 的 `aresetn`。这样 test 可以通过 vif 控制 reset。

**`<=` 是什么？**

非阻塞赋值。在时钟沿统一生效，不会立即改变值。硬件信号驱动必须用 `<=`，不能用 `=`。

---

### 1.6 例化 DUT

```systemverilog
    axicb_crossbar_top #(
        .AXI_ADDR_W(AXI_ADDR_W),
        .MST_NB(4), .SLV_NB(4),
        .MST0_ROUTES(4'b1111),
        .SLV0_START_ADDR(0), .SLV0_END_ADDR(4095),
        // ...
    ) dut (
        .aclk(aclk), .aresetn(aresetn), .srst(srst),
        .slv0_awvalid(mst_if[0].awvalid),
        .slv0_awready(mst_if[0].awready),
        // ... 几十根信号线 ...
    );
```

**`.MST0_ROUTES(4'b1111)` 是什么？**

`4'b1111`：4 位二进制值。`b` 前面是位宽，后面是值。`1111` 表示 Master 0 可以访问所有 4 个 Slave。

**`.slv0_awvalid(mst_if[0].awvalid)` 是什么？**

端口连接。DUT 的 `slv0_awvalid` 端口连到 `mst_if[0].awvalid` 信号。`.端口名(信号名)` 的语法。

---

### 1.7 config_db 传递 vif

```systemverilog
    initial begin
        uvm_config_db#(virtual axi_if)::set(
            null, "*.mst_drv0", "vif", mst_if[0]
        );
        uvm_config_db#(virtual axi_if)::set(
            null, "*.mst_mon0", "vif", mst_if[0]
        );
        // ... 每个 driver 和 monitor 都要 set ...
```

**`uvm_config_db#(virtual axi_if)` 是什么？**

UVM 的全局配置数据库。`#(virtual axi_if)` 指定存的类型是"虚拟 AXI interface"。

**`::set(null, "*.mst_drv0", "vif", mst_if[0])` 每个参数什么意思？**

| 参数 | 值 | 含义 |
|------|-----|------|
| context | `null` | 全局（不限定在哪个组件下） |
| inst_name | `"*.mst_drv0"` | 路径匹配，`*` 匹配任意前缀 |
| field_name | `"vif"` | key，取出时用同样的 key |
| value | `mst_if[0]` | 存入的值 |

**`"*.mst_drv0"` 怎么匹配？**

`*` 是通配符。它会匹配 `uvm_test_top.env.mst_drv0` 这样的完整路径。这样不管 env 叫什么名字，只要里面有个 `mst_drv0` 就能匹配到。

---

### 1.8 启动 UVM

```systemverilog
        run_test("axi_basic_test");
    end
```

**`run_test("axi_basic_test")` 做了什么？**

这是 UVM 的入口。它会：
1. 在工厂里查找 `axi_basic_test` 类
2. 实例化它
3. 按顺序执行所有 phase：`build_phase` → `connect_phase` → `run_phase` → `report_phase`

从这里开始，控制权交给 UVM。

---

### 1.9 超时保护

```systemverilog
    initial begin
        #50000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end
```

**`` `uvm_fatal("TIMEOUT", "Simulation timeout")`` 是什么？**

UVM 宏，打印 `[FATAL]` 消息并立即终止仿真。如果 50ms 内仿真没结束（比如 objection 忘了 drop），这里兜底终止。

---

## 第 2 步：UVM build_phase — 创建所有组件

`run_test("axi_basic_test")` 被调用后，UVM 开始执行 phase。

### 2.1 Test 的 build_phase

文件：[tests/axi_base_test.sv](verification/tests/axi_base_test.sv)

```systemverilog
class axi_base_test extends uvm_test;
    `uvm_component_utils(axi_base_test)
    axi_env env;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction
endclass
```

**`class axi_base_test extends uvm_test` 是什么？**

定义一个类 `axi_base_test`，继承 `uvm_test`。`extends` 就是继承，和 Java/C++ 一样。

**`` `uvm_component_utils(axi_base_test)`` 是什么？**

宏，把这个类注册到 UVM 工厂。注册后才能用 `type_id::create()` 创建实例。

**`axi_env env` 是什么？**

声明一个成员变量，类型是 `axi_env`，名字是 `env`。此时还没创建对象，只是声明。

**`function void build_phase(uvm_phase phase)` 是什么？**

UVM 的 phase 之一。`build_phase` 在仿真开始时自动调用，用于创建子组件。

**`phase` 参数是什么？**

UVM 传进来的 phase 对象，一般不直接用它，但函数签名必须有。

**`super.build_phase(phase)` 是什么？**

调用父类（`uvm_test`）的 `build_phase`。UVM 要求每个 phase 都先调 super。

**`axi_env::type_id::create("env", this)` 是什么？**

通过工厂创建 `axi_env` 实例。等价于 `new("env", this)`，但支持 factory override。

| 参数 | 含义 |
|------|------|
| `"env"` | 实例名字，出现在 UVM 层次路径里 |
| `this` | 父组件，表示 env 是 test 的子组件 |

---

### 2.2 axi_basic_test 没有 build_phase

文件：[tests/axi_basic_test.sv](verification/tests/axi_basic_test.sv)

```systemverilog
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)

    task run_phase(uvm_phase phase);
        // ...
    endtask
endclass
```

`axi_basic_test` 继承 `axi_base_test`，没有定义自己的 `build_phase`，所以直接用父类的——创建 `env`。

---

### 2.3 Environment 的 build_phase — 创建所有子组件

文件：[components/axi_env.sv](verification/components/axi_env.sv)

```systemverilog
class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)

    axi_mst_drv    mst_drv[4];    // 4 个 Master Driver
    axi_slv_drv    slv_drv[4];    // 4 个 Slave Driver
    axi_monitor    mst_mon[4];    // 4 个 Master Monitor
    axi_monitor    slv_mon[4];    // 4 个 Slave Monitor
    uvm_sequencer #(axi_txn) sqr[4];  // 4 个 Sequencer
    axi_scoreboard scbd;           // Scoreboard
    axi_coverage   cov;            // Coverage
    axi_slv_cfg    slv_cfg[4];    // 4 个 Slave 配置
```

**`uvm_sequencer #(axi_txn)` 是什么？**

泛型参数化。`#(axi_txn)` 表示这个 sequencer 只传递 `axi_txn` 类型的事务。类似 C++ 的 `vector<int>`。

**`axi_mst_drv mst_drv[4]` 是什么？**

声明 4 个 `axi_mst_drv` 类型的变量数组。此时还没创建对象。

```systemverilog
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i] = axi_mst_drv::type_id::create(
                $sformatf("mst_drv%0d", i), this
            );
```

**这段在做什么？**

DUT 有 4 个 Master 端口，每个端口需要一个独立的 Driver 来驱动信号。所以用循环创建 4 个 Driver 实例。

**`for (int i = 0; i < 4; i++)` 是什么？**

循环，`i` 从 0 到 3，执行 4 次。`int i` 在 for 里声明变量（SV 允许，不需要提前声明）。

**`$sformatf("mst_drv%0d", i)` 是什么？**

格式化字符串函数，类似 C 的 `sprintf`。`%0d` 是十进制占位符。
- `i=0` → `"mst_drv0"`
- `i=1` → `"mst_drv1"`
- ...

每个 Driver 需要唯一的名字，这样 UVM 层次路径里能区分它们（`env.mst_drv0`、`env.mst_drv1`...）。

```systemverilog
            slv_cfg[i] = axi_slv_cfg::type_id::create(
                $sformatf("slv_cfg%0d", i)
            );
            uvm_config_db#(axi_slv_cfg)::set(
                this,
                $sformatf("slv_drv%0d", i),
                "cfg",
                slv_cfg[i]
            );
```

**这段在做什么？**

创建 slave 配置对象，然后通过 config_db 传给对应的 slave driver。

`this` 是当前 env，`$sformatf("slv_drv%0d", i)` 匹配 env 下名字为 `slv_drv0/1/2/3` 的组件。

```systemverilog
        end
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction
```

创建 scoreboard 和 coverage。到此 `build_phase` 结束，所有组件都创建好了。

---

## 第 3 步：connect_phase — 连接 TLM 端口

文件：[components/axi_env.sv](verification/components/axi_env.sv)

```systemverilog
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);
            mst_mon[i].ap.connect(scbd.imp);
            mst_mon[i].ap.connect(cov.analysis_export);
        end
    endfunction
```

**`.connect()` 是什么？**

把两个 TLM 端口连起来。连上之后，一端的操作会触发另一端。

**`seq_item_port` 和 `seq_item_export` 是什么？**

| 端口 | 在哪 | 作用 |
|------|------|------|
| `seq_item_port` | Driver | 主动拉取事务（`get_next_item()`） |
| `seq_item_export` | Sequencer | 被动提供事务 |

连接后，Driver 调 `get_next_item()` 就能从 Sequencer 拿到事务。

**`ap` 和 `imp` 是什么？**

| 端口 | 在哪 | 作用 |
|------|------|------|
| `ap` (analysis_port) | Monitor | 广播事务（`write(txn)`） |
| `imp` (analysis_imp) | Scoreboard | 接收事务（`write()` 被调用） |

一个 `ap` 可以连多个 `imp`。这里 Monitor 的 `ap` 同时连了 Scoreboard 和 Coverage。

---

## 第 4 步：Driver 的 build_phase — 拿到 vif

文件：[components/axi_mst_drv.sv](verification/components/axi_mst_drv.sv)

```systemverilog
class axi_mst_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_mst_drv)

    virtual axi_if vif;
```

**`extends uvm_driver #(axi_txn)` 是什么？**

继承 `uvm_driver`，参数化为 `axi_txn` 类型。`uvm_driver` 内置了 `seq_item_port` 等端口。

**`virtual axi_if vif` 是什么？**

声明一个虚拟 interface 变量。`virtual` 表示这是 interface 的指针，可以在 class 里使用（class 不能直接例化 interface）。

```systemverilog
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction
```

**`uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)` 是什么？**

从 config_db 取出之前 set 进去的 vif。

| 参数 | 值 | 含义 |
|------|-----|------|
| context | `this` | 从自己开始找 |
| inst_name | `""` | 空 = 自己 |
| field_name | `"vif"` | key |
| value | `vif` | 取出的值存到这里 |

**`!get(...)` 是什么？**

`get()` 返回 `bit`，1=成功，0=失败。`!` 取反，所以失败时进入 if。

**`` `uvm_fatal("NOVIF", ...)`` 是什么？**

打印 `[FATAL]` 消息并终止仿真。Driver 没有 vif 就无法驱动信号，必须终止。

**`get_full_name()` 是什么？**

返回组件的完整层次路径，如 `"uvm_test_top.env.mst_drv0"`。

---

## 第 5 步：run_phase — Test 启动 Sequence

文件：[tests/axi_basic_test.sv](verification/tests/axi_basic_test.sv)

```systemverilog
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
```

**`task run_phase(uvm_phase phase)` 是什么？**

UVM 的主仿真 phase。和 `function` 不同，`task` 可以消耗时间（包含 `#延迟`、`@等待` 等）。

```systemverilog
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;
```

声明两个 sequence 变量。`wr_seq` 负责生成写事务，`rd_seq` 负责生成读事务。此时只是声明，还没创建对象，后面循环里才创建。

```systemverilog
        phase.raise_objection(this);
```

**`phase.raise_objection(this)` 是什么？**

"抬起反对"。告诉 UVM："我还没做完，不要结束 run_phase。"

如果不 raise，run_phase 会立即结束，sequence 没机会执行。

**`this` 是什么？**

当前组件（`axi_basic_test` 实例）。UVM 用它来追踪谁 raise 了 objection。

```systemverilog
        @(posedge env.mst_drv[0].vif.aresetn);
```

**这行在等什么？**

等待 `aresetn` 从 0 变 1（复位释放）。`@(...)` 是"等待事件"，`posedge` 是"上升沿"。

**`env.mst_drv[0].vif.aresetn` 怎么读？**

从左到右：env → mst_drv[0]（第一个 master driver）→ vif（它的虚拟 interface）→ aresetn（复位信号）。

```systemverilog
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);
```

**`repeat(5)` 是什么？**

重复 5 次。等 5 个时钟上升沿，让 DUT 稳定下来。

---

## 第 6 步：创建并启动 Sequence

```systemverilog
        for (int s = 0; s < 4; s++) begin
            wr_seq = axi_wr_seq::type_id::create(
                $sformatf("wr_seq%0d", s)
            );
            wr_seq.s_addr = s * 16'h1000;
            wr_seq.s_data = 32'hDEAD0000 + s;
            wr_seq.s_id   = 8'h10;
            wr_seq.start(env.sqr[0]);
        end
```

**`s * 16'h1000` 是什么？**

`s` 是循环变量 0~3，`16'h1000` 是 16 位十六进制值 0x1000。
- s=0: `0 * 0x1000 = 0x0000` → SLV0
- s=1: `1 * 0x1000 = 0x1000` → SLV1
- s=2: `2 * 0x1000 = 0x2000` → SLV2
- s=3: `3 * 0x1000 = 0x3000` → SLV3

**`32'hDEAD0000 + s` 是什么？**

32 位十六进制值。`+s` 让每个 slave 的测试数据不同，方便调试。
- s=0: `0xDEAD0000`
- s=1: `0xDEAD0001`
- ...

**`8'h10` 是什么？**

8 位十六进制值 `0x10`。这是 AXI 事务的 ID。高 4 位 `0001` 标识 Master 0。

**`wr_seq.start(env.sqr[0])` 是什么？**

启动 sequence。`env.sqr[0]` 是第一个 sequencer。`start()` 会调用 sequence 的 `body()` 任务。

---

## 第 7 步：Sequence 的 body — 生成事务

文件：[sequences/axi_wr_seq.sv](verification/sequences/axi_wr_seq.sv)

```systemverilog
class axi_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_seq)
```

**`uvm_sequence` 和 `uvm_component` 有什么区别？**

| | uvm_component | uvm_sequence |
|---|---|---|
| 生命周期 | 仿真全程 | 只在 start() 期间 |
| 层次 | 有 parent | 无 parent |
| 注册宏 | `uvm_component_utils` | `uvm_object_utils` |
| new 参数 | `(name, parent)` | `(name)` |

Sequence 是临时对象，用完就销毁。

```systemverilog
    bit [15:0] s_addr;
    bit [31:0] s_data;
    bit [7:0]  s_id;
```

**这三个变量是做什么的？**

它们是 sequence 的"配置参数"。test 在启动 sequence 之前会给它们赋值，sequence 的 `body()` 里用它们来填充事务。

| 变量 | 含义 | 例子 |
|------|------|------|
| `s_addr` | 写的目标地址 | `0x1000`（SLV1） |
| `s_data` | 要写入的数据 | `0xDEAD0001` |
| `s_id` | AXI 事务 ID | `0x10`（Master 0） |

**`bit [15:0]` 是什么？**

16 位两态逻辑（只有 0/1，没有 x/z）。比 `logic` 仿真更快。在 class 里用 `bit`，在 interface/module 里用 `logic`。

```systemverilog
    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
```

**`body()` 是什么？**

Sequence 的主任务。`start()` 被调用时，UVM 自动调用 `body()`。

```systemverilog
        txn.kind  = axi_txn::WRITE;
```

**`axi_txn::WRITE` 是什么？**

`axi_txn` 类里定义的枚举值。`::` 是作用域解析符，类似 C++ 的 `axi_txn::WRITE`。

```systemverilog
        txn.addr  = s_addr;
        txn.id    = s_id;
        txn.len   = 0;
        txn.size  = 2;
```

把 test 配置的参数填到事务对象里。

- `txn.addr = s_addr`：写到哪个地址（由 test 决定写哪个 slave）
- `txn.id = s_id`：事务 ID（标识是哪个 master 发的）
- `txn.len = 0`：burst 长度 - 1。`0` = 单拍传输（只写 1 个数据）
- `txn.size = 2`：每拍字节数 = 2^size = 2^2 = 4 字节（32-bit）

`len` 和 `size` 的组合决定了这次传输总共写多少数据。这里 `len=0, size=2` = 写 1 拍 × 4 字节 = 4 字节。

```systemverilog
        txn.wdata = new[1];
        txn.wstrb = new[1];
        txn.wdata[0] = s_data;
        txn.wstrb[0] = 4'hF;
```

**这段在做什么？**

填充写数据。因为 `len=0`（单拍），所以只有 1 拍数据。

**`new[1]` 是什么？**

动态数组分配。`wdata` 和 `wstrb` 是动态数组（大小不确定），必须先用 `new[1]` 分配 1 个元素，然后才能给 `wdata[0]` 赋值。不 new 直接赋值会报错。

**`txn.wdata[0] = s_data` 是什么？**

把 test 传入的测试数据写到数组第 0 个元素。`[0]` 是数组索引。

**`4'hF` 是什么？**

4 位十六进制值 `1111`（二进制）。`wstrb` 是写选通（Write Strobe），AXI 用它按字节选择哪些位有效：
- `4'hF` = `1111` = 4 个字节全部写入
- `4'h1` = `0001` = 只写最低 1 个字节
- `4'hC` = `1100` = 只写高 2 个字节

这里用 `4'hF` 表示 4 字节全部有效。

```systemverilog
        start_item(txn);
        finish_item(txn);
    endtask
endclass
```

**`start_item(txn)` 做了什么？**

请求 sequencer 授权。阻塞直到 sequencer 允许这个 sequence 发送事务。

**`finish_item(txn)` 做了什么？**

把 `txn` 发给 driver，然后阻塞等 driver 完成（`item_done()`）。

---

## 第 8 步：Driver 的 run_phase — 驱动信号

文件：[components/axi_mst_drv.sv](verification/components/axi_mst_drv.sv)

```systemverilog
    task run_phase(uvm_phase phase);
        vif.awvalid <= 0; vif.wvalid <= 0;
        vif.bready  <= 0; vif.arvalid <= 0; vif.rready <= 0;
```

初始化：所有输出信号清零。

```systemverilog
        forever begin
            axi_txn txn;
            seq_item_port.get_next_item(txn);
```

**`forever` 是什么？**

无限循环，Driver 要一直接收事务，所以必须 forever。

**`seq_item_port.get_next_item(txn)` 是什么？**

从 sequencer 拉取一个事务。**阻塞调用**——如果没有事务可取，就一直等。

取出后 `txn` 就是 sequence 里创建的那个对象（地址、数据、ID 都在里面）。

```systemverilog
            if (txn.kind == axi_txn::WRITE)
                drive_wr(txn);
            else
                drive_rd(txn);

            seq_item_port.item_done();
        end
    endtask
```

**`item_done()` 是什么？**

告诉 sequencer "这个事务我处理完了"。sequence 的 `finish_item()` 才会返回。

---

### 8.1 drive_wr — 驱动写事务

```systemverilog
    task drive_wr(axi_txn txn);
        @(posedge vif.aclk);
```

等一个时钟上升沿。

```systemverilog
        vif.awvalid <= 1;
        vif.awaddr  <= txn.addr;
        vif.awlen   <= txn.len;
        vif.awsize  <= txn.size;
        vif.awburst <= 2'b01;
        vif.awid    <= txn.id;
```

**这段在做什么？**

驱动 AXI 写地址通道（AW）。把事务对象里的字段拆开，逐个驱动到 interface 信号线上。

- `awvalid <= 1`：告诉 slave "我有地址要发"
- `awaddr <= txn.addr`：目标地址
- `awlen <= txn.len`：burst 长度
- `awsize <= txn.size`：每拍字节数
- `awburst <= 2'b01`：burst 类型。`2'b01` = INCR（地址递增），这是最常用的模式
- `awid <= txn.id`：事务 ID

**`<=` 是什么？**

非阻塞赋值。所有信号在同一个时钟沿同时生效，不会有先后顺序问题。硬件信号驱动必须用 `<=`。

```systemverilog
        do @(posedge vif.aclk); while (!vif.awready);
```

**这行在做什么？**

等 slave 的 ready。先等一个时钟，检查 `awready`。如果 ready=0，再等一个时钟，直到 ready=1。

这就是 AXI 握手：valid 和 ready 同时为 1 时数据被采样。

```systemverilog
        vif.awvalid <= 0;
```

握手完成，拉低 valid。

```systemverilog
        vif.wvalid <= 1;
        vif.wdata  <= txn.wdata[0];
        vif.wstrb  <= txn.wstrb[0];
        vif.wlast  <= 1;
        do @(posedge vif.aclk); while (!vif.wready);
        vif.wvalid <= 0; vif.wlast <= 0;
```

**这段在做什么？**

驱动写数据通道（W）。把实际数据发出去。

- `wdata <= txn.wdata[0]`：第 0 拍数据（单拍只有 1 拍）
- `wstrb <= txn.wstrb[0]`：字节选通（哪些字节有效）
- `wlast <= 1`：告诉 slave "这是最后一拍"。AXI 协议要求 burst 传输的最后一拍必须拉高 wlast

等 slave 回复 `wready=1` 后，拉低 `wvalid` 和 `wlast`，表示数据通道传输完成。

```systemverilog
        vif.bready <= 1;
        do @(posedge vif.aclk); while (!vif.bvalid);
        txn.bresp = vif.bresp;
        vif.bready <= 0;
    endtask
```

**这段在做什么？**

等待写响应通道（B）。slave 收到数据后会回复一个响应，告诉 master 写操作是否成功。

- `bready <= 1`：告诉 slave "我准备好接收响应了"
- 等 `bvalid=1`：slave 发来了响应
- `txn.bresp = vif.bresp`：读取响应状态（`2'b00`=OKAY 成功，`2'b10`=SLVERR 错误）
- `bready <= 0`：响应接收完毕

注意这里读取信号用 `=`（阻塞赋值），不是 `<=`。`<=` 用于驱动（写入信号），`=` 用于读取（取信号值）。

---

## 第 9 步：Slave Driver 接收数据

文件：[components/axi_slv_drv.sv](verification/components/axi_slv_drv.sv)

```systemverilog
    task wr_handler();
        bit [7:0]  awid;
        bit [31:0] awaddr, wr_addr;
        bit [7:0]  awlen;
        bit        inject_err;
        forever begin
            vif.awready <= 0;
            @(posedge vif.aclk);
            while (!(vif.awvalid && vif.awready)) begin
                vif.awready <= !cfg.should_bp(0);
                @(posedge vif.aclk);
            end
```

**这段整体在做什么？**

Slave Driver 的写处理任务。它被动等待 Master Driver 发来写请求，接收地址和数据，存入内存模型，然后回复响应。

**前几行的逻辑：**
1. 先把 `awready` 拉低（默认不接收）
2. 每个时钟检查：Master 发了 `awvalid` 了吗？
3. 如果发了，随机决定是否给 `awready`（模拟背压）
4. 当 `awvalid && awready` 同时为 1，地址被接收

**`!(vif.awvalid && vif.awready)` 是什么？**

条件取反。当 valid 和 ready **不同时**为 1 时，继续循环等待。只有两者同时为 1（握手成功）才退出循环。

**`cfg.should_bp(0)` 是什么？**

调用配置对象的方法，随机决定是否施加背压。参数 `0` 表示 AW 通道。返回 1 表示"不给 ready"（背压），`!` 取反后变成 `ready=0`。这样 Master 就得继续等。

这是验证的关键：通过随机背压，测试 DUT 在反压场景下是否正常工作。

```systemverilog
            awid = vif.awid; awaddr = vif.awaddr; awlen = vif.awlen;
```

**这段在做什么？**

握手成功后，从信号线上采样地址和控制信息，存到局部变量里备用。后面收数据和回复响应时要用到这些值。

**用 `=` 而不是 `<=`，为什么？**

这里是**读取**信号值到局部变量，不是驱动信号。规则：
- **驱动**信号（写入 interface）用 `<=`：`vif.awready <= 1;`
- **读取**信号（从 interface 取值）用 `=`：`awid = vif.awid;`

```systemverilog
            for (int i = 0; i < awlen + 1; i++) begin
                vif.wready <= !cfg.should_bp(1);
                @(posedge vif.aclk);
                while (!(vif.wvalid && vif.wready))
                    @(posedge vif.aclk);
                mem[wr_addr]     = vif.wdata[7:0];
                mem[wr_addr + 1] = vif.wdata[15:8];
                mem[wr_addr + 2] = vif.wdata[23:16];
                mem[wr_addr + 3] = vif.wdata[31:24];
                wr_addr += 4;
            end
```

**这段在做什么？**

逐拍接收写数据。循环 `awlen + 1` 次（`len=0` 就是 1 次）。

每拍的逻辑：
1. W 通道也加随机背压（`should_bp(1)`，参数 1 = W 通道）
2. 等 `wvalid && wready` 握手成功
3. 把 32-bit 数据拆成 4 个字节，按字节地址存入内存模型
4. 地址加 4（下一拍数据存到下一个 4 字节位置）

**`vif.wdata[7:0]` 是什么？**

位选择（bit select）。`[7:0]` 取第 7 位到第 0 位（低 8 位 = 1 字节）。一个 32-bit 数据按字节拆开：
```
wdata[31:24] wdata[23:16] wdata[15:8] wdata[7:0]
   字节3        字节2        字节1       字节0
   → mem[addr+3] → mem[addr+2] → mem[addr+1] → mem[addr]
```

**为什么要拆字节？**

内存模型是按字节寻址的（`bit [7:0] mem[bit [31:0]]`），一个地址存 1 字节。32-bit 数据要存到 4 个连续地址。

```systemverilog
            vif.bid    <= awid;
            vif.bresp  <= inject_err ? cfg.err_resp : 2'b00;
            vif.bvalid <= 1;
            @(posedge vif.aclk);
            while (!vif.bready) @(posedge vif.aclk);
            vif.bvalid <= 0;
        end
    endtask
```

**这段在做什么？**

收完数据后，slave 回复写响应（B 通道）。

- `bid <= awid`：响应 ID 必须和请求 ID 一致（AXI 协议要求）
- `bresp`：响应状态。正常返回 `OKAY(2'b00)`，如果之前随机决定注入错误就返回 `SLVERR(2'b10)`
- `bvalid <= 1`：告诉 master "我有响应要发"
- 等 `bready=1`：master 接收了响应
- `bvalid <= 0`：响应发送完毕

**`inject_err ? cfg.err_resp : 2'b00` 是什么？**

三元运算符，和 C 一样。`条件 ? 真值 : 假值`。

- `inject_err=1` → 返回 `cfg.err_resp`（SLVERR=2'b10），模拟 slave 报错
- `inject_err=0` → 返回 `2'b00`（OKAY），正常响应

这是错误注入机制：test 可以配置 `err_pct=10`（10% 概率），slave 就会随机返回错误，测试 DUT 的异常处理能力。

---

## 第 10 步：Monitor 采集事务

文件：[components/axi_monitor.sv](verification/components/axi_monitor.sv)

```systemverilog
    task mon_wr();
        forever begin
            axi_txn txn;
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));
```

**`@(posedge vif.aclk iff (...))` 是什么？**

带条件的时钟边沿等待。`iff` = "if and only if"。只在 `awvalid && awready` 同时为 1 的那个时钟沿才继续，否则继续等。

这是 AXI 握手的采样点：valid 和 ready 同时为 1 的瞬间，数据被采样。

```systemverilog
            txn = axi_txn::type_id::create("wr_txn");
            txn.kind = axi_txn::WRITE;
            txn.addr = vif.awaddr;
            txn.id   = vif.awid;
            txn.len  = vif.awlen;
```

**这段在做什么？**

Monitor 检测到 AW 握手后，创建一个事务对象，把信号线上的信息"打包"成事务。这样 Scoreboard 和 Coverage 拿到的是一个完整的事务对象，而不是零散的信号。

为什么需要这一步？因为 Scoreboard 和 Coverage 工作在"事务级"，它们不关心每个时钟沿的信号值，只关心"一次完整的写操作"的所有信息。

```systemverilog
            txn.wdata = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));
                txn.wdata[i] = vif.wdata;
            end
```

**这段在做什么？**

逐拍采样 W 通道数据。`len=0` 时循环 1 次，`len=3` 时循环 4 次。

每拍等 `wvalid && wready` 握手成功，然后把 `wdata` 存到事务对象的数组里。

`new[txn.len + 1]` 先分配好数组大小（和 burst 长度一致），然后逐个填充。

```systemverilog
            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            txn.bresp = vif.bresp;

            ap.write(txn);
```

**`ap.write(txn)` 是什么？**

通过 analysis_port 广播事务。所有连接到这个 port 的 imp（Scoreboard 和 Coverage）的 `write()` 都会被调用。

```systemverilog
        end
    endtask
```

---

## 第 11 步：Scoreboard 比对数据

文件：[components/axi_scoreboard.sv](verification/components/axi_scoreboard.sv)

```systemverilog
    function void write(axi_txn txn);
```

**`write()` 是什么时候被调用的？**

Monitor 的 `ap.write(txn)` 触发时，UVM 自动调用所有连接的 imp 的 `write()`。

```systemverilog
        if (txn.kind == axi_txn::WRITE) begin
            if (txn.bresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;
            end else begin
                wr_fail++;
            end
```

**这段整体逻辑是什么？**

Scoreboard 的核心思路：**先记住写了什么，读回来时再比对**。

收到写事务时：
1. 检查响应是否 OKAY（`2'b00`）
2. 如果 OKAY，把数据存到 `exp_data` 表（"期望数据"），以地址为 key
3. 如果不是 OKAY（slave 报错），计数失败

**`exp_data[txn.addr + i * 4]` 是什么？**

关联数组访问。`exp_data` 是一个"地址→数据"的映射表。
- key = 地址（`txn.addr + i * 4`）
- value = 数据（`txn.wdata[i]`）

`i * 4` 是因为每个数据 4 字节。`len=0` 时只存 1 个，`len=3` 时存 4 个。

例子：写地址 `0x1000`，数据 `0xDEAD0001` → `exp_data[0x1000] = 0xDEAD0001`

```systemverilog
        end else begin
            if (txn.rresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++) begin
                    bit [31:0] key = txn.addr + i * 4;
                    if (exp_data.exists(key) && txn.rdata[i] !== exp_data[key]) begin
                        `uvm_error("SCBD", $sformatf(
                            "DATA MISMATCH: addr=0x%04h got=0x%08h exp=0x%08h",
                            key, txn.rdata[i], exp_data[key]))
                        rd_fail++; return;
                    end
                end
                rd_pass++;
            end
        end
    endfunction
```

**这段整体逻辑是什么？**

收到读事务时：
1. 检查响应是否 OKAY
2. 遍历每一拍数据，用地址去 `exp_data` 表查之前写过的期望值
3. 如果读回来的数据和期望值不一致 → `uvm_error`（测试失败）
4. 如果所有数据都匹配 → `rd_pass++`

**`exp_data.exists(key)` 是什么？**

关联数组方法，检查这个地址是否之前写过。如果没写过，就没有期望值可比，跳过。防止"读了一个没写过的地址"时误报错。

**`txn.rdata[i] !== exp_data[key]` 的 `!==` 和 `!=` 有什么区别？**

| 运算符 | 含义 |
|--------|------|
| `!=` | 逻辑不等（如果值里有 x，结果也是 x，不是 true/false） |
| `!==` | 严格不等（4 态精确比较，x 就是 x，不会变成不确定） |

用 `!==` 更安全。如果读回来的数据是 `x`（总线错误），`!=` 可能给出不确定结果，`!==` 会正确报告不匹配。

**`txn.rdata[i] !== exp_data[key]` 的 `!==` 和 `!=` 有什么区别？**

| 运算符 | 含义 |
|--------|------|
| `!=` | 逻辑不等（x 参与比较时结果可能为 x） |
| `!==` | 严格不等（4 态精确比较，x 就是 x） |

用 `!==` 更安全，避免 x 导致的不确定结果。

---

## 第 12 步：Coverage 采样

文件：[components/axi_coverage.sv](verification/components/axi_coverage.sv)

```systemverilog
    function void write(axi_txn t);
        txn = t;
        cg.sample();
    endfunction
```

**这段在做什么？**

Coverage 组件收到 Monitor 广播的事务后，记录这次事务覆盖了哪些场景。

- `txn = t`：把事务赋给成员变量（covergroup 里的 coverpoint 引用这个变量）
- `cg.sample()`：触发采样，检查 `txn` 的当前值命中了哪些 bin

**`cg.sample()` 做了什么？**

采样 covergroup 里的所有 coverpoint 和 cross。`txn` 的当前值被记录到对应的 bin 里。

比如这次是 Master 0 写 SLV0：
- `cp_kind` → bins wr ✓
- `cp_slave` → bins s0 ✓
- `cp_master` → bins m0 ✓
- `cx_routing` → bins {m0, s0} ✓

---

## 第 13 步：report_phase — 打印报告

仿真结束时 UVM 自动调用 report_phase。

```
UVM_INFO components/axi_scoreboard.sv(71) @ 1155000: [SCBD] WR: 4 pass / 0 fail
UVM_INFO components/axi_scoreboard.sv(72) @ 1155000: [SCBD] RD: 4 pass / 0 fail
UVM_INFO components/axi_coverage.sv(47) @ 1155000: [COV] Coverage: 56.7%
```

然后 UVM 打印汇总：

```
UVM_ERROR :    0
UVM_FATAL :    0
```

0 error，0 fatal → 测试通过。

---

## 完整执行时间线

```
时间        事件
────────────────────────────────────────────────
0ns         仿真开始，aclk 开始翻转
0ns         aresetn=0，DUT 处于复位状态
100ns       aresetn=1，复位释放
105ns       Test 等到 5 个时钟
155ns       wr_seq[0] start → 发送写 SLV0 事务
            Driver 驱动 awvalid/awaddr
            Slave Driver 回复 awready
            Driver 驱动 wvalid/wdata/wlast
            Slave Driver 回复 wready
            Slave Driver 回复 bvalid/bresp=OKAY
            Monitor 采集事务 → Scoreboard 存数据
            155ns+     wr_seq[0] done
155ns       wr_seq[1] start → 发送写 SLV1 事务
...
1155ns      所有事务完成，drop objection
1155ns      report_phase 打印结果
1155ns      仿真结束
```
