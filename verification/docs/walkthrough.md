# 从零读懂 UVM 验证环境：axi_basic_test 完整执行流程

> 跟着 `axi_basic_test` 的执行顺序，一步步看代码。遇到每个语法都会解释，不会跳过任何细节。**每个代码块前面都会先说"这段在干什么"。**

---

## 第 0 步：仿真器启动，找到入口

你在终端敲命令，VCS 编译完成后执行 `./simv`，仿真器从 testbench top 开始运行。

---

## 第 1 步：Testbench Top — 仿真器的第一个 module

文件：[tb/axi_crossbar_tb.sv](verification/tb/axi_crossbar_tb.sv)

定义仿真器的最外层模块，这是仿真的入口。

```systemverilog
module axi_crossbar_tb;
```

仿真器找最外层的 `module`，名字必须和文件名一致。

---

### 1.1 import 和 include

导入 UVM 库和我们自己的包，让后面所有类和宏都能用。

```systemverilog
    import uvm_pkg::*;
    import axi_pkg::*;
    `include "uvm_macros.svh"
```

**`import uvm_pkg::*` 是什么？**

把 UVM 库里的所有类（`uvm_test`、`uvm_driver`、`uvm_sequence` 等）导入当前作用域。不写这行，后面用 `uvm_test` 会报"找不到"。`::*` 表示导入包里所有东西，类似 C++ 的 `using namespace std;`。

**`import axi_pkg::*` 是什么？**

导入我们自己定义的包（包含 `axi_txn`、`axi_mst_drv`、`axi_basic_test` 等所有类）。

**`` `include "uvm_macros.svh"`` 是什么？**

`` `include `` 是预处理指令，把文件内容原地插入，类似 C 的 `#include`。`uvm_macros.svh` 里定义了 `` `uvm_info ``、`` `uvm_error ``、`` `uvm_fatal `` 等宏。

**为什么 `import` 了还要 `include`？**

`import` 导入的是 `class`、`function`、`task`。`` `include `` 导入的是 `` `define `` 宏。两者机制不同，都需要。

---

### 1.2 参数定义

定义 DUT 的接口宽度参数，后面例化 interface 和 DUT 时都要用。

```systemverilog
    parameter AXI_ADDR_W = 16;
    parameter AXI_ID_W   = 8;
    parameter AXI_DATA_W = 32;
```

**`parameter` 是什么？**

编译时常量，整个 module 里都能用，但不能在运行时修改。

---

### 1.3 时钟和复位

产生 100MHz 时钟和复位信号。前 100ns DUT 处于复位状态，之后释放。

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

`always`：永远执行的块。`#5`：延迟 5ns。`~aclk`：取反。效果：每 5ns 翻转一次 → 10ns 一个周期 → 100MHz 时钟。

**`initial begin ... end` 是什么？**

`initial`：仿真开始时执行一次。`begin...end`：把多条语句组合成一个块，相当于 C 的 `{...}`。等 100ns 后释放复位。

---

### 1.4 例化 Interface

创建 4 个 Master 侧 interface 和 4 个 Slave 侧 interface，作为 DUT 和 UVM 组件之间的信号桥梁。

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

把顶层的复位信号同步到每个 interface 的 `aresetn`，这样 test 可以通过 vif 控制复位。

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

**`<=` 是什么？**

非阻塞赋值。在时钟沿统一生效，不会立即改变值。硬件信号驱动必须用 `<=`。

---

### 1.6 例化 DUT

把 AXI Crossbar 的 RTL 例化进来，把它的端口连到 interface 上。

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

`4'b1111`：4 位二进制值。`1111` 表示 Master 0 可以访问所有 4 个 Slave。

**`.slv0_awvalid(mst_if[0].awvalid)` 是什么？**

端口连接。DUT 的 `slv0_awvalid` 端口连到 `mst_if[0].awvalid` 信号。`.端口名(信号名)` 的语法。

---

### 1.7 config_db 传递 vif

把每个 interface 通过 UVM 的全局配置数据库传给对应的 Driver 和 Monitor，让它们能访问信号。

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

`*` 是通配符。它会匹配 `uvm_test_top.env.mst_drv0` 这样的完整路径。

---

### 1.8 启动 UVM

告诉 UVM 实例化哪个 test，然后执行所有 phase。

```systemverilog
        run_test("axi_basic_test");
    end
```

**`run_test("axi_basic_test")` 做了什么？**

UVM 的入口。它会：在工厂里查找 `axi_basic_test` 类 → 实例化它 → 按顺序执行 phase：`build_phase` → `connect_phase` → `run_phase` → `report_phase`。

---

### 1.9 超时保护

如果仿真跑飞了（比如 objection 忘了 drop），50ms 后强制终止。

```systemverilog
    initial begin
        #50000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end
```

**`` `uvm_fatal("TIMEOUT", ...)`` 是什么？**

UVM 宏，打印 `[FATAL]` 消息并立即终止仿真。

---

## 第 2 步：UVM build_phase — 创建所有组件

`run_test("axi_basic_test")` 被调用后，UVM 开始执行 phase。`build_phase` 自顶向下创建所有组件。

---

### 2.1 Test 的 build_phase — 创建 Environment

Test 的 build_phase 创建整个验证环境的容器 `env`。

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

定义一个类，继承 `uvm_test`。`extends` 就是继承。

**`` `uvm_component_utils(axi_base_test)`` 是什么？**

宏，把这个类注册到 UVM 工厂。注册后才能用 `type_id::create()` 创建实例。

**`axi_env env` 是什么？**

声明一个成员变量，类型是 `axi_env`，名字是 `env`。此时还没创建对象，只是声明。

**`super.build_phase(phase)` 是什么？**

调用父类的 `build_phase`。UVM 要求每个 phase 都先调 super。

**`axi_env::type_id::create("env", this)` 是什么？**

通过工厂创建 `axi_env` 实例。`"env"` 是实例名字，`this` 是父组件。

---

### 2.2 axi_basic_test 继承父类

`axi_basic_test` 没有定义 `build_phase`，直接用父类的——创建 `env`。

文件：[tests/axi_basic_test.sv](verification/tests/axi_basic_test.sv)

```systemverilog
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)

    task run_phase(uvm_phase phase);
        // ...
    endtask
endclass
```

---

### 2.3 Environment 的 build_phase — 创建所有子组件

Environment 创建 4 个 Master Driver、4 个 Slave Driver、4 个 Monitor、4 个 Sequencer、Scoreboard 和 Coverage。

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

泛型参数化，类似 C++ 的 `vector<int>`。`#(axi_txn)` 表示这个 sequencer 只传递 `axi_txn` 类型的事务。

---

### 2.4 循环创建 4 个 Master Driver

DUT 有 4 个 Master 端口，每个端口需要一个独立的 Driver 来驱动信号。

```systemverilog
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i] = axi_mst_drv::type_id::create(
                $sformatf("mst_drv%0d", i), this
            );
```

**`for (int i = 0; i < 4; i++)` 是什么？**

循环 4 次，`i` 从 0 到 3。`int i` 在 for 里声明变量（SV 允许）。

**`$sformatf("mst_drv%0d", i)` 是什么？**

格式化字符串，类似 C 的 `sprintf`。`i=0` → `"mst_drv0"`，`i=1` → `"mst_drv1"`... 每个 Driver 需要唯一名字。

---

### 2.5 创建 Slave 配置并传给 Slave Driver

创建 slave 配置对象（控制背压、错误注入等参数），通过 config_db 传给对应的 slave driver。

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
        end
```

`this` 是当前 env，`$sformatf("slv_drv%0d", i)` 匹配 env 下名字为 `slv_drv0/1/2/3` 的组件。

---

### 2.6 创建 Scoreboard 和 Coverage

创建记分板（比对数据）和覆盖率收集器。

```systemverilog
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction
```

到此 `build_phase` 结束，所有组件都创建好了。

---

## 第 3 步：connect_phase — 连接 TLM 端口

把 Driver、Sequencer、Monitor、Scoreboard、Coverage 之间的数据通道连起来。

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

Driver 从 config_db 取出 testbench top 里 set 进去的 vif，后面通过它驱动信号。

文件：[components/axi_mst_drv.sv](verification/components/axi_mst_drv.sv)

```systemverilog
class axi_mst_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_mst_drv)

    virtual axi_if vif;
```

**`extends uvm_driver #(axi_txn)` 是什么？**

继承 `uvm_driver`，参数化为 `axi_txn` 类型。`uvm_driver` 内置了 `seq_item_port` 等端口。

**`virtual axi_if vif` 是什么？**

虚拟 interface 变量。`virtual` 表示这是 interface 的指针，可以在 class 里使用（class 不能直接例化 interface）。

---

### 4.1 从 config_db 取出 vif

取出 testbench top 里 set 进去的 vif。取不到就报 fatal 终止仿真。

```systemverilog
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", $sformatf("No vif for %s", get_full_name()))
    endfunction
```

**`uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)` 每个参数什么意思？**

| 参数 | 值 | 含义 |
|------|-----|------|
| context | `this` | 从自己开始找 |
| inst_name | `""` | 空 = 自己 |
| field_name | `"vif"` | key |
| value | `vif` | 取出的值存到这里 |

**`!get(...)` 是什么？**

`get()` 返回 `bit`，1=成功，0=失败。`!` 取反，失败时进入 if。

**`get_full_name()` 是什么？**

返回组件的完整层次路径，如 `"uvm_test_top.env.mst_drv0"`。

---

## 第 5 步：run_phase — Test 启动 Sequence

Test 的 run_phase 是仿真的主逻辑：等复位 → 启动写 sequence → 启动读 sequence → 结束。

文件：[tests/axi_basic_test.sv](verification/tests/axi_basic_test.sv)

### 5.1 抬起 objection，防止仿真提前结束

```systemverilog
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
```

**`phase.raise_objection(this)` 是什么？**

告诉 UVM："我还没做完，不要结束 run_phase。" 如果不 raise，run_phase 会立即结束。

---

### 5.2 等复位释放，再等 5 个时钟稳定

```systemverilog
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);
```

**`@(posedge ...)` 是什么？**

等待信号的上升沿（从 0 变 1）。这里等 `aresetn` 从 0 变 1（复位释放）。

**`env.mst_drv[0].vif.aresetn` 怎么读？**

从左到右：env → mst_drv[0]（第一个 master driver）→ vif（它的虚拟 interface）→ aresetn（复位信号）。

**`repeat(5)` 是什么？**

重复 5 次。等 5 个时钟上升沿，让 DUT 内部状态稳定。

---

### 5.3 循环写 4 个 Slave

依次创建 4 个写 sequence，分别写到 SLV0~SLV3，然后启动。

```systemverilog
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

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

计算目标地址。`16'h1000` = 0x1000。
- s=0: `0x0000` → SLV0
- s=1: `0x1000` → SLV1
- s=2: `0x2000` → SLV2
- s=3: `0x3000` → SLV3

**`32'hDEAD0000 + s` 是什么？**

测试数据。`+s` 让每个 slave 的数据不同，方便调试时区分。

**`8'h10` 是什么？**

AXI 事务 ID。高 4 位 `0001` 标识 Master 0。

**`wr_seq.start(env.sqr[0])` 是什么？**

启动 sequence。`env.sqr[0]` 是第一个 sequencer。`start()` 会调用 sequence 的 `body()` 任务。

---

### 5.4 循环读 4 个 Slave

写完之后，依次读回 4 个地址的数据，Scoreboard 会自动比对。

```systemverilog
        #200;

        for (int s = 0; s < 4; s++) begin
            rd_seq = axi_rd_seq::type_id::create(
                $sformatf("rd_seq%0d", s)
            );
            rd_seq.s_addr = s * 16'h1000;
            rd_seq.s_id   = 8'h10;
            rd_seq.start(env.sqr[0]);
        end
```

**`#200` 是什么？**

等 200ns。给 Slave Driver 时间处理完所有写事务的响应。

---

### 5.5 放下 objection，允许仿真结束

```systemverilog
        #200;
        phase.drop_objection(this);
    endtask
endclass
```

**`phase.drop_objection(this)` 是什么？**

告诉 UVM："我做完了，可以结束 run_phase 了。"

---

## 第 6 步：Sequence 的 body — 生成事务

Sequence 被 `start()` 调用后，执行 `body()` 任务，创建一个事务对象并发送。

文件：[sequences/axi_wr_seq.sv](verification/sequences/axi_wr_seq.sv)

### 6.1 定义 Sequence 类

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

Sequence 是临时对象，用完就销毁。

---

### 6.2 配置参数

这些变量由 test 在启动 sequence 前赋值，body() 里用它们填充事务。

```systemverilog
    bit [15:0] s_addr;   // 目标地址，如 0x1000
    bit [31:0] s_data;   // 写入数据，如 0xDEAD0001
    bit [7:0]  s_id;     // 事务 ID，如 0x10
```

---

### 6.3 body() — 创建并发送事务

```systemverilog
    task body();
        axi_txn txn = axi_txn::type_id::create("txn");

        txn.kind  = axi_txn::WRITE;
        txn.addr  = s_addr;
        txn.id    = s_id;
        txn.len   = 0;         // 单拍（1 拍数据）
        txn.size  = 2;         // 2^2 = 4 字节
```

**`body()` 是什么？**

Sequence 的主任务。`start()` 被调用时，UVM 自动调用 `body()`。

**`axi_txn::WRITE` 是什么？**

`axi_txn` 类里定义的枚举值。`::` 是作用域解析符。

**`len=0, size=2` 意味着什么？**

`len+1` 拍 × `2^size` 字节 = 1 × 4 = 4 字节数据。

---

### 6.4 填充写数据

```systemverilog
        txn.wdata = new[1];       // 分配 1 个元素的动态数组
        txn.wstrb = new[1];
        txn.wdata[0] = s_data;    // 第 0 拍数据
        txn.wstrb[0] = 4'hF;     // 4 字节全部有效
```

**`new[1]` 是什么？**

动态数组分配。必须先 `new` 才能给数组元素赋值。

**`4'hF` 是什么？**

`wstrb` 是写选通，每一位控制一个字节是否写入。`4'hF` = `1111` = 4 字节全部写入。

---

### 6.5 发送事务

```systemverilog
        start_item(txn);      // 请求 sequencer 授权
        finish_item(txn);     // 发给 driver，等 driver 完成
    endtask
endclass
```

**`start_item(txn)` 做了什么？**

阻塞等待 sequencer 授权。多个 sequence 同时请求时，sequencer 会仲裁。

**`finish_item(txn)` 做了什么？**

把 `txn` 发给 driver，然后阻塞等 driver 的 `item_done()`。

---

## 第 7 步：Driver 的 run_phase — 驱动信号

Driver 从 sequencer 拿到事务，把事务里的字段拆开，按 AXI 时序驱动到信号线上。

文件：[components/axi_mst_drv.sv](verification/components/axi_mst_drv.sv)

### 7.1 初始化信号 + 主循环

```systemverilog
    task run_phase(uvm_phase phase);
        vif.awvalid <= 0; vif.wvalid <= 0;
        vif.bready  <= 0; vif.arvalid <= 0; vif.rready <= 0;

        forever begin
            axi_txn txn;
            seq_item_port.get_next_item(txn);   // 从 sequencer 拿事务

            if (txn.kind == axi_txn::WRITE)
                drive_wr(txn);                   // 驱动写事务
            else
                drive_rd(txn);                   // 驱动读事务

            seq_item_port.item_done();           // 通知完成
        end
    endtask
```

**`forever` 是什么？**

无限循环。Driver 要一直接收事务，所以必须 forever。

**`get_next_item(txn)` 是什么？**

从 sequencer 拉取事务。**阻塞调用**——没有事务时一直等。

**`item_done()` 是什么？**

告诉 sequencer "处理完了"。sequence 的 `finish_item()` 才会返回。

---

### 7.2 drive_wr — 驱动写地址通道（AW）

把事务的地址和控制信息驱动到 AW 通道信号线上。

```systemverilog
    task drive_wr(axi_txn txn);
        @(posedge vif.aclk);
        vif.awvalid <= 1;
        vif.awaddr  <= txn.addr;
        vif.awlen   <= txn.len;
        vif.awsize  <= txn.size;
        vif.awburst <= 2'b01;    // INCR（地址递增）
        vif.awid    <= txn.id;
```

**每个信号是什么意思？**

- `awvalid <= 1`：告诉 slave "我有地址要发"
- `awaddr`：目标地址
- `awlen`：burst 长度
- `awsize`：每拍字节数
- `awburst <= 2'b01`：burst 类型，`01` = INCR（最常用）
- `awid`：事务 ID

---

### 7.3 等 AW 握手完成

等 slave 回复 `awready=1`，表示地址被接收。

```systemverilog
        do @(posedge vif.aclk); while (!vif.awready);
        vif.awvalid <= 0;
```

AXI 握手规则：valid 和 ready 同时为 1 时数据被采样。

---

### 7.4 驱动写数据通道（W）

把实际数据发出去，`wlast=1` 告诉 slave "这是最后一拍"。

```systemverilog
        vif.wvalid <= 1;
        vif.wdata  <= txn.wdata[0];
        vif.wstrb  <= txn.wstrb[0];
        vif.wlast  <= 1;
        do @(posedge vif.aclk); while (!vif.wready);
        vif.wvalid <= 0; vif.wlast <= 0;
```

---

### 7.5 等写响应通道（B）

slave 收到数据后回复响应，告诉 master 写操作是否成功。

```systemverilog
        vif.bready <= 1;
        do @(posedge vif.aclk); while (!vif.bvalid);
        txn.bresp = vif.bresp;
        vif.bready <= 0;
    endtask
```

**`txn.bresp = vif.bresp` 为什么用 `=` 不用 `<=`？**

读取信号值用 `=`，驱动信号用 `<=`。这里是读取 slave 返回的响应状态。

---

## 第 8 步：Slave Driver 接收数据

Slave Driver 被动等待 Master Driver 发来请求，接收地址和数据，存入内存模型，然后回复响应。

文件：[components/axi_slv_drv.sv](verification/components/axi_slv_drv.sv)

### 8.1 等待 AW 握手，接收地址

```systemverilog
    task wr_handler();
        forever begin
            vif.awready <= 0;
            @(posedge vif.aclk);
            while (!(vif.awvalid && vif.awready)) begin
                vif.awready <= !cfg.should_bp(0);  // 随机背压
                @(posedge vif.aclk);
            end
            awid = vif.awid; awaddr = vif.awaddr; awlen = vif.awlen;
```

**整体逻辑：** 先把 `awready` 拉低，每个时钟检查 master 是否发了 `awvalid`。如果发了，随机决定是否给 `awready`（模拟背压）。握手成功后采样地址信息。

**`cfg.should_bp(0)` 是什么？**

配置对象的方法，随机决定是否施加背压。参数 `0` = AW 通道。返回 1 表示不给 ready。

**为什么读取用 `=` 不用 `<=`？**

读取信号值到局部变量用 `=`，驱动信号用 `<=`。

---

### 8.2 逐拍接收写数据，存入内存模型

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

**整体逻辑：** 逐拍接收数据，每拍也加随机背压。32-bit 数据按字节拆开存入内存模型。

**`vif.wdata[7:0]` 是什么？**

位选择。`[7:0]` 取低 8 位 = 1 字节。一个 32-bit 数据拆成 4 字节：
```
wdata[31:24]  wdata[23:16]  wdata[15:8]  wdata[7:0]
   字节3         字节2         字节1        字节0
   → addr+3      → addr+2      → addr+1     → addr
```

---

### 8.3 回复写响应

收完数据后回复响应，告诉 master 写操作是否成功。可随机注入错误。

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

**`inject_err ? cfg.err_resp : 2'b00` 是什么？**

三元运算符。`inject_err=1` → 返回 SLVERR(2'b10)；`inject_err=0` → 返回 OKAY(2'b00)。

**`bid <= awid` 为什么？**

AXI 协议要求响应 ID 必须和请求 ID 一致。

---

## 第 9 步：Monitor 采集事务

Monitor 被动监听接口信号，检测到完整事务后打包成 `axi_txn` 对象，广播给 Scoreboard 和 Coverage。

文件：[components/axi_monitor.sv](verification/components/axi_monitor.sv)

### 9.1 等待 AW 握手，采样地址

```systemverilog
    task mon_wr();
        forever begin
            axi_txn txn;
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));
            txn = axi_txn::type_id::create("wr_txn");
            txn.kind = axi_txn::WRITE;
            txn.addr = vif.awaddr;
            txn.id   = vif.awid;
            txn.len  = vif.awlen;
```

**`@(posedge vif.aclk iff (...))` 是什么？**

带条件的时钟边沿等待。`iff` = "if and only if"。只在 `awvalid && awready` 同时为 1 的那个时钟沿才继续。这是 AXI 握手的采样点。

**为什么要创建 txn 对象？**

Scoreboard 和 Coverage 工作在"事务级"，不关心信号细节，只关心一次完整操作的所有信息。

---

### 9.2 逐拍采样写数据

```systemverilog
            txn.wdata = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));
                txn.wdata[i] = vif.wdata;
            end
```

**整体逻辑：** 先分配数组，然后逐拍等 `wvalid && wready` 握手，把数据存到事务对象里。

---

### 9.3 采样写响应，广播事务

```systemverilog
            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            txn.bresp = vif.bresp;

            ap.write(txn);
        end
    endtask
```

**`ap.write(txn)` 是什么？**

通过 analysis_port 广播事务。所有连接的 imp（Scoreboard 和 Coverage）的 `write()` 都会被调用。

---

## 第 10 步：Scoreboard 比对数据

Scoreboard 收到 Monitor 的事务后：写事务存期望值，读事务比对实际值。

文件：[components/axi_scoreboard.sv](verification/components/axi_scoreboard.sv)

### 10.1 写事务：存期望数据

```systemverilog
    function void write(axi_txn txn);
        if (txn.kind == axi_txn::WRITE) begin
            if (txn.bresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;
            end else begin
                wr_fail++;
            end
```

**整体逻辑：** 写事务来了，如果响应是 OKAY，把数据存到 `exp_data` 表（以地址为 key）。后面读回来时用这个表比对。

---

### 10.2 读事务：比对实际数据

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

**整体逻辑：** 读事务来了，用地址去 `exp_data` 表查之前写过的期望值。如果读回来的数据和期望值不一致 → `uvm_error`。

**`exp_data.exists(key)` 是什么？**

检查这个地址是否之前写过。没写过就不比对。

**`!==` 和 `!=` 有什么区别？**

`!==` 是严格不等（4 态精确比较），`!=` 是逻辑不等（有 x 时结果不确定）。用 `!==` 更安全。

---

## 第 11 步：Coverage 采样

Coverage 收到 Monitor 的事务后，记录这次事务覆盖了哪些场景。

文件：[components/axi_coverage.sv](verification/components/axi_coverage.sv)

```systemverilog
    function void write(axi_txn t);
        txn = t;
        cg.sample();
    endfunction
```

**`cg.sample()` 做了什么？**

采样 covergroup 里的所有 coverpoint 和 cross。比如 Master 0 写 SLV0 → 记录 `{MST0, SLV0}` 路由组合被覆盖。

---

## 第 12 步：report_phase — 打印报告

仿真结束时 UVM 自动调用 report_phase，打印 Scoreboard 和 Coverage 的统计结果。

```
UVM_INFO [SCBD] WR: 4 pass / 0 fail
UVM_INFO [SCBD] RD: 4 pass / 0 fail
UVM_INFO [COV] Coverage: 56.7%

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
