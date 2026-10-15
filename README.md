# FPGA

面向 Agliex-7（AGI x027.022）的两个算法模块：加密和压缩。内部数据通路按 1024 bit、400 MHz 设计，目标吞吐 400 Gbps。PCIe 由客户侧现成 IP 承担，不在本仓库的开发范围内。

当前仓库里，加密模块已有设计说明、RTL 和模块级仿真。压缩模块仍停留在需求，尚无实现目录。

## 目录

```text
.
├── Requirements/          客户需求与澄清
├── crypto/                加密模块（AES-256、SM4）
│   ├── spec/              设计说明与可行性
│   ├── rtl/               功能 RTL
│   └── verify/            模块级验证
│       ├── spec/          验证方案
│       ├── test/          测试平台、用例和 Makefile
│       └── work/          仿真产物（不入库）
└── .cursor/agents/        项目内对话代理说明
```

### Requirements

| 文件 | 说明 |
| --- | --- |
| `requirements_v1.md` | 客户原始需求：加密与压缩的平台、吞吐和资源 |
| `requirements_v1_Q&A.md` | 已和客户确认的问答 |
| `requirements_clarify_list.md` | 开发前仍待客户确认的问题 |
| `requirements_clarify_list_1013.md` | 10 月 13 日关于算法模式和报文对齐的补充问题 |

### crypto

加密模块支持 AES-256 与 SM4，模式为 ECB 和 CTR。顶层 `crypto/rtl/crypto_top.v` 同时提供加密流和解密流。行为对齐 OpenSSL 提交 `2506f1fc`，说明见 `crypto/spec/aes_sm4_design_spec.md`。

`crypto/rtl/` 中的文件：

| 文件 | 说明 |
| --- | --- |
| `crypto_top.v` | 顶层，例化加密流和解密流 |
| `crypto_stream.v` | 一条 1024 bit 流，负责上下文、ECB/CTR 和 8 路调度 |
| `aes256_key_expand.v`、`aes256_pipe.v` | AES-256 密钥扩展和单路流水线 |
| `sm4_key_expand.v`、`sm4_pipe.v` | SM4 密钥扩展和单路流水线 |
| `aes_sbox.vh`、`aes_inv_sbox.vh`、`sm4_sbox.vh` | S 盒 |

验证使用 SystemVerilog，默认仿真器是 Verilator，也可选 VCS。参考模型通过 DPI-C 调用 OpenSSL。在 `crypto/verify/test/` 下运行：

```bash
make TEST=regress
```

单条用例示例：`make TEST=aes256_ecb_16`。仿真输出在 `crypto/verify/work/`，该目录已写入 `.gitignore`。

### .cursor/agents

给 Cursor 对话用的角色说明，不参与综合或仿真。

| 文件 | 角色 |
| --- | --- |
| `pm.md` | 项目经理：范围、澄清清单和验收边界 |
| `de_crypto.md` | 加密模块设计：规格和 RTL |
| `dv_crypto.md` | 加密模块验证 |
