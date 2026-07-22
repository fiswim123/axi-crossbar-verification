# AXI Crossbar UVM 验证环境 —— 问题日志

> 本文档记录了在学习 AXI Crossbar UVM 验证环境过程中提出的问题和解答，
> 按 UVM 的核心概念链路组织，帮助理解验证平台的架构设计思路。

---

## 一、Transaction 与 Sequence 的关系

### Q1：为什么 `uvm_sequence #(axi_txn)` 直接传入 `axi_txn`？

**文件：** [axi_wr_seq.sv](../sequences/axi_wr_seq.sv:13)

**答：**
- `uvm_sequence #(REQ, RSP)` 的模板参数期望一个 `uvm_sequence_item` 的子类
- `axi_txn extends uvm_sequence_item`，满足要求
- 直接参数化后，sequence 内部可以直接使用 `axi_txn` 的具体字段（`addr`, `id`, `wdata` 等），无需向下转型
- Sequencer 和 Driver 两侧也使用 `#(axi_txn)` 参数化，类型保持统一

---

### Q2：为什么 Driver 的 `run_phase` 中没有 `axi_txn::type_id::create()`，但 Monitor 中有？

**文件：** [axi_mst_drv.sv](../components/axi_mst_drv.sv:104) vs [axi_monitor.sv](../components/axi_monitor.sv:98)

**答：** 因为数据流方向相反。

```
Sequence 创建 txn  →  Sequencer 转发  →  Driver 用 get_next_item 接收（不创建）
                                           Monitor 自己看到握手信号后创建 txn（自己造）
```

- **Driver：** txn 由 Sequence 创建，通过 Sequencer 转发给 Driver。Driver 只负责"读 txn 字段 → 驱动信号"。
- **Monitor：** 没有 Sequence 给它发 txn。Monitor 看到总线上发生握手后，自己创建一个 txn，把采样的信号填进去，再通过 `ap.write(txn)` 广播出去。

---

## 二、UVM 工厂注册机制

### Q3：为什么 Sequence 用 `uvm_object_utils`，而 Transaction 用 `uvm_object_utils_begin/end`？

**文件：** [axi_wr_seq.sv:17](../sequences/axi_wr_seq.sv:17) vs [axi_txn.sv:124](../components/axi_txn.sv:124)

**答：**

| 宏 | Sequence (`axi_wr_seq`) | Transaction (`axi_txn`) |
|---|---|---|
| 注册宏 | `uvm_object_utils` | `uvm_object_utils_begin/end` |
| 有 `uvm_field_*` 吗 | 没有 | 有（enum, int, array 等字段自动化） |
| 自动生成的方法 | 只有工厂创建 | 工厂创建 + `print/copy/compare/pack/unpack` |

- **Sequence** 的字段是外部手动赋值的（`s_addr`, `s_data`, `s_id`），不需要被复制、比较、打印，所以只需注册到工厂。
- **Transaction** 需要被 Scoreboard 复制（`copy`）和比较（`compare`），需要被打印（`print`）调试，所以需要用 `uvm_field_*` 声明字段，让 UVM 自动实现这些方法。

---

## 三、UVM 面向对象基础

### Q4：`new()` 构造函数中 `super.new(name)` 是什么意思？

**文件：** [axi_wr_seq.sv:33-35](../sequences/axi_wr_seq.sv:33)

**答：**
- `super` 指代父类（`uvm_sequence #(axi_txn)`）
- `super.new(name)` 调用父类的构造函数，让父类完成自己的初始化（如 UVM 层次命名、资源分配）
- 规则：子类构造函数必须在第一行调用父类构造函数
- 如果不写，SystemVerilog 会隐式插入无参的 `super.new()`，但 `uvm_sequence` 需要 `name` 参数，所以必须显式调用

---

## 四、Sequence → Sequencer → Driver 握手机制

### Q5：`start_item/finish_item` 是怎么工作的？不是应该由 Sequencer 仲裁后再转发吗？

**文件：** [axi_wr_seq.sv:68-85](../sequences/axi_wr_seq.sv:68)

**答：** 确实由 Sequencer 仲裁和转发，完整路径是：

```
start_item(txn)  →  Sequencer.wait_for_grant()    ← 仲裁在这里
                       └─ 多个 Sequence 竞争时按优先级/lock/grab 裁决
                       └─ 拿到许可后才返回

finish_item(txn) →  Sequencer.send_request(txn)   ← txn 进 Sequencer FIFO
                  →  Sequencer → Driver (TLM 连接)
                  →  Driver.get_next_item() 取出 txn
                  →  Driver.item_done()
                  →  finish_item 返回
```

所以不是"直接发给 Driver"，而是 **Sequence → Sequencer（仲裁+转发）→ Driver**。

---

### Q6：最后为什么要阻塞等待 Driver 返回？

**答：** `finish_item` 内部调用 `wait_for_item_done()`，阻塞等待 Driver 的 `item_done()`。阻塞的意义：

| 目的 | 说明 |
|---|---|
| **有序执行** | Sequence 是"脚本"，描述"先做A、等A完成、再做B"的顺序 |
| **流控** | 防止 Sequence 产生 txn 速度超过 Driver 的消费速度 |
| **获取响应** | 读事务需要等 Driver 从总线上拿回 `rdata` |

**不阻塞的情况：** `finish_item` 可拆为 `send_request` + `wait_for_item_done`。Outstanding 场景下只调 `send_request` 不等完成，发完一批再统一等。见 [axi_outstanding_read_seq.sv](../sequences/axi_outstanding_read_seq.sv)。

---

### Q7：Sequencer 内部的仲裁函数和 FIFO 怎么没在 Agent 中体现？

**文件：** [axi_mst_agent.sv](../components/axi_mst_agent.sv)

**答：** 它们在 UVM 库内部，不在项目代码中。

Agent 中与 Sequencer 相关的代码只有 **3 处**：

```systemverilog
// ① 句柄声明（第 47 行）
uvm_sequencer #(axi_txn) sequencer;

// ② 创建对象（第 108 行）
sequencer = uvm_sequencer#(axi_txn)::type_id::create("sequencer", this);

// ③ 连接 Driver（第 125 行）
driver.seq_item_port.connect(sequencer.seq_item_export);
```

`wait_for_grant`、`send_request`、`wait_for_item_done` 以及内部 FIFO 都是 UVM 库的 `uvm_sequencer` 基类中预实现的，对用户透明。

---

## 五、验证组件架构设计

### Q8：Sequencer 能不能从 Agent 里单独拿出来？

**答：** 技术上可以，但当前项目（1 Agent : 1 Driver : 1 Sequencer）情况下不需要。

```
// 如果拆出来，在 env 层创建并手动连接：
mst_sequencer = uvm_sequencer#(axi_txn)::type_id::create("mst_sequencer", this);
// agent 里只留 driver + monitor
mst_agent.driver.seq_item_port.connect(mst_sequencer.seq_item_export);
```

**拆的代价：** 破坏 `is_active = UVM_PASSIVE` 的封装（需要手动关闭 Sequencer），且没有实质收益。

**需要拆的场景：** 一个 Driver 接多个 Sequencer、Virtual Sequencer、多个 Driver 共享一个 Sequencer。

---

### Q9：Sequencer 能不能像 Driver/Monitor 那样单独写一个文件，再由 Agent 封装？

**答：** 可以写，但没必要。`uvm_sequencer` 是 UVM 库中预定义好的类，几乎不需要用户扩展。如果单独写：

```systemverilog
class axi_mst_sequencer extends uvm_sequencer #(axi_txn);
    `uvm_component_utils(axi_mst_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    // 空的——不需要加任何代码
endclass
```

**需要子类化的唯一场景：** 自定义仲裁策略（加权轮询、优先级矩阵）或全局状态跟踪（outstanding 计数）。当前项目不需要。

---

### Q10：为什么 Agent、Driver、CFG 要区分 Master 和 Slave？

**文件：** [axi_mst_agent.sv](../components/axi_mst_agent.sv) vs 理论上应有 `axi_slv_agent.sv`

**答：** 因为 AXI 协议中 Master 和 Slave 的角色**镜像对称**。

| 方面 | Master | Slave |
|---|---|---|
| **Driver 行为** | 主动驱动 AW/W/AR 通道 valid | 被动响应，控制 ready 和 B/R 通道 valid |
| **Sequencer** | 需要（产生激励） | 不需要（被动响应） |
| **配置** | 不需要 | `axi_slv_cfg`——背压概率、错误注入、延迟配置 |
| **存储器模型** | 无 | 有（`mem[]`，存储写入数据供读回） |

Master Driver 和 Slave Driver 的 `run_phase` 代码完全不同，无法复用同一个类。

---

### Q11：Monitor 就一份文件，Master 和 Slave 都在用，没问题吗？

**文件：** [axi_monitor.sv](../components/axi_monitor.sv)

**答：** 完全没问题。Monitor 是被动观察者，**只采样不驱动**。对于同一组 AXI 接口信号，Master 侧和 Slave 侧看到的信号是一样的。

靠两个配置字段区分角色：

```systemverilog
// Master Agent 设置：
uvm_config_db#(int)::set(this, "monitor", "source_id", master_id);
uvm_config_db#(bit)::set(this, "monitor", "is_slave",  0);

// Slave Agent 设置：
uvm_config_db#(int)::set(this, "monitor", "source_id", slave_id);
uvm_config_db#(bit)::set(this, "monitor", "is_slave",  1);
```

Monitor 在采样时将这两个标记填入 txn 对象，Scoreboard 据此区分事务来源。

---

### Q12：为什么 Driver 和 Monitor 都要通过 `virtual interface` 获取 `axi_if`？

**答：** 因为两者都需要访问 DUT 的物理信号：

| 组件 | 访问方式 | 用途 |
|---|---|---|
| **Driver** | 读写信号 | 驱动激励到 DUT（写 valid/addr/data，读 ready） |
| **Monitor** | 只读信号 | 采样总线上的握手和数据 |

`virtual interface` 是指向物理 `interface` 的句柄，通过 `uvm_config_db` 从 Testbench 顶层分发到各个组件。

Agent 中一次 `set`，Driver 和 Monitor 各自 `get`：

```systemverilog
// Agent 从 config_db 拿到 vif，分发给子组件
uvm_config_db#(virtual axi_if)::set(this, "driver", "vif", vif);
uvm_config_db#(virtual axi_if)::set(this, "monitor", "vif", vif);
```

---

## 六、信号驱动细节

### Q13：初始化时为什么只清了 valid/ready，没清 len/size/burst/wstrb？

**文件：** [axi_mst_drv.sv:93-100](../components/axi_mst_drv.sv:93)

**答：** 因为 AXI 握手协议中 **`valid=0` 时其他信号是 "don't care"**。

```
当 valid = 0  →  接收方必须忽略 addr, len, size, burst, wdata...
当 valid = 1  →  接收方采样这些信号（此时它们必须有效）
```

所以初始化只需保证 `valid=0`（没有正在进行的交易），`len/size/burst` 等信号即使为 X，只要 `valid` 拉高时它们已确定就没有问题。

**Slave Driver 初始化更彻底的原因：** Slave 在 B/R 通道上是发送方，虽然 `valid=0` 时数据也是 don't care，但清掉可以让波形更干净。

---

## 七、Scoreboard 数据比对

### Q14：Scoreboard 中队列命名 `mst_wr_txns` / `slv_wr_txns`，是只收集写事务吗？

**文件：** [axi_scoreboard.sv:24-25](../components/axi_scoreboard.sv:24)

**答：** 是的，只收集写事务用于路由验证。

```systemverilog
function void write_master(axi_txn txn);
    if (txn.kind == axi_txn::WRITE)
        mst_wr_txns.push_back(txn);  // ← 写才入队
    else
        mst_rd_cnt++;                 // ← 读只计数
endfunction
```

读事务只有统计计数，没有入队比对。

---

### Q15：读的路由验证为什么没做？

**答：** 读事务无法通过 `(addr, rdata)` 唯一匹配写事务可以通过 `(addr + wdata)` 双重匹配，但读的问题：

```
Master 读 #1: addr=0x1000, rdata=0xAAAA
Master 读 #2: addr=0x1000, rdata=0xAAAA  ← 无法区分！
Slave  读 #1: addr=0x1000, rdata=0xAAAA
Slave  读 #2: addr=0x1000, rdata=0xAAAA
```

正确的读路由验证需要**按 AXI ID 匹配**（`slv_txn.id == mst_txn.id`），但这要求 Monitor 能正确处理 **Outstanding 场景下 AR 和 R 的配对**：

```
AR 发 #0 (id=5)    AR 发 #1 (id=8)
                    R 收 #1 (id=8)  ← 乱序返回
                    R 收 #0 (id=5)
```

当前 `axi_monitor.mon_rd()` 是顺序等 AR 握手 → 等 R 数据的方式，不支持 Outstanding 乱序下的正确配对。所以读路由验证暂时留空，留待后续扩展。

---

## 附录：涉及的文件索引

| 文件 | 相关问题 |
|------|---------|
| [axi_txn.sv](../components/axi_txn.sv) | Q1, Q3 |
| [axi_wr_seq.sv](../sequences/axi_wr_seq.sv) | Q1, Q3, Q4, Q5 |
| [axi_mst_agent.sv](../components/axi_mst_agent.sv) | Q7, Q10, Q11, Q12 |
| [axi_mst_drv.sv](../components/axi_mst_drv.sv) | Q2, Q10, Q13 |
| [axi_slv_drv.sv](../components/axi_slv_drv.sv) | Q10, Q13 |
| [axi_slv_cfg.sv](../components/axi_slv_cfg.sv) | Q10 |
| [axi_monitor.sv](../components/axi_monitor.sv) | Q2, Q11, Q12, Q15 |
| [axi_scoreboard.sv](../components/axi_scoreboard.sv) | Q14, Q15 |
| [axi_outstanding_read_seq.sv](../sequences/axi_outstanding_read_seq.sv) | Q6 |

---

*本文档由对话记录整理生成，持续更新。*
