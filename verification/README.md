# AXI Crossbar UVM Verification

## 目录结构

```
verification/
├── env/
│   ├── axi_if.sv                # AXI4 Interface + SVA
│   └── axi_pkg.sv              # UVM Package（include 所有组件）
├── components/                  # UVM 组件
│   ├── axi_slv_cfg.sv          # Slave 配置（错误注入、背压）
│   ├── axi_txn.sv              # Transaction
│   ├── axi_mst_drv.sv          # Master Driver
│   ├── axi_slv_drv.sv          # Slave Driver (Memory Model)
│   ├── axi_monitor.sv          # Monitor
│   ├── axi_scoreboard.sv       # Scoreboard（性能统计）
│   ├── axi_coverage.sv         # Coverage
│   └── axi_env.sv              # Environment
├── sequences/                   # UVM 序列
│   ├── axi_wr_seq.sv           # Write Sequence
│   ├── axi_rd_seq.sv           # Read Sequence
│   ├── axi_burst_wr_seq.sv     # Burst Write Sequence
│   ├── axi_burst_rd_seq.sv     # Burst Read Sequence
│   ├── axi_burst_size_seq.sv   # Burst Size Sequence
│   ├── axi_outstanding_read_seq.sv  # Outstanding Read
│   ├── axi_same_slave_seq.sv   # Same Slave Contention
│   ├── axi_interleave_seq.sv   # Read/Write Interleave
│   ├── axi_concurrent_seq.sv   # Concurrent Read/Write
│   ├── axi_err_inject_seq.sv   # Error Injection
│   ├── axi_boundary_seq.sv     # Boundary Test
│   ├── axi_backpressure_seq.sv # Backpressure Test
│   ├── axi_random_seq.sv       # Random Test
│   └── axi_perf_seq.sv         # Performance Test
├── tests/                       # 测试用例（27 个）
│   ├── axi_base_test.sv        # Base Test + Helper Tasks
│   ├── axi_basic_test.sv       # T001-T003
│   ├── axi_routing_test.sv     # T010-T018
│   ├── axi_protocol_test.sv    # T020-T023
│   ├── axi_burst_size_test.sv  # T024-T026
│   ├── axi_outstanding_test.sv # T030
│   ├── axi_outstanding_read_test.sv # T031
│   ├── axi_multi_master_test.sv # T040
│   ├── axi_same_slave_test.sv  # T041
│   ├── axi_interleave_test.sv  # T042
│   ├── axi_err_slverr_test.sv  # T050
│   ├── axi_err_decerr_test.sv  # T051
│   ├── axi_err_recovery_test.sv # T053
│   ├── axi_boundary_addr_test.sv # T060
│   ├── axi_boundary_burst_test.sv # T061
│   ├── axi_boundary_ostd_test.sv # T063
│   ├── axi_bp_wready_test.sv   # T070
│   ├── axi_bp_bready_test.sv   # T071
│   ├── axi_bp_rready_test.sv   # T072
│   ├── axi_bp_all_test.sv      # T073
│   ├── axi_reset_wr_test.sv    # T080
│   ├── axi_reset_rd_test.sv    # T081
│   ├── axi_reset_recovery_test.sv # T082
│   ├── axi_random_test.sv      # T090
│   ├── axi_random_concurrent_test.sv # T091
│   ├── axi_perf_latency_test.sv # T100
│   └── axi_perf_bandwidth_test.sv # T101
├── tb/
│   └── axi_crossbar_tb.sv      # TB Top（DUT + config_db）
├── docs/
│   └── verification_plan.md    # 测试点分解
├── Makefile
├── filelist.f
└── README.md
```

## 编译顺序

```
axi_if.sv → axi_pkg.sv → axi_crossbar_tb.sv
```

interface → package → module，保证 virtual interface 类型对 package 可见。
package 内部通过 `include 引入 components/、sequences/、tests/ 下的所有文件。

## UVM 架构

```
axi_crossbar_tb
  └── axi_env
        ├── axi_mst_drv[0..3]    # Master drivers（config_db vif）
        ├── axi_slv_drv[0..3]    # Slave drivers（内存模型 + 错误注入）
        ├── axi_monitor[0..3]    # Master 侧 monitors
        ├── axi_monitor[0..3]    # Slave 侧 monitors
        ├── uvm_sequencer[0..3]
        ├── axi_scoreboard       # 写数据校验 + 读回比对 + 性能统计
        └── axi_coverage         # 路由交叉覆盖率
```

## 测试用例（27 个）

### 基础功能（9 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_basic_test` | 写 4 slave + 读回验证 | T001-T003 |
| `axi_routing_test` | 7 条路由路径 | T010-T018 |
| `axi_protocol_test` | 变长 burst (len=0/3/7/15) | T020-T023 |
| `axi_burst_size_test` | 变长 size (1B/2B/4B) | T024-T026 |
| `axi_outstanding_test` | 4 个 outstanding 写 | T030 |
| `axi_outstanding_read_test` | 4 个 outstanding 读 | T031 |
| `axi_multi_master_test` | 4 master 并发 | T040 |
| `axi_same_slave_test` | 2 master 写同一 slave | T041 |
| `axi_interleave_test` | 读写交织 | T042 |

### 错误注入（3 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_err_slverr_test` | SLVERR 响应 | T050 |
| `axi_err_decerr_test` | DECERR 响应 | T051 |
| `axi_err_recovery_test` | 错误后恢复 | T053 |

### 边界条件（3 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_boundary_addr_test` | 边界地址访问 | T060 |
| `axi_boundary_burst_test` | 最大 burst 长度 | T061 |
| `axi_boundary_ostd_test` | 最大 outstanding | T063 |

### 背压测试（4 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_bp_wready_test` | W 通道背压 | T070 |
| `axi_bp_bready_test` | B 通道背压 | T071 |
| `axi_bp_rready_test` | R 通道背压 | T072 |
| `axi_bp_all_test` | 全通道背压 | T073 |

### Reset 测试（3 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_reset_wr_test` | 写传输中复位 | T080 |
| `axi_reset_rd_test` | 读传输中复位 | T081 |
| `axi_reset_recovery_test` | 多次复位循环 | T082 |

### 随机测试（2 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_random_test` | 100+ 随机事务 | T090 |
| `axi_random_concurrent_test` | 4 master 并发随机 | T091 |

### 性能测试（2 个）
| 测试 | 描述 | 测试点 |
|------|------|--------|
| `axi_perf_latency_test` | 延迟测量 | T100 |
| `axi_perf_bandwidth_test` | 带宽测量 | T101 |

## 运行

```bash
cd verification
make compile SIM=vcs              # 编译
make sim SIM=vcs UVM_TEST=axi_basic_test  # 运行单个测试
make regression SIM=vcs           # 全部回归 + 覆盖率
make clean                        # 清理
```

## 覆盖率目标

| 指标 | 目标 |
|------|------|
| 功能覆盖率 | >95% |
| 代码覆盖率 | >95% |
| 路由覆盖 (4×4) | 16/16 |
| burst 长度覆盖 | 0-15 |
| burst size 覆盖 | 0-2 |
| 错误响应覆盖 | SLVERR + DECERR |
| 背压覆盖 | 全通道 |
