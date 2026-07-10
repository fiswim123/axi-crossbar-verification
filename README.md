# AXI Crossbar 验证项目

## 项目概述

这是一个4x4 AXI Crossbar模块的完整验证环境，采用企业级数字IC验证流程。

## 设计规格

| 参数 | 值 |
|------|-----|
| 主接口数量 | 4 |
| 从接口数量 | 4 |
| 地址宽度 | 16-bit |
| ID宽度 | 8-bit |
| 数据宽度 | 32-bit |
| AXI协议 | AXI4 |

### 地址映射

| 从接口 | 起始地址 | 结束地址 | 大小 |
|--------|----------|----------|------|
| SLV0   | 0x0000   | 0x0FFF   | 4KB  |
| SLV1   | 0x1000   | 0x1FFF   | 4KB  |
| SLV2   | 0x2000   | 0x2FFF   | 4KB  |
| SLV3   | 0x3000   | 0x3FFF   | 4KB  |

## 目录结构

```
axi_crossbar/
├── src/                          # RTL源代码
│   ├── axicb_crossbar_top.sv    # Crossbar顶层
│   ├── axicb_switch_top.sv      # Switch顶层
│   ├── axicb_slv_switch.sv      # Slave Switch
│   ├── axicb_mst_switch.sv      # Master Switch
│   ├── axicb_round_robin.sv     # Round Robin仲裁器
│   ├── axicb_pipeline.sv        # Pipeline模块
│   └── ...
├── verification/                 # 验证环境
│   ├── agents/                  # 验证组件
│   │   ├── axi_interface.sv     # AXI接口定义
│   │   ├── axi_transaction.sv   # 事务类
│   │   ├── axi_mst_agent.sv     # Master Agent
│   │   └── axi_slv_agent.sv     # Slave Agent
│   ├── env/                     # 验证环境
│   │   └── axi_scoreboard.sv    # 记分板
│   ├── coverage/                # 覆盖率
│   │   └── axi_coverage.sv      # 覆盖率收集器
│   ├── tests/                   # 测试用例
│   │   └── axi_test_list.sv     # 测试库
│   ├── tb/                      # 测试平台
│   │   └── axi_crossbar_tb.sv   # 测试平台
│   ├── docs/                    # 文档
│   │   └── verification_plan.md # 验证计划
│   ├── Makefile                 # 构建脚本
│   └── README.md                # 使用说明
├── verify.sh                    # 主验证脚本
├── run_verification.sh          # 运行验证
└── README.md                    # 本文件
```

## 快速开始

### 前提条件

- SystemVerilog仿真器 (VCS, Xcelium, ModelSim, 或 Icarus Verilog)
- Make工具
- Bash shell

### 运行验证

```bash
# 检查环境
./verify.sh check

# 运行快速验证
./run_verification.sh

# 运行完整测试套件
cd verification
./run_tests.sh -s vcs -t all

# 使用Makefile
make all SIM=vcs
```

### 查看波形

```bash
gtkwave axi_crossbar_tb.vcd &
```

## 验证计划

### 测试场景 (62个测试用例)

1. **基础功能测试** (4个)
   - 复位测试、单次读写、写后读验证

2. **路由测试** (5个)
   - 各主接口到所有从接口路由、地址边界

3. **仲裁测试** (3个)
   - Round Robin、优先级、竞争

4. **并发测试** (4个)
   - 多主多从并发、混合读写、压力测试

5. **协议测试** (4个)
   - 突发长度/大小、Outstanding、连续事务

6. **边界测试** (4个)
   - 最小/最大地址、地址回绕、满Outstanding

7. **异常测试** (3个)
   - 事务期间复位、反压测试

### 覆盖率目标

- 功能覆盖率: > 95%
- 代码覆盖率: > 90%
- FSM覆盖率: 100%

## 验证组件

### 1. AXI Interface
- 完整的AXI信号定义
- Clocking Block用于同步
- SVA协议检查断言

### 2. AXI Transaction
- 随机化事务生成
- 支持所有AXI参数
- 地址对齐约束

### 3. AXI Master/Slave Agent
- 事务驱动和监控
- 支持突发传输
- 统计和跟踪

### 4. AXI Scoreboard
- 地址路由验证
- 数据完整性检查
- 顺序检查

### 5. AXI Coverage
- 功能覆盖率收集
- 交叉覆盖率
- 覆盖率报告

## 文档

- [验证计划](verification/docs/verification_plan.md)
- [使用说明](verification/README.md)
- [验证总结](VERIFICATION_SUMMARY.md)
- [完成报告](VERIFICATION_COMPLETE.md)

## 工具支持

### 仿真工具
- Synopsys VCS
- Cadence Xcelium
- Mentor ModelSim
- Icarus Verilog (开源)

### 调试工具
- GTKWave
- Verdi
- DVE

## 贡献

欢迎提交Issue和Pull Request！

## 许可证

MIT License

## 联系方式

如有问题，请提交Issue或联系维护者。

---

**项目状态**: 验证环境已完成，待进一步调试和优化
