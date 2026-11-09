# 从零理解这个 AXI Crossbar：设计、UVM 验证、覆盖率与调试

> 适用对象：第一次系统学习数字 IC 验证、希望能独立解释本项目的人。本文以仓库**当前代码**为准，按“我接到需求后会如何设计、如何证明它工作”的工程顺序写。RTL 原有部分和后续修复、验证环境的来历不等于读者本人独立原创；面试时应说清自己理解、修改和实测了什么，不要把没有做过的工作说成亲手完成。

读完本文，你应该能回答四个问题：**请求怎样找到从机？返回怎样找到主机？验证环境凭什么判定对错？100% 覆盖率究竟覆盖了什么？** 若只记住组件名字而说不清这四条因果链，面试官追问几轮就会暴露空白。

本文只要求你打开仓库代码，不依赖其他说明文档。所有路径均相对仓库根目录。建议阅读时先看第 1～4 节建立图像，再把第 5～10 节与代码并排看，最后按第 13 节自行复述。

## 1. 先在脑中画出整台机器

Crossbar 是 4 个上游 Master 与 4 个下游 Slave 之间的互连。它**不是存储器**：不决定读出的业务数据是什么，主要负责地址译码、请求仲裁、数据/响应转发和 ID 路由。验证环境中的 Slave driver 才扮演简化的存储设备。

```text
TB 上游 Master Agent         DUT                         TB 下游 Slave Agent
mst_if[0..3] ───────► slv0..3 │ slv_if → 4×4 switch → mst_if │ mst0..3 ───────► slv_if[0..3]
            AW/W/AR 请求 ────►│                              │────► 请求
            ◄──── B/R 响应 ───│                              │◄──── 响应
```

命名来自**DUT 自己的视角**：DUT 的 `slv0` 是接受请求的 *Slave port*，接外部 Master；DUT 的 `mst0` 是发请求的 *Master port*，接外部 Slave。TB 则按外部设备身份命名 `mst_if`、`slv_if`。这不是两套方向相反的设计，而是观察视角不同。连接实物见 [`verification/top/dut_connect.svh`](../verification/top/dut_connect.svh)；顶层、时钟和复位见 [`verification/top/harness.sv`](../verification/top/harness.sv)。

**本配置的设计合同**如下；这些值是“本次验证对象”，不是整个参数化 RTL 已被证明支持的全部组合。

| 项目 | 当前值 | 它带来的可检查结果 |
|---|---:|---|
| 上/下游端口 | 4 / 4 | 理论上 16 个 M→S 路由格 |
| 地址、ID、数据宽度 | 16、8、32 bit | 地址范围 64 KiB；每拍总线 4 字节；ID 物理宽度 8 bit |
| 时钟/复位 | 10 ns 周期；低有效 `aresetn`，高有效 `srst` | TB 在 100 ns 释放复位；当前所有端口同一时钟域 |
| 地址映射 | S0=`0x0000–0x0FFF`，S1=`0x1000–0x1FFF`，S2=`0x2000–0x2FFF`，S3=`0x3000–0x3FFF` | 高 4 位为 0～3 时选目标；例如 `0x1234` 进入 S1 |
| 本地地址 | `SLVx_KEEP_BASE_ADDR=0` | S1 收到 `0x1234-0x1000=0x0234`；S2/S3 同理 |
| 访问许可 | 四个 `MSTx_ROUTES=4'b1111` | 每个 Master 都允许访问每个 Slave |
| ID 前缀 | M0=`0x10`，M1=`0x20`，M2=`0x30`，M3=`0x40` | 返回 B/R 依据前缀回到源 Master；当前测试主要使用前缀加低位 0～3 |
| 其他 | `MST_PIPELINE=SLV_PIPELINE=0`、CDC=0、USER=0、优先级均为 0、`OSTDREQ_NUM=4` | 未验证额外流水/CDC/USER/优先级配置；`OSTDREQ_NUM` 不能替代多 outstanding 测试 |

配置实物见 [`verification/top/dut_connect.svh`](../verification/top/dut_connect.svh) 和 [`src/axicb_crossbar_top.sv`](../src/axicb_crossbar_top.sv)。`0x4000` 等未映射地址应该得到 `DECERR`，不应真的进入任何下游口。当前 `axi_txn` 的随机约束只产生 4 字节对齐、`INCR` 突发，`size=0..2`、`len=0..15`；因此不能因为 RTL 有更多字段就宣称 WRAP、非对齐或所有 256 个 ID 都签核了。见 [`verification/common/axi_txn.sv`](../verification/common/axi_txn.sv)。

### 我会怎样写需求与验收标准

设计前先把自然语言改写为可判定的句子，而不是直接写 `case`：

1. 对任一合法 M、地址窗口 S，AW/AR 最终只到 S，且下游地址为本地地址。**验收**：两侧 monitor 配对；16 格逐格核验。
2. 两个 Master 同时请求同一个 Slave 时，必须仲裁，不能把两者的 AW/AR/W 混成一笔。**验收**：竞争场景 + 数据/ID 比较；公平性另做定量检查。
3. 一个写请求的每个 W beat 必须沿该 AW 选择的路走，`WLAST` 才释放路由记录。**验收**：多拍写、背压、逐拍 WDATA/WSTRB 比较。
4. B 和 R 必须送回原 Master，ID 和响应码不得变。**验收**：跨 Master 并发、错误响应、BID/RID 比较。
5. 未映射访问返回 `DECERR`，下游不得出现对应请求。**验收**：`0x4000` 的读写以及无额外下游事务。
6. `VALID` 被 `READY=0` 阻塞时数据保持；`LAST` 只随有效数据出现，最后一拍在背压期间不能提前撤掉。**验收**：接口断言、背压用例、波形排错。

这里故意把“结果”和“检查手段”同时写下：没有观察点与判定规则的测试点只是愿望。

## 2. AXI 基础：五条通道与一次握手

AXI 把一次写拆成 AW（写地址）、W（写数据）、B（写响应），一次读拆成 AR（读地址）、R（读数据）。每条通道各有 `VALID`/`READY`：**只有某个时钟采样沿两者同为 1，才算这一拍传输成功**。`VALID=1, READY=0` 是“我有东西但你还没收”，不允许把这拍当完成；发送者必须保持有效性和相关 payload 稳定。注意当前接口断言只检查部分 `VALID`/`LAST` 关系，尚未完整检查 payload 稳定性，见 [`verification/if/axi_if.sv`](../verification/if/axi_if.sv)。

举一个四拍写：`AWLEN=3` 代表 `3+1=4` 个 W beat。AW 描述地址/ID/长度/size；W 有 `WDATA/WSTRB/WLAST`，最后一拍 `WLAST=1`；从机收到后返回一次 `BID/BRESP`。读请求 `ARLEN=3` 则应返回 4 个 R beat，最后一拍 `RLAST=1`。`AxSIZE=2` 代表每拍 4 字节；`AxBURST=INCR` 意味着按传输步长递增。`WSTRB=4'b0101` 表示 4 字节中只有第 0、2 个字节有效，但**当前简化 Slave 内存模型未按 WSTRB 逐字节写入**，不能拿写后读来证明部分写语义正确。

面试里要能区分三个“完成”：AW 握手只表示地址被接受，W 的最后一拍握手只表示写数据送完，B 握手才表示写事务最终响应完成。读的 AR 握手与 RLAST 握手也不是同一件事。仲裁和 FIFO 的入/出队时机正是围绕这些边界安排的。

### 为什么 AW 与 W 不能只看同一个周期？

它们是独立通道，AW 可以先被接受，W 稍后到；背压也可能让它们在不同周期推进。因此“当前 W 属于哪个目标”的信息必须**记下来**，不能随意用此时线上的 `AWADDR` 重新译码。类似地，收到一个 B/R 时也不能用“最近刚发出的地址”猜原 Master；需要 ID 和未完成事务的上下文。

## 3. 从零画 RTL 结构：谁负责哪一半

我会把设计拆成三层，而不是把 16 条路径写成一个巨型 `case`：

```text
每个上游口：地址译码 + 记录 W 目标 + 汇集 B/R
                    ↓ 4×4 连接矩阵（仅换线/转置索引）
每个下游口：多源 AW/AR 仲裁 + 记录 W 来源 + 按 ID 分发 B/R
```

顶层 [`src/axicb_crossbar_top.sv`](../src/axicb_crossbar_top.sv) 负责端口和参数，四个 [`src/axicb_slv_if.sv`](../src/axicb_slv_if.sv) 把外部 AXI 物理引脚打包为内部通道并处理可选缓冲；[`src/axicb_switch_top.sv`](../src/axicb_switch_top.sv) 实例化上游 `axicb_slv_switch`、连接矩阵、下游 `axicb_mst_switch`；四个 [`src/axicb_mst_if.sv`](../src/axicb_mst_if.sv) 再解包至下游引脚，并在 `KEEP_BASE_ADDR=0` 时减去窗口基地址。矩阵索引近似是 `out[slave,master] = in[master,slave]`，不是数据处理器。**本次只在 4×4 参数组合上做了实测**，不要把它直接外推到任意 N×M。

内部为省布线把 payload 打包，例如本配置 AW/AR 53 bit、W 36 bit、B 10 bit、R 42 bit；在 `AXI_SIGNALING=1, USER_SUPPORT=0` 下，AW/AR 含地址、ID、LEN、SIZE、BURST 等，W 含 DATA/STRB，B 含 ID/RESP，R 含 DATA/ID/RESP。`VALID/READY/LAST` 在适当位置另外传递。打包只改变表示方式，不改变通道的握手含义。

### 3.1 写地址：译码、许可与仲裁

上游 [`src/axicb_slv_switch_wr.sv`](../src/axicb_slv_switch_wr.sv) 根据 `AWADDR` 是否落在某个 4 KiB 窗口、以及 `MSTx_ROUTES` 是否许可，生成目标 one-hot 候选。若内部 W/B 跟踪 FIFO 满，就不能继续接受一个将来无处记录的 AW；因此 `AWVALID` 转发与 `AWREADY` 都受资源条件制约。未命中窗口不会转给下游，而是走错误响应路径。

每个下游 [`src/axicb_mst_switch_wr.sv`](../src/axicb_mst_switch_wr.sv) 面对至多四个上游 AW 候选，采用 round-robin 仲裁。同优先级配置下，持续请求、且每次 grant 真正被接受时，仲裁指针会轮换；具体轮转实现见 [`src/axicb_round_robin_core.sv`](../src/axicb_round_robin_core.sv)。**有 round-robin RTL 不等于当前测试已经严格测出公平性界限**：需要四路持续施压、记录每路等待周期与 grant 次数，才可作有界等待结论。当前 `AxQOS` 并未被验证成动态优先级策略。

### 3.2 写数据：两端都要保存“这笔 AW 选了谁”

当上游 AW 真正握手，上游写开关把目标、ID、是否译码失败写入 `wch_gnt_fifo`。后续 W beat 根据 FIFO 队头转发；当 `WVALID && WREADY && WLAST`，这笔写的 W 路由记录才出队。下游写开关也在 AW 握手时记录**来源 Master**，这样多个 Master 竞争同一 Slave 后，下游能把每组 W beat 接到正确来源。FIFO 的“入队条件”和“出队条件”要写成握手表达式，不能写成只看 `VALID`，否则背压时会重复入/出队。

未映射写是一个很好的设计推导题：既不能向任何真实 Slave 发 AW/W，又不能让上游永远等着；所以上游要接收并丢弃对应 W，最后产生 `DECERR` B 响应。[`src/axicb_slv_switch_wr.sv`](../src/axicb_slv_switch_wr.sv) 正在做这件事。写响应的完成跟踪由 [`src/axicb_slv_ooo.sv`](../src/axicb_slv_ooo.sv) 协助；在本写路径中，完成记录与 WLAST 接受有关，不能简单说“每个 AW 都立刻压入同一个 B 队列”。

### 3.3 B 返回：为什么必须做完整 ID 前缀比较

下游 B 可能来自任何已接受的写，`BID` 要指向源 Master。当前约定 M0/1/2/3 的高位前缀分别是 `0x10/0x20/0x30/0x40`。原实现使用“这个 ID 包含我的 mask 位”式比较：`(ID & 0x10)==0x10`。当 `ID=0x30`，它同时满足 `0x10`、`0x20`、`0x30`，B/R 可能被错误扇出，READY 也可能从错误端口选取。修复后 [`src/axicb_mst_switch_wr.sv`](../src/axicb_mst_switch_wr.sv) 用四个前缀的并集作统一路由掩码，再与**某一个完整前缀**比较；读返回在 [`src/axicb_mst_switch_rd.sv`](../src/axicb_mst_switch_rd.sv) 同样处理。本修复依赖当前四个前缀互异且不与低位索引冲突，换 ID 编码必须重新审视。

### 3.4 读路径：AR 仲裁、R 拍计数与 RLAST

AR 与 AW 类似先译码再到下游仲裁，见 [`src/axicb_slv_switch_rd.sv`](../src/axicb_slv_switch_rd.sv)、[`src/axicb_mst_switch_rd.sv`](../src/axicb_mst_switch_rd.sv)。但读数据由下游主动返回，每个 R beat 带 `RID/RRESP/RDATA`，最后一拍带 `RLAST`。上游开关要跟踪 ID、目标、预期长度，并按有效握手计数，不是每过一拍时钟就把剩余长度减一。`axicb_slv_ooo` 为每个允许的低位 ID 槽保存关联信息；当前 `MST_OSTDREQ_NUM=4`，测试使用 `0x10..0x13` 等分组，而不是任意 8-bit ID 都能无条件映射到 4 槽。

`RLAST` 特别容易出错：如果最后一拍 `RVALID=1,RREADY=0`，这拍**没有被消费**，发送端仍须维持 RLAST；若 FIFO 已空、旧寄存值还留着，则 `RVALID=0,RLAST=1` 又是无效尾标记。当前代码分别在 [`src/axicb_slv_switch_rd.sv`](../src/axicb_slv_switch_rd.sv) 和 [`src/axicb_slv_if.sv`](../src/axicb_slv_if.sv) 处理有效性/空状态。这个问题在真实波形中出现过，后文第 11 节讲如何定位。

### 3.5 复位、FIFO、流水与“支持”一词的边界

复位要把有效位、FIFO 读写位置和未完成事务的路由上下文清掉；否则复位后旧 B/R 会错投。[`src/axicb_scfifo.sv`](../src/axicb_scfifo.sv) 是同步 FIFO，相关模块也有 pipeline/CDC 分支。但本次 testbench 关闭 `MST_PIPELINE/SLV_PIPELINE/CDC`，且 reset 测试没有证明**在多笔未完成请求中途复位**的全部行为。所以面试应说“RTL 有这些参数分支；当前证据只支持共同步、无额外流水配置”。

### 3.6 把 RTL 的关键条件翻译成人话

阅读 RTL 时不要先逐行记语法，先问“这行保证哪条不变量”。从 [`src/axicb_slv_switch_wr.sv`](../src/axicb_slv_switch_wr.sv) 可以抽出如下骨架（为阅读省略了其余三个目标分支）：

```systemverilog
// 地址落在 S0 窗口且 route bit 许可，才可能把 AW 送往 S0
assign o_awvalid[0] = slv_aw_targeted[0] ?
                      i_awvalid & !bch_full & !wch_full : 1'b0;
// wch_gnt_fifo 的端口连接：AW 握手时入队；W 最后一拍握手时出队
.push (i_awvalid & i_awready),
.pull (i_wvalid & i_wready & i_wlast)
```

第一行的两个 `!full` 是“我能承诺接下来接住 W、并管理 B”才接 AW；若把它们去掉，后续 W/B 路由状态可能溢出。第二行只在 AW 握手时入队；AWVALID 连续高但 AWREADY 低时绝不可重复入队。第三行只在最后一拍握手时出队；若 `WLAST=1` 但 `WREADY=0`，本笔数据还悬着，目标必须继续保持。

下游的对应 FIFO 在 [`src/axicb_mst_switch_wr.sv`](../src/axicb_mst_switch_wr.sv) 里 `data_in=awch_grant`，保存“本次仲裁选的是哪个来源”。同一笔事务因此有两份互补的上下文：**上游记目标，下游记来源**。这是从 4×4 网络推导出的状态，不是重复存储。返回 B 不再查 AW 当前地址，而是看 `BID` 前缀；这也解释为什么请求路径正确并不保证返回路径正确。

读路径同样可以翻成一张条件表；关键在于“哪一个握手推进哪一份状态”：

| 事件 | 状态必须怎样变化 | 背压时怎样保持 |
|---|---|---|
| `ARVALID && ARREADY` | 保存 ID、目标、预期 `ARLEN`，准备未来 R 回送 | `ARREADY=0` 时不创建完成记录 |
| 中间 R beat `RVALID && RREADY && !RLAST` | 当前读的拍计数前进一步 | `RREADY=0` 时数据、ID、LAST 与计数都不前进 |
| 最后 R beat `RVALID && RREADY && RLAST` | 该读完成，释放对应上下文 | `RLAST=1,RREADY=0` 时不能提前释放 |
| FIFO 空 | 不得声称有有效 R/LAST | 旧寄存数据即使仍为 1 也不可泄漏到有效输出 |

这也是在白板上推设计的办法：先列事件、状态、不变量，再写组合选择和时序更新。实际代码中读错误路径的 `rlen` 只在 `i_rvalid && i_rready` 递增，`i_rlast` 根据 `rlen==rch_len` 且有效时产生；正常路径则由被选下游的 RLAST 与 RVALID 共同形成。见 [`src/axicb_slv_switch_rd.sv`](../src/axicb_slv_switch_rd.sv)。

## 4. 亲自推演一笔事务：M2 → S1

假设外部 M2 发 4 拍 `INCR` 写，`AWID=0x30`、`AWADDR=0x1234`、`AWLEN=3`、`AWSIZE=2`，数据依次 `D0..D3`、最后一拍 `WLAST=1`。这里的地址与 ID 是讲原理的实例，并非声称某测试恰用这组值。

1. `AWADDR[15:12]=1` 命中 S1；M2 的路由许可位为 1。上游写开关待资源可用时提交 S1 候选。
2. S1 的下游写仲裁器若还有其他 M 竞争，选中一个；M2 的 AW 在两侧对应握手后，源/目标关系进入两侧跟踪 FIFO。下游引脚输出本地地址 `0x0234`、同一 ID `0x30`。
3. 四个 W beat 按 FIFO 队头从 M2 走到 S1。即便某拍 `WREADY=0`，该拍不能算已转发。最后一拍 `WVALID && WREADY && WLAST` 后释放 W 路由记录。
4. S1 返回 `BID=0x30`、`BRESP=OKAY`。下游开关完整匹配前缀 `0x30`，仅 M2 能收到 B；M2 `BREADY` 接受后写结束。
5. 若随后 M2 对 `0x1234` 发 AR，S1 看见 `0x0234`，四个 R beat 返回 M2，最后一拍携 `RLAST`。Crossbar 只负责无损转发，不应凭空改变内存数据。

你可以用此例自测：若把地址换成 `0x4000`，第 1 步该如何变？答：无目标 Slave，写仍需吃掉 W 并回 `DECERR`；读回错误 R，且下游 monitor 不应看到对应请求。若把 ID 换成 `0x31`，它仍属 M2 当前前缀，但低位 1 对应另一槽；若换成 `0x20` 从 M2 发，现有验证的 ID 契约已被破坏，不能指望“自动识别真实发起者”。

## 5. 从零搭 UVM：每个部件解决什么问题

设计端是 module、信号和时钟；验证端希望写“给 M2 一笔读 `0x1234`”这种更高层的动作。UVM 的核心就是在**事务级意图**与**引脚级时序**之间建立可复用的层次，同时从引脚独立观察结果。

```text
test → sequence → sequencer → master driver → virtual interface → DUT
                                                   │
                 master/slave monitor ◄─────────────┘
                            │ analysis port（广播已观测事务）
                            ├────────► scoreboard ──核验成功──► verified-route coverage
                            └────────► intent coverage
```

[`verification/top/harness.sv`](../verification/top/harness.sv) 是普通 SV module：产生 100 MHz 时钟、复位，实例化 8 个 `axi_if` 和 DUT，调用 `run_test()`。接口实例无法直接“装进”class，故以 `virtual axi_if` 句柄通过 `uvm_config_db` 传给 8 个 agent；driver 用它驱动，monitor 用它采样。这个桥接是理解 UVM 的第一关：`virtual interface` 不是另一个硬件接口，它只是 class 访问已有 interface 实例的句柄。若 `get` 失败，agent/driver/monitor 会 fatal，避免静默运行空测试。

### 5.1 `axi_txn`、item 与 transaction 是什么关系？

[`verification/common/axi_txn.sv`](../verification/common/axi_txn.sv) 的 `axi_txn extends uvm_sequence_item`。这里的一个 `axi_txn` 对象**通常表示一笔完整的读或写事务**：请求字段有 `kind/addr/id/len/size/burst/wdata[]/wstrb[]`，响应字段有 `bid/bresp/rid/rresp/rdata[]`，再附来源与时间戳。`sequence_item` 是 UVM 的基类/传递单位，*transaction* 是“在某个抽象层次上描述的一次操作”这个概念；因此“本项目的 item 是一个事务表示”是对的，但“任何 item 都必然等于一个完整 AXI transaction”不对。其他项目可以一个 item 只表示一拍 W，或者一个 item 包含一组更大的场景。

`axi_txn` 是类，`txn` 是对象句柄，`axi_txn::type_id::create("req")` 才创建对象。`rand` 字段可供 `randomize()` 求解；`constraint c_basic` 把 burst 固定为 INCR、地址四字节对齐、length 0～15、size 0～2；还有边界地址/长度/ID 约束，所以所谓 random 测试的值域**比 AXI 全域窄得多**。`uvm_object_utils` 将 item 注册到 factory，便于类型覆盖和自动化字段操作；但自动 `compare` 不能取代按设计合同编写的 scoreboard，因为本项目两侧地址本来就不同。

[`verification/tc/axi_wr_seq.sv`](../verification/tc/axi_wr_seq.sv) 等 sequence 负责“产生什么”，例如配置地址、ID、写数据后 `start_item(req)`、`finish_item(req)`；sequencer 负责在同一个 agent 内仲裁多个 sequence 向 driver 交付 item；driver 负责“怎样按协议驱动”。典型传递链是：

```systemverilog
// 与 axi_wr_seq 的关键顺序一致；省略了数组初始化等字段
req = axi_txn::type_id::create("req");
// 填写 req.kind/addr/id/len/wdata/...
start_item(req);       // 取得 sequencer 的发放资格
finish_item(req);      // 将 item 提交给 driver

seq_item_port.get_next_item(txn);  // driver 接收
// drive_wr(txn) 或 drive_rd(txn)
seq_item_port.item_done();         // 通知 sequencer 此 item 已处理完
```

这里的示意特意不把 `start_item` 等同于“DUT 已接到 AW”，也不把 `item_done` 等同于硬件普遍意义上的事务完成。**在当前 driver 的具体实现里**，`drive_wr` 会等 AW、所有 W、B，`drive_rd` 会等 AR、所有 R，才调用 `item_done`，所以这个 driver 对同一个 Master 端口是串行的。AXI 协议本身允许更丰富的并行和 outstanding，只是这个 BFM 尚未实现。

### 5.2 Agent、env、test 各自负责什么？

[`verification/agent/mst/axi_mst_agent.sv`](../verification/agent/mst/axi_mst_agent.sv) 是主动 agent：包含 sequencer、[`axi_mst_drv`](../verification/agent/mst/axi_mst_drv.sv)、monitor，`connect_phase` 把 `driver.seq_item_port` 接到 `sequencer.seq_item_export`。这就是 driver 为什么可以调用 `get_next_item()`。[`verification/agent/slv/axi_slv_agent.sv`](../verification/agent/slv/axi_slv_agent.sv) 是“主动响应型”：有 driver 和 monitor，没有 sequencer；它不从 test 取主动请求，而是看 DUT 下游 AW/W/AR 后扮演从机。Slave 配置对象 [`axi_slv_cfg`](../verification/common/axi_slv_cfg.sv) 调整错误注入、响应延迟和部分 ready 背压。它不是完整 AXI 内存 VIP，尤其当前写入内存**忽略 WSTRB 的逐字节语义**。

[`verification/env/axi_env.sv`](../verification/env/axi_env.sv) 在 `build_phase` 创建 4+4 个 agent、一个 scoreboard、一个 coverage collector；在 `connect_phase` 接好 analysis 端口。[`verification/tc/axi_base_test.sv`](../verification/tc/axi_base_test.sv) 创建 env；具体 test 只定义场景，比如全路由、错误注入、背压。`type_id::create` 的好处是后续可以用 factory override 换 driver/sequence 而不改组件树，但**本项目当前结果不依赖一个已配置的 override**。UVM 的 phase 顺序可用“建树 `build` → 连线 `connect` → 带时钟的 `run` → 停止后 `check` → 报告 `report`”理解。Test 在 `run_phase` 里 `raise_objection` 让仿真继续，序列结束并留等待窗口后 `drop_objection`；若忘记 raise，可能还没发激励就进入后处理，若忘记 drop，只能靠超时结束。

### 5.3 Monitor 为什么不能把 driver 的 item 直接给 scoreboard？

Driver 手里的 `req` 只代表**想发什么**，并不证明 DUT 真接到、更不证明到达正确 Slave。[`verification/common/axi_monitor.sv`](../verification/common/axi_monitor.sv) 被动监听实际 `VALID && READY`，写线程收集 AW、`LEN+1` 个 W beat、B，读线程收集 AR、`LEN+1` 个 R beat；完整事务组装好才 `ap.write(txn)`。主侧与从侧各有 monitor，`source_id` 指明是哪一个物理口。`uvm_analysis_port` 是广播：同一个主侧事务可同时送 scoreboard 和 coverage；不是 driver 那种需要 `item_done` 的请求/响应握手。

当前 monitor 的代价也要说清：每个方向基本按“等待一笔地址→收齐该笔数据/响应→下一笔”组织，不能可靠重建**同一端口上多个 ID 并发、乱序返回**；读只留最后采样的 `RID/RRESP`，未逐拍检查每个 R beat 的 ID/RESP/LAST。若某笔请求永远没有完成响应，monitor 不会 `ap.write`，当前 scoreboard 在 `check_phase` 看不到这笔“正在卡住”的请求，主要靠仿真超时暴露。因此它是当前激励模式下可用的 monitor，不是完整 AXI 协议检查器。

## 6. 记分板如何不依赖 DUT 自说自话地判错

[`verification/env/axi_scoreboard.sv`](../verification/env/axi_scoreboard.sv) 有两个入口：主侧 monitor 的 `mst_imp` 与从侧 monitor 的 `slv_imp`。每次 `write_master/write_slave` 把完成事务放进队列；`check_phase` 用合同做配对与比较。若把主侧 data 直接当 expected，再和自己比较，永远不会发现转发错；所以必须和**下游独立观测到的** transaction 比。

配对键是 `kind + ID + 目标 Slave + 本地地址 + LEN + SIZE`。主侧地址高四位确定期望 Slave，低 12 位是本地地址；从侧 `source_id` 必须等于期望 S。例如 M2 写 `0x1234`，主侧看到 `0x1234`，S1 下游看到 `0x0234`。若要求二者地址字面相等，会误判全部 S1～S3。**数据绝不能放进匹配键**：假设转发把 `D2` 改坏了，若用 WDATA 找匹配，则会报告“找不到事务”，反而隐藏真正的数据破坏位置。找到对应从侧事务后再比较每个 WDATA/WSTRB 或 RDATA beat、BID/RID、响应。未匹配主侧、额外从侧都报 `uvm_error`。只有全部通过，`checked_ap.write(m)` 才把它发布为“已核验路由”。

未映射访问有不同判定：主侧必须收到 `DECERR`；并且对应的从侧若意外出现，会作为 unmatched slave 被报错。这里无需硬凑一个不存在的目标 Slave。Scoreboard 还检查 `m.id[7:4] == m.source_id+1`，这是**当前测试配置的 ID 编码合同**，不是 AXI 协议普适规则。

这个 scoreboard 不是万能的独立参考模型：

- 它把下游 Slave 返回的读数据当作互连应无损转发的参考，能抓 crossbar 数据破坏；若 Slave BFM 自己内存语义错，可能两侧一致却仍然错。
- 它在 `check_phase` 统一配对完成事务，不检查逐周期延迟上界、同 ID 次序、所有 beat 的 RLAST/RRESP，也不能覆盖当前 monitor 未发出的半途事务。
- 当前匹配模式适合被串行化的同端口交易；重复同键并发或真正乱序时需要按 ID/序号建立 in-flight 表，而不是只靠首次未用的队列元素。

面试官若问“为什么需要同时接主从两侧 monitor”，答法是：主侧说明**用户看到了什么**，从侧说明**实际路由去了哪里**；两者配对才能区分“发送意图”、路由错误和数据错误。

## 7. 从需求到测试点：不是把 16 个 test 名字排一行

我会先画四个维度：**空间**（4×4、窗口边界、未映射）、**操作**（读/写、长度、size、响应）、**时序**（竞争、背压、响应回送、复位）、**异常**（SLVERR/DECERR、超时）。然后每个测试点写“激励—观察—检查—覆盖”，防止只有刺激没有判定。

| 需求/风险 | 如何刺激 | 主要观察与判定 | 当前实现位置 |
|---|---|---|---|
| 16 条 M→S 路由 | 对每个 `(m,s)` 先写后读，ID=`(m+1)<<4`、地址=`(s<<12)|(m<<2)` | 主/从完成事务配对；本地地址、ID、每拍数据正确；已核验路由 16 格 | [`axi_full_routing_test`](../verification/tc/axi_full_routing_test.sv)、[`axi_full_routing_seq`](../verification/tc/axi_full_routing_seq.sv)、scoreboard |
| 长度/size | `LEN=0,3,7,15` 等与 `SIZE=0,1,2` | W/R beat 数与数据，`kind×len`、`kind×size` | [`axi_burst_size_test`](../verification/tc/axi_burst_size_test.sv) 等 |
| 多 Master 争用 | 多个 agent 对同一个下游 S 发请求 | 不混 ID/数据、最终能完成 | [`axi_same_slave_test`](../verification/tc/axi_same_slave_test.sv)、[`axi_multi_master_test`](../verification/tc/axi_multi_master_test.sv) |
| 背压 | Slave 配置 AW/W/AR READY 延迟 | 未被接受的请求不算握手；能继续完成 | [`axi_backpressure_test`](../verification/tc/axi_backpressure_test.sv)、Slave driver |
| 异常 | S0 配置 SLVERR；访问 `0x4000` | 读/写响应码正确；无意外下游事务；恢复后 OKAY | [`axi_error_test`](../verification/tc/axi_error_test.sv) |
| 边界 | 窗口起止、相邻窗口 | 路由目标与本地地址正确 | [`axi_boundary_test`](../verification/tc/axi_boundary_test.sv) |
| 复位/并发/性能探索 | 相应 test 发场景 | 当前可发现部分卡死、串路；未达到完整签核 | [`verification/tc/`](../verification/tc/) 中 reset、interleave、outstanding、random、perf 系列 |

回归脚本 [`verification/sim/regress.sh`](../verification/sim/regress.sh) 实际运行 16 个 test：`basic`、`routing`、`protocol`、`burst_size`、`outstanding`、`multi_master`、`same_slave`、`interleave`、`boundary`、`backpressure`、`error`、`random`、`random_concurrent`、`perf`、`reset`、`full_routing`。名称只是场景意图，不能据 `axi_outstanding_test` 就说同一 Master 多 outstanding 已被测：当前 driver 会等待整笔响应后才接下一 item，现用例验证的是**不同 Master 同时在途**。同理 `perf` 存在不代表已经有吞吐/延迟签核指标，`random` 存在不代表全合法空间被随机覆盖。

### 全路由 test 为什么只有 32 笔，却能核验 16 条路径？

[`axi_full_routing_test`](../verification/tc/axi_full_routing_test.sv) 两层循环遍历 M0～M3、S0～S3，每格发一写一读，故 `4×4×2=32` 笔。它是一格一格地顺序启动，不是 32 笔同时发。Scoreboard 的 `Routing: 32 pass` 表示 32 笔完成事务被核验；coverage 的 `16/16` 表示 16 个不同 M/S 配对都至少成功过一次。**数量不同，是因为一个格有读写两笔。** 若要证明“同一 Slave 四路持续竞争公平”，还需另一类长时间并发测试。

## 8. 覆盖率：到底收集了什么，为什么不能只看 100%

覆盖率不是正确性的同义词。一次事务若到了错误 Slave，`cp_master` 和 `cp_slave` 仍可能被“请求原本想去哪里”命中；只有检查通过才有资格声称某条路径真正被核验。当前 [`verification/env/axi_coverage.sv`](../verification/env/axi_coverage.sv) 故意分为两层：

1. `cg`：主侧 monitor 的**已完成事务**进入 `write(t)` 就采样。它描述本次跑到了哪些测试意图/观察到哪些响应，仍不能单独证明下游路由正确。`cp_master` 取 ID 高 nibble，`cp_slave` 取主侧地址高 nibble；并不是 DUT 内部通路探针。
2. `cg_verified_routes`：scoreboard 两侧配对且 ID、响应、数据检查全部通过，才通过 `checked_ap → checked_imp → write_checked(t)` 采样。它描述“已核验成功的 M/S 组合”。此外 `verified_route_hits[4][4]` 打印缺哪格。

`cg` 的 coverpoint 与 cross 可以逐个心算：

对读事务，当前 monitor 的 `txn.rresp` 保存的是最后采到的响应值，故下面的 `cp_resp` 代表**事务级最后响应**，不是“每个 R beat 的响应都已覆盖”。

| 项目 | bins | 为什么这样分 |
|---|---:|---|
| `cp_kind` | READ/WRITE：2 | 两种基本操作 |
| `cp_master` | M0～M3：4 | ID 高 nibble = 1/2/3/4 |
| `cp_slave` | S0～S3：4 | 地址高 nibble = 0/1/2/3；未映射地址不属于这四 bin |
| `cp_len` | single=`0`、short=`1..3`、medium=`4..7`、long=`8..15`：4 | 把 1～16 拍分成四档 |
| `cp_size` | 1、2、4 字节：3 | 对应 `AxSIZE=0/1/2` |
| `cp_resp` | OKAY/SLVERR/DECERR：3 | 写看 BRESP，读看 RRESP |
| `cx_routing` | `4×4=16` | 请求端 M/S 意图覆盖 |
| `cx_kind_len` | `2×4=8` | 读和写都要覆盖四类突发长度 |
| `cx_kind_size` | `2×3=6` | 读和写都要覆盖三种 size |
| `cx_kind_slave` | `2×4=8` | 每个 Slave 都要读过、写过 |
| `cx_kind_resp` | `2×3=6` | 两种操作都见到三种响应 |
| `cx_verified_routing` | `4×4=16` | **检查通过**的实际 M/S 路由 |

一个最容易理解的例子：`cp_kind=READ` 命中、`cp_len=short` 也命中，不代表 `READ×short` 命中；两者可能分别来自“单拍读”和“四拍写”。交叉 bin 必须在**同一次采样**同时成立。此前第一次有效覆盖合并就发现 `READ×short` 和 `READ×medium` 两个漏项；[`axi_burst_size_test`](../verification/tc/axi_burst_size_test.sv) 增加 `LEN=3` 与 `LEN=7` 的读 burst，配同地址写入数据后，这两格才闭环。这是“覆盖率驱动补测试”的具体例子，而不是为了好看去改目标值。

### 一次 coverage sample 怎样发生？

拿全路由里 M2→S1 的读为例：主侧 M2 monitor 在 AR 与全部 R 握手后 `ap.write(txn)`；env 把这个 port 连接到 `cov.analysis_export`，coverage 的 `write` 存句柄并 `cg.sample()`，于是 `READ`、M2、S1、对应 length/size/response 以及交叉 bin 被计数。与此同时两侧 monitor 分别把完成事务送 scoreboard；它在 `check_phase` 匹配 S1 的本地地址与读数据，确认后 `checked_ap.write(m)`，coverage 的 `write_checked` 才给 `(M2,S1)` 已核验格 +1。**采样时机不同、证据强度不同。**

### URG 的 100% 与代码覆盖率 67.43% 为什么不矛盾？

在本次 `SEED=1` 的 16-test 合并结果中，两个定义好的功能 covergroup 都是 100%，`cx_routing=16/16`、`cx_verified_routing=16/16`、`cx_kind_len=8/8`、`cx_kind_size=6/6`、`cx_kind_slave=8/8`、`cx_kind_resp=6/6`。与此同时 URG 总分 67.43%，LINE 66.28%、COND 66.87%、TOGGLE 31.64%、BRANCH 72.36%；报告还包括 harness、UVM/Verdi 辅助模块，**不是纯 DUT 代码覆盖率**。本地重新运行 `make -C verification/sim cov` 后，可查看 `verification/sim/build/coverage_report/dashboard.txt` 与 `grpinfo.txt`；这些生成物不提交到仓库。功能覆盖率 100 只说明**当前定义的 bins** 被命中，不能证明未定义的协议角落、其他参数组合、任意时序、所有 data 值都正确，更不能说项目“整体覆盖率 100%”。

当前 `cg_verified_routes` 只在 mapped 4×4 范围内采样，并且把读写合并为同一个 `(M,S)` bin。因此“一格命中”不自动表示读和写都通过；本次全路由 test 的确每格读写各做一笔，是从 test 和 scoreboard 的 32/32 结果补强这一结论。若以后单靠 covergroup 做 sign-off，应把 `kind×master×slave` 也加到**已核验**侧。

## 9. 一次真实调试：从“不对劲”走到可复现证据

这段不是虚构“我一眼看出 bug”的故事，而是根据本仓库本次 VCS/波形/覆盖报告可复现的现象整理出的工程方法。旧记录曾写 `cx_routing=13/16`，数学上代表**缺三格**，不能据此推断“恰好两条物理通路坏”。后续确实发现了另两个功能交叉空 bin，但它们是 `READ×short`、`READ×medium`，不是 M/S 物理路径；要把两件事分开讲。

### 9.1 先排除 testbench 自身的假象

原全路由用例并未遍历 16 格，还误以为 M3 只能到 S3；实际 `MST3_ROUTES=4'b1111`。若 stimulus 没发 M3→S0，再好的 RTL 也不可能让覆盖 bin 命中。早期随机并发让多个 Master 使用相同的 `0x20` 前缀，与本项目的路由合同冲突；outstanding 用例在 fork 中复用 sequence 句柄，可能造成并发问题。这类问题先查配置、序列、ID，而不能一看到 coverage 红色就改 RTL。修正后全路由逐格发 32 笔，随机并发给各 Master 独立的 `0x10/20/30/40` 前缀和 sequence 对象。

### 9.2 再查设计里“请求能去、响应回不来”的非对称故障

AW/AR 路由按地址选目标，而 B/R 返回按 ID 选源，故一条路径“请求端有波形、主端等不到响应”时，优先看 B/R 解复用。对 `ID=0x30` 手算原条件：

```text
(0x30 & 0x10) == 0x10  → 真
(0x30 & 0x20) == 0x20  → 真
(0x30 & 0x30) == 0x30  → 真
```

三个输出同时认为自己该收这笔响应，这就是具体反例。把条件改成在统一前缀掩码下**完整相等**，并检查读、写两个返回通道。修复位置是 [`src/axicb_mst_switch_wr.sv`](../src/axicb_mst_switch_wr.sv) 和 [`src/axicb_mst_switch_rd.sv`](../src/axicb_mst_switch_rd.sv)。验证不是“重新编译成功”就结束，而是再看 16 格已核验和 32 笔数据比较结果。

### 9.3 波形定位 RLAST 的边界条件

另一个故障是 `RLAST=1` 却 `RVALID=0`。本次生成 FSDB，并用 Verdi 套件的 `fsdb2vcd` 读过修复前 940～990 ns 窗口：`mst_if[0].rvalid` 在 955 ns 下降，但 `rlast` 仍保持 1；这和接口 SVA 报错一致。分析链：FIFO 的数据被消费后 `empty=1`，旧寄存器 `rlast_r` 仍保存上笔的 1；若出口不看 empty，就会把旧 LAST 暴露在无效周期。[`src/axicb_slv_if.sv`](../src/axicb_slv_if.sv) 出口加 `!r_empty` 门控；[`src/axicb_slv_switch_rd.sv`](../src/axicb_slv_switch_rd.sv) 也修正未命中 RLAST 不能依赖 RREADY、正常输出随有效性门控。修后重跑没有 SVA 错误。本环境无交互式图形桌面，**没有声称在 Verdi GUI 中手工点查过波形**；`verdi -ssf` 是可用的本机复现命令。

### 9.4 修验证判定，再补覆盖空洞

旧 scoreboard 要求主从地址直接相等，而 DUT 当前会减窗口 base，这会造成“正确设计也匹配不上”。它还曾把数据纳入匹配键、对缺失事务只 warning。修成“先用不易被数据损坏影响的请求身份找对应，再逐 beat 比数据；缺失直接 error”，才有资格把 16/16 称作**核验通过**而非“发起过”。覆盖脚本也改为 VCS 支持的 `-cm line+cond+fsm+tgl+branch`，URG 合并设计库和每个 run 的 coverage DB；脚本让 SVA `$error` 令运行失败。第一轮有效合并后再补 `READ×short/medium`，最终得到本节末的结果。

这套 debug 顺序面试可概括为：**确认配置和激励 → 看握手定位请求/响应在哪一侧丢失 → 用具体 ID/地址/拍数构造反例 → 修设计或 checker → 定向复现 → 全回归 → 覆盖率查剩余空洞。**

## 10. 如何亲手运行、看日志、看波形

在仓库根目录执行；这次实测工具为 VCS T-2022.06、UVM 1.2，种子 1。`regression` 会先编译，再依次运行 16 个 test；`cov` 调用 URG 合并。

```bash
make -C verification/sim regression SIM=vcs COV=1 SEED=1 PLUS_ARGS=+UVM_TIMEOUT=100000
make -C verification/sim cov
```

第一次只想看一条路径，建议运行定向用例：

```bash
make -C verification/sim sim SIM=vcs COV=1 UVM_TEST=axi_full_routing_test SEED=1 PLUS_ARGS=+UVM_TIMEOUT=100000
```

如果此前已按相同 `COV` 选项编译，可用 `run` 省去编译。关键文件位置：[`verification/sim/Makefile`](../verification/sim/Makefile)、`verification/sim/build/runs/<test>_1/run.log`、`verification/sim/build/coverage_report/dashboard.html` 与 `grpinfo.txt`。本次全路由日志里有：

```text
Verified routing matrix: 16/16 (100.0%); missing:
Routing: 32 pass / 0 fail; data: 32 pass / 0 fail
UVM_ERROR :    0
UVM_FATAL :    0
```

本次总回归输出 `Regression passed (16/16 tests)`，且这 16 次运行日志未见 UVM error/fatal 或 `[SVA]` 错误。若自己重跑结果不同，先看**编译是否与 run 用同一 COV 设置、seed、test 名，是否为最新 RTL**；再看首个 `UVM_ERROR` 或超时位置，不要只截取最后一行“coverage 100%”。

要记录 FSDB：

```bash
make -C verification/sim sim SIM=vcs UVM_TEST=axi_basic_test SEED=1 PLUS_ARGS='+DUMP_FSDB +UVM_TIMEOUT=100000'
verdi -ssf verification/sim/build/runs/axi_basic_test_1/harness.fsdb
```

波形排查不要一上来展开全层次几千个信号。以“某笔 R 丢失”为例，先同屏放主侧 `ARVALID/ARREADY/ARADDR/ARID`、下游侧相应 AR，再放下游 `RVALID/RREADY/RID/RLAST` 与主侧同名信号；从第一个两侧分歧的时钟沿往内追 `target/grant/FIFO empty/full`。`VALID && READY` 是数拍边界，`LAST` 必须和对应有效拍一起看，单独看到 LAST 高不代表完成。报告中的百分比必须连同 bins 名称、错误计数和参数配置一起解读。

## 11. 如果我从零继续把它做成更扎实的项目

工程上，“已通过当前测试”与“完全符合 AXI”之间还有距离。下面这些不是给现有结果抹黑，而是你应主动提出的下一版验证计划；优先级来自**当前观察盲区**，不是凭空堆功能。

1. **先修检查盲区**：monitor 按每个握手单独采样，逐 beat 检查 `RID/RRESP/RLAST`、`WLAST` 与 `AxLEN+1` 的关系；接口 SVA 增加 `VALID && !READY |=> VALID && $stable(payload)`，并检查复位期间的合法状态。对“发出地址却永无完成”的请求建立 timeout/in-flight 记录，不只靠 test 的全局超时。
2. **再把真正 outstanding 跑起来**：Master driver 将 AW/AR 发射与 B/R 接收拆成并行线程，同一 Master 可在前一笔尚未结束时发下一笔；monitor/scoreboard 按 ID 和顺序约束管理未完成队列，测试同/不同 ID 的返回、跨 Slave 乱序与竞争。先定义允许的 ID 值域和每 ID 深度，避免 `id ^ mask` 索引越界。
3. **建立独立内存 oracle**：Slave BFM 按 WSTRB 更新 byte lane，reference model 单独计算写后读预期，覆盖窄写、混合 strobe、不同 size、读回。当前“主从两侧 RDATA 一致”只能证明 Crossbar 未改坏数据，不能证明存储语义。
4. **扩大协议和参数维度**：随机化约束要分为合法基础与专项测试，不要把边界地址约束永久叠在所有随机用例上；增加 `FIXED/WRAP`、非对齐/4 KiB 边界检查、B/R 背压、复位中断、流水开关、CDC、不同端口数与不同 ID 前缀配置。每加一个配置，先写可达性和非法组合判定，再做回归，不可仅改参数就宣称支持。
5. **定义真正的 sign-off 指标**：对每个需求给出被检查的功能交叉 bin、断言、错误注入和预期日志；代码覆盖率排除工具/不可达分支后分析未命中 RTL 行与条件，说明 waiver 理由；性能测试量化最大等待、平均/尾延迟、吞吐与饥饿上界。不同 seed 反复运行并保存复现信息。

若面试官问“你觉得现在最危险的盲点是什么”，我会选**同一 Master 多 outstanding/乱序**与**部分写 WSTRB 的独立数据检查**：前者涉及 AXI 最核心的并发语义，而当前驱动和 monitor 都把它串行化；后者会使写后读看起来有流量，但缺乏真实字节语义。这比笼统说“还可以加随机用例”更有工程判断。

## 12. 面试时怎样诚实、完整地讲成自己的理解

下面是一个可练习的三分钟版本。不要逐字背，务必能画出第 3 节的两层开关和第 4 节的事务流，再根据自己实际做过的部分调整措辞。

> 我验证的是 4 上游、4 下游的 AXI Crossbar 当前配置。四个 4 KiB 地址窗口决定请求去哪个从机，下游地址减去窗口 base；所有 Master 都可访问所有 Slave，返回按约定的 ID 前缀回源。RTL 分成上游译码/记录 W 目标、4×4 矩阵、下游竞争仲裁/记录 W 来源与 B/R 解复用。写地址和写数据是独立通道，所以必须在 AW 握手时保存路由，等最后一拍 W 握手才释放。
>
> UVM 端的 sequence 生成 `axi_txn`，sequencer 交给 Master driver 转成 AW/W/B 或 AR/R 引脚时序；Slave driver 响应并带简化内存。两侧 monitor 只看真实握手，scoreboard 按 ID、目标口、转换后的本地地址、长度/size 配对，再比较 ID、响应、每拍数据。功能覆盖一层统计请求意图，另一层只采样 scoreboard 核验成功的 M/S 路径。全路由用例每个 M/S 各发一写一读，32 笔全通过、16 格全核验；16 个回归用例种子 1 全通过。
>
> 调试中发现返回路由原先用“mask 包含”判断，`0x30` 会同时命中多个 Master，改为完整前缀匹配；还修了 FIFO 空时 RLAST 残留及 checker 本地地址配对。第一轮覆盖还缺 `READ×short/medium` 两个功能交叉 bin，补读 burst 后两个 covergroup 达 100%。我不会把它说成整体验证闭环：代码覆盖总分约 67%，当前 Master driver 不支持同端口多 outstanding，Slave 内存也未实现 WSTRB 字节语义。

面试官常会用追问确认你是否真的理解，下面给出“先答结论，再落到本项目”的版本：

| 追问 | 应抓住的机制与本项目证据 |
|---|---|
| 为什么不在 AW 到来时直接把 W 路由锁成组合逻辑？ | AW/W 独立且可能跨周期；[`axicb_slv_switch_wr`](../src/axicb_slv_switch_wr.sv) 的 `wch_gnt_fifo` 保存目标，末拍 W 握手才弹出。 |
| `item_done` 是 B 握手吗？ | UVM API 本身不是硬件握手；**这个 driver 的实现**等完整 B/R 后才 `item_done`，因此同 Master 串行。见 [`axi_mst_drv`](../verification/agent/mst/axi_mst_drv.sv)。 |
| 为什么 `0x30` 会错投？ | 原来按每个 mask 做包含判定，`0x30` 含 `0x10`、`0x20`、`0x30`；完整前缀相等才互斥。 |
| scoreboard 为什么不用数据做配对键？ | 数据可能正是被 DUT 损坏的字段；先按请求身份找对应，再比较数据，否则错误会变成“找不到事务”。 |
| “功能覆盖 100%”说明什么？ | 说明已定义 bins 命中；当前已核验路由 16/16，`kind×len` 8/8，但不说明任意 AXI 场景正确。 |
| UVM 的 monitor、driver 为何都需要？ | driver 表达激励并驾驭引脚，monitor 被动观察真实握手；scoreboard 必须拿观察值判定，而非拿 driver 意图自我证明。 |
| 这个项目支持乱序吗？ | RTL 有 per-ID outstanding 跟踪结构；**当前验证未证明同一 Master 多 outstanding 和乱序**，因为驱动/monitor/scoreboard 的实现限制。 |
| Verdi 怎么帮你定位？ | 从错误日志时间点回看 FSDB，同时显示 `RVALID/RREADY/RLAST`、FIFO empty 与 ID/目标；这次用 Verdi 套件转换 FSDB 查到 955 ns 的 stale RLAST，未使用交互式 GUI。 |

## 13. 自己做一遍：三道贯穿全文的小练习

只读文档还不足以“像自己做的”。建议拿纸推演，再回代码找对应表达式；答案故意不全部直接给出。

**练习 A：换一条路径。** 设 M3 用 ID `0x40` 对 `0x2FFC` 发单拍写。写出目标 S、下游本地地址、上游/下游 monitor 各会记录什么地址、scoreboard 的匹配键是什么；再把它改成多拍 burst，思考窗口尾部是否有跨窗口风险、当前测试是否证明了跨窗口行为。你应该得到 S2 和本地 `0x0FFC`，但跨窗口的合法性不可凭本项目已通过测试推断。

**练习 B：手工判一次故障。** 假设主侧观察到 M1 写 `0x1004`、ID `0x20`、一拍数据 `0xAABBCCDD`，从侧却在 S2 收到本地 `0x0004`、ID `0x20`、相同数据。问题不是数据，而是**目标错误**；现有 scoreboard 会因为主侧期望 S1 而找不到匹配，随后报告额外 S2 事务。若把 data 也改坏，仍应优先报告路由不匹配，而不是把两个错误混成一个“没覆盖”。

**练习 C：看一个覆盖率洞。** 只有 `WRITE×short` 和 `READ×single` 两笔时，`cp_kind` 100%、`cp_len` 会命中 single/short，但 `cx_kind_len` 的 `READ×short` 仍是空的。最小补测是一笔短读；然而若它到错 Slave，你只能说意图 bin 命中，不能让已核验路由 bin 命中。想一想为什么 coverage collector 要有两个入口。

能不看答案讲清这三题，再独立跑一次定向用例与回归、指出日志里的 32/32、16/16、代码覆盖率边界，你就已经不是在背 UVM 名词，而是在解释一套具体设计和验证的因果关系。

---

### 代码阅读最短路径

初次读代码不用从顶层 1600 多行端口表一路往下翻。按下面顺序，每打开一个文件只带着对应问题：

1. [`verification/top/dut_connect.svh`](../verification/top/dut_connect.svh)：当前实例到底配成什么？尤其地址窗口、ID、路线掩码。
2. [`src/axicb_switch_top.sv`](../src/axicb_switch_top.sv)：四个上游开关、矩阵、四个下游开关怎样连接？
3. [`src/axicb_slv_switch_wr.sv`](../src/axicb_slv_switch_wr.sv) 与 [`src/axicb_mst_switch_wr.sv`](../src/axicb_mst_switch_wr.sv)：AW 选择、W 跟踪、B 回送各在哪里？
4. [`src/axicb_slv_switch_rd.sv`](../src/axicb_slv_switch_rd.sv) 与 [`src/axicb_mst_switch_rd.sv`](../src/axicb_mst_switch_rd.sv)：AR/R、ID、RLAST 怎样处理？
5. [`verification/common/axi_txn.sv`](../verification/common/axi_txn.sv) → [`verification/agent/mst/axi_mst_drv.sv`](../verification/agent/mst/axi_mst_drv.sv) → [`verification/common/axi_monitor.sv`](../verification/common/axi_monitor.sv)：抽象 item 怎样变成引脚，又怎样从引脚重建？
6. [`verification/env/axi_env.sv`](../verification/env/axi_env.sv) → [`verification/env/axi_scoreboard.sv`](../verification/env/axi_scoreboard.sv) → [`verification/env/axi_coverage.sv`](../verification/env/axi_coverage.sv)：观察值怎样变成判定和覆盖证据？
7. [`verification/tc/axi_full_routing_test.sv`](../verification/tc/axi_full_routing_test.sv) 与 [`verification/sim/Makefile`](../verification/sim/Makefile)：如何实际把 16 格发出来并看到结果？

**一句话收尾**：设计的本质是“地址找目标、ID 找来源、握手决定何时保存/释放上下文”；验证的本质是“把每条需求变成可观测的刺激、独立判定和覆盖证据”，并诚实划清未验证的边界。

## 14. 设计报告：当前配置的合同与开放问题

这一节是给设计评审用的“单页结论”。它把当前 RTL 的可观察行为、验证对象与**尚未获设计负责人批准的假设**放在一起；不能把文档中的期望反过来当作 RTL 已实现的证明。

**范围**：当前验证对象是单时钟 4×4、16-bit 地址/8-bit ID/32-bit 数据、`AXI_SIGNALING=1`、`USER_SUPPORT=0`、无可选 pipeline/CDC 的互连。上游四个窗口互不重叠、各 4 KiB，所有 Master 路由许可位都为 1。它接收 AW/W/AR，转发或内部生成错误响应，并将 B/R 回给源 Master；下游设备的存储语义不在互连本身的功能范围内。RTL 注释中的 DDR、NPU_LMEM、DMA_REG、NPU_REG 是窗口用途标签，不代表本仓库实现了这些设备。规格合同以 [`verification/top/dut_connect.svh`](../verification/top/dut_connect.svh) 的显式覆盖值与 [`src/axicb_crossbar_top.sv`](../src/axicb_crossbar_top.sv) 的其余默认值共同确定。

**关键设计约束**：AW/AR 按起始地址译码，当前四个窗口互斥；若将来配成重叠窗口，RTL 可能同时对多个目标拉 VALID，不能把此行为认定为受支持。起始地址选中目标后，并没有对 burst 的每个数据拍重新译码；跨 4 KiB、越过窗口、WRAP 与未对齐输入的系统合法性需另行规定。`MSTx_ROUTES=1111` 只是本次实例值，RTL 也有被 route mask 禁行时走错误路径的逻辑，但本次回归并未切换路由掩码去单独核验。`AxQOS/PROT/CACHE/REGION/LOCK` 的信号转发不意味着实现了相应权限或动态 QoS 仲裁；当前静态 `MSTx_PRIORITY` 全为 0。`MSTx_RW` 与 `TIMEOUT_ENABLE/TIMEOUT_VALUE` 在顶层标记为 UNUSED，不能据参数名声称只读控制或自动超时响应已实现。

**设计评审待定事项**：合法 ID 前缀与低位索引的完整集合、同一 Master 同时在途上界及同 ID 顺序保证；复位中途请求的处置；跨窗口 burst 的拒绝/允许策略；公平性和性能量化上界；非 4×4、流水、CDC、USER 等配置的交付范围。尤其 CDC 分支依赖的异步 FIFO 不在当前 `src/` 编译路径内，不能仅凭参数存在就宣称跨时钟能力已可用。若需求变更，应先更新合同和 checker，再变更 RTL/激励，而不是让 scoreboard 默默把 RTL 当前行为当成正确规格。

## 15. 验证报告：本次证据、通过范围与下一步

**运行批次**：2026-11-09，VCS T-2022.06、UVM 1.2、`SEED=1`、`COV=1`、`+UVM_TIMEOUT=100000`，运行 [`verification/sim/regress.sh`](../verification/sim/regress.sh) 中的 16 个 test。结果为 `Regression passed (16/16 tests)`；各运行日志中的 UVM error/fatal 与 `[SVA]` 错误均为 0。定向全路由测试中 16 个 M/S 格每格读、写一次，共 32 笔，scoreboard 报 `Routing: 32 pass / 0 fail; data: 32 pass / 0 fail`，已核验路由矩阵 `16/16`。证据留在 `verification/sim/build/runs/` 与 URG 报告目录，重跑命令见第 10 节。

| 可交付的结论 | 本次证据 | 不能外推为 |
|---|---|---|
| 当前 4×4 路由的读写转发在定向全路由用例中通过 | 16 格、每格读写、32 笔两侧配对及逐拍数据比较 | 任意端口数/ID 配置、任意并发时序均正确 |
| 定义好的功能覆盖模型闭环 | 两个 covergroup 各 100%；`cx_routing` 与已核验 `cx_verified_routing` 均 16/16；`kind×len=8/8`、`kind×size=6/6`、`kind×slave=8/8`、`kind×resp=6/6` | AXI 全协议、未建模场景或整片设计覆盖率 100% |
| 回归批次没有报告可见错误 | 16/16；UVM error/fatal 与接口 SVA 错误为 0 | Checker 没有盲区，或者所有种子和参数都通过 |
| 代码覆盖率已收集、但未收敛 | URG 总分 67.43%；LINE 66.28%、COND 66.87%、TOGGLE 31.64%、BRANCH 72.36% | 纯 DUT 的同名指标，或达到流片签核门槛 |

**已定位并修复的具体问题**：B/R 用局部 mask“包含”匹配会让 `0x30` 同时命中多路，已改为完整前缀匹配；读 FIFO 空后 RLAST 残留，以及未命中读最后一拍的 READY 依赖已修；scoreboard 曾因全局/本地地址误配、把数据当匹配键和缺失事务仅警告产生错误结论，现改为先配对再比较并对缺失/额外事务报错；全路由、并发、错误测试的激励也按当前配置修正。首次有效 URG 合并剩下的两个功能洞是 `READ×short`、`READ×medium`，补相应读 burst 后闭合。旧资料中的 `13/16` 是**缺三格**，无法据此证明“恰有两条物理通路坏”。

**尚未签核**：当前 Master driver 同端口一次只处理一笔完整事务，monitor 和 scoreboard 也不能完整重建乱序；Slave 内存未按 WSTRB 做逐字节更新；B/R 背压与传输中复位未系统闭环；未知/非法 ID、跨窗口 burst、全部配置组合及公平性/性能上界没有足够证据。代码覆盖率还需排除基础设施与不可达配置分支后逐项评审。以上项目应作为下一版验证计划，而不是补一个好看的百分比。
