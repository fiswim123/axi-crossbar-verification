# AXI Crossbar UVM 测试点分解与覆盖率收集指南

## 1. 总体方法

这个项目的测试点分解遵循下面的链路：

```text
DUT 规格
  ↓
功能特性 Feature
  ↓
具体场景 Scenario
  ↓
激励 Sequence/Test
  ↓
检查 Scoreboard/SVA
  ↓
功能覆盖 Covergroup
  ↓
回归与覆盖率收敛
```

当前项目已经具备验证计划、测试用例和基础 covergroup 框架，但部分测试点还没有形成真正的检查闭环。因此阅读时要区分：

- 项目计划验证什么；
- 代码实际上产生了什么激励；
- Scoreboard/SVA 实际检查了什么；
- Coverage 实际记录了什么；
- 哪些覆盖数字目前还不能作为功能正确的证据。

---

## 2. 为什么要做测试点分解

不能直接看着 DUT 写几十个 test，否则容易出现：

- 多个 test 重复验证同一功能；
- 某些规格没有对应测试；
- 有激励但没有 checker；
- 有 checker 但没有 coverage；
- test 名字叫 outstanding，实际总线上没有 outstanding；
- 回归全绿，但存在 false pass。

例如规格要求：

> Crossbar 根据地址把 Master 请求转发到正确 Slave。

不能只写一个模糊测试点“验证路由”，而应继续拆成：

```text
Master 0 → Slave 0
Master 0 → Slave 1
...
Master 3 → Slave 3
```

这样得到 4×4=16 条路由路径。每条路径还要定义：

```text
激励：哪个 Master 发什么地址
检查：实际到了哪个 Slave，地址是否正确转换
覆盖：master × slave 的 cross bin 是否命中
```

只有“激励、检查、覆盖”三者齐全，一个测试点才形成闭环。

项目现有验证计划：

[verification_plan.md](verification_plan.md)

---

## 3. 基础读写测试点

### 3.1 测试点

- 单拍写传输；
- 单拍读传输；
- 写后读；
- BRESP/RRESP 是否正确；
- 写入数据与读回数据是否一致。

对应测试：

[axi_basic_test.sv](../tests/axi_basic_test.sv)

它执行的场景为：

```text
Master 0 写 Slave 0
Master 0 写 Slave 1
Master 0 写 Slave 2
Master 0 写 Slave 3
        ↓
Master 0 从四个地址读回
```

### 3.2 理论检查闭环

```text
Master Monitor 观察成功写
        ↓
Scoreboard 更新 reference memory
        ↓
Master Monitor 观察读响应
        ↓
Scoreboard 比较 RDATA 与 reference memory
```

### 3.3 当前实现情况

当前 [axi_scoreboard.sv](../components/axi_scoreboard.sv) 收到读事务后只增加计数，没有比较 `rdata`：

```text
读激励：有
读事务采集：有
读覆盖率采样：有
读数据检查：没有
```

所以 basic test 中“写后读数据一致”尚未形成完整闭环。

---

## 4. 地址路由测试点

### 4.1 地址映射

| 目标 Slave | 全局地址范围 |
|---|---:|
| Slave 0 | `0x0000~0x0FFF` |
| Slave 1 | `0x1000~0x1FFF` |
| Slave 2 | `0x2000~0x2FFF` |
| Slave 3 | `0x3000~0x3FFF` |

### 4.2 路由空间分解

| Master | S0 | S1 | S2 | S3 |
|---|---:|---:|---:|---:|
| M0 | M0→S0 | M0→S1 | M0→S2 | M0→S3 |
| M1 | M1→S0 | M1→S1 | M1→S2 | M1→S3 |
| M2 | M2→S0 | M2→S1 | M2→S2 | M2→S3 |
| M3 | M3→S0 | M3→S1 | M3→S2 | M3→S3 |

功能覆盖中对应：

```systemverilog
cx_routing: cross cp_master, cp_slave;
```

理论上共有 16 个 cross bins。

对应测试：

- [axi_routing_test.sv](../tests/axi_routing_test.sv)
- [axi_full_routing_test.sv](../tests/axi_full_routing_test.sv)
- [axi_multi_master_test.sv](../tests/axi_multi_master_test.sv)

### 4.3 全局地址与局部地址

DUT 配置：

```systemverilog
SLVx_KEEP_BASE_ADDR = 0
```

RTL 在 [axicb_mst_if.sv](../../src/axicb_mst_if.sv) 中执行：

```systemverilog
o_awaddr = awaddr - BASE_ADDR;
o_araddr = araddr - BASE_ADDR;
```

因此：

| 上游全局地址 | 目标 Slave | 下游局部地址 |
|---:|---:|---:|
| `0x0004` | S0 | `0x0004` |
| `0x1004` | S1 | `0x0004` |
| `0x2004` | S2 | `0x0004` |
| `0x3004` | S3 | `0x0004` |

正确 reference model 应计算：

```systemverilog
expected_slave     = decode(global_addr);
expected_local_addr = global_addr - slave_base[expected_slave];
```

当前 scoreboard 直接比较：

```systemverilog
slv_txn.addr == mst_txn.addr
```

这会把 Slave 1～3 的合法地址转换误认为不匹配。

这里要区分：

- `cp_slave` 根据上游全局地址记录“想访问哪个 Slave”；
- Scoreboard 检查事务是否真的到达正确下游端口；
- Coverage 命中不能证明 DUT 路由正确。

---

## 5. Burst 与传输宽度测试点

### 5.1 Burst length

AXI 定义：

```text
实际 beat 数 = AxLEN + 1
```

项目选择以下等价类：

| AxLEN | 实际拍数 | 分类 |
|---:|---:|---|
| 0 | 1 | single |
| 1～3 | 2～4 | short |
| 4～7 | 5～8 | medium |
| 8～15 | 9～16 | long |

Coverage：

```systemverilog
cp_len: coverpoint txn.len {
    bins single = {0};
    bins short  = {[1:3]};
    bins med    = {[4:7]};
    bins long_b = {[8:15]};
}
```

### 5.2 Transfer size

```text
每拍字节数 = 2^AxSIZE
```

| AxSIZE | 每拍字节数 |
|---:|---:|
| 0 | 1 byte |
| 1 | 2 bytes |
| 2 | 4 bytes |

Coverage：

```systemverilog
cp_size: coverpoint txn.size {
    bins b1 = {0};
    bins b2 = {1};
    bins b4 = {2};
}
```

### 5.3 当前局限

虽然 sequence 可以产生 `size=0/1/2`，但 [axi_slv_drv.sv](../components/axi_slv_drv.sv) 中的 memory model 始终写四个字节并执行 `addr += 4`。

它没有正确处理：

- `WSTRB`；
- `AxSIZE`；
- 窄传输 byte lane；
- FIXED/WRAP burst；
- 非 4-byte 地址步长。

因此：

```text
size 覆盖率：可以命中
size 功能正确性：尚未被可靠检查
```

Coverage 只表示某个取值发生过，不表示该取值对应的功能正确。

---

## 6. Outstanding 测试点

验证计划希望覆盖：

- 多笔写请求未等 B 就继续发 AW；
- 多笔读请求未等 R 就继续发 AR；
- 达到最大 outstanding 深度；
- 不同 ID 的响应匹配；
- 同 ID 保序、不同 ID 允许乱序。

当前 Master Driver 的执行方式是：

```text
取 item 0
→ AW0
→ W0
→ 等 B0
→ item_done

取 item 1
→ AW1
→ W1
→ 等 B1
→ item_done
```

即使 test 用多个线程同时 `sequence.start()`，也只是在 sequencer 前排队。

真正的 outstanding 必须在波形中出现：

```text
AW0 handshake
AW1 handshake
AW2 handshake
B0/B1/B2 尚未全部返回
```

或者：

```text
AR0 handshake
AR1 handshake
R0/R1 尚未全部返回
```

当前 coverage model 没有 `outstanding_depth`，因此该测试点目前缺少：

- 真实 outstanding 激励；
- pending depth 检查；
- outstanding depth coverage；
- 按 ID 的响应比较。

---

## 7. 多 Master 并发与仲裁

### 7.1 多 Master 访问不同 Slave

```text
M0 → S0
M1 → S1
M2 → S2
M3 → S3
```

检查：

- Crossbar 能否并行传输；
- 数据路径是否相互隔离；
- 一个端口阻塞是否影响无关端口。

对应测试：

[axi_multi_master_test.sv](../tests/axi_multi_master_test.sv)

### 7.2 多 Master 访问同一 Slave

```text
M0 ─┐
M1 ─┼→ Slave 0
M2 ─┤
M3 ─┘
```

检查：

- 同一时刻只能产生合法授权；
- 没有数据串扰；
- response 返回正确 Master；
- Round-robin 是否公平；
- 是否存在 starvation；
- backpressure 下仲裁是否稳定。

对应测试：

[axi_same_slave_test.sv](../tests/axi_same_slave_test.sv)

当前 coverage 没有：

- 同周期竞争 Master 数；
- 仲裁等待周期；
- grant 顺序；
- 最大等待时间；
- starvation；
- 同 Slave 并发场景。

16 条路由 coverage 全部命中，也不能证明仲裁公平。

---

## 8. 错误响应测试点

计划测试：

- SLVERR；
- DECERR；
- 错误传播；
- 错误后恢复；
- 错误事务不污染 reference memory。

配置对象：

[axi_slv_cfg.sv](../components/axi_slv_cfg.sv)

主要字段：

```systemverilog
int unsigned err_pct;
bit [1:0] err_resp;
```

Responder 根据配置返回：

```systemverilog
bresp = inject_err ? cfg.err_resp : 2'b00;
rresp = inject_err ? cfg.err_resp : 2'b00;
```

### 8.1 当前 response coverage

```systemverilog
cp_resp: coverpoint (...) {
    bins okay = {0};
}
```

应该补充：

```systemverilog
bins exokay = {1};
bins slverr = {2};
bins decerr = {3};
```

并与读写类型交叉：

```text
READ × SLVERR
READ × DECERR
WRITE × SLVERR
WRITE × DECERR
```

### 8.2 配置目标错位

如果访问：

```text
0x0000 → 应配置 slv_cfg[0]
0x1000 → 应配置 slv_cfg[1]
0x2000 → 应配置 slv_cfg[2]
0x3000 → 应配置 slv_cfg[3]
```

当前 error test 存在配置 Slave 0、实际访问 Slave 1/2 的情况，导致错误可能没有真正注入。

---

## 9. Backpressure 测试点

| 通道 | 谁控制 READY | 应在哪里配置 |
|---|---|---|
| AW | Slave responder | Slave agent |
| W | Slave responder | Slave agent |
| B | Master driver | Master agent |
| AR | Slave responder | Slave agent |
| R | Master driver | Master agent |

当前 `axi_slv_cfg` 只有：

```systemverilog
bp_awready_pct
bp_wready_pct
bp_arready_pct
```

因此只能控制 AW/W/AR backpressure。现有测试中的 B/R backpressure 没有真正控制 BREADY/RREADY。

完整 coverage 可以增加：

```text
AW wait cycles
W wait cycles
B wait cycles
AR wait cycles
R wait cycles
```

等待周期 bins 示例：

| 等待周期 | Bin |
|---:|---|
| 0 | zero_wait |
| 1～3 | short_wait |
| 4～15 | medium_wait |
| ≥16 | long_wait |

进一步交叉：

```text
channel × wait-cycle-range
kind × target-slave × backpressure
LAST-beat × backpressure
```

---

## 10. Reset 测试点

计划场景：

- AW 后 reset；
- W burst 中 reset；
- 等待 B 时 reset；
- AR 后 reset；
- R burst 中 reset；
- reset 后恢复；
- 多次 reset。

对应测试：

[axi_reset_test.sv](../tests/axi_reset_test.sv)

完整检查流程：

```text
Reset 发生
  ├── Driver 拉低 VALID/READY
  ├── Responder 清空输出
  ├── Monitor 丢弃未完成 transaction
  ├── Scoreboard 清理 pending
  ├── Reference memory 按规格保留或清空
  └── Reset 释放后可以重新传输
```

当前项目没有 reset coverpoint，也没有统计 reset 在事务哪个阶段发生。

另外，test 直接写 `vif.aresetn`，顶层 module 也在写同一信号，存在多过程驱动/调度竞争。成熟环境应提供唯一 reset driver。

---

## 11. 边界条件测试点

地址边界应包括：

```text
Slave 0 起始/结束地址
Slave 1 起始/结束地址
Slave 2 起始/结束地址
Slave 3 起始/结束地址
未映射地址
```

还应检查：

- 对齐和非对齐地址；
- burst 最后一拍恰好到窗口末尾；
- burst 跨 Slave window；
- burst 跨 4 KB；
- 最大 AxLEN；
- 最小/最大 ID；
- 最大 outstanding。

当前 boundary constraint 选择了若干 4-byte 对齐的窗口边界，但缺少：

- 未对齐地址；
- 未映射地址；
- 跨窗口 burst；
- 4 KB crossing；
- illegal burst；
- WRAP boundary。

---

## 12. 随机与性能测试点

### 12.1 随机测试

完整随机维度应包括：

```text
kind
master
slave/address
ID
LEN
SIZE
BURST
data
WSTRB
response delay
backpressure
```

当前 `axi_random_seq` 主要按照循环序号决定读写和目标地址，并固定 ID、LEN、SIZE，更接近规则化 directed sequence，不是完整 constrained-random。

### 12.2 性能测试

计划测量：

- AW 到 B 延迟；
- AR 到首个/最后一个 R 的延迟；
- 吞吐量；
- back-to-back efficiency；
- 竞争下最大等待时间。

`axi_txn` 有时间戳和 latency 字段，但 monitor 没有真正填写，因此当前性能报告可能一直是 0。

---

## 13. 功能覆盖率收集链路

核心组件：

[axi_coverage.sv](../components/axi_coverage.sv)

它继承：

```systemverilog
class axi_coverage extends uvm_subscriber #(axi_txn);
```

### 13.1 Monitor 发送事务

Master monitor 收齐完整写或读事务后调用：

```systemverilog
ap.write(txn);
```

因此 coverage 采到的是已经在上游接口完成的事务，而不是 sequence 计划发送但没有完成的事务。

### 13.2 Environment 建立连接

[axi_env.sv](../components/axi_env.sv) 中：

```systemverilog
mst_agent[i].monitor.ap.connect(cov.analysis_export);
```

数据流：

```text
M0 Monitor ─┐
M1 Monitor ─┤
M2 Monitor ─┼→ 一个 axi_coverage
M3 Monitor ─┘
```

Coverage 聚合四个 Master 的事务，没有使用 per-master 独立 coverage 实例。

Slave monitor 没连接 coverage，所以它不能直接证明实际下游路由，只能记录上游事务属性。

### 13.3 Subscriber 采样

```systemverilog
function void write(axi_txn t);
    txn = t;
    cg.sample();
endfunction
```

流程：

```text
Monitor.ap.write(t)
        ↓
coverage.write(t)
        ↓
txn = t
        ↓
cg.sample()
        ↓
所有 coverpoint/cross 更新命中计数
```

`write()` 是 function，不能在其中等待仿真时间。

---

## 14. 当前 Covergroup 的覆盖内容

### 14.1 读写类型

```systemverilog
cp_kind: coverpoint txn.kind {
    bins rd = {0};
    bins wr = {1};
}
```

能证明读写事务都发生过，不能证明数据正确。

### 14.2 目标 Slave

```systemverilog
cp_slave: coverpoint txn.addr[15:12] {
    bins s0 = {0};
    bins s1 = {1};
    bins s2 = {2};
    bins s3 = {3};
}
```

它根据 Master 侧全局地址推断目标，只能证明四个窗口都被访问过，不能证明 DUT 实际正确路由。

### 14.3 来源 Master

当前通过 ID 高 4 bit 推断 Master：

```systemverilog
cp_master: coverpoint txn.id[7:4] {
    bins m0 = {1};
    bins m1 = {2};
    bins m2 = {3};
    bins m3 = {4};
}
```

更稳健的做法是使用 monitor 已经填写的 `source_id`：

```systemverilog
cp_master: coverpoint txn.source_id {
    bins m0 = {0};
    bins m1 = {1};
    bins m2 = {2};
    bins m3 = {3};
}
```

AXI ID 是协议字段，不应天然等同于 Master 编号。

### 14.4 Cross coverage

```systemverilog
cx_routing:    cross cp_master, cp_slave;
cx_kind_len:   cross cp_kind, cp_len;
cx_kind_size:  cross cp_kind, cp_size;
cx_kind_slave: cross cp_kind, cp_slave;
```

它们分别回答：

- 每个 Master 是否访问过每个 Slave；
- 读写是否都覆盖各类 burst length；
- 读写是否都覆盖各类 transfer size；
- 每个 Slave 是否都被读过和写过。

---

## 15. 为什么需要 Cross Coverage

假设：

```text
cp_master = 100%
cp_slave  = 100%
```

可能只发生：

```text
M0→S0
M1→S1
M2→S2
M3→S3
```

虽然两个单点 coverage 都是 100%，但 16 条路由只覆盖 4 条。

因此需要：

```systemverilog
cross cp_master, cp_slave;
```

同样，`cp_kind=100%` 且 `cp_len=100%`，不代表读和写分别覆盖了所有长度，需要 `kind×len` cross。

如果规格关心两个维度的组合，就不能只分别覆盖两个维度。

---

## 16. 代码覆盖率收集

Makefile：

[Makefile](../Makefile)

编译选项：

```makefile
-cm line+cond+fsm+tgl+branch
-cm_dir ./cov_db
```

| 类型 | 检查内容 |
|---|---|
| line | RTL 语句是否执行 |
| branch | `if/else`、`case` 分支是否执行 |
| condition | 布尔子条件是否取到真/假 |
| FSM | 状态和状态跳转是否覆盖 |
| toggle | bit 是否发生 0→1、1→0 |
| assertion | property 是否触发/成功/失败；当前没有正确纳入 |

仿真时使用：

```makefile
-cm_name $(UVM_TEST)
```

报告：

```makefile
urg -dir cov_db -report coverage_report
```

流程：

```text
编译时插入 coverage instrumentation
        ↓
各 test 运行并写 coverage database
        ↓
URG 读取/合并数据库
        ↓
生成 HTML/text report
```

### 16.1 当前 Makefile 的风险

日志已经报告：

```text
'func' is not a valid argument to -cm
```

`func` 对当前 VCS 版本不是合法的代码覆盖选项。SystemVerilog covergroup functional coverage 也不等同于 `-cm func`。

此外：

- 每个 test 可能重新编译；
- test 默认使用同名 `sim.log`；
- coverage database 是否正确累计需要核验；
- assertion coverage 没有完整配置；
- README 与 verification plan 的覆盖数字不一致。

旧文档中的覆盖率数字不能未经 coverage database 核验就作为最终结果。

---

## 17. SVA 覆盖与功能覆盖

Interface：

[axi_if.sv](../infra/axi_if.sv)

当前断言主要检查：

- VALID 等待 READY 时保持；
- WLAST 必须伴随 WVALID；
- RLAST 必须伴随 RVALID。

SVA coverage 需要关注：

```text
Attempt：前件是否发生
Success：属性是否成功
Failure：属性是否失败
```

一个 assertion 如果从未触发：

```text
0 attempt
0 failure
```

不能证明协议正确，只能说明相关场景没有发生。

当前 `$error` 产生的 assertion failure 没进入 UVM_ERROR 统计，因此回归必须同时检查 simulator assertion summary 与 UVM summary。

---

## 18. Test、Checker、Coverage 映射示例

| 测试点 | 激励 | Checker | Coverage |
|---|---|---|---|
| M2→S3 路由 | M2 发 `0x3000` 请求 | S3 monitor 收到，其他 Slave 没收到 | `M2×S3` |
| 4-beat 写 | `AWLEN=3` | 4 个 W handshake，最后一拍 WLAST | write×len=3 |
| 2-byte 写 | `AWSIZE=1` | 正确 byte lane/WSTRB | write×size=1 |
| SLVERR 写 | responder 返回 `2'b10` | 上游 BRESP=SLVERR | write×SLVERR |
| R backpressure | Master 拉低 RREADY | RVALID/RDATA 保持 | R wait-cycle bin |
| outstanding=4 | 连续四个 AR | pending depth=4、响应全部匹配 | depth=4 |
| 同 Slave 竞争 | 4M 同时访问 S0 | one-hot grant、公平性、数据不串 | contender=4 |
| 读中 reset | R burst 中复位 | pending flush、复位后恢复 | reset-point=R |

```text
Test 产生场景
Checker 判断正确
Coverage 记录场景发生
```

三者缺一不可。

---

## 19. 当前测试点闭环评价

| 类别 | 激励 | Checker | Coverage | 当前评价 |
|---|---|---|---|---|
| 基础写 | 有 | 部分有 | 有 | 基本可用 |
| 基础读 | 有 | 没有数据比较 | 有 | false pass 风险 |
| 地址路由 | 有 | 地址转换模型错误 | 有 cross | 需修复 |
| Burst length | 有 | 没完整 LAST/数据检查 | 有 | 部分闭环 |
| Transfer size | 有 | memory model 不支持窄传输 | 有 | 只覆盖激励 |
| 多 Master | 有 | matcher 不够稳健 | 有 routing cross | 部分闭环 |
| 同 Slave 仲裁 | 有 | 无公平性检查 | 无竞争覆盖 | 不完整 |
| Outstanding | 名义上有 | 不支持 | 无 depth coverage | 实际未实现 |
| SLVERR/DECERR | 部分有 | expected error 处理不足 | 无错误 bins | 不完整 |
| Backpressure | 只有 AW/W/AR | 部分 SVA | 无等待周期覆盖 | 不完整 |
| Reset | 有名义场景 | 无 pending/reset model | 无 reset coverage | 不完整 |
| 随机 | 规则化 directed | 基础 checker | 基础 coverage | 随机性不足 |
| 性能 | 有字段 | 时间戳未填写 | 无 latency coverage | 未闭环 |

---

## 20. 覆盖率收敛流程

### 第一步：建立可追踪矩阵

```text
Requirement ID
→ Test/Sequence
→ Scoreboard/SVA
→ Coverpoint/Cross
```

### 第二步：先验证 Checker

故意注入错误：

- 改错 RDATA；
- 把请求送错 Slave；
- 少一个 W beat；
- 提前 RLAST；
- 返回错误 RID；
- 丢掉 B response。

确认测试必然失败。如果故障注入后仍 PASS，应先修 checker，而不是继续提高 coverage。

### 第三步：运行基础 Directed Tests

确保：

- 单笔读写正确；
- 四个 Slave 正确；
- reference model 正确；
- assertion 没有误报。

### 第四步：增加组合场景

```text
burst
→ size/WSTRB
→ multi-master
→ same-slave arbitration
→ backpressure
→ errors
→ reset
→ outstanding/reordering
```

### 第五步：分析 Coverage Holes

未命中 bin 可能是：

1. 激励没有产生；
2. 约束冲突；
3. sequence 产生了但 driver 没驱动；
4. monitor 没采到；
5. DUT 不可达；
6. bin 定义错误；
7. 当前配置不支持；
8. 合法但缺 test。

### 第六步：合理 Exclusion

只有规格证明不可达的 bin 才能排除。例如 DUT 参数明确不支持 WRAP，才可以对 WRAP coverage 做 exclusion，不能因为难以命中就删除。

---

## 21. 面试回答模板

> 我先根据 Crossbar 规格把验证内容分为基础读写、4×4 地址路由、burst length/size、多 Master 并发、同 Slave 仲裁、outstanding、错误响应、backpressure、reset、边界和性能等类别。每个类别继续按 master、slave、读写类型、长度、size、response 和时序压力拆成可检查的原子测试点。
>
> 激励由对应 test 和 sequence 产生，Master/Slave 两侧 monitor 从实际握手信号重建 transaction。Scoreboard 根据地址窗口预测目标 Slave，并需要考虑 `KEEP_BASE_ADDR=0` 带来的全局地址到局部地址转换；写后读则通过 byte-addressed reference memory 比较数据。
>
> 功能覆盖由 `axi_coverage` subscriber 收集。四个 Master monitor 的 analysis port 都连接到同一个 coverage component，在每笔完整事务结束时调用 `cg.sample()`。现有模型覆盖 kind、master、slave、length、size 和 master×slave 等交叉组合。代码覆盖通过 VCS 的 line、condition、branch、FSM 和 toggle 收集，再由 URG 生成报告。
>
> 我在审查中发现，原始 AI 版本虽然有较多测试名称和覆盖点，但部分没有检查闭环。例如读数据没有比较、outstanding 实际仍是串行、错误 response 没有 coverage bins、B/R backpressure 没真正产生。因此我不会只依据覆盖率数字判断完成，而会要求每个测试点同时具备有效激励、独立 checker 和对应 coverage，并通过故障注入证明 checker 确实能发现错误。

## 22. 总结

```text
测试点分解回答：需要验证什么
Checker 回答：结果是否正确
Coverage 回答：场景是否真的发生过
```

Coverage 不是正确性的证明。只有以下条件同时满足，验证点才真正闭环：

1. 激励确实在总线上发生；
2. Checker 能发现对应错误；
3. Coverage 记录到该场景；
4. 故障注入可以证明 Checker 不会 false pass；
5. 回归脚本能统一识别 UVM、SVA、timeout 和 pending failures。
