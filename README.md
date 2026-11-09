# AXI Crossbar 设计与验证项目

完整的设计思路、RTL 数据流、UVM 环境、测试点、覆盖率、调试记录和验证报告统一放在 [AXI Crossbar 设计与验证总览](docs/axi-crossbar.md)。从零学习本项目，请从这份文档开始，并对照其中链接的代码。

可执行 RTL 位于 `src/`，UVM 验证环境位于 `verification/`。`docs/tutorial/source/` 是不参与编译的旧版教学快照，可能与已修复的 RTL 不一致；分析设计行为请以 `src/` 为准。当前验证配置为单时钟 4×4、16-bit 地址、8-bit ID、32-bit 数据；文档仅对这一配置的已运行测试给出结论。

在仓库根目录复现 2026-11-09 的 VCS 回归与覆盖率合并：

```bash
make -C verification/sim regression SIM=vcs COV=1 SEED=1 PLUS_ARGS=+UVM_TIMEOUT=100000
make -C verification/sim cov
```

已有记录显示：固定种子 1 的 16 个测试通过，4×4 路由核验 16/16；这**不等于完整 AXI 签核**。同一 Master 多笔 outstanding、部分写的 WSTRB 存储语义、更多参数组合等仍是已知验证盲区；合并代码覆盖率也未收敛。详情见总览文档第 14～15 节。覆盖率报告由上述命令在本地生成，不随仓库提交。
