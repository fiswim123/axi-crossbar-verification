# AXI Crossbar UVM 验证项目 — 面试宝典

> 本文档按面试官提问逻辑组织，从项目概述到深挖细节，覆盖面试中可能被问到的每个角度。每个问题都给出了"标准答案"和"加分回答"。

---

## 目录

- [第一部分：项目概述](#第一部分项目概述)
- [第二部分：架构深挖](#第二部分架构深挖)
- [第三部分：UVM 环境详解](#第三部分uvm-环境详解)
- [第四部分：测试点分解](#第四部分测试点分解)
- [第五部分：覆盖率](#第五部分覆盖率)
- [第六部分：Bug 与 Debug](#第六部分bug-与-debug)
- [第七部分：不足与改进](#第七部分不足与改进)
- [第八部分：基础知识追问](#第八部分基础知识追问)
- [附录：专业术语中英文对照](#附录专业术语中英文对照)

---

## 第一部分：项目概述

### Q1：介绍一下你的项目

**标准回答：**

我做的是一个 4×4 AXI4 Crossbar 的 UVM 验证项目。Crossbar 的功能是把 4 个 Master 发出的读写请求，根据地址路由到 4 个 Slave 中的某一个，同时支持 round-robin 仲裁和乱序完成。

我搭建了完整的 UVM 验证环境，包含 8 个 UVM 组件、15 个 Sequence、28 个测试用例，覆盖基础功能、协议、并发、错误注入、背压、复位、随机和性能 9 大场景。全回归功能覆盖率 98%，Scoreboard 全部 pass。

**加分回答：**

DUT 本身是一个开源的 AXI Crossbar IP，我的工作重点不在 RTL 设计，而是验证。我从零搭建了整个 UVM 环境，包括 interface、transaction、driver、monitor、scoreboard、coverage，以及所有的 sequence 和 test。中间遇到了不少问题，比如 aresetn 端口方向导致 test 无法驱动 reset、coverage 跨测试不累积等，都实际解决了。

---

### Q2：DUT 的接口规格是什么？

```
| 参数       | 值       |
|------------|----------|
| 主/从接口  | 4 × 4    |
| 数据宽度   | 32-bit   |
| 地址宽度   | 16-bit   |
| ID 宽度    | 8-bit    |
| 协议       | AXI4     |
```

地址映射：
```
SLV0: 0x0000 ~ 0x0FFF (4KB)
SLV1: 0x1000 ~ 0x1FFF (4KB)
SLV2: 0x2000 ~ 0x2FFF (4KB)
SLV3: 0x3000 ~ 0x3FFF (4KB)
```

路由方式：根据地址的高 4 位 `[15:12]` 选择 Slave。

**追问：为什么地址宽度是 16-bit？**

这是项目参数化设定的，16-bit 地址空间 64KB，对于验证 4 个 4KB 的 Slave 足够了。实际 SoC 中地址宽度通常是 32-bit 或 64-bit，这里简化是为了仿真效率。

---

### Q3：Crossbar 和普通 MUX 有什么区别？

**普通 MUX（总线仲裁器）：** 同一时刻只允许一个 Master 访问一个 Slave，其他 Master 必须等待。

**Crossbar（交叉开关）：** 同一时刻允许多个 Master 并行访问不同 Slave，只有当多个 Master 访问同一个 Slave 时才需要仲裁。

```
普通 MUX:   M0 ──┐         ┌── S0
            M1 ──┤──仲裁──┤── S1    （串行）
            M2 ──┘         └── S2

Crossbar:   M0 ──╫──────────╫── S0
            M1 ──╫──────────╫── S1    （并行）
            M2 ──╫──────────╫── S2
```

**追问：你项目里的 Crossbar 用的什么仲裁策略？**

Round-robin 轮询仲裁。当多个 Master 同时访问同一个 Slave 时，仲裁器按轮询顺序选择一个 Master，保证公平性。

---

## 第二部分：架构深挖

### Q4：画一下你的验证环境架构图

```
axi_crossbar_tb (Testbench Top)
  │
  ├── 时钟/复位产生
  ├── Interface 例化 (mst_if[4], slv_if[4])
  ├── DUT 例化 (axicb_crossbar_top)
  ├── config_db 传递 vif
  └── run_test()
        │
        └── axi_env
              ├── axi_mst_drv[0..3]  ←── sequencer[0..3]  ←── sequence
              ├── axi_slv_drv[0..3]   (内存模型 + 背压 + 错误注入)
              ├── axi_monitor[0..3]   (MST 侧) ──→ scoreboard + coverage
              ├── axi_monitor[0..3]   (SLV 侧)
              ├── axi_scoreboard      (写存读比 + 延迟统计)
              └── axi_coverage        (路由交叉 + burst 类型覆盖)
```

**追问：为什么 Master 侧和 Slave 侧各需要一个 Monitor？**

Master 侧 Monitor 采的是 Master 发出的事务（用于 scoreboard 比对），Slave 侧 Monitor 采的是 Slave 收到的事务（用于验证 DUT 路由是否正确）。当前实现只把 Master 侧 Monitor 连到 Scoreboard，避免重复计数。

---

### Q5：数据流是怎样的？

**写事务数据流：**
```
Sequence 生成 axi_txn(WRITE)
    │
    ▼
Sequencer 缓存
    │
    ▼
Driver.get_next_item() 取出 txn
    │
    ▼
Driver 驱动 AW 通道（awvalid, awaddr, awlen...）
    │  等 awready
    ▼
Driver 驱动 W 通道（wvalid, wdata, wstrb, wlast）
    │  等 wready
    ▼
Driver 等 B 通道响应（bvalid, bresp）
    │
    ▼
Driver.item_done() 通知 Sequencer
    │
    ▼
Monitor 采样完整事务 → 发给 Scoreboard + Coverage
```

**追问：Driver 怎么知道什么时候驱动下一拍数据？**

通过 `do @(posedge vif.aclk); while (!vif.awready);` 这种方式。AXI 协议规定 valid 和 ready 同时为 1 时数据被采样，所以 Driver 先拉高 valid，然后等 ready 拉高。

---

### Q6：Slave Driver 的内存模型是怎么做的？

Slave Driver 内部维护一个关联数组 `bit [7:0] mem[bit [31:0]]`，按字节寻址。

**写操作：** 收到 AW 地址后，把 W 通道的数据按字节存入 mem：
```systemverilog
mem[addr]   = wdata[7:0];
mem[addr+1] = wdata[15:8];
mem[addr+2] = wdata[23:16];
mem[addr+3] = wdata[31:24];
```

**读操作：** 收到 AR 地址后，从 mem 取出数据拼成 32-bit 返回：
```systemverilog
rdata = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
```

**追问：为什么用关联数组而不是普通数组？**

因为地址空间是 16-bit（64KB），如果用普通数组要分配 64K 个元素，大部分不会被访问到。关联数组只存实际被写入的地址，节省内存。

---

## 第三部分：UVM 环境详解

### Q7：你的 Sequence 和 Test 是怎么分工的？

| 层次 | 职责 | 例子 |
|------|------|------|
| **Sequence** | 定义"发什么事务" | axi_wr_seq 定义一次写事务的地址、数据、ID |
| **Test** | 定义"启动哪些 sequence、怎么调度" | axi_multi_master_test 用 fork/join 启动 4 个 sequence 并行 |

**Test 不直接驱动信号**，只做三件事：
1. 配置环境（比如设置背压概率）
2. 启动 sequence（通过 `seq.start(env.sqr[x])`）
3. 控制仿真时长（raise/drop objection）

**追问：为什么不把激励直接写在 Test 里？**

因为 Sequence 可以复用。比如 `axi_wr_seq` 被 basic_test、routing_test、multi_master_test 等十多个 test 共用。如果写在 test 里，每个 test 都要重复写一遍驱动逻辑。

---

### Q8：start_item 和 finish_item 是做什么的？

```systemverilog
start_item(txn);    // 请求 sequencer 授权（阻塞直到 sequencer 允许）
// 这里可以修改 txn 的字段
finish_item(txn);   // 把 txn 发给 driver，等 driver 完成
```

**握手过程：**
```
Sequence          Sequencer          Driver
   │                  │                 │
   ├──start_item()──→ │                 │
   │  (等待授权)       │                 │
   │ ←─ grant ────────┤                 │
   │                  │                 │
   ├──finish_item()──→│──get_next_item()→│
   │                  │                 ├── 驱动信号
   │                  │                 │
   │                  │ ←─item_done()───┤
   │ ←─ complete ─────┤                 │
```

**追问：如果两个 sequence 同时 start_item 会怎样？**

Sequencer 会仲裁。默认是 FIFO 顺序，也可以自定义仲裁策略。同一时刻只有一个 sequence 能拿到授权。

---

### Q9：objection 机制是什么？为什么需要它？

UVM 的 phase 机制默认是**零时间完成**——如果没有人 raise objection，run_phase 会立即结束。

```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this);   // "我还没做完，别结束"
    
    // ... 发事务 ...
    
    phase.drop_objection(this);    // "我做完了，可以结束了"
endtask
```

**追问：如果忘记 drop objection 会怎样？**

仿真永远不会结束，直到超时（`#50000000; uvm_fatal("TIMEOUT")`）。这是最常见的 bug 之一。

---

### Q10：config_db 是怎么用的？

两步：**set（传入）** 和 **get（取出）**。

**Testbench Top（set）：**
```systemverilog
uvm_config_db#(virtual axi_if)::set(null, "*.mst_drv0", "vif", mst_if[0]);
//                                    context  inst_name    key    value
```

**Driver（get）：**
```systemverilog
if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
    `uvm_fatal("NOVIF", "No vif")
```

**追问：`"*.mst_drv0"` 是什么意思？**

通配符路径匹配。`*` 匹配任意层次，所以 `"*.mst_drv0"` 匹配 `uvm_test_top.env.mst_drv0`。

---

### Q11：TLM 端口连接是怎么做的？

在 `connect_phase` 里：

```systemverilog
// Driver 从 Sequencer 拿事务
mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);

// Monitor 把事务发给 Scoreboard 和 Coverage
mst_mon[i].ap.connect(scbd.imp);
mst_mon[i].ap.connect(cov.analysis_export);
```

**三种 TLM 端口：**
| 端口 | 方向 | 用途 |
|------|------|------|
| `seq_item_port` | Driver → Sequencer | Driver 拉取事务 |
| `analysis_port` | Monitor → Scoreboard/Cov | Monitor 广播事务 |
| `analysis_imp` | Scoreboard/Cov 接收 | 接收端（write 函数） |

---

## 第四部分：测试点分解

### Q12：你的测试点是怎么分解的？

按 AXI 协议特征 + Crossbar 特有功能分解：

```
1. 基础功能
   ├── 单次读写是否正确
   ├── 路由是否正确（地址 → 正确的 Slave）
   └── 读写数据一致性

2. 协议合规
   ├── Burst 长度 (len=0/3/7/15)
   ├── Burst size (1B/2B/4B)
   └── Outstanding 深度

3. 并发仲裁
   ├── 多 Master 并行访问不同 Slave
   ├── 多 Master 访问同一 Slave（竞争仲裁）
   └── 读写交织

4. 异常场景
   ├── Slave 返回 SLVERR/DECERR
   ├── 背压（ready 随机延迟）
   └── 传输中复位

5. 边界条件
   ├── 地址边界（0x0FFF/0x1000 交界）
   ├── 最大 burst 长度
   └── 最大 outstanding 深度

6. 随机压力
   └── 大量随机事务长时间运行
```

**追问：为什么 burst 长度选 0/3/7/15 这几个值？**

覆盖 AXI 协议定义的 4 种典型长度区间：single(0)、short(1-3)、medium(4-7)、long(8-15)。选择区间的边界值，最大化覆盖效率。

---

### Q13：路由测试具体怎么做的？

`axi_routing_test` 测试 7 条路由路径：
- Master 0 → SLV0/1/2/3（遍历所有 Slave）
- Master 1 → SLV0
- Master 2 → SLV1
- Master 3 → SLV3

`axi_full_routing_test` 补全覆盖 13/16 种路由组合。

**追问：为什么不是 16/16？**

发现 DUT 有 bug：Master 3 无法访问 SLV0/1/2，只能访问 SLV3。写入 SLV0 时仿真卡死。这属于 DUT 问题，不是验证环境的问题。

**加分回答：** 这个 bug 是在跑 `axi_full_routing_test` 时发现的——仿真超时，通过加 debug 信息定位到 `seq.start(env.sqr[3])` 卡在第 4 个 sequence 上，进一步排除发现是 MST3→SLV0 路由不通。

---

### Q14：背压测试怎么做的？

通过 `axi_slv_cfg` 配置类控制 Slave Driver 的行为：

```systemverilog
env.slv_cfg[i].bp_wready_pct = 30;    // W 通道 30% 概率不给 ready
env.slv_cfg[i].bp_awready_pct = 20;   // AW 通道 20% 概率不给 ready
```

Slave Driver 内部用 `$urandom_range(0, 99) < bp_pct` 决定本拍是否给 ready。

**追问：背压覆盖了哪些通道？**

AW、W、AR 三个通道独立配置。B 和 R 通道的 ready 由 Master Driver 控制，当前实现是立即拉高，没有做延迟。

---

### Q15：错误注入测试怎么做的？

```systemverilog
env.slv_cfg[i].err_pct = 10;          // 10% 概率返回错误
env.slv_cfg[i].err_resp = 2'b10;      // SLVERR
```

Slave Driver 收到事务后，随机决定是正常响应还是返回错误。Scoreboard 根据 `expect_err` 标志判断是否应该出现错误响应。

---

## 第五部分：覆盖率

### Q16：你的覆盖率模型是怎么设计的？

```systemverilog
covergroup cg;
    cp_kind:  coverpoint txn.kind { bins rd, wr; }
    cp_slave: coverpoint txn.addr[15:12] { bins s0, s1, s2, s3; }
    cp_master: coverpoint txn.id[7:4] { bins m0, m1, m2, m3; }
    cp_len:   coverpoint txn.len { bins single, short, med, long; }
    cp_size:  coverpoint txn.size { bins b1, b2, b4; }

    cx_routing:  cross cp_master, cp_slave;      // 4×4 = 16 bins
    cx_kind_len: cross cp_kind, cp_len;           // 2×4 = 8 bins
    cx_kind_size: cross cp_kind, cp_size;         // 2×3 = 6 bins
    cx_kind_slave: cross cp_kind, cp_slave;       // 2×4 = 8 bins
endgroup
```

**全回归结果：**
| 覆盖点 | 结果 |
|--------|------|
| cp_kind (读/写) | 100% |
| cp_slave (4 个 slave) | 100% |
| cp_master (4 个 master) | 100% |
| cp_len (burst 长度) | 100% |
| cp_size (burst size) | 100% |
| cx_routing (路由交叉) | 81.25% (13/16) |
| 其他 cross | 100% |
| **功能覆盖率** | **98.12%** |

**追问：coverpoint 和 cross 有什么区别？**

coverpoint 是单维度覆盖（比如"4 个 slave 是否都访问过"），cross 是多维度组合覆盖（比如"每个 master 是否都访问过每个 slave"）。cross 的 bin 数量是各维度 bin 数量的乘积。

---

### Q17：代码覆盖率是多少？

```
LINE:    70.99%
COND:    55.49%
TOGGLE:  22.66%
BRANCH:  61.94%
综合:    61.84%
```

**追问：为什么 toggle 覆盖率这么低？**

因为 DUT 内部有很多配置信号（如 `MST0_CDC`、`MST0_OSTDREQ_SIZE` 等）在仿真中始终保持默认值不变，不会 toggle。要提高 toggle 覆盖率需要遍历更多配置参数组合。

**追问：功能覆盖率和代码覆盖率哪个更重要？**

功能覆盖率更重要。代码覆盖率只能证明"代码被跑到"，不能证明"功能被验证到"。功能覆盖率直接衡量验证计划的完成度。

---

### Q18：功能覆盖率是怎么累积的？

最初功能覆盖率不能跨测试累积——每次 `make sim` 是一个新进程，UVM covergroup 重新实例化，之前采到的 bin 归零。

**解决方案：** 在 Makefile 的编译和仿真选项中都加上 `-cm func`，让 VCS 把 covergroup 数据写入 `cov_db.vdb` 目录。每个测试用不同的 `-cm_name`，最后 `urg -dir cov_db.vdb` 合并所有测试的覆盖率。

---

## 第六部分：Bug 与 Debug

### Q19：项目中遇到了哪些 Bug？

**Bug 1：interface aresetn 端口方向问题**

现象：reset test 里 `env.mst_drv[0].vif.aresetn <= 0` 编译报错 "Variable input ports cannot be driven"。

原因：`aresetn` 是 interface 的 `input` port，从 interface 内部不能驱动。

解决：把 `aresetn` 从 input port 改为 interface 内部 logic 信号，testbench top 用 generate 块同步驱动。

---

**Bug 2：功能覆盖率不累积**

现象：全回归 27 个测试，urg 报告覆盖率只有 44.8%（最后一个测试的值）。

原因：Makefile 的 `-cm_name regression` 导致所有测试写入同一个数据库，后面覆盖前面。

解决：改成 `-cm_name $(UVM_TEST)`，每个测试独立命名，urg 自动合并。

---

**Bug 3：MST3 路由死锁**

现象：`axi_full_routing_test` 仿真超时。

排查：加 `uvm_info` debug 信息，定位到 `seq.start(env.sqr[3])` 卡在第 4 个 sequence。进一步测试发现 MST3 写 SLV0 时卡死。

结论：DUT 路由 bug，MST3 只能访问 SLV3。验证环境正确发现了 DUT 问题。

---

**Bug 4：test 直接驱动信号绕过 Driver**

现象：最初 12 个 test 用 `mst_write()` task 直接操作 interface 信号，Driver 完全空转。

排查：检查 `get_next_item()` 永远阻塞，因为没有 sequence 给它发事务。

解决：重写所有 test，统一走 sequence → sequencer → driver 链路。

---

**Bug 5：axi_pkg.sv 缺少 include**

现象：3 个 reset test 文件存在于磁盘上，但从未被编译运行。

原因：`axi_pkg.sv` 没有 include 这 3 个文件，Makefile 也没有它们的 target。

解决：补上 include 和 Makefile target。

---

### Q20：你一般怎么 Debug？

**系统化方法：**

1. **看日志**：`sim.log` 里搜 `UVM_ERROR`、`UVM_FATAL`、`TIMEOUT`
2. **加 debug 信息**：在关键位置加 `uvm_info` 打印时间戳和状态
3. **波形分析**：`$dumpfile/$dumpvars` 生成 VCD，用 DVE/Verdi 看波形
4. **最小化复现**：写一个最小 test 只测出问题的场景
5. **二分法排查**：注释一半代码看是否还出问题，逐步缩小范围

---

## 第七部分：不足与改进

### Q21：你觉得这个验证环境有什么不足？

**1. 没有独立参考模型（RM）**

当前 Scoreboard 用的是"写存读比"策略——写入数据存起来，读回来比对。这只验证了"数据不丢"，没有验证"DUT 内部路由逻辑是否正确"。

改进：写一个 C/SystemVerilog 的参考模型，模拟 Crossbar 的路由和仲裁行为，和 DUT 输出逐拍比对。

**2. 覆盖率模型不够细**

当前只覆盖了路由、burst 长度、读写类型。缺少：
- 错误响应的覆盖率点
- 背压场景的覆盖率点
- outstanding 深度的覆盖率点

**3. B/R 通道没有背压控制**

当前背压只覆盖 AW/W/AR 三通道，B 和 R 通道的 ready 由 Master Driver 立即拉高，没有模拟真实场景。

**4. 没有 Assertion-Based Verification**

只有基础的 valid 稳定性 SVA，缺少 burst 信号一致性、握手协议完整性等深层断言。

**5. 没有形式验证/形式属性检查**

只做了动态仿真，没有用形式验证工具证明属性永远成立。

---

### Q22：如果再给你一周时间，你会做什么？

1. 补齐 B/R 通道的背压控制
2. 增加错误响应、背压、outstanding 的覆盖率点
3. 写一个简单的参考模型替换当前 Scoreboard
4. 补充更多 SVA 断言（burst 信号一致性、地址对齐等）
5. 分析 toggle 覆盖率低的原因，补充配置参数遍历测试

---

## 第八部分：基础知识追问

### Q23：AXI 协议的 5 个通道分别是什么？

| 通道 | 全称 | 方向 | 作用 |
|------|------|------|------|
| AW | Write Address | Master → Slave | 写地址和控制信息 |
| W | Write Data | Master → Slave | 写数据和选通 |
| B | Write Response | Slave → Master | 写完成响应 |
| AR | Read Address | Master → Slave | 读地址和控制信息 |
| R | Read Data | Slave → Master | 读数据和响应 |

---

### Q24：AXI 握手协议是什么？

valid 和 ready 同时为 1 时数据被采样：

```
      ┌─────────────────────────┐
      │  valid=1, ready=0       │  等待
      │  valid=1, ready=1       │  数据传输（这一拍）
      │  valid=0, ready=1       │  空闲
      └─────────────────────────┘
```

规则：
- valid 不能依赖 ready（不能看 ready 才拉 valid）
- valid 一旦拉高，ready 没来之前不能掉
- ready 可以依赖 valid

---

### Q25：Burst 类型有哪些？

| 类型 | 编码 | 行为 |
|------|------|------|
| FIXED | 2'b00 | 每拍地址不变（FIFO 访问） |
| INCR | 2'b01 | 每拍地址递增（普通内存访问） |
| WRAP | 2'b10 | 地址到边界回绕（Cache line 填充） |

项目里只用了 INCR。

---

### Q26：UVM 的 factory 机制是什么？

factory 允许你在不修改原始类的情况下，用子类替换它：

```systemverilog
// 原始
class my_driver extends uvm_driver;
    `uvm_component_utils(my_driver)
endclass

// 替换
class my_fast_driver extends my_driver;
    `uvm_component_utils(my_fast_driver)
endclass

// 在 test 里替换
my_driver::type_id::set_type_override(my_fast_driver::get_type());
```

好处：不用改 env 代码，只在 test 里一行就能换 driver。

---

### Q27：UVM 的 phase 机制有哪些？

```
build_phase        → 创建组件
connect_phase      → 连接 TLM 端口
end_of_elaboration → 最终调整
start_of_simulation → 打印拓扑
run_phase          → 主仿真循环（消耗时间）
extract_phase      → 提取数据
check_phase        → 检查结果
report_phase       → 打印报告
```

run_phase 有 12 个子 phase（reset/configure/main/shutdown...），一般不用。

---

### Q28：virtual interface 和 interface 有什么区别？

`interface` 是硬件层面的信号bundle，只能在 `module` 里例化。

`virtual interface` 是 interface 的指针，可以在 `class`（UVM 组件）里使用。

UVM 组件是 class，不能直接例化 interface，所以用 virtual interface 间接访问。

---

### Q29：约束随机和直接测试有什么区别？

| | 约束随机 | 直接测试 |
|---|---|---|
| 激励生成 | solver 自动按 constraint 生成 | 人工写死 |
| 覆盖率 | 高（大量组合） | 低（只测已知场景） |
| 可复用 | 高（改 constraint 就行） | 低（每个场景重写） |
| 调试 | 难（随机值不确定） | 定（确定性输入） |

实际验证中两者结合：用约束随机覆盖大范围，用直接测试覆盖边界和已知 bug。

---

### Q30：你对 UVM 的理解是什么？

UVM 不是一个工具，是一套**验证方法论**。它规定了：
- 谁干什么（Driver 驱动、Monitor 采集、Scoreboard 比对）
- 怎么配合（TLM 端口、config_db、phase 机制）
- 怎么复用（factory、sequence、virtual sequence）

核心思想：**层次分离 + 可复用 + 覆盖率驱动**。有了这套框架，换一个 DUT 只需要改 interface 和 test，其他组件都能复用。

---

## 附录：专业术语中英文对照

### 验证方法学

| 英文 | 中文 | 说明 |
|------|------|------|
| UVM (Universal Verification Methodology) | 通用验证方法学 | 行业标准验证框架 |
| Constraint Random Verification | 约束随机验证 | 用 constraint 控制随机激励生成 |
| Coverage Driven Verification | 覆盖率驱动验证 | 以覆盖率为目标驱动验证完成 |
| Assertion Based Verification | 基于断言的验证 | 用 SVA 属性检查协议行为 |
| Reference Model (RM) | 参考模型 | 模拟 DUT 预期行为的软件模型 |
| Testbench (TB) | 测试平台 | 验证环境的顶层 |
| Testplan | 验证计划 | 定义测试点和覆盖目标的文档 |
| Regression | 回归测试 | 跑全部测试用例确认无退化 |

### UVM 组件与机制

| 英文 | 中文 | 说明 |
|------|------|------|
| Sequence Item | 事务对象 | 一次事务的数据载体 |
| Sequence | 序列 | 生成一组事务的激励脚本 |
| Sequencer | 仲裁器 | 调度多个 sequence 的执行顺序 |
| Driver | 驱动器 | 把事务对象转为信号级时序 |
| Monitor | 监视器 | 被动采集接口信号，打包成事务 |
| Scoreboard | 记分板 | 比对预期数据和实际数据 |
| Coverage | 覆盖率 | 衡量验证完成度的指标 |
| Agent | 代理 | Driver + Sequencer + Monitor 的封装 |
| Environment (Env) | 环境 | 所有 UVM 组件的容器 |
| Factory | 工厂 | 运行时替换组件类型的机制 |
| Phase | 阶段 | UVM 仿真的生命周期（build/connect/run/report） |
| Objection | 异议 | 控制 phase 何时结束的机制 |
| Config DB | 配置数据库 | 组件间传递参数的全局存储 |
| TLM (Transaction Level Modeling) | 事务级建模 | 组件间的数据传输接口 |
| Analysis Port | 分析端口 | 一对多的广播端口（Monitor → Scoreboard/Coverage） |
| Virtual Sequence | 虚拟序列 | 跨多个 sequencer 的顶层序列 |
| Modport | 模块端口 | Interface 内信号方向的定义 |

### AXI 协议

| 英文 | 中文 | 说明 |
|------|------|------|
| AXI (Advanced eXtensible Interface) | 高级可扩展接口 | ARM AMBA 总线协议 |
| Master | 主设备 | 发起读写请求的一方（如 CPU） |
| Slave | 从设备 | 响应读写请求的一方（如内存） |
| Crossbar | 交叉开关 | 多对多的路由互连结构 |
| Arbitration | 仲裁 | 多个 Master 竞争同一 Slave 时的调度策略 |
| Round Robin | 轮询 | 公平轮流的仲裁方式 |
| Burst | 突发传输 | 一次地址发送多拍数据 |
| Burst Length | 突发长度 | 一次 burst 传输的数据拍数 |
| Burst Size | 突发大小 | 每拍数据的字节数 (1/2/4B) |
| Outstanding | 未完成事务 | 已发出但未收到响应的事务数量 |
| Interleaving | 交织 | 不同事务的数据拍交替传输 |
| Handshake | 握手 | valid/ready 同时有效时数据传输 |
| Backpressure | 背压 | 接收方通过 ready 信号控制传输速率 |
| Valid | 有效 | 发送方表示数据准备好 |
| Ready | 就绪 | 接收方表示可以接收数据 |
| Address | 地址 | 读写操作的目标地址 |
| Write Strobe (WSTRB) | 写选通 | 按字节选择有效写入位 |
| Response (RESP) | 响应 | Slave 返回的事务状态 |
| OKAY (2'b00) | 正常响应 | 事务成功完成 |
| SLVERR (2'b10) | 从设备错误 | Slave 报告错误 |
| DECERR (2'b11) | 解码错误 | 地址无法路由到任何 Slave |
| WLAST | 最后一拍 | 写数据通道最后一拍标志 |
| RLAST | 最后一拍 | 读数据通道最后一拍标志 |

### SystemVerilog

| 英文 | 中文 | 说明 |
|------|------|------|
| Interface | 接口 | 信号 bundle 的封装 |
| Virtual Interface | 虚拟接口 | Interface 的指针，可在 class 中使用 |
| Covergroup | 覆盖组 | 功能覆盖率的采样容器 |
| Coverpoint | 覆盖点 | 单维度覆盖（如读/写） |
| Cross | 交叉覆盖 | 多维度组合覆盖（如 master × slave） |
| Bin | 覆盖仓 | 覆盖点的一个目标值或范围 |
| Constraint | 约束 | 限制随机变量取值范围的规则 |
| Randomize | 随机化 | 调用 solver 按 constraint 生成随机值 |
| Associative Array | 关联数组 | 按任意索引访问的稀疏数组 |
| Dynamic Array | 动态数组 | 运行时确定大小的数组 |
| Mailbox | 邮箱 | 进程间的 FIFO 通信机制 |
| Semaphore | 信号灯 | 进程间的互斥访问控制 |
| SVA (SystemVerilog Assertions) | 断言 | 用属性描述时序行为的检查机制 |
| Property | 属性 | SVA 中描述时序关系的规则 |
| Assertion | 断言 | 检查属性是否成立的语句 |
| Implication (|->) | 蕴含 | SVA 中的"如果...则..."关系 |

### 覆盖率与度量

| 英文 | 中文 | 说明 |
|------|------|------|
| Functional Coverage | 功能覆盖率 | 验证计划中测试场景的覆盖度 |
| Code Coverage | 代码覆盖率 | RTL 代码被执行的程度 |
| Line Coverage | 行覆盖率 | 代码行被执行的百分比 |
| Branch Coverage | 分支覆盖率 | if/else 分支被执行的百分比 |
| Toggle Coverage | 翻转覆盖率 | 信号 0→1/1→0 翻转的百分比 |
| Condition Coverage | 条件覆盖率 | 条件表达式各组合被执行的百分比 |
| FSM Coverage | 状态机覆盖率 | 状态机各状态/转移被执行的百分比 |
| Coverage Hole | 覆盖率空洞 | 未被任何测试覆盖的场景 |
| Coverage Goal | 覆盖率目标 | 验证计划要求达到的覆盖率阈值 |

### 仿真与调试

| 英文 | 中文 | 说明 |
|------|------|------|
| Simulation | 仿真 | 用软件模拟硬件行为 |
| VCS | VCS | Synopsys 的 Verilog 仿真器 |
| Xcelium | Xcelium | Cadence 的仿真器 |
| Waveform | 波形 | 信号随时间变化的图形 |
| VCD (Value Change Dump) | 值变化转储 | 通用波形文件格式 |
| FSDB | FSDB | Synopsys 的压缩波形格式 |
| Debug | 调试 | 定位和修复错误的过程 |
| Breakpoint | 断点 | 仿真暂停的条件 |
| Dump | 转储 | 把数据写到文件 |
| Elaboration | 精化 | 编译阶段的层次展开和连接 |
| Compilation | 编译 | 把源码转为目标代码 |
| Linking | 链接 | 把多个目标文件合并为可执行文件 |
| Timeout | 超时 | 仿真超过最大时间限制 |
| Objection Drop | 放弃异议 | 表示当前 phase 可以结束 |
