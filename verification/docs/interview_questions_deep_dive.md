# 数字 IC 验证面试深度问答：结合 AXI Crossbar UVM 项目

> 范围：SystemVerilog、UVM、Scoreboard/方法学、Functional Coverage、SVA、AXI、Debug、项目追问和十五题速答。按要求不包含“数字电路基础”部分。

## 使用说明

每组问题按四个层次回答：

- **问题含义**：面试官真正想判断什么；
- **资深回答**：不仅给定义，还给设计取舍、边界和常见误区；
- **项目分析**：指出本项目的代码证据和当前局限；
- **文档扩展示例**：项目没有实现时给出示意代码。示例只存在于本文，不代表仓库源码已经修改或验证。

回答项目问题时要严格区分“当前已经实现”“当前存在缺陷”“建议如何改造”。诚实识别 false pass，通常比背诵完整 UVM 名词更能体现工程能力。

---

# 第一部分：SystemVerilog

## 1. 数据类型

### Q1：`wire`、`reg`、`logic` 有什么区别？2-state 与 4-state 如何选择？

**问题含义**

面试官在确认你是否理解 net、variable 和四态仿真的本质，而不是只会说“SystemVerilog 用 logic 代替 reg”。

**资深回答**

- `wire` 是 net，表达连接关系，本身不保存过程赋值结果，传统上由 continuous assignment、module output 等驱动；
- `reg` 是 Verilog 的过程变量，并不代表硬件一定是寄存器；
- `logic` 是 SystemVerilog 四态变量，可用于大多数过程赋值和端口声明，但一个变量原则上不应由多个过程驱动；
- `bit` 是二态变量，只有 0/1，速度和内存通常更好，但会吞掉 X/Z；
- DUT 接口、协议监测和需要 X 检查的位置优先四态 `logic`；transaction 中已经保证抽象值合法的字段可用二态 `bit`。

不能笼统说 `logic` 完全取代 `wire`：多驱动解析网络、三态总线等仍需要 net 语义。

**项目分析**

[axi_if.sv](../infra/axi_if.sv) 的总线信号使用 `logic`，适合协议仿真。但 [axi_txn.sv](../components/axi_txn.sv) 的字段多数使用 `bit`，monitor 将接口上的 X 采入二态字段时可能静默变成 0，降低 X-propagation 检查能力。成熟 VIP 可以在 monitor 采样前使用 `$isunknown()` 报错。

### Q2：packed/unpacked array，以及静态、动态、队列、关联数组如何选择？

**问题含义**

考察数据布局、位选择能力，以及你能否为 scoreboard/transaction 选对容器。

**资深回答**

- packed 维度写在变量名前，整体可当作连续位向量做算术、切片和打包；
- unpacked 维度写在变量名后，表示元素集合；
- 静态数组大小编译时固定；
- 动态数组运行时 `new[n]` 分配，适合已知最终长度的 burst payload；
- 队列支持高效 push/pop，适合按时间到来的 pending transactions；
- 关联数组按 key 稀疏存储，适合地址空间和按 ID 分类的表。

**项目分析**

- `bit [31:0] wdata[]`：32 bit packed 元素组成的 unpacked 动态数组；
- `mst_wr_txns[$]`：scoreboard 事务队列；
- `mem[bit [31:0]]`：以地址为 key 的 byte memory 关联数组。

当前 `exp_data` 按地址保存整字，没有按 WSTRB 建模，后续应改为 byte-addressed 关联数组。

### Q3：enum、struct、union、signed/unsigned 有什么注意点？

**问题含义**

考察类型安全、可读性和算术位宽陷阱。

**资深回答**

enum 用于有限状态集合并提供类型检查；packed struct 适合把协议字段作为连续位流；union 让多个视图共享存储，误用会产生类型解释风险。SV 表达式的 signedness 和最大操作数位宽会影响扩展、比较和移位，应显式转换或统一类型，避免无符号地址与负偏移混算。

**项目分析**

`axi_txn::kind_e` 用 enum 表示 READ/WRITE，比 magic number 清晰。项目的 `expected_slave = addr[15:12]` 转成 `int` 后再比较没有明显问题，但地址减 base、长度 `len+1` 和数组 size 混用不同有符号类型时，成熟代码应显式使用 `int unsigned` 或参数化地址类型。

## 2. 阻塞/非阻塞与调度区

### Q4：`=` 与 `<=` 的区别？为什么组合逻辑常用阻塞、时序逻辑常用非阻塞？

**问题含义**

考察你是否理解事件调度，而不是机械记编码规范。

**资深回答**

阻塞赋值在当前 active region 立即更新，下一条语句看到新值；非阻塞赋值先计算 RHS，把更新排入 NBA region。同一时钟沿的触发器用 NBA 可让所有 RHS 读取旧状态，符合并行采样的硬件行为。组合过程用 blocking 便于按语句依赖计算最终值。关键不是语法决定硬件，而是过程结构和赋值时序共同决定。

### Q5：driver、DUT、monitor 同时在 `posedge` 操作会怎样？什么是 race？

**问题含义**

考察 testbench 时序的确定性。

**资深回答**

若多个过程在同一调度区读写同一信号，标准不保证它们的执行先后，仿真结果可能依赖工具或微小代码变化。clocking block 通过 input/output skew 把采样和驱动放到明确区域，program block 或 UVM clocking block 也能减少 race。只用 NBA 并不能解决所有采样竞态。

**项目分析**

[axi_mst_drv.sv](../components/axi_mst_drv.sv) 在 `@(posedge vif.aclk)` 后 NBA 驱动，而 [axi_monitor.sv](../components/axi_monitor.sv) 直接在 `posedge` 采样；interface 没有 clocking block。这可能造成“本沿还是下沿才生效”的理解偏差。

**文档扩展示例**

```systemverilog
interface axi_if(input logic aclk);
  clocking mst_cb @(posedge aclk);
    default input #1step output #0;
    output awvalid, awaddr, wvalid, wdata, bready;
    input  awready, wready, bvalid, bresp;
  endclocking
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awvalid, awready, awaddr, wvalid, wready, wdata;
  endclocking
endinterface
```

## 3. 进程与并发

### Q6：`fork/join`、`join_any`、`join_none`、`wait fork`、`disable fork` 分别是什么？

**问题含义**

考察线程生命周期、父子进程关系和安全退出。

**资深回答**

- `join` 等全部直接子线程结束；
- `join_any` 等任一子线程结束，其他线程继续；
- `join_none` 不等待，父线程继续；
- `wait fork` 等待当前进程所有尚存的直接子线程；
- `disable fork` 终止当前进程所有活动的直接子线程，容易误杀同一作用域里无关线程，常用额外命名 block 隔离。

**项目分析**

多 master test 用 `fork/join` 是物理多接口并发；outstanding test 用 `join_none` 并发启动多个 sequence，但 driver 等完整 B/R 后才取下一项，所以只形成 sequence 排队，不形成 AXI outstanding。

### Q7：`automatic`/`static`、共享句柄和线程安全怎么解释？

**问题含义**

考察你能否发现并发测试中的偶发 bug。

**资深回答**

automatic 每次调用/迭代有独立存储，static 被所有调用共享。fork 循环中的变量若在子线程真正执行前已经变化，会产生经典 loop-index bug。即使索引 automatic，对象句柄仍可能指向同一对象；线程安全需要同时检查变量存储和对象所有权。

**项目分析**

[axi_outstanding_test.sv](../tests/axi_outstanding_test.sv) 使用 `automatic int idx=i` 是正确意识；[axi_concurrent_seq.sv](../sequences/axi_concurrent_seq.sv) 两个线程共享 `req`，一个线程阻塞在 `start_item` 时另一个线程可能改写句柄，是更严重的问题。

### Q8：semaphore、mailbox、event 分别用于什么？

**问题含义**

考察基本进程同步工具及其适用边界。

**资深回答**

- semaphore 是 token 计数器，保护有限资源或临界区；
- mailbox 是线程安全消息队列，支持阻塞/非阻塞 put/get；
- event 是无数据的瞬时同步通知，需注意 trigger 与 wait 的竞态；
- UVM 组件通信优先使用类型安全的 TLM，底层 BFM 内部仍可使用这些原语。

**文档扩展示例**

```systemverilog
mailbox #(axi_txn) aw_mb = new();
semaphore pending_slots = new(4);
event reset_done;
// 请求线程 pending_slots.get(1)，响应线程完成后 put(1)。
```

## 4. OOP

### Q9：class/struct、继承、多态、封装、virtual/pure virtual 分别意味着什么？

**问题含义**

考察 UVM 可复用架构背后的语言基础。

**资深回答**

struct 主要是数据聚合，class 是引用语义对象，支持继承和虚方法。继承复用接口与默认行为；多态让基类句柄调用实际派生实现；封装把状态和操作约束在类内；virtual 允许动态派发；pure virtual 只规定契约，派生类必须实现。UVM factory override 的价值依赖多态。

**项目分析**

`axi_mst_drv extends uvm_driver#(axi_txn)`、具体 tests 继承 `axi_base_test`。当前项目很少定义自己的 virtual API，因此能演示继承，尚未充分展示抽象 VIP 接口。

### Q10：shallow/deep copy、对象赋值、`copy()`、`clone()` 有何区别？

**问题含义**

考察 analysis port、队列和预测模型中的对象所有权。

**资深回答**

`b=a` 只复制句柄；shallow copy 对嵌套对象仍共享句柄；deep copy 递归复制。UVM `copy()` 把 rhs 内容复制到已有 lhs，`clone()` 创建新对象再 copy，返回 `uvm_object`，通常需要 `$cast`。自动 field 宏能实现基础字段复制，但复杂对象最好重写 `do_copy()` 明确语义。

**项目分析**

Monitor 每次创建新 txn 后才 `ap.write()`，当前队列保存句柄尚可。但如果为了性能复用 txn，scoreboard 必须 clone，否则所有队列元素可能最终指向同一笔数据。

### Q11：static property、向上/向下转型和 `$cast` 怎么解释？

**资深回答**

static property 属于类而不是实例，所有对象共享。派生类句柄赋给基类句柄是安全向上转型；基类转派生类需要运行时检查，使用 `$cast`，失败时返回 0。Factory `create()` 或 `clone()` 返回较宽类型时经常需要 `$cast`。

**文档扩展示例**

```systemverilog
axi_txn typed;
uvm_object obj = original.clone();
if (!$cast(typed, obj))
  `uvm_fatal("CAST", "clone type mismatch")
```

## 5. 约束随机

### Q12：`rand`/`randc`、`inside`、`dist`、inline constraint 怎么用？

**资深回答**

`rand` 每次按约束重新求解；`randc` 尽量在值域重复前遍历所有值，但复杂约束下周期行为需谨慎。`inside` 表示集合成员，`dist` 指定权重，`randomize() with {}` 添加本次调用的约束，并与 class constraints 一起求解，不是覆盖原约束。

**项目分析**

`axi_txn` 使用 `inside` 限制 len/size/边界地址。`axi_random_seq` 名称虽叫 random，却直接按 `i%2` 和 `i%4` 定向赋值，没有调用 randomize，本质是规则化 directed sequence。

### Q13：implication、`solve before`、soft constraint 有什么价值？

**资深回答**

- implication 用条件启用约束，例如 `kind==WRITE -> wdata.size()==len+1`；
- `solve A before B` 改变随机分布选择顺序，不改变合法解集合；
- soft constraint 给默认值，inline/hard constraint 可覆盖它，适合可配置 VIP 默认策略。

**文档扩展示例**

```systemverilog
constraint c_payload {
  kind == WRITE -> wdata.size() == len + 1;
  kind == READ  -> wdata.size() == 0;
}
constraint c_default { soft burst == 2'b01; }
constraint c_route_dist {
  solve addr before len;
  addr[15:12] dist {0:=1, 1:=1, 2:=1, 3:=1};
}
```

### Q14：如何开关 constraint/rand 字段？pre/post_randomize 做什么？

**资深回答**

`constraint_mode(0/1)` 控制约束块，`rand_mode(0/1)` 控制字段是否参与求解；`pre_randomize` 可准备求解状态，`post_randomize` 可派生非随机字段或做合法性检查，但不应悄悄修正一个已经非法的求解结果。

**项目分析**

项目的 boundary constraints 永久开启。普通随机场景应关闭专项约束，边界 sequence 再开启，否则覆盖空间被意外压缩。

### Q15：randomize 为什么失败？如何处理冲突？怎样约束数组、对齐和 4 KB 边界？

**资深回答**

失败通常来自约束无交集、数组 size/index 循环矛盾、溢出、函数副作用或 randc 状态。必须检查返回值并以 fatal 处理，逐块关闭约束定位冲突。常用约束：

```systemverilog
addr % (1 << size) == 0;
wdata.size() == len + 1;
(addr[11:0] + ((len + 1) << size)) <= 4096;
```

最后一个表达式还需考虑 FIXED/WRAP 和整数位宽，工程实现最好用辅助函数计算最后有效 byte address。

**项目分析**

`axi_concurrent_seq` 的 inline 地址集合与 `c_boundary_addr` 无交集；而且 `0100/0200/0400/0800` 全在 Slave 0。当前使用即时 `assert(randomize())`，失败后仍可能继续执行；应改为 `if (!randomize()) uvm_fatal`。

---

# 第二部分：UVM 核心机制

## 6. 整体架构与组件职责

### Q16：标准 UVM 平台有哪些组件？数据如何往返？

**问题含义**

考察你是否真正理解平台分层和独立检查路径。

**资深回答**

Test 配置场景；env 集成验证组件；active agent 包含 sequencer/driver/monitor；sequence 创建 item；sequencer 仲裁；driver 做 transaction-to-pin；monitor 做 pin-to-transaction；predictor/reference model 产生期望；scoreboard 比较；subscriber 收覆盖。激励链路和检查链路必须独立，否则 driver 发错时 checker 也可能沿用同一错误数据。

**项目分析**

[axi_env.sv](../components/axi_env.sv) 创建四组 master/slave agents、一个 scoreboard 和 coverage。Master monitor 同时连 scoreboard 与 coverage，Slave monitor 连 scoreboard，符合一对多分析拓扑。

### Q17：Active/passive agent 区别？Monitor 为什么独立于 Driver？

**资深回答**

Active agent 驱动协议，通常有 sequencer、driver、monitor；passive agent 不驱动，只保留 monitor/config。Monitor 必须从真实接口重建事务，不能接收 driver 的“意图”，否则无法发现 driver、连线或 DUT 对信号的破坏。

**项目分析**

`axi_mst_agent.is_active` 有默认值但没有从配置对象读取，实际无法由 test 灵活配置。Slave agent 的 driver 是 reactive responder，不消费 sequence；继承 `uvm_driver` 并非必须。

## 7. object/component

### Q18：`uvm_object` 与 `uvm_component`、sequence 与 sequencer 如何区分？

**资深回答**

Object 没有固定 topology，按需创建，构造函数无 parent；component 有层次、phase 和 parent。Transaction、sequence、config 是 object；test/env/agent/driver/monitor/sequencer 是 component。Sequence 生成激励算法，sequencer 是组件化仲裁和 TLM 接口。

**项目分析**

`axi_txn`、`axi_wr_seq`、`axi_slv_cfg` 使用 object utils；`axi_env`、agents、drivers 使用 component utils，整体选择正确。

## 8. Factory

### Q19：Factory 为什么存在？为什么 `create` 而不是 `new`？

**资深回答**

Factory 将请求的基类型与实际构造类型解耦。Type override 替换该类型的所有 factory 创建，instance override 只影响匹配路径；越具体的实例规则通常优先。Override 必须在目标对象创建前设置。调试时打印 factory、对象实际 type name 和 instance path。

**项目分析**

项目几乎全部使用 `type_id::create`，具备 override 基础，但没有实际 override test，所以面试不能声称“项目已用 override 完成错误注入”。错误注入当前来自 `axi_slv_cfg`。

**文档扩展示例**

```systemverilog
class bad_crc_axi_txn extends axi_txn;
  `uvm_object_utils(bad_crc_axi_txn)
  function new(string name="bad_crc_axi_txn"); super.new(name); endfunction
endclass

// 必须早于 sequence 创建 txn
axi_txn::type_id::set_type_override(bad_crc_axi_txn::get_type());
// 或 set_inst_override(..., "uvm_test_top.env.mst_agent0.*")
```

## 9. Phases

### Q20：常用 phase、遍历方向、function/task phase 和并发关系是什么？

**资深回答**

build 自顶向下，便于父组件先放配置再创建子组件；connect 通常自底向上，确保子结构存在后连接；end_of_elaboration/start_of_simulation 做结构检查和打印；run 及 reset/configure/main/shutdown 等 runtime phases 可耗时；extract/check/report/final 不耗时。结构 phase 完成后，各 component 的同一 runtime phase 并行执行。run 与 main 属于不同 phase domain 使用方式，项目应避免随意混用造成同步误解。

Phase jumping 是主动把 phase 调度跳到目标 phase，常用于异常恢复或重新复位；它会影响多个组件和未完成线程，必须配合 domain、objection、pending 清理使用，普通测试流程不要把它当 `goto`。

**项目分析**

env 在 build 创建 agent，在 connect 连接 analysis ports；test、drivers、monitors、responders 的 run_phase 并行。当前 test 文档注释中“run_phase 与其他 phase 并行”是不准确的。

## 10. Objection

### Q21：Objection、drain time、raise/drop 的边界是什么？

**资深回答**

Objection 表示某 task phase 仍有参与者，不是 transaction ack。所有 objection 清零后 phase 才准备结束；漏 raise 会提前结束，漏 drop 会挂死。Drain time 给最后一个 objection drop 后的固定排空窗口，但不能替代精确 pending 计数。通常由 test 或顶层 virtual sequence 管理，底层 sequence 自动 objection 容易在并发场景失控。

**项目分析**

具体 tests 成对 raise/drop，但大量使用 `#200` 等固定等待。因为当前 `sequence.start()` 等到 driver 完整响应，很多固定延迟没有必要；成熟环境应等待 scoreboard pending 清空或 phase_ready_to_end，而不是猜时间。

## 11. config_db

### Q22：config_db 的用途、参数、路径、时机和 resource_db 区别？

**资深回答**

`set(context, inst_path, field, value)` 将类型化配置放到层次范围，`get(this,"",field,value)` 按当前层次和优先级查找。常在父 build 前 set、子 build 中 get。路径过宽会串配置，过窄会 miss。config_db 是在 resource database 之上的层次化便利接口；普通 UVM 组件配置优先用 config_db。失败时打印 topology/config tracing，核对类型、字段、路径和 set/get 时间。

**项目分析**

顶层将八个 vif 设置给各 agent，agent 再下发给 driver/monitor；env 下发 master/slave ID 和 slave cfg。路径基于字符串，建议后续集中进 agent config，避免散落。

## 12. Sequence/Driver 握手

### Q23：四步握手、`get`、response、仲裁、lock/grab 怎么解释？

**资深回答**

`start_item` 请求 grant；`finish_item` 发送完成并等待 driver 的 item_done；driver 以 `get_next_item/item_done` 配对。`get` 会取走请求并完成 sequencer 侧握手，不能再 item_done。Driver 可 `item_done(rsp)` 或 `put_response(rsp)`，sequence 用 `get_response`，response 应设置 request ID。Sequencer 可配置 FIFO/random/weighted 等仲裁。`lock` 等当前持有者结束后获得连续访问权，`grab` 优先级更强、尽快插队；都要谨慎防止饥饿。

**项目分析**

Master driver 正确配对 `get_next_item/item_done`，但直接修改 request 保存 BID/RDATA，sequence 没显式取 response。因为 driver 等到完整 B/R 才 item_done，吞吐量被串行化。

## 13. Virtual sequence/sequencer

### Q24：为什么需要 virtual sequence？

**资深回答**

当一个场景需要协调多个物理 agent、reset、配置或 sideband 时，virtual sequence 负责场景级编排，virtual sequencer 保存各底层 sequencer 句柄。它本身通常不直接向 driver 发送协议 item。

**项目分析与文档扩展**

项目的多 master tests 直接访问 `env.mst_agent[i].sequencer`，规模小时可用，扩展性差。可仅在设计文档中规划：

```systemverilog
class axi_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(axi_virtual_sequencer)
  uvm_sequencer #(axi_txn) mst_sqr[4];
endclass

class all_master_vseq extends uvm_sequence;
  `uvm_object_utils(all_master_vseq)
  `uvm_declare_p_sequencer(axi_virtual_sequencer)
  task body();
    fork
      begin axi_wr_seq s0 = new("s0"); s0.start(p_sequencer.mst_sqr[0]); end
      begin axi_wr_seq s1 = new("s1"); s1.start(p_sequencer.mst_sqr[1]); end
    join
  endtask
endclass
```

## 14. TLM

### Q25：port/export/imp、blocking/nonblocking、analysis port/subscriber/FIFO 怎么区分？

**资深回答**

Port 表示调用需求，export 转发接口实现，imp 是最终实现。Blocking TLM 方法可以等待，nonblocking 立即返回成功与否。Analysis port 是一对多、无返回值的 function 广播；analysis imp 直接实现 write callback；subscriber 封装一个 analysis export 和纯虚 write；analysis FIFO 把同步 write 转成可由 task 阻塞 get 的队列。`write()` 不能耗时，接收者若长期保存对象应 clone。

**项目分析**

Driver `seq_item_port` 连 sequencer `seq_item_export`；monitor analysis port 连 scoreboard 两个 analysis imps 和 coverage subscriber。Scoreboard 当前在 write 中只做轻量计数/入队，适合 function；若实时配对两个异步来源，analysis FIFO 更清晰。

## 15. UVM RAL

### Q26：RAL 的 register/field/block/map、frontdoor/backdoor、adapter/predictor 是什么？

**问题含义**

即使本项目没有寄存器，面试官也在看你能否把寄存器抽象连接到总线 agent。

**资深回答**

- `uvm_reg_field` 描述字段访问属性和复位值；`uvm_reg` 聚合字段；`uvm_reg_block` 聚合寄存器和子块；`uvm_reg_map` 描述地址、总线宽度和 endian；
- frontdoor 通过真实总线访问，可验证 decode/协议但较慢；backdoor 通过 HDL path 直接访问，快但绕开总线；
- adapter 在 `uvm_reg_bus_op` 与 AXI transaction 间转换；predictor 根据 monitor 观察到的总线事务更新 mirror；
- explicit prediction 由 sequence/调用方主动 predict，implicit prediction 常由 map auto_predict；有独立 monitor 时推荐 predictor 避免“driver 意图等于实际发生”；
- desired 是模型希望写入的值，mirrored 是模型认为 DUT 当前值，实际硬件值需通过 read/peek 才知道。

### Q27：`read/write/peek/poke`、reset、volatile/W1C/RO/WO 如何回答？

**资深回答**

read/write 按 path 走 frontdoor 或 backdoor并更新 status/mirror；peek/poke 是直接 backdoor，不模拟访问策略。`model.reset()` 只重置模型镜像，不会自动复位 DUT。复位测试应先驱动 DUT reset，再 reset model，再 mirror/check。Volatile 表示值可能由硬件自行变化，预测策略要谨慎；W1C、RO、WO 由 field access policy 建模，并通过专门 sequence 验证副作用和非法访问。

**项目分析与文档扩展**

当前 Crossbar 没有 CSR，所以不应硬塞 RAL。若未来增加 route-mask 配置寄存器，可定义 `route_mask_reg`，adapter 把 32-bit reg operation 转成单拍 AXI txn，predictor连接 master monitor。面试要明确这是扩展方案，不是现有实现。

---

# 第三部分：Scoreboard 与验证方法学

## 16. Scoreboard/Reference Model

### Q28：Scoreboard 做什么？期望值从哪里来？

**问题含义**

考察检查闭环是否独立、可信。

**资深回答**

Scoreboard 接收 observed transactions，用规格驱动的 reference model 产生 expected，再比较身份、顺序、路径、数据、响应和数量。期望值不应来自 DUT 内部实现，也不应简单照抄 driver 结果。对 Crossbar，模型至少预测 address decode、base-address translation、ID 映射、response routing 和数据守恒。

**项目分析**

[axi_scoreboard.sv](../components/axi_scoreboard.sv) 已接收上下游 monitor，但当前只完整收集写；`exp_data` 写入后从未用于读比较，因此 T003 写后读没有真正检查。

### Q29：In-order/out-of-order scoreboard 如何设计？怎样发现丢失、重复、乱序？

**资深回答**

严格 in-order 可用 expected/actual FIFO 逐笔比较。允许乱序时按合法 matching key 建 pending queues，例如 `pending_read[master][id]`；同 ID 从队首取，允许不同 ID 独立完成。每笔 actual 必须恰好匹配一次，匹配后删除；结束时 expected 和 actual pending 均为空。重复 actual 会找不到期望，丢失 response 会留下 pending。

**文档扩展示例**

```systemverilog
axi_txn pending_rd[int /*master*/][bit[7:0] /*id*/][$];

function void expect_read(axi_txn t);
  axi_txn copied;
  if (!$cast(copied, t.clone()))
    `uvm_fatal("CLONE", "axi_txn clone failed")
  pending_rd[t.source_id][t.id].push_back(copied);
endfunction

function void check_read(axi_txn actual);
  if (pending_rd[actual.source_id][actual.rid].size() == 0)
    `uvm_error("UNEXPECTED_R", actual.convert2string())
  else begin
    axi_txn exp = pending_rd[actual.source_id][actual.rid].pop_front();
    // compare every beat, response and LAST
  end
endfunction
```

### Q30：Matching key 怎么选？为什么不能只比地址或 OKAY？

**资深回答**

Key 必须能在规格允许的并发下唯一关联事务，同时不能禁止合法乱序。常包含 source port、ID、同 ID 序号、目标 port、规范化地址、方向；payload 用于比较而不是作为唯一 key。只比地址会在重复访问时误配，只看 OKAY 会漏掉错路由、错数据、丢失和重复。

**项目分析**

当前按“地址 + 第一拍数据”匹配写事务：重复数据/地址会误配，burst 后续 beat 完全没参与 key/compare。

### Q31：Scoreboard 在 write 中比较还是用 FIFO？Reset 时怎么办？

**资深回答**

单源、无等待、顺序明确时可在 write 中处理；多来源到达次序不定或需要等待 expected 时，write 只 clone 入 FIFO，run task 负责配对。Reset 策略必须来自 spec：清空所有 pending，标记 aborted，决定 reference memory 是否清除，并忽略/报告 reset 边界上的残余 response。不能让 reset 前事务在 reset 后被误配。

**项目分析**

当前只在 check_phase 批量匹配，reset 时无任何 flush；reset test 即便有悬挂事务也可能空通过。

## 17. False pass/false fail

### Q32：什么是 false pass、false fail？如何证明 checker 有效？

**资深回答**

False pass 是 DUT 有错而测试通过，风险高于普通失败；false fail 是 DUT 正确但环境误报。Checker qualification 要做 mutation/negative testing：故意改地址、数据、LAST、ID、数量或 response，确认对应 checker 必然报错且错误分类准确。

**项目证据**

- 读计数有 4，但 `RD: 0 pass / 0 fail`；
- 3 笔 master/slave 写未匹配只报 warning；
- SVA 多次 `RLAST without RVALID`，UVM summary 仍为 0 error；
- 最终仍打印 PASS。

所以 warning 是否失败要按验证意图决定；“未匹配事务”属于核心正确性，不能只是 warning。`0/0` 是 vacuous pass，应配最小期望计数。

## 18. Verification Plan

### Q33：如何从 spec 提取验证点并定义 done？

**资深回答**

把每条需求拆成 feature、场景维度、激励方法、checker、assertion、coverage、目标 test 和验收条件，维护可追踪矩阵。Directed test 用于 bring-up、边界和精确错误注入；constrained random 用于组合空间和时序交互。Done 不是“用例都跑了”，而是需求检查闭环、回归无未解释失败、coverage closure、bug 状态和 waiver 审核完成。

### Q34：Coverage closure 和 exclusion 怎么做？

**资深回答**

Hole 需要分类：激励没产生、monitor 没采到、bin 定义错误、checker 不支持、设计不可达或配置禁用。只有有规格/结构证明的不可达项才能 exclusion，并记录原因、配置和评审。代码覆盖高而功能覆盖低说明场景不足；功能覆盖高而代码覆盖低可能存在未触发异常路径或不可达 RTL，两者都需分析，不能互相替代。

**项目分析**

[verification_plan.md](verification_plan.md) 列了 timeout、outstanding、B/R backpressure 等点，但对应环境并未形成有效激励或检查；这是“有计划/测试名，没有闭环”的典型案例。

---

# 第四部分：Functional Coverage

## 19. Covergroup 基础与高级选项

### Q35：covergroup、coverpoint、bin、cross 是什么？automatic/explicit bin 怎么选？

**资深回答**

Covergroup 是覆盖模型实例；coverpoint 对表达式分桶；bin 是需求等价类；cross 衡量维度组合。Automatic bins 适合简单完整值域探索，explicit bins 更能表达验证计划和边界。Cross 只应覆盖有业务意义且可控的组合，否则 bin explosion 会让数字失去解释性。

**项目分析**

[axi_coverage.sv](../components/axi_coverage.sv) 显式定义 kind/slave/master/len/size/resp，并交叉 master×slave、kind×len 等，基本结构合理。

### Q36：illegal_bins、ignore_bins、wildcard、transition bins 分别怎么用？

**资深回答**

- `illegal_bins` 表示采到即规格违规，但关键协议非法值更建议 assertion/reporting，避免工具处理差异；
- `ignore_bins` 从覆盖目标排除规格不要求或不可达组合；
- wildcard 对 X/Z 和掩码匹配要非常谨慎；
- transition bins 覆盖值序列，适合状态/响应转换，不适合无关联事务流乱采。

**文档扩展示例**

```systemverilog
cp_resp: coverpoint resp {
  bins okay   = {2'b00};
  bins exokay = {2'b01};
  bins slverr = {2'b10};
  bins decerr = {2'b11};
}
cp_burst: coverpoint burst {
  bins fixed = {0}; bins incr = {1}; bins wrap = {2};
  illegal_bins reserved = {3};
}
```

### Q37：`iff`/`with`、per-instance、weight/goal/at_least 是什么？

**资深回答**

`iff` 控制某次采样是否计入，不能把它当生成约束；`with` 过滤或构造 bins。`option.per_instance=1` 保留每个实例覆盖，适合四个 agent 分别检查；weight 影响总覆盖聚合，goal 定义目标百分比，at_least 定义 bin 至少命中次数。设置这些选项必须由验证计划驱动，不能为提高数字随意调权重。

### Q38：应该什么时候、采什么对象？Cross 爆炸怎么办？

**资深回答**

功能覆盖通常采 monitor 观察到的已完成或关键握手事务，而不是 sequence 意图；否则事务未真正到达 DUT 也会命中。采样点应与定义一致，例如请求覆盖在 address handshake，response 覆盖在完成时。Cross 爆炸可通过需求分解、条件采样、ignore bins、分层 covergroups 和只交叉关键等价类处理。

**项目分析**

项目 coverage 连接 master monitor，因此采到的是上游实际完成事务，这是优点。但 `cp_master` 从 ID 高 nibble 推断来源，而 monitor 已提供 `source_id`；ID policy 改变后 coverage 会错。`cp_resp` 只有 OKAY，错误测试无法闭环。

### Q39：功能覆盖 100% 为什么不代表完成？

**资深回答**

100% 只说明模型中定义的 bins 达标，不能证明模型完整、采样正确、checker 有效或 DUT 无错。还要结合 requirement traceability、scoreboard、SVA、代码/断言覆盖、bug closure 和多配置回归。

---

# 第五部分：SVA

## 20. 基本语义

### Q40：Immediate/concurrent assertion，sequence/property 有何区别？

**资深回答**

Immediate assertion 在过程执行点立即检查表达式；concurrent assertion 按采样时钟对跨周期行为求值。Sequence 描述时序模式，property 在 sequence 基础上表达蕴含、禁用等可断言性质。协议规则通常用 concurrent assertion，过程内部不变量可用 immediate assertion。

### Q41：`|->`、`|=>`、延迟范围、采样函数如何解释？

**资深回答**

`|->` 是 overlapped implication，consequent 从 antecedent 结束同周期开始；`|=>` 是 non-overlapped，从下一周期开始。`##0/##1/##[1:5]` 表示同周期、下一采样周期、1~5 周期窗口。`$rose/$fell` 判断采样值边沿，`$stable` 判断相邻采样不变，`$past` 取之前采样值；复位刚释放时使用 `$past` 要防止历史无效。

### Q42：`disable iff`、throughout/within/until、assert/assume/cover 有何含义？

**资深回答**

`disable iff` 在条件成立时异步终止当前 property attempts，常用于 reset。`throughout` 要求表达式贯穿某 sequence；`within` 要求一段 sequence 包含于另一段；`until` 表示保持到终止条件。仿真/形式中 assert 检查设计义务，assume 约束环境，cover 寻找可达场景；在动态仿真中误用 assume 可能没有预期效果。

## 21. 常见手写题

### Q43：如何写 VALID 稳定、payload 稳定和有限响应？

```systemverilog
ap_aw_hold: assert property (@(posedge aclk) disable iff (!aresetn)
  awvalid && !awready |=> awvalid &&
  $stable({awaddr, awid, awlen, awsize, awburst}));

ap_bounded_b: assert property (@(posedge aclk) disable iff (!aresetn)
  wvalid && wready && wlast |-> ##[1:32] bvalid);
```

资深回答要补一句：第二条 32 周期上界不是 AXI 协议本身规定，必须来自项目性能/超时规格，否则 checker 会人为限制合法 slave。

### Q44：FIFO、grant、LAST、reset 类断言怎么设计？

```systemverilog
ap_no_overflow : assert property (@(posedge clk) !(push && full));
ap_no_underflow: assert property (@(posedge clk) !(pop  && empty));
ap_grant_has_req: assert property (@(posedge clk) (|grant) |-> (|(grant & req)));
ap_onehot_grant : assert property (@(posedge clk) $onehot0(grant));
ap_reset_valid  : assert property (@(posedge aclk) !aresetn |-> !awvalid && !wvalid);
```

LAST 与 LEN 需要本地计数器或 assertion local variable，既检查提前 LAST，也检查最后拍缺失。不能只写 `rlast |-> rvalid` 就声称验证了 burst 长度。

**项目分析**

[axi_if.sv](../infra/axi_if.sv) 当前有 VALID hold 和 LAST implies VALID，但没有 payload stable、beat count、ID、4 KB、X 检查。

## 22. SVA 与 UVM 报告

### Q45：`$error` 是否增加 UVM_ERROR？断言怎样进入回归判定？

**资深回答**

不保证。`$error` 属于 simulator reporting，UVM report server 有独立计数。回归必须同时检查退出码、assertion summary、UVM severity、timeout 和 scoreboard；或者 assertion action block 调统一 UVM report，并配置 simulator 让 assertion failure 返回非零。

**项目证据**

现有 `sim.log` 多次报告 `RLAST without RVALID`，但最后 `UVM_ERROR: 0` 并打印 PASS，证明只解析 UVM summary 会 false pass。

---

# 第六部分：AXI 协议

## 23. 五通道与依赖关系

### Q46：五通道方向、拆分原因、独立性和 B 产生条件？

**资深回答**

- AW：master→slave 写地址；W：master→slave 写数据；B：slave→master 写响应；
- AR：master→slave 读地址；R：slave→master 读数据/响应；
- 地址、数据、响应解耦利于流水和 backpressure；
- AW/W 没有协议规定的固定先后，可先后或同周期；
- BVALID 只能在该写事务地址和全部写数据被接受后产生；
- 读写通道彼此独立，可以全双工并发。

**项目分析**

Master driver 固定 AW→W→B，并让读写共享一个串行 run loop，这是合法子集但没有覆盖通道独立性。Slave responder 用两个线程并行读写，较好体现全双工。

## 24. VALID/READY

### Q47：握手规则、依赖、稳定性、READY 常高和 backpressure 怎么回答？

**资深回答**

只有采样沿 `VALID&&READY` 才转移。源端不能等待 READY 才拉 VALID；目标端 READY 可以组合依赖 VALID，但要结合规范的禁止组合路径建议和系统死锁分析。VALID 未握手时自身和 payload 必须保持。READY 可常高以实现零等待接收；随机拉低 READY 形成 backpressure，源端仍必须保持数据。

**项目分析**

Slave cfg 只控制 AWREADY/WREADY/ARREADY；BREADY/RREADY 由 master 控制，当前 backpressure test 并未真正覆盖 B/R backpressure。

## 25. Burst/size/strobe

### Q48：LEN、SIZE、FIXED/INCR/WRAP、wrap boundary 和 4 KB 怎么解释？

**资深回答**

`beats=AxLEN+1`，`bytes_per_beat=2^AxSIZE`。FIXED 地址不变；INCR 每拍向前；WRAP 在对齐的 `beats×bytes_per_beat` 区域内回绕，WRAP 长度只能是 2、4、8 或 16 beats。AXI4 INCR 可达 256 beats，而当前项目 transaction 主动限制在 16 beats。所有 burst 不得跨 4 KB 边界，因为互连 decode 以 4 KB 为最小边界，跨界可能命中不同 slave/属性。

4 KB 可用起始和最后 byte 的高位判断：

```systemverilog
start_addr[ADDR_W-1:12] == last_byte_addr[ADDR_W-1:12]
```

### Q49：窄传输、byte lane、WSTRB、WLAST/RLAST 怎么处理？

**资深回答**

窄传输每拍有效字节小于总线宽，地址低位选择 byte lanes；WSTRB 每 bit 对应一个 WDATA byte，只有置位字节能修改 memory。WLAST 标识写 burst 最后一拍，RLAST 标识读最后一拍，必须与 LEN 计数一致。RRESP 每个读 beat 都有效，B 是整笔写的单个 response。

**项目分析**

Slave model 无视 WSTRB/SIZE，每拍固定写四字节并 `addr+=4`；所以当前 `axi_burst_size_test` 不能证明窄传输正确。Monitor 也不检查 LAST。

## 26. ID、Outstanding、乱序、Interleave

### Q50：四个概念有什么区别？同/不同 ID 顺序规则是什么？

**资深回答**

Outstanding 是有多个已发请求未完成；out-of-order 是完成顺序不同于发出顺序；interleaving 是不同事务的数据 beat 交错；ID 用于关联并定义 ordering domain。同 ID 通常必须保持协议要求的顺序，不同 ID 可乱序。AXI4 移除了 WID，不支持 AXI3 式写数据 interleaving；读数据可按不同 RID 在事务之间交错，但每个 burst 自身需要正确完成。

### Q51：如何验证 outstanding？Crossbar 为什么改 ID？

**资深回答**

波形必须在旧 B/R 完成前看到新 AW/AR handshake；driver、monitor、scoreboard 都要有 pending queues 和 ID-aware matching。Crossbar 汇聚多个 master 时，下游原始 ID 可能冲突，因此常扩展或编码 source port，response 返回时再恢复/路由。验证模型必须建 ID translation，不能假设上下游 ID 总相等。

**项目分析**

顶层为四个 master 配置不同 ID masks；coverage 又依赖 ID 高 nibble识别 master。当前 driver 等完整 response 后 item_done，不产生同 master outstanding；monitor 单一当前事务也无法观察它。

## 27. Response

### Q52：OKAY、EXOKAY、SLVERR、DECERR，以及错误恢复怎么解释？

**资深回答**

OKAY 是普通成功；EXOKAY 是成功的 exclusive access；SLVERR 表示已 decode 到 slave 但 slave 无法完成；DECERR 通常由 interconnect 表示没有合法目标。RRESP 每拍有效，B response 覆盖整笔写。错误后环境要检查错误是否原样路由、ID 正确、没有错误写污染模型、后续合法事务能继续完成。

**项目分析**

Slave cfg 能返回 SLVERR/DECERR，但 error test 对 Slave 0 配置错误率后访问 Slave 1/2 地址，注入没有作用到目标 responder。用 slave 返回 DECERR只能测传播，未必测 decode miss。

---

# 第八部分：Debug 与工程实践

> 编号沿用原问题分类；按要求跳过第七部分“数字电路基础”。

## 28. 仿真 Hang

### Q53：UVM 仿真 hang，如何区分 objection、协议死锁和线程未退出？

**问题含义**

面试官在看你是否有系统化定位能力，而不是只会开波形。

**资深回答**

先判断时间是否推进：时间不推进可能是 zero-time loop；时间推进但 phase 不结束，打印 objection trace/topology；driver 卡住则检查最后一次 `get_next_item`、各通道 VALID/READY 和 reset；sequence 卡在 `finish_item` 说明 driver 未 item_done；test 已 drop 但有 pending，说明结束策略错误。开启 `+UVM_OBJECTION_TRACE`、transaction recording 和定点 channel logs，设置分层 watchdog。

**项目分析**

Master driver 的 `do @(posedge); while(!ready/valid)` 没有 reset/timeout 退出。若 DUT 或 responder 不再拉握手，会一直阻塞。顶层 50 ms 全局 timeout 能终止仿真，但只能说明“挂了”，不能指出哪笔事务、哪个通道。

**文档扩展示例**

```systemverilog
fork
  begin wait (vif.bvalid && vif.bready); end
  begin
    repeat (100) @(posedge vif.aclk);
    `uvm_fatal("B_TIMEOUT", $sformatf("id=%0h addr=%0h", t.id, t.addr))
  end
  begin wait (!vif.aresetn); return; end
join_any
disable fork;
```

## 29. Randomize/config/driver Debug

### Q54：randomize 失败怎么定位？

**资深回答**

第一步永远检查返回值；打印当前约束模式和已固定 rand 字段；逐块 `constraint_mode(0)` 做二分定位；缩小 inline constraint；检查数组 size、溢出和函数约束；保存 test/seed/tool version。不要在失败后继续发送默认字段。

**项目分析**

`axi_concurrent_seq` 的边界 constraint 与 inline 地址集合冲突，是可直接复现的例子。

### Q55：config_db get 失败怎么定位？

**资深回答**

核对四件事：参数化类型完全一致、field string 一致、实际 component full path 匹配、set 发生在 get 之前。开启 `+UVM_CONFIG_DB_TRACE`，打印 topology，避免一开始用 `*` 掩盖路径错误。

**项目分析**

顶层 set 路径 `*.mst_agent0`，agent get 后再给 `driver/monitor` set。任何实例重命名都会影响匹配，配置对象化更稳健。

### Q56：Driver 收不到 item 怎么查？

**资深回答**

确认 test 被 factory 正确创建、sequence body 进入、start 的 sequencer 非 null、sequencer-driver port/export 已 connect、item 类型一致、sequence 没卡在 pre_body/仲裁/lock、driver run_phase 没被 reset/hang 阻塞。分别在 start_item、get_next_item 前后打 ID 日志能迅速定位断点。

**项目分析**

连接位于 master agent connect_phase：`driver.seq_item_port.connect(sequencer.seq_item_export)`。Slave responder 没有 sequencer，所以不应期待它收到 item。

## 30. Monitor/Scoreboard/X Debug

### Q57：Monitor 少采一拍怎么定位？

**资深回答**

以握手沿为唯一事实，对照 AWLEN/ARLEN、实际 beat count、LAST、reset 和 backpressure。检查 monitor sampling region 是否与 driver/DUT race；检查 monitor 是否因处理上一事务而漏掉新 address；对每个 channel 独立记录 handshake sequence number。

**项目分析**

当前 monitor 收到一笔 AW 后停止监听 AW 直到 B，所以 outstanding 时会漏后续 AW；它按 LEN 循环而不验证 LAST，也可能“采够数量但协议已错”。

### Q58：Scoreboard mismatch 先看哪里？

**资深回答**

先看第一笔 mismatch 的原始 observed input；确认 matcher key 和地址/ID translation；再查 predictor；随后对照上下游 monitor；最后才怀疑 DUT。要区分 DUT bug、BFM bug、monitor race、reference model bug和测试配置错误。

**项目分析**

basic log 中 master `0x1000/0x2000/0x3000` 对应 slave 都是 `0x0000`，这是 DUT 配置的 base removal，不是路由错误；scoreboard 未做规范化导致 false fail warning，随后又因 warning 不计 fail 形成 false pass。

### Q59：X 从哪里来，如何定位？

**资深回答**

从第一次出现 X 的时间和 fan-in 逆推，常见源包括未复位寄存器、未初始化 memory、越界访问、多驱动、case 漏分支、时钟/复位竞争。启用 X-prop、`$isunknown` assertion 和驱动追踪。不要简单把 transaction 用二态 bit 后宣称 X 消失。

**项目分析**

Slave 对未写地址直接读取关联数组，值的默认/工具行为需要明确；transaction 用 bit 还会吞掉接口 X。Reset test 又对顶层已驱动的复位变量二次过程赋值，可能引入调度竞争。

## 31. Seed、错误阶段和回归

### Q60：如何保存和重现 seed？修复后怎样回归？

**资深回答**

记录 test name、seed、RTL/TB commit、工具版本、编译/运行参数和配置。先用原 seed 验证修复，再跑相关 directed tests、局部多 seed、完整 regression，确认没有新 coverage hole 或性能退化。

### Q61：Compile、elaboration、runtime 错误有何区别？

**资深回答**

Compile 处理语法、类型和 package 依赖；elaboration 建 module/interface 层次、解析参数和端口；runtime 才执行 process/UVM phases。Factory 找不到 test 通常是运行/注册问题，端口宽度/参数实例化可能在 elaboration 暴露，约束失败和 assertion 是 runtime。

### Q62：回归脚本如何可靠判 PASS/FAIL？

**资深回答**

综合判定进程退出码、compile/elab 成功、UVM_FATAL/ERROR、simulator assertion failures、timeout、scoreboard final status、pending count和必要 coverage threshold。每个 test/seed 使用独立日志和 coverage DB，生成机器可读汇总；不能只 grep `TEST PASSED`。

**项目分析**

当前所有运行写同一 `sim.log`，VCS `-cm ... +func` 产生非法选项 warning，SVA failure 未进入 UVM count，回归可信度不足。

### Q63：如何减少波形并定位第一处异常？

**资深回答**

默认只 dump DUT 接口、仲裁状态、队列指针和错误相关层次；失败后按时间窗口/层次重跑增加信号。日志带 transaction ID、source、address、phase 和 cycle。按“激励→上游→DUT decode→下游→response→monitor→scoreboard”的因果链找第一处偏离，不从最终连锁报错倒推。

---

# 第九部分：AXI Crossbar 项目追问

## 32. 项目定位与架构

### Q64：为什么选择 Crossbar？核心验证难点是什么？

**资深回答**

Crossbar 同时包含协议、地址 decode、并发仲裁、response routing、ID/order、backpressure 和 reset，能展示从 transaction 到端到端 checker 的完整方法学。难点不是单笔读写，而是多端口竞争、不同通道独立、地址/ID translation、outstanding 和错误恢复的组合。

**项目证据**

DUT 是 4×4、四个地址窗口、每 master 配 ID mask 和路由 mask；环境也创建四组上游/下游 agents。

### Q65：Topology 怎么设计？为什么 master 有 sequencer、slave 可以没有？

**资深回答**

每个主动 master 需要 sequence 产生主动请求，所以有 sequencer/driver；slave responder 是看到 DUT 请求后反应，不需要预先从 sequence 取完整请求，可由配置对象控制 latency/error/backpressure。两侧 monitor 独立观察，集中进 scoreboard/coverage。

**项目分析**

当前 slave responder 虽继承 `uvm_driver#(axi_txn)`，但不使用 `seq_item_port`，语义上是 reactive component。

### Q66：地址如何映射？为什么删除 base？Scoreboard 如何匹配？

**资深回答**

上游全局地址高 nibble选择 4 KB window；`KEEP_BASE_ADDR=0` 时下游设备看到相对自身窗口的局部地址，有利于复用相同 slave IP。Scoreboard 先 decode `target_slave`，再计算 `local_addr=global-base[target]`，按 target+local address 对应下游事务。

**项目证据**

RTL `axicb_mst_if.sv` 明确执行 `awaddr-BASE_ADDR`；现 scoreboard 直接比较全局/局部地址，是已确认缺陷。

## 33. 仲裁、Outstanding 和顺序

### Q67：如何验证多 master 同 slave 仲裁和公平性？

**资深回答**

让所有 master 对同一 slave持续发请求，记录 request eligible 到 grant/handshake 延迟，检查 mutual exclusion、无请求不授权、数据不串、每个持续请求在规定窗口内获得服务。Round-robin 公平性不能只看四笔都完成，要在持续压力、不同 backpressure 下统计最大等待和服务比例。

**项目分析**

`axi_same_slave_test` 提供了基本竞争激励，但当前 scoreboard matcher 和数量检查不足，也没有 fairness coverage/assertion。

### Q68：当前项目真的支持 outstanding 吗？如何验证不同 ID 乱序？

**资深回答**

不支持同一 master 真 outstanding：driver 在 B/R 完成后才 item_done，第二个地址请求不会提前握手；monitor 也只有单笔上下文。改造需请求/响应线程解耦、pending queues、response path 和 ID-aware scoreboard。乱序验证要给不同 ID 请求配置不同响应延迟，并证明完成次序翻转且同 ID 仍保序。

## 34. Backpressure、错误和 Reset

### Q69：如何模拟 backpressure？

**资深回答**

对 DUT 输入端的 READY/VALID 分角色控制：slave responder 随机/定向拉低 AWREADY/WREADY/ARREADY；master driver 拉低 BREADY/RREADY。必须覆盖连续低、单周期抖动、LAST beat 和响应边界，并用 assertion 检查源端 payload stable。

**项目分析**

现 cfg 只有 AW/W/AR，test 的 B/R backpressure 名称没有实际控制对应信号。

### Q70：如何注入 SLVERR/DECERR并验证恢复？

**资深回答**

按目标 slave 精确配置响应，保存预期错误上下文；检查错误 code/ID/路由正确、错误事务不污染期望 memory、所有 pending 正确退休，再发送合法写读证明恢复。DECERR decode 测试应访问未映射地址并由 interconnect 产生，与 slave 主动返回 DECERR 的传播测试区分。

**项目分析**

当前 error test 配置 Slave 0 却访问 Slave 1/2，目标错位；scoreboard 又把所有非 OKAY 写计为 `wr_fail`，无法区分 expected error 与 unexpected error。

### Q71：如何验证传输中 reset？

**资深回答**

在 AW 后、W 中间、等待 B、AR 后、R 中间分别复位。检查 VALID/READY 回到复位值、pending 被 abort/flush、monitor 不拼接跨 reset 事务、scoreboard 按规格清 memory/状态、释放后重新发请求能完成。Reset 只能有一个受控驱动源。

**项目分析**

当前 test 从 class 写 `vif.aresetn`，同时顶层 always 也写同一变量；drivers/monitors 没 reset abort 路径，所以该 test 不能作为成熟 reset 验证。

## 35. Reference model、Monitor、Coverage

### Q72：如何做写后读 reference memory，处理 WSTRB？

**资深回答**

用 byte-addressed associative array；每个 beat 根据 burst/size 得到地址，根据 WSTRB 逐 byte 提交；错误 response 是否提交依 spec。读时按地址/lane重组每拍 expected RDATA，并逐拍比较 RRESP/RID/RLAST。

**项目分析**

Slave model 和 scoreboard 都固定每拍 4 byte，scoreboard 写入整 word，且不读出比较，是优先级最高的修复。

### Q73：Monitor 如何重组五个独立通道？

**资深回答**

每 channel 独立采样：AW queue、按顺序组 W packet、B 按 BID 完成；AR 按 ID 入 pending、R 按 RID 累积到 RLAST。写地址/数据关联还要遵循 AXI4 无 WID 的顺序规则。Reset 时原子清空或标记全部上下文。

### Q74：如何制定和收敛覆盖？

**资深回答**

从 vplan 建 master×slave、kind×len×size、response、burst、竞争、backpressure depth、outstanding depth、ID reorder、reset point 等模型；每个 bin 绑定 checker。回归后分类 hole，增加合法激励或批准 exclusion。

**项目分析**

现有基础 cross 合理，但没有错误 response、真实 outstanding/backpressure/reset coverage；README 和 vplan 数字也不一致，必须重新从 coverage DB 核验。

## 36. 项目反思

### Q75：当前环境最大不足、发现的 false pass、如何重构？

**资深回答模板**

> 最大问题不是组件缺失，而是检查闭环不可信。读数据没有比较、unmatched 只 warning、地址 translation 未建模、SVA failure 未纳入 UVM/回归结果；driver/monitor 又不支持宣称的 outstanding。我会先修 scoreboard 和统一 pass/fail，再修随机/测试配置，之后做 byte-accurate model，最后重构 channel-parallel driver/monitor 和 ID pending queues。优先修 checker，是因为激励再丰富，如果错误不能被可靠发现，覆盖数字没有意义。

这也回答了“如果重做一次”的问题：先建立 executable vplan、统一 config、channel BFMs、predictor/scoreboard 和 result qualification，再扩展 tests。

---

# 第十部分：十五题面试速答

> 以下不是替代前文，而是训练 30～60 秒回答。面试官追问时再展开项目证据。

### Q76：UVM 数据流？

Test 配置 env 并启动 sequence；sequence 创建 item；sequencer 仲裁；driver 转 pin；monitor 从实际接口重建 transaction；reference model/scoreboard 比较；coverage 订阅实际事务。本项目四组 master/slave agents，两侧 monitor 汇入集中 scoreboard。

### Q77：Object 与 Component？

Object 无固定层次、按需创建，如 txn/sequence/cfg；component 有 parent、topology 和 phases，如 env/agent/driver。对应使用 object/component factory registration 宏。

### Q78：Factory 与 override？

Factory 让请求类型与实际类型解耦；type override 全局替换，instance override 按路径替换；必须在 create 前设置。本项目使用 factory create，但还没有真实 override 场景。

### Q79：Phases 与 objection？

Build 创建和配置，connect 连 TLM，runtime phases 并行耗时，check/report 收尾。Objection只控制 phase 结束，不是 transaction ack。本项目用固定 `#200` 排空，建议改成 pending 清零。

### Q80：config_db 与 virtual interface？

顶层 module 实例化真实 interface，通过类型化 config_db 按层次传 virtual handle 给 class driver/monitor。本项目从 tb→agent→driver/monitor 两级传递。

### Q81：Sequence-driver 四步握手？

`start_item→finish_item` 对应 `get_next_item→item_done`。Finish 返回的精确业务含义取决于 driver 何时 item_done；本项目等完整 response，因此天然串行。

### Q82：Analysis port 与 analysis FIFO？

Analysis port 是一对多 function 广播、无 backpressure；FIFO 把同步 write 解耦成 task 可阻塞 get。长期保存对象要 clone。

### Q83：Scoreboard/reference model？

由规格独立预测期望，按 ID/source/order匹配 actual，逐 beat 比数据/响应，结束检查 pending 为空。本项目需补 base translation、WSTRB byte model 和读比较。

### Q84：功能覆盖与代码覆盖？

功能覆盖回答需求场景是否发生，代码覆盖回答 RTL 结构是否执行；两者均不证明结果正确，必须结合 checker/SVA 和 coverage closure。

### Q85：SVA `|->`、`|=>`、`disable iff`？

前两者分别为同周期开始和下一周期开始的蕴含；`disable iff` 在 reset 等条件下终止 property attempts。项目 SVA 还缺 payload stable 和 LAST beat count。

### Q86：阻塞/NBA 与仿真调度？

Blocking 当前区域立即更新；NBA 延后统一提交，适合触发器并行采样。TB/DUT 同沿仍可能 race，clocking block 才能明确采样/驱动 skew。

### Q87：AXI 五通道和握手？

AW/W/B 写，AR/R 读；各 channel 以 VALID&&READY 在采样沿完成，源端 VALID 不依赖 READY，等待时 payload 稳定；AW/W 可任意先后。

### Q88：Burst、SIZE、WSTRB、4 KB？

beats=LEN+1，bytes/beat=2^SIZE；FIXED/INCR/WRAP决定地址；WSTRB逐 byte 生效；比较首尾 byte 的 `[...:12]` 防跨 4 KB。项目当前固定 `addr+=4`，窄传输模型不正确。

### Q89：Outstanding、乱序和 ID？

Outstanding 是多个未完成请求，乱序是完成顺序翻转，ID 用于关联和 ordering domain。验证要在旧响应前看到新地址握手，并按 ID pending queue 比较；项目当前不是真 outstanding。

### Q90：项目 false pass 与修复优先级？

读不比较、unmatched 只 warning、base translation 漏建模、SVA 不计 UVM error。先让 checker 和回归判定可信，再扩激励、协议精度和 outstanding，否则覆盖越高只会放大虚假的信心。

---

# 附录：面试表达检查表

每个回答尽量包含四句话：

1. 一句准确的定义；
2. 一句为什么需要它；
3. 一句边界或常见误区；
4. 一句本项目证据。

例如回答 outstanding：

> Outstanding 是一个接口在旧事务完成前继续接受新请求，不等于多个 sequence 同时 start。要支持它，driver 必须把请求发送和 response 回收解耦，monitor/scoreboard 按 ID 保存 pending。本项目原始 driver 等 B/R 后才 item_done，所以同一 master 仍是串行；我通过检查 AW/AR 与前一 B/R 的波形关系确认这一点。

不要把文档中的扩展示例说成已经实现。只有源码修改、定向故障注入和回归结果都完成后，才能说“已经验证”。
