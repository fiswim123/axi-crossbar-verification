# 从零搭建 UVM 验证环境：AXI Crossbar 实战教程

> 写给零基础小白的保姆级教程。不讲空话，每一步都告诉你"为什么这么想"和"代码怎么敲"。

---

## 目录

- [第一章：先搞懂我们在干什么](#第一章先搞懂我们在干什么)
- [第二章：搭骨架——目录和文件怎么组织](#第二章搭骨架目录和文件怎么组织)
- [第三章：第一个文件——Interface](#第三章第一个文件interface)
- [第四章：Transaction——激励的数据结构](#第四章transaction激励的数据结构)
- [第五章：Driver——把事务变成信号](#第五章driver把事务变成信号)
- [第六章：Slave Driver——DUT 对面怎么接](#第六章slave-driverdut-对面怎么接)
- [第七章：Monitor——旁观者清](#第七章monitor旁观者清)
- [第八章：Scoreboard——裁判](#第八章scoreboard裁判)
- [第九章：Coverage——覆盖率](#第九章coverage覆盖率)
- [第十章：Environment——把组件装到一起](#第十章environment把组件装到一起)
- [第十一章：Sequence——激励生成器](#第十一章sequence激励生成器)
- [第十二章：Test——入口和调度](#第十二章test入口和调度)
- [第十三章：Testbench Top——最顶层](#第十三章testbench-top最顶层)
- [第十四章：Package——把所有文件串起来](#第十四章package把所有文件串起来)
- [第十五章：Makefile——一键编译运行](#第十五章makefile一键编译运行)
- [第十六章：运行和调试](#第十六章运行和调试)
- [附录：常见问题](#附录常见问题)

---

## 第一章：先搞懂我们在干什么

### 1.1 DUT 是什么

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

### 1.2 验证的目标

验证 = 确认 DUT 行为正确。具体来说：

1. **写数据到 Slave 0，能从 Slave 0 读回来** → 路由正确
2. **4 个 Master 同时访问不同 Slave，不冲突** → 并发正确
3. **Burst 传输（连续发多个数据）不丢数据** → 协议正确
4. **中间出错（Slave 返回错误），DUT 不卡死** → 异常处理正确
5. **中途复位，DUT 能恢复** → 鲁棒性正确

### 1.3 为什么用 UVM

不用 UVM，你也可以直接写个 `initial begin ... end` 去驱动信号。但：

| | 直接写 | UVM |
|---|---|---|
| 换个项目能复用吗 | ❌ | ✅ |
| 能随机生成激励吗 | ❌ | ✅ |
| 能自动收集覆盖率吗 | ❌ | ✅ |
| 面试官认可吗 | ❌ | ✅ |

**UVM 就是一套"验证框架"**，规定了谁干什么、怎么配合。你只要按规矩填代码就行。

### 1.4 UVM 的核心思想

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

## 第二章：搭骨架——目录和文件怎么组织

### 2.1 思路

UVM 有固定套路，文件要按功能分目录放：

```
verification/
├── env/                ← 接口 + Package（最底层）
├── components/         ← Driver、Monitor、Scoreboard 等（组件层）
├── sequences/          ← 激励序列（数据层）
├── tests/              ← 测试用例（调度层）
├── tb/                 ← Testbench Top（最顶层）
└── Makefile            ← 编译脚本
```

### 2.2 为什么要这么分

- `env/` 放最底层的东西（接口定义、Package），其他所有目录的文件都依赖它
- `components/` 放 UVM 组件，它们互相独立，只通过 TLM 端口连接
- `sequences/` 放激励，它只依赖 `axi_txn`（Transaction 类）
- `tests/` 放测试，它依赖 `sequence` 和 `env`
- `tb/` 放顶层，它把 DUT 和验证环境连起来

**从下往上依赖：env → components → sequences → tests → tb**

### 2.3 创建目录

```bash
mkdir -p verification/{env,components,sequences,tests,tb,docs}
```

---

## 第三章：第一个文件——Interface

### 3.1 为什么需要 Interface

DUT 有几十根信号线（awvalid, awready, awaddr, wvalid, wready, wdata...）。如果每根都手动连，代码又长又容易错。

**Interface 把一堆信号打包成一个对象**，后面 Driver、Monitor 都通过它来访问信号。

### 3.2 思路

1. 把 AXI 协议的所有信号列出来
2. 分成 5 个通道：AW（写地址）、W（写数据）、B（写响应）、AR（读地址）、R（读数据）
3. 定义 modport 区分方向（Master 看和 Slave 看，信号方向相反）
4. 加 SVA 断言做基础协议检查

### 3.3 代码

文件：`env/axi_if.sv`

```systemverilog
`timescale 1ns/1ps

interface axi_if #(
    parameter AXI_ADDR_W = 16,   // 地址宽度
    parameter AXI_ID_W   = 8,    // ID 宽度
    parameter AXI_DATA_W = 32    // 数据宽度
)(
    input logic aclk              // 时钟从外面接进来
);

    // aresetn 放成内部信号，不放 port
    // 因为后面 reset test 需要从 test 里面控制它
    logic aresetn = 0;

    // ============ 写地址通道 (AW) ============
    logic                  awvalid, awready;
    logic [AXI_ADDR_W-1:0] awaddr;
    logic [7:0]            awlen;      // burst 长度 - 1
    logic [2:0]            awsize;     // 每拍字节数 = 2^size
    logic [1:0]            awburst;    // burst 类型
    logic [AXI_ID_W-1:0]   awid;

    // ============ 写数据通道 (W) ============
    logic                  wvalid, wready, wlast;
    logic [AXI_DATA_W-1:0] wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;

    // ============ 写响应通道 (B) ============
    logic                  bvalid, bready;
    logic [AXI_ID_W-1:0]   bid;
    logic [1:0]            bresp;

    // ============ 读地址通道 (AR) ============
    logic                  arvalid, arready;
    logic [AXI_ADDR_W-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic [AXI_ID_W-1:0]   arid;

    // ============ 读数据通道 (R) ============
    logic                  rvalid, rready, rlast;
    logic [AXI_ID_W-1:0]   rid;
    logic [1:0]            rresp;
    logic [AXI_DATA_W-1:0] rdata;

    // ============ Modport ============
    // Master 侧：我发起写/读请求
    modport master (
        input  aclk, aresetn,
        output awvalid, awaddr, awlen, awsize, awburst, awid,
        input  awready,
        output wvalid, wlast, wdata, wstrb,
        input  wready,
        input  bvalid, bid, bresp,
        output bready,
        output arvalid, araddr, arlen, arsize, arburst, arid,
        input  arready,
        input  rvalid, rid, rresp, rdata, rlast,
        output rready
    );

    // Slave 侧：方向反过来
    modport slave (
        input  aclk, aresetn,
        input  awvalid, awaddr, awlen, awsize, awburst, awid,
        output awready,
        input  wvalid, wlast, wdata, wstrb,
        output wready,
        output bvalid, bid, bresp,
        input  bready,
        input  arvalid, araddr, arlen, arsize, arburst, arid,
        output arready,
        output rvalid, rid, rresp, rdata, rlast,
        input  rready
    );

    // ============ SVA 断言 ============
    // valid 一旦拉高，ready 没来之前不能掉
    property sig_stable(sig, ready);
        @(posedge aclk) disable iff (!aresetn)
        sig && !ready |=> sig;
    endproperty

    assert property (sig_stable(awvalid, awready)) else $error("[SVA] AWVALID unstable");
    assert property (sig_stable(wvalid, wready))   else $error("[SVA] WVALID unstable");
    assert property (sig_stable(arvalid, arready))  else $error("[SVA] ARVALID unstable");

endinterface
```

### 3.4 关键点解释

**Q：为什么 `aresetn` 不放 input port？**

因为 reset test 需要从 test 里面强制拉低 reset 来模拟复位。如果放成 input port，VCS 不允许从 interface 内部驱动它。

**Q：modport 是什么？**

modport 定义了信号的方向。同一个 interface，Master 看 `awvalid` 是 output，Slave 看 `awvalid` 是 input。Driver 用 master modport，Slave Driver 用 slave modport。

---

## 第四章：Transaction——激励的数据结构

### 4.1 思路

一次 AXI 事务包含：读还是读？地址多少？ID 多少？burst 多长？数据是什么？

我们要把这些信息封装成一个 **Transaction 对象**，让 Sequence 生成它，Driver 消费它。

### 4.2 代码

文件：`components/axi_txn.sv`

```systemverilog
class axi_txn extends uvm_sequence_item;
    // ============ 枚举：读还是写 ============
    typedef enum {READ, WRITE} kind_e;

    // ============ 随机字段：由 constraint solver 生成 ============
    rand kind_e     kind;       // 读/写
    rand bit [15:0] addr;       // 地址
    rand bit [7:0]  id;         // 事务 ID
    rand bit [7:0]  len;        // burst 长度 - 1（0 = 单拍）
    rand bit [2:0]  size;       // 每拍字节数 = 2^size
    rand bit [1:0]  burst;      // burst 类型（2'b01 = INCR）
    rand bit [31:0] wdata[];    // 写数据（动态数组）
    rand bit [3:0]  wstrb[];    // 写选通

    // ============ 非随机字段：由 Driver 或 Monitor 填充 ============
    bit [7:0]  bid, rid;        // 响应 ID
    bit [1:0]  bresp, rresp;    // 响应状态
    bit [31:0] rdata[];         // 读数据

    // ============ 性能统计 ============
    time aw_time, b_time;       // 写延迟计算
    time ar_time, r_time;       // 读延迟计算
    int  wr_latency, rd_latency;

    // ============ 错误注入标志 ============
    bit expect_err = 0;

    // ============ 约束：告诉 solver 怎么随机 ============
    constraint c_basic {
        size inside {[0:2]};        // 1B / 2B / 4B
        len  inside {[0:15]};       // 1~16 拍
        burst == 2'b01;             // INCR 类型
        addr[1:0] == 2'b00;         // 4 字节对齐
        wdata.size() == len + 1;    // 数据数组大小 = burst 长度
        wstrb.size() == len + 1;
    }

    // ============ UVM field automation ============
    // 让 print()、compare()、copy() 自动生效
    `uvm_object_utils_begin(axi_txn)
        `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(id,    UVM_ALL_ON)
        `uvm_field_int(len,   UVM_ALL_ON)
        `uvm_field_int(size,  UVM_ALL_ON)
        `uvm_field_array_int(wdata, UVM_ALL_ON)
        `uvm_field_array_int(wstrb, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_txn");
        super.new(name);
    endfunction
endclass
```

### 4.3 关键点解释

**Q：`rand` 是什么？**

加了 `rand` 的字段，调用 `randomize()` 时 SystemVerilog 会自动按 constraint 生成随机值。

**Q：constraint 怎么用？**

```systemverilog
axi_txn txn = new();
txn.randomize();  // addr、id、len 等全部随机生成
// txn.addr 现在是一个合法的随机地址
```

**Q：`uvm_field_*` 有什么用？**

它让 UVM 内置的 `print()`、`compare()`、`clone()` 自动工作，不用你手写。比如 `txn.print()` 会自动打印所有字段。

---

## 第五章：Driver——把事务变成信号

### 5.1 思路

Driver 的工作：
1. 从 Sequencer 拿到一个 `axi_txn` 对象
2. 按 AXI 协议时序，把 txn 的内容驱动到 interface 信号上
3. 驱动完，告诉 Sequencer "我搞定了，给我下一个"

```
Sequencer ──get_next_item()──→ Driver ──drive signals──→ Interface
              ←item_done()────
```

### 5.2 代码

文件：`components/axi_mst_drv.sv`

```systemverilog
class axi_mst_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_mst_drv)

    virtual axi_if vif;  // 虚拟接口，build_phase 从 config_db 拿

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // ============ build_phase：拿 vif ============
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "No vif")
    endfunction

    // ============ run_phase：主循环 ============
    task run_phase(uvm_phase phase);
        // 初始化：所有输出信号清零
        vif.awvalid <= 0; vif.wvalid <= 0;
        vif.bready  <= 0; vif.arvalid <= 0; vif.rready <= 0;

        forever begin
            axi_txn txn;
            seq_item_port.get_next_item(txn);   // ① 从 sequencer 拿事务

            if (txn.kind == axi_txn::WRITE)
                drive_wr(txn);                   // ② 驱动写事务
            else
                drive_rd(txn);                   // ② 驱动读事务

            seq_item_port.item_done();           // ③ 通知完成
        end
    endtask

    // ============ 驱动写事务 ============
    task drive_wr(axi_txn txn);
        // --- AW 通道 ---
        @(posedge vif.aclk);
        vif.awvalid <= 1;
        vif.awaddr  <= txn.addr;
        vif.awlen   <= txn.len;
        vif.awsize  <= txn.size;
        vif.awburst <= txn.burst;
        vif.awid    <= txn.id;

        // 等 slave 接受（awready = 1）
        do @(posedge vif.aclk); while (!vif.awready);
        vif.awvalid <= 0;

        // --- W 通道：发 len+1 拍数据 ---
        for (int i = 0; i <= txn.len; i++) begin
            vif.wvalid <= 1;
            vif.wdata  <= txn.wdata[i];
            vif.wstrb  <= txn.wstrb[i];
            vif.wlast  <= (i == txn.len);       // 最后一拍拉高 wlast
            do @(posedge vif.aclk); while (!vif.wready);
        end
        vif.wvalid <= 0; vif.wlast <= 0;

        // --- B 通道：等响应 ---
        vif.bready <= 1;
        do @(posedge vif.aclk); while (!vif.bvalid);
        txn.bid   = vif.bid;
        txn.bresp = vif.bresp;
        vif.bready <= 0;
    endtask

    // ============ 驱动读事务 ============
    task drive_rd(axi_txn txn);
        vif.rready <= 1;
        @(posedge vif.aclk);

        // --- AR 通道 ---
        vif.arvalid <= 1;
        vif.araddr  <= txn.addr;
        vif.arlen   <= txn.len;
        vif.arsize  <= txn.size;
        vif.arburst <= txn.burst;
        vif.arid    <= txn.id;
        do @(posedge vif.aclk); while (!vif.arready);
        vif.arvalid <= 0;

        // --- R 通道：收 len+1 拍数据 ---
        txn.rdata = new[txn.len + 1];
        for (int i = 0; i <= txn.len; i++) begin
            @(posedge vif.aclk);
            while (!vif.rvalid) @(posedge vif.aclk);
            txn.rdata[i] = vif.rdata;
            txn.rid      = vif.rid;
            txn.rresp    = vif.rresp;
        end
        vif.rready <= 0;
    endtask
endclass
```

### 5.3 关键点解释

**Q：`virtual axi_if` 是什么？**

interface 不能直接例化，要用 `virtual interface`。它是一个"指针"，指向 testbench top 里例化的真实 interface。

**Q：`get_next_item()` 和 `item_done()` 是什么？**

这是 UVM 内置的握手协议：
- `get_next_item()`：阻塞等待，直到 Sequencer 有事务给我
- `item_done()`：告诉 Sequencer "这个我处理完了"

**Q：`<=` 和 `=` 的区别？**

`<=` 是非阻塞赋值（时钟边沿生效），`=` 是阻塞赋值（立即生效）。信号驱动用 `<=`，读取信号用 `=`。

---

## 第六章：Slave Driver——DUT 对面怎么接

### 6.1 思路

DUT 的 Master 侧由 `axi_mst_drv` 驱动。但 DUT 的 Slave 侧需要有人"接住"请求并回复。

Slave Driver 做的事：
1. 等 Master 发来 AW/AR 请求
2. 接收 W 数据，存到内存模型
3. 回复 B 响应（写完成）或 R 数据（读数据）
4. 可配置：背压（故意延迟 ready）、错误注入（返回 SLVERR）

### 6.2 代码（简化版，展示核心逻辑）

文件：`components/axi_slv_drv.sv`

```systemverilog
class axi_slv_drv extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_slv_drv)

    virtual axi_if vif;
    bit [7:0] mem[bit [31:0]];   // 内存模型：地址 → 数据
    axi_slv_cfg cfg;             // 配置：背压率、错误率

    // ... build_phase 类似，拿 vif 和 cfg ...

    task run_phase(uvm_phase phase);
        // 初始化信号
        vif.awready <= 0; vif.wready <= 0;
        vif.bvalid  <= 0; vif.rvalid <= 0;

        fork
            wr_handler();    // 处理写请求
            rd_handler();    // 处理读请求
        join
    endtask

    // ============ 写处理 ============
    task wr_handler();
        forever begin
            // --- AW 通道：接收地址 ---
            vif.awready <= 0;
            @(posedge vif.aclk);
            while (!(vif.awvalid && vif.awready)) begin
                vif.awready <= !cfg.should_bp(0);  // 背压：随机不给 ready
                @(posedge vif.aclk);
            end
            // 此刻 awvalid && awready 同时为 1，地址被接收
            bit [31:0] addr = vif.awaddr;
            int len = vif.awlen;
            bit inject_err = cfg.should_error();    // 随机决定是否注入错误

            // --- W 通道：接收数据 ---
            for (int i = 0; i <= len; i++) begin
                vif.wready <= !cfg.should_bp(1);
                @(posedge vif.aclk);
                while (!(vif.wvalid && vif.wready))
                    @(posedge vif.aclk);

                if (!inject_err) begin
                    // 存入内存模型
                    mem[addr]     = vif.wdata[7:0];
                    mem[addr + 1] = vif.wdata[15:8];
                    mem[addr + 2] = vif.wdata[23:16];
                    mem[addr + 3] = vif.wdata[31:24];
                end
                addr += 4;
            end

            // --- B 通道：回复响应 ---
            vif.bid    <= vif.awid;
            vif.bresp  <= inject_err ? 2'b10 : 2'b00;  // SLVERR 或 OKAY
            vif.bvalid <= 1;
            @(posedge vif.aclk);
            while (!vif.bready) @(posedge vif.aclk);
            vif.bvalid <= 0;
        end
    endtask

    // ============ 读处理 ============
    task rd_handler();
        forever begin
            // --- AR 通道：接收读地址 ---
            vif.arready <= 0;
            @(posedge vif.aclk);
            while (!(vif.arvalid && vif.arready))
                @(posedge vif.aclk);

            bit [31:0] addr = vif.araddr;
            int len = vif.arlen;
            bit inject_err = cfg.should_error();

            // --- R 通道：返回数据 ---
            for (int i = 0; i <= len; i++) begin
                vif.rid    <= vif.arid;
                vif.rdata  <= inject_err ? 32'hDEAD_BEEF :
                              {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
                vif.rresp  <= inject_err ? 2'b10 : 2'b00;
                vif.rlast  <= (i == len);
                vif.rvalid <= 1;
                @(posedge vif.aclk);
                while (!vif.rready) @(posedge vif.aclk);
                addr += 4;
            end
            vif.rvalid <= 0; vif.rlast <= 0;
        end
    endtask
endclass
```

### 6.3 Slave 配置

文件：`components/axi_slv_cfg.sv`

```systemverilog
class axi_slv_cfg extends uvm_object;
    int unsigned err_pct = 0;          // 错误注入概率 (0-100)
    bit [1:0]    err_resp = 2'b10;     // SLVERR
    int unsigned bp_awready_pct = 0;   // AW 通道背压概率
    int unsigned bp_wready_pct  = 0;   // W 通道背压概率
    int unsigned bp_arready_pct = 0;   // AR 通道背压概率

    function bit should_error();
        return ($urandom_range(0, 99) < err_pct);
    endfunction

    function bit should_bp(int channel);
        case (channel)
            0: return ($urandom_range(0, 99) < bp_awready_pct);
            1: return ($urandom_range(0, 99) < bp_wready_pct);
            2: return ($urandom_range(0, 99) < bp_arready_pct);
            default: return 0;
        endcase
    endfunction
endclass
```

**在 test 里配置背压和错误注入：**
```systemverilog
// 在 test 的 run_phase 里
for (int i = 0; i < 4; i++) begin
    env.slv_cfg[i].err_pct = 10;          // 10% 概率返回错误
    env.slv_cfg[i].bp_wready_pct = 30;    // 30% 概率 W 通道背压
end
```

---

## 第七章：Monitor——旁观者清

### 7.1 思路

Monitor 不驱动任何信号，它只"看"。看到一次完整的写事务或读事务后，打包成 `axi_txn` 发出去。

谁需要这些事务？
- **Scoreboard**：比对数据
- **Coverage**：统计覆盖率

### 7.2 代码

文件：`components/axi_monitor.sv`

```systemverilog
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_txn) ap;  // 发送端口

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        // 拿 vif（注意：monitor 的 vif 通过 config_db 从 env 设置）
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "No vif")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            mon_wr();   // 监控写通道
            mon_rd();   // 监控读通道
        join
    endtask

    // ============ 监控写事务 ============
    task mon_wr();
        forever begin
            axi_txn txn;

            // 等 AW 握手
            @(posedge vif.aclk iff (vif.awvalid && vif.awready));
            txn = axi_txn::type_id::create("wr_txn");
            txn.kind = axi_txn::WRITE;
            txn.addr = vif.awaddr;
            txn.id   = vif.awid;
            txn.len  = vif.awlen;

            // 收 W 数据
            txn.wdata = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.wvalid && vif.wready));
                txn.wdata[i] = vif.wdata;
            end

            // 收 B 响应
            @(posedge vif.aclk iff (vif.bvalid && vif.bready));
            txn.bresp = vif.bresp;

            ap.write(txn);  // 发给 scoreboard 和 coverage
        end
    endtask

    // ============ 监控读事务 ============
    task mon_rd();
        forever begin
            axi_txn txn;

            // 等 AR 握手
            @(posedge vif.aclk iff (vif.arvalid && vif.arready));
            txn = axi_txn::type_id::create("rd_txn");
            txn.kind = axi_txn::READ;
            txn.addr = vif.araddr;
            txn.id   = vif.arid;
            txn.len  = vif.arlen;

            // 收 R 数据
            txn.rdata = new[txn.len + 1];
            for (int i = 0; i <= txn.len; i++) begin
                @(posedge vif.aclk iff (vif.rvalid && vif.rready));
                txn.rdata[i] = vif.rdata;
            end

            ap.write(txn);
        end
    endtask
endclass
```

### 7.3 关键点解释

**Q：`@(posedge vif.aclk iff (vif.awvalid && vif.awready))` 是什么？**

这是"带条件的时钟边沿等待"。只在 `awvalid && awready` 都为 1 的那个时钟上升沿才继续，否则继续等。这就是 AXI 握手的采样方式。

**Q：`uvm_analysis_port` 是什么？**

它是一对多的广播端口。一个 Monitor 的 `ap` 可以同时连到 Scoreboard 和 Coverage，谁需要谁接。

---

## 第八章：Scoreboard——裁判

### 8.1 思路

Scoreboard 收到 Monitor 发来的事务，做两件事：
1. **写事务**：把数据存到 `exp_data` 表里（期望值）
2. **读事务**：从 `exp_data` 表里查对应地址的数据，和实际读回来的比对

```
Monitor 发来 WR txn: addr=0x0000, data=0xDEAD
  → Scoreboard: exp_data[0x0000] = 0xDEAD

Monitor 发来 RD txn: addr=0x0000, data=0xDEAD
  → Scoreboard: 比对 exp_data[0x0000] 和实际 rdata → PASS
```

### 8.2 代码

文件：`components/axi_scoreboard.sv`

```systemverilog
class axi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_scoreboard)

    uvm_analysis_imp #(axi_txn, axi_scoreboard) imp;  // 接收端口
    bit [31:0] exp_data[bit [31:0]];  // 期望数据表：地址 → 数据
    int unsigned wr_pass, wr_fail, rd_pass, rd_fail;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    // ============ write()：收到事务时被调用 ============
    function void write(axi_txn txn);
        if (txn.kind == axi_txn::WRITE) begin
            // 写事务：存期望值
            if (txn.bresp == 2'b00) begin  // OKAY 响应
                for (int i = 0; i <= txn.len; i++)
                    exp_data[txn.addr + i * 4] = txn.wdata[i];
                wr_pass++;
            end else begin
                wr_fail++;
            end
        end else begin
            // 读事务：比对
            if (txn.rresp == 2'b00) begin
                for (int i = 0; i <= txn.len; i++) begin
                    bit [31:0] key = txn.addr + i * 4;
                    if (exp_data.exists(key) && txn.rdata[i] !== exp_data[key]) begin
                        `uvm_error("SCBD", $sformatf(
                            "DATA MISMATCH: addr=0x%04h got=0x%08h exp=0x%08h",
                            key, txn.rdata[i], exp_data[key]))
                        rd_fail++;
                        return;
                    end
                end
                rd_pass++;
            end
        end
    endfunction

    // ============ report_phase：仿真结束时打印报告 ============
    function void report_phase(uvm_phase phase);
        `uvm_info("SCBD", $sformatf("WR: %0d pass / %0d fail", wr_pass, wr_fail), UVM_LOW)
        `uvm_info("SCBD", $sformatf("RD: %0d pass / %0d fail", rd_pass, rd_fail), UVM_LOW)
    endfunction
endclass
```

---

## 第九章：Coverage——覆盖率

### 9.1 思路

功能覆盖率回答这个问题：**"我们的测试覆盖了多少种场景？"**

比如：
- 4 个 Master 写 4 个 Slave，是否都测到了？（4×4 = 16 种路由）
- burst 长度 0~15，是否都测到了？
- 读和写是否都测到了？

### 9.2 代码

文件：`components/axi_coverage.sv`

```systemverilog
class axi_coverage extends uvm_subscriber #(axi_txn);
    `uvm_component_utils(axi_coverage)

    axi_txn txn;

    covergroup cg;
        // 读还是写
        cp_kind: coverpoint txn.kind {
            bins rd = {0}; bins wr = {1};
        }

        // 访问哪个 slave（看地址高 4 位）
        cp_slave: coverpoint txn.addr[15:12] {
            bins s0 = {0}; bins s1 = {1}; bins s2 = {2}; bins s3 = {3};
        }

        // 哪个 master（看 ID 高 4 位）
        cp_master: coverpoint txn.id[7:4] {
            bins m0 = {1}; bins m1 = {2}; bins m2 = {3}; bins m3 = {4};
        }

        // burst 长度
        cp_len: coverpoint txn.len {
            bins single = {0};
            bins short  = {[1:3]};
            bins med    = {[4:7]};
            bins long_b = {[8:15]};
        }

        // 交叉覆盖：master × slave = 16 种路由
        cx_routing: cross cp_master, cp_slave;

        // 交叉覆盖：读写 × burst 长度
        cx_kind_len: cross cp_kind, cp_len;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg = new();  // 实例化 covergroup
    endfunction

    // 收到事务时采样
    function void write(axi_txn t);
        txn = t;
        cg.sample();
    endfunction

    // 仿真结束时打印覆盖率
    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Coverage: %.1f%%", cg.get_coverage()), UVM_LOW)
    endfunction
endclass
```

---

## 第十章：Environment——把组件装到一起

### 10.1 思路

Environment 是"集装箱"，把所有组件实例化并连接起来：

```
axi_env
  ├── mst_drv[0..3]     实例化 4 个 Master Driver
  ├── slv_drv[0..3]     实例化 4 个 Slave Driver
  ├── mst_mon[0..3]     实例化 4 个 Master Monitor
  ├── slv_mon[0..3]     实例化 4 个 Slave Monitor
  ├── sqr[0..3]         实例化 4 个 Sequencer
  ├── scbd              实例化 Scoreboard
  ├── cov               实例化 Coverage
  └── slv_cfg[0..3]     实例化 4 个 Slave Config
```

### 10.2 代码

文件：`components/axi_env.sv`

```systemverilog
class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)

    axi_mst_drv    mst_drv[4];
    axi_slv_drv    slv_drv[4];
    axi_monitor    mst_mon[4];
    axi_monitor    slv_mon[4];
    uvm_sequencer #(axi_txn) sqr[4];
    axi_scoreboard scbd;
    axi_coverage   cov;
    axi_slv_cfg    slv_cfg[4];

    // ============ build_phase：创建所有组件 ============
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i] = axi_mst_drv::type_id::create($sformatf("mst_drv%0d", i), this);
            slv_drv[i] = axi_slv_drv::type_id::create($sformatf("slv_drv%0d", i), this);
            mst_mon[i] = axi_monitor::type_id::create($sformatf("mst_mon%0d", i), this);
            slv_mon[i] = axi_monitor::type_id::create($sformatf("slv_mon%0d", i), this);
            sqr[i]     = uvm_sequencer#(axi_txn)::type_id::create($sformatf("sqr%0d", i), this);
            slv_cfg[i] = axi_slv_cfg::type_id::create($sformatf("slv_cfg%0d", i));
            uvm_config_db#(axi_slv_cfg)::set(this, $sformatf("slv_drv%0d", i), "cfg", slv_cfg[i]);
        end
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction

    // ============ connect_phase：连接 TLM 端口 ============
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        for (int i = 0; i < 4; i++) begin
            // Driver 从 Sequencer 拿事务
            mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);
            // Monitor 把事务发给 Scoreboard 和 Coverage
            mst_mon[i].ap.connect(scbd.imp);
            mst_mon[i].ap.connect(cov.analysis_export);
        end
    endfunction
endclass
```

### 10.3 关键点解释

**Q：`type_id::create()` 和 `new()` 有什么区别？**

`create()` 是 UVM 的工厂机制，允许你在 test 里用 `set_type_override` 替换组件类型，不用改 env 代码。`new()` 做不到这一点。

**Q：`connect_phase` 里的连接是什么意思？**

```
Driver.seq_item_port ──→ Sequencer.seq_item_export
```

这是 UVM 的 TLM 端口连接。Driver 通过这个连接从 Sequencer 拿事务。

```
Monitor.ap ──→ Scoreboard.imp
Monitor.ap ──→ Coverage.analysis_export
```

Monitor 通过 analysis_port 把事务广播给 Scoreboard 和 Coverage。

---

## 第十一章：Sequence——激励生成器

### 11.1 思路

Sequence 定义"发什么事务"。test 决定"启动哪些 sequence"。

一个最简单的写 sequence：
1. 创建一个 `axi_txn`
2. 填充字段（地址、数据、ID）
3. `start_item()` 请求发送
4. `finish_item()` 发给 Driver 并等完成

### 11.2 代码

文件：`sequences/axi_wr_seq.sv`

```systemverilog
class axi_wr_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_seq)

    // 由 test 配置这些参数
    bit [15:0] s_addr;
    bit [31:0] s_data;
    bit [7:0]  s_id;

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");

        // 填充事务
        txn.kind  = axi_txn::WRITE;
        txn.addr  = s_addr;
        txn.id    = s_id;
        txn.len   = 0;          // 单拍写
        txn.size  = 2;          // 4 字节
        txn.wdata = new[1];
        txn.wstrb = new[1];
        txn.wdata[0] = s_data;
        txn.wstrb[0] = 4'hF;

        // 发送
        start_item(txn);        // 请求 sequencer 授权
        finish_item(txn);       // 发给 driver，等 driver 完成
    endtask
endclass
```

文件：`sequences/axi_rd_seq.sv`

```systemverilog
class axi_rd_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_rd_seq)

    bit [15:0] s_addr;
    bit [7:0]  s_id;

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind = axi_txn::READ;
        txn.addr = s_addr;
        txn.id   = s_id;
        txn.len  = 0;
        txn.size = 2;
        txn.rdata = new[1];

        start_item(txn);
        finish_item(txn);
    endtask
endclass
```

### 11.3 更复杂的 Sequence

Burst 写（多拍数据）：

```systemverilog
class axi_burst_wr_seq extends uvm_sequence #(axi_txn);
    bit [15:0] s_addr;
    bit [7:0]  s_id;
    bit [7:0]  s_len;     // burst 长度 - 1

    task body();
        axi_txn txn = axi_txn::type_id::create("txn");
        txn.kind  = axi_txn::WRITE;
        txn.addr  = s_addr;
        txn.id    = s_id;
        txn.len   = s_len;
        txn.size  = 2;
        txn.wdata = new[s_len + 1];
        txn.wstrb = new[s_len + 1];
        for (int i = 0; i <= s_len; i++) begin
            txn.wdata[i] = 32'hA500_0000 + i;
            txn.wstrb[i] = 4'hF;
        end
        start_item(txn);
        finish_item(txn);
    endtask
endclass
```

---

## 第十二章：Test——入口和调度

### 12.1 思路

Test 是 UVM 的入口。testbench top 里的 `run_test("axi_basic_test")` 就是实例化它。

Test 做三件事：
1. **build_phase**：创建 environment
2. **run_phase**：启动 sequence，控制仿真时长
3. **raise/drop objection**：告诉 UVM "我还没做完，别结束仿真"

### 12.2 代码

文件：`tests/axi_base_test.sv`

```systemverilog
// 基类：所有 test 的父亲
class axi_base_test extends uvm_test;
    `uvm_component_utils(axi_base_test)
    axi_env env;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction
endclass
```

文件：`tests/axi_basic_test.sv`

```systemverilog
class axi_basic_test extends axi_base_test;
    `uvm_component_utils(axi_basic_test)

    task run_phase(uvm_phase phase);
        axi_wr_seq wr_seq;
        axi_rd_seq rd_seq;

        phase.raise_objection(this);     // ① 抬起反对：仿真别结束

        // 等复位完成
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // ② 写 4 个 slave
        for (int s = 0; s < 4; s++) begin
            wr_seq = axi_wr_seq::type_id::create($sformatf("wr%0d", s));
            wr_seq.s_addr = s * 16'h1000;
            wr_seq.s_data = 32'hDEAD0000 + s;
            wr_seq.s_id   = 8'h10;
            wr_seq.start(env.sqr[0]);    // 从 sequencer 0 发出
        end

        #200;

        // ③ 读回验证
        for (int s = 0; s < 4; s++) begin
            rd_seq = axi_rd_seq::type_id::create($sformatf("rd%0d", s));
            rd_seq.s_addr = s * 16'h1000;
            rd_seq.s_id   = 8'h10;
            rd_seq.start(env.sqr[0]);
        end

        #200;
        phase.drop_objection(this);      // ④ 放下反对：可以结束了
    endtask
endclass
```

### 12.3 多 Master 并发测试

```systemverilog
class axi_multi_master_test extends axi_base_test;
    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 4 个 master 同时写，fork/join 并行
        fork
            begin
                seq = axi_wr_seq::type_id::create("m0");
                seq.s_addr = 16'h0000; seq.s_data = 32'hAAAAAAAA; seq.s_id = 8'h10;
                seq.start(env.sqr[0]);  // Master 0
            end
            begin
                seq = axi_wr_seq::type_id::create("m1");
                seq.s_addr = 16'h1000; seq.s_data = 32'hBBBBBBBB; seq.s_id = 8'h20;
                seq.start(env.sqr[1]);  // Master 1
            end
            begin
                seq = axi_wr_seq::type_id::create("m2");
                seq.s_addr = 16'h2000; seq.s_data = 32'hCCCCCCCC; seq.s_id = 8'h30;
                seq.start(env.sqr[2]);  // Master 2
            end
            begin
                seq = axi_wr_seq::type_id::create("m3");
                seq.s_addr = 16'h3000; seq.s_data = 32'hDDDDDDDD; seq.s_id = 8'h40;
                seq.start(env.sqr[3]);  // Master 3
            end
        join

        #200;
        phase.drop_objection(this);
    endtask
endclass
```

---

## 第十三章：Testbench Top——最顶层

### 13.1 思路

Testbench Top 做 4 件事：
1. 产生时钟和复位
2. 例化 Interface
3. 例化 DUT，把 Interface 连到 DUT
4. 把 Interface 通过 `config_db` 传给 UVM 组件
5. 调用 `run_test()` 启动 UVM

### 13.2 代码

文件：`tb/axi_crossbar_tb.sv`

```systemverilog
module axi_crossbar_tb;
    import uvm_pkg::*;
    import axi_pkg::*;
    `include "uvm_macros.svh"

    // ============ 时钟和复位 ============
    logic aclk = 0;
    logic aresetn = 0;
    logic srst = 1;
    always #5 aclk = ~aclk;           // 100MHz
    initial begin #100; aresetn = 1; srst = 0; end

    // ============ 例化 Interface ============
    axi_if mst_if[4] (.aclk(aclk));   // Master 侧
    axi_if slv_if[4] (.aclk(aclk));   // Slave 侧

    // 同步 aresetn 到所有 interface
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_rst
            always @(posedge aclk) mst_if[i].aresetn <= aresetn;
            always @(posedge aclk) slv_if[i].aresetn <= aresetn;
        end
    endgenerate

    // ============ 例化 DUT ============
    axicb_crossbar_top #(
        .AXI_ADDR_W(16), .AXI_ID_W(8), .AXI_DATA_W(32),
        .MST_NB(4), .SLV_NB(4),
        // ... 其他参数 ...
    ) dut (
        .aclk(aclk), .aresetn(aresetn), .srst(srst),
        // Master 0 连 mst_if[0]
        .slv0_awvalid(mst_if[0].awvalid), .slv0_awready(mst_if[0].awready),
        .slv0_awaddr(mst_if[0].awaddr),   /* ... 其他信号 ... */
        // Slave 0 连 slv_if[0]
        .mst0_awvalid(slv_if[0].awvalid), .mst0_awready(slv_if[0].awready),
        .mst0_awaddr(slv_if[0].awaddr),   /* ... 其他信号 ... */
        // ... Master 1~3, Slave 1~3 ...
    );

    // ============ config_db：把 vif 传给 UVM 组件 ============
    initial begin
        // 每个 driver 和 monitor 都需要自己的 vif
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv0", "vif", mst_if[0]);
        uvm_config_db#(virtual axi_if)::set(null, "*.mst_mon0", "vif", mst_if[0]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_drv0", "vif", slv_if[0]);
        uvm_config_db#(virtual axi_if)::set(null, "*.slv_mon0", "vif", slv_if[0]);
        // ... mst_if[1~3], slv_if[1~3] ...

        run_test("axi_basic_test");  // 启动 UVM
    end

    // ============ 超时保护 ============
    initial begin
        #50000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end
endmodule
```

### 13.3 关键点解释

**Q：`config_db::set` 的参数是什么？**

```systemverilog
uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv0", "vif", mst_if[0]);
//                                    │      │            │      │
//                                 context  inst_name    field   value
//                                 (null=全局) (路径匹配) (key)   (值)
```

`"*.mst_drv0"` 匹配 env 里名字为 `mst_drv0` 的组件。Driver 的 `build_phase` 里用 `get(this, "", "vif", vif)` 取出来。

**Q：为什么 `run_test()` 放在 `initial` 里？**

`run_test()` 是 UVM 的入口，它会启动所有 phase（build → connect → run → report）。放在 `initial` 里是因为它是仿真开始时执行一次的操作。

---

## 第十四章：Package——把所有文件串起来

### 14.1 思路

SystemVerilog 的 `package` 把所有类定义打包，避免命名冲突。所有 UVM 组件、序列、测试都放在一个 package 里。

### 14.2 代码

文件：`env/axi_pkg.sv`

```systemverilog
package axi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ============ 组件 ============
    `include "components/axi_slv_cfg.sv"
    `include "components/axi_txn.sv"
    `include "components/axi_mst_drv.sv"
    `include "components/axi_slv_drv.sv"
    `include "components/axi_monitor.sv"
    `include "components/axi_scoreboard.sv"
    `include "components/axi_coverage.sv"
    `include "components/axi_env.sv"

    // ============ 序列 ============
    `include "sequences/axi_wr_seq.sv"
    `include "sequences/axi_rd_seq.sv"
    `include "sequences/axi_burst_wr_seq.sv"
    // ... 其他序列 ...

    // ============ 测试 ============
    `include "tests/axi_base_test.sv"
    `include "tests/axi_basic_test.sv"
    `include "tests/axi_routing_test.sv"
    // ... 其他测试 ...
endpackage
```

### 14.3 编译顺序

```
1. axi_if.sv        ← Interface 先编译（package 里的类需要 virtual interface 类型）
2. axi_pkg.sv       ← Package 编译（include 所有类）
3. axi_crossbar_tb.sv ← Testbench Top 编译（import package）
```

---

## 第十五章：Makefile——一键编译运行

### 15.1 代码

文件：`Makefile`

```makefile
SIM ?= vcs
SRC_DIR = ../src

# RTL 文件
SRC_FILES = \
    $(SRC_DIR)/axicb_crossbar_top.sv \
    $(SRC_DIR)/axicb_switch_top.sv \
    # ... 其他 RTL ...

# TB 文件（注意顺序：interface → package → module）
TB_FILES = \
    env/axi_if.sv \
    env/axi_pkg.sv \
    tb/axi_crossbar_tb.sv

# VCS 编译选项
VCS_OPTS = -sverilog -full64 \
           +incdir+$(SRC_DIR) +incdir+env \
           +incdir+components +incdir+sequences +incdir+tests \
           -ntb_opts uvm-1.2 -timescale=1ns/1ps

# 通用目标
compile:
	vcs $(VCS_OPTS) $(SRC_FILES) $(TB_FILES) -o simv

sim: compile
	./simv +UVM_TESTNAME=$(UVM_TEST) -l sim.log

clean:
	rm -rf simv simv.daidir csrc *.log *.vcd cov_db

# 测试目标
test_basic:    ; $(MAKE) sim UVM_TEST=axi_basic_test SIM=$(SIM)
test_routing:  ; $(MAKE) sim UVM_TEST=axi_routing_test SIM=$(SIM)
# ... 其他测试 ...

regression:
	$(MAKE) test_basic SIM=$(SIM)
	$(MAKE) test_routing SIM=$(SIM)
	# ... 所有测试 ...
```

---

## 第十六章：运行和调试

### 16.1 编译

```bash
cd verification
make compile SIM=vcs
```

看到 `simv up to date` 就成功了。

### 16.2 运行单个测试

```bash
make sim SIM=vcs UVM_TEST=axi_basic_test
```

### 16.3 看结果

仿真日志里关键信息：

```
UVM_INFO ... [SCBD] WR: 4 pass / 0 fail     ← Scoreboard：4 个写事务全对
UVM_INFO ... [SCBD] RD: 4 pass / 0 fail     ← Scoreboard：4 个读事务全对
UVM_INFO ... [COV] Coverage: 56.7%           ← 覆盖率
UVM_ERROR : 0                                ← 0 个错误
UVM_FATAL : 0                                ← 0 个致命错误
```

### 16.4 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `NOVIF` | config_db 没传 vif | 检查 testbench top 的 `set()` 和 driver 的 `get()` |
| `TIMEOUT` | objection 没放下 | 检查 `drop_objection()` 有没有漏 |
| `SCBD DATA MISMATCH` | 数据不对 | 检查 DUT 或 test 逻辑 |
| 编译报 `class not found` | include 顺序错 | 确保 `axi_txn.sv` 在 `axi_mst_drv.sv` 之前 |

---

## 附录：常见问题

### Q：为什么 test 里要 `@(posedge env.mst_drv[0].vif.aresetn)`？

等复位释放。复位期间信号都是 0，不能发事务。等 `aresetn` 从 0 变 1，再等几个时钟周期，DUT 就稳定了。

### Q：`fork/join` 和 `fork/join_none` 的区别？

- `fork/join`：等所有子线程全部完成才继续
- `fork/join_none`：不等，立刻继续（子线程后台运行）

并发测试用 `fork/join`，流水线 outstanding 用 `fork/join_none`。

### Q：怎么加一个新的测试？

1. 在 `sequences/` 下写一个新 sequence
2. 在 `tests/` 下写一个新 test，继承 `axi_base_test`
3. 在 `axi_pkg.sv` 里 include 新文件
4. 在 `Makefile` 里加一个 target
5. `make compile && make sim UVM_TEST=你的test名`

### Q：怎么提高覆盖率？

看覆盖率报告里哪些 bin 没覆盖到，然后：
- 加新的 sequence 刺激那个场景
- 在 test 里配置 sequence 的参数
- 用 `constraint_mode(0)` 关闭某些约束，让随机范围更大
