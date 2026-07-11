# AXI Crossbar UVM 验证环境

4×4 AXI4 Crossbar 的 UVM 验证平台，28 个测试用例全部走标准 `test → sequence → sequencer → driver → interface` 链路。

## 设计规格

| 参数 | 值 |
|------|-----|
| 主/从接口 | 4 × 4 |
| 数据宽度 | 32-bit |
| 地址宽度 | 16-bit |
| ID 宽度 | 8-bit |
| 协议 | AXI4 |

### 地址映射

| Slave | 起始地址 | 结束地址 |
|-------|---------|---------|
| SLV0  | 0x0000  | 0x0FFF  |
| SLV1  | 0x1000  | 0x1FFF  |
| SLV2  | 0x2000  | 0x2FFF  |
| SLV3  | 0x3000  | 0x3FFF  |

## 目录结构

```
axi_crossbar/
├── src/                            # RTL
│   ├── axicb_crossbar_top.sv       # Crossbar 顶层
│   ├── axicb_switch_top.sv         # Switch 顶层
│   ├── axicb_slv_switch*.sv        # Slave Switch
│   ├── axicb_mst_switch*.sv        # Master Switch
│   ├── axicb_round_robin*.sv       # Round Robin 仲裁
│   ├── axicb_pipeline.sv           # Pipeline
│   └── axicb_scfifo*.sv            # 同步 FIFO
└── verification/                   # UVM 验证环境
    ├── env/
    │   ├── axi_if.sv               # AXI4 Interface + SVA
    │   └── axi_pkg.sv              # Package（include 所有组件）
    ├── components/                 # UVM 组件
    │   ├── axi_txn.sv              # Transaction（约束随机 + 延迟统计）
    │   ├── axi_mst_drv.sv          # Master Driver
    │   ├── axi_slv_drv.sv          # Slave Driver（内存模型 + 错误注入 + 背压）
    │   ├── axi_monitor.sv          # Monitor（写/读通道采集）
    │   ├── axi_scoreboard.sv       # Scoreboard（数据校验 + 性能统计）
    │   ├── axi_coverage.sv         # Coverage（路由交叉 + burst 类型）
    │   ├── axi_slv_cfg.sv          # Slave 配置（错误率、背压率、延迟）
    │   └── axi_env.sv              # Environment（4 MST + 4 SLV + 4 SQR）
    ├── sequences/                  # 15 个 UVM Sequence
    ├── tests/                      # 28 个 Test
    ├── tb/
    │   └── axi_crossbar_tb.sv      # Testbench Top
    ├── docs/
    │   ├── uvm_tutorial.md         # UVM 入门教程
    │   └── verification_plan.md    # 测试点分解
    └── Makefile
```

## UVM 架构

```
axi_crossbar_tb
  └── axi_env
        ├── axi_mst_drv[0..3]      ──→  sequencer[0..3]  ←──  sequence
        ├── axi_slv_drv[0..3]       (内存模型 + 背压 + 错误注入)
        ├── axi_monitor[0..3]       (MST 侧)  ──→  scoreboard + coverage
        ├── axi_monitor[0..3]       (SLV 侧)
        ├── axi_scoreboard          (写存读比 + 延迟统计)
        └── axi_coverage            (路由/类型/长度交叉覆盖)
```

## 测试用例（28 个）

| 类别 | 测试 | 描述 |
|------|------|------|
| **基础** | `axi_basic_test` | 写 4 slave + 读回验证 |
| | `axi_routing_test` | 多 master 多 slave 路由 |
| | `axi_protocol_test` | 变长 burst (len=0/3/7/15) |
| | `axi_burst_size_test` | 变长 size (1B/2B/4B) |
| | `axi_outstanding_test` | 流水线 outstanding 写 |
| | `axi_outstanding_read_test` | outstanding 读 |
| | `axi_multi_master_test` | 4 master 并发写 |
| | `axi_same_slave_test` | 多 master 写同一 slave |
| | `axi_interleave_test` | 读写交织 |
| | `axi_full_routing_test` | 补全路由交叉覆盖 |
| **错误注入** | `axi_err_slverr_test` | SLVERR 响应 |
| | `axi_err_decerr_test` | DECERR 响应 |
| | `axi_err_recovery_test` | 错误后恢复 |
| **边界** | `axi_boundary_addr_test` | 边界地址访问 |
| | `axi_boundary_burst_test` | 最大 burst 长度 |
| | `axi_boundary_ostd_test` | 最大 outstanding 深度 |
| **背压** | `axi_bp_wready_test` | W 通道背压 |
| | `axi_bp_bready_test` | B 通道背压 |
| | `axi_bp_rready_test` | R 通道背压 |
| | `axi_bp_all_test` | 全通道背压 |
| **复位** | `axi_reset_wr_test` | 写传输中复位 |
| | `axi_reset_rd_test` | 读传输中复位 |
| | `axi_reset_recovery_test` | 多次复位循环恢复 |
| **随机** | `axi_random_test` | 100+ 随机事务 |
| | `axi_random_concurrent_test` | 4 master 并发随机 |
| **性能** | `axi_perf_latency_test` | 延迟测量 |
| | `axi_perf_bandwidth_test` | 带宽测量 |

## 运行

```bash
cd verification

# 编译
make compile SIM=vcs

# 运行单个测试
make sim SIM=vcs UVM_TEST=axi_basic_test

# 运行指定测试（简写）
make test_basic SIM=vcs
make test_routing SIM=vcs

# 全部回归
make regression SIM=vcs

# 清理
make clean
```

## 覆盖率

全回归 28 个测试结果：

| 指标 | 值 |
|------|-----|
| 功能覆盖率 | **98.12%** |
| 代码覆盖率 (LINE) | 71% |
| 代码覆盖率 (BRANCH) | 62% |

功能覆盖点：

| 覆盖点 | 说明 | 结果 |
|--------|------|------|
| `cp_kind` | 读/写 | 100% |
| `cp_slave` | 4 个 slave | 100% |
| `cp_master` | 4 个 master | 100% |
| `cp_len` | burst 长度 | 100% |
| `cp_size` | burst size | 100% |
| `cx_routing` | master × slave 路由交叉 | 81.25% (13/16) |
| `cx_kind_len` | 读写 × 长度 | 100% |
| `cx_kind_size` | 读写 × size | 100% |
| `cx_kind_slave` | 读写 × slave | 100% |
