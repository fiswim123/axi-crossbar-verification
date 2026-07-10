# AXI Crossbar 验证环境

## 概述

这是一个完整的AXI Crossbar验证环境，用于验证4x4 AXI交叉开关模块的功能正确性。

## 目录结构

```
verification/
├── agents/               # 验证组件
│   ├── axi_interface.sv # AXI接口定义
│   ├── axi_transaction.sv # 事务类
│   ├── axi_mst_agent.sv # 主接口Agent
│   └── axi_slv_agent.sv # 从接口Agent
├── env/                  # 验证环境
│   └── axi_scoreboard.sv # 记分板
├── coverage/            # 覆盖率收集
│   └── axi_coverage.sv
├── tests/               # 测试用例
│   └── axi_test_list.sv
├── tb/                  # 测试平台
│   └── axi_crossbar_tb.sv
├── docs/                # 文档
│   └── verification_plan.md
├── Makefile             # 构建脚本
├── filelist.f           # 文件列表
├── run_tests.sh         # 测试运行脚本
└── run_quick_test.sh    # 快速测试脚本
```

## 快速开始

### 前提条件

- SystemVerilog仿真器 (VCS, Xcelium, ModelSim, 或 Icarus Verilog)
- Make工具
- Bash shell

### 运行快速测试

```bash
# 进入验证目录
cd verification

# 运行快速测试
./run_quick_test.sh
```

### 运行完整测试套件

```bash
# 使用VCS
./run_tests.sh -s vcs -t all

# 使用Xcelium
./run_tests.sh -s xcelium -t all

# 使用Makefile
make all SIM=vcs
```

### 运行特定测试

```bash
# 运行冒烟测试
./run_tests.sh -s vcs -t smoke_test

# 运行地址路由测试
./run_tests.sh -s vcs -t address_routing_test

# 运行并发测试
./run_tests.sh -s vcs -t concurrent_access_test
```

### 带覆盖率运行

```bash
./run_tests.sh -s vcs -t all -c
```

### GUI模式运行

```bash
./run_tests.sh -s vcs -t smoke_test -g
```

## 测试用例列表

### 基础测试
- `smoke_test` - 冒烟测试，验证基本功能
- `single_master_test` - 单主接口测试
- `multi_master_test` - 多主接口测试

### 路由测试
- `address_routing_test` - 地址路由验证
- `all_slaves_routing_test` - 所有从接口路由测试

### 并发测试
- `concurrent_access_test` - 并发访问测试
- `same_slave_contention_test` - 同一从接口竞争测试

### 压力测试
- `burst_write_test` - 突发写测试
- `burst_read_test` - 突发读测试
- `outstanding_test` - Outstanding测试
- `pipeline_stress_test` - 流水线压力测试

## 设计规格

### 接口配置
- 主接口数量: 4
- 从接口数量: 4
- 地址宽度: 16-bit
- ID宽度: 8-bit
- 数据宽度: 32-bit

### 地址映射
| 从接口 | 起始地址 | 结束地址 | 大小 |
|--------|----------|----------|------|
| SLV0   | 0x0000   | 0x0FFF   | 4KB  |
| SLV1   | 0x1000   | 0x1FFF   | 4KB  |
| SLV2   | 0x2000   | 0x2FFF   | 4KB  |
| SLV3   | 0x3000   | 0x3FFF   | 4KB  |

### 主接口ID掩码
| 主接口 | ID掩码 | ID范围 |
|--------|--------|--------|
| MST0   | 0x00   | 0x00-0x0F |
| MST1   | 0x10   | 0x10-0x1F |
| MST2   | 0x20   | 0x20-0x2F |
| MST3   | 0x30   | 0x30-0x3F |

## 验证计划

详细的验证计划请参考 `docs/verification_plan.md`。

### 覆盖率目标
- 功能覆盖率: > 95%
- 代码覆盖率: > 90%
- FSM覆盖率: 100%

### 通过标准
- 所有定向测试通过
- 无协议违规断言
- 覆盖率达标

## Makefile目标

```bash
# 编译并运行所有测试
make all SIM=vcs

# 只编译
make compile SIM=vcs

# 运行特定测试
make test_smoke SIM=vcs

# 生成覆盖率报告
make cov SIM=vcs

# 清理生成文件
make clean

# 显示帮助
make help
```

## 调试

### 查看日志
```bash
# 查看编译日志
cat logs/compile.log

# 查看测试日志
cat logs/smoke_test.log
```

### 查看波形
```bash
# VCS
dve -vpd vcdplus.vpd &

# Xcelium
simvision -input simvision.sv &
```

### 运行回归测试
```bash
# 运行所有测试并生成报告
make regression SIM=vcs
```

## 扩展验证环境

### 添加新测试

1. 在 `tests/axi_test_list.sv` 中添加新的测试任务
2. 在测试平台中调用新测试
3. 更新Makefile添加新的测试目标

### 添加覆盖率

1. 在 `coverage/axi_coverage.sv` 中添加新的覆盖点
2. 在测试中调用覆盖率采样

### 添加检查器

1. 在 `axi_interface.sv` 中添加新的SVA断言
2. 在Scoreboard中添加新的检查逻辑

## 常见问题

### Q: 如何更改测试参数？
A: 修改 `tb/axi_crossbar_tb.sv` 中的参数定义。

### Q: 如何添加新的主/从接口？
A: 修改参数 `MST_NB` 和 `SLV_NB`，并更新接口实例化。

### Q: 如何运行长时间压力测试？
A: 修改测试中的循环次数或使用随机测试。

## 联系方式

如有问题，请查看验证计划文档或联系验证团队。

## 许可证

本验证环境仅供学习和研究使用。
