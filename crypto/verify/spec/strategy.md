# 加解密模块验证方案

本阶段只交付基本验证框架和 regress。覆盖率以后再做，不作为本阶段通过条件。

## 1. 约定

- 测试平台是 SystemVerilog，不使用 UVM。同一套平台用 `TOOL` 选择仿真器，默认 Verilator，也可以编 VCS。本机回归使用 Verilator 5.020。
- 参考模型是 OpenSSL 提交 `2506f1fc323b567b0e48a13b6069c7778077e55e`。框架把该提交的静态 `libcrypto` 编到 `crypto/verify/work/openssl-install`。测试平台用 DPI-C 调用 EVP。
- 激励在某条流采样 `init` 的那一拍不拉高该流的 `in_valid`。这是 `crypto/spec/aes_sm4_design_spec.md` 第 5 节和第 7.2 节的接口约束。
- `init` 与 `in_valid` 同拍时，RTL 可能在 `in_ready=1` 的情况下丢弃数据拍。该项留作后续规格核对，不写进参考模型，也不放进 regress。

## 2. 目录

| 内容 | 路径 |
| --- | --- |
| 本说明 | `crypto/verify/spec/strategy.md` |
| SystemVerilog 测试平台、DPI-C、编译 | `crypto/verify/test/` |
| 测试用例 | `crypto/verify/test/case/` |
| 仿真产物和 OpenSSL 构建 | `crypto/verify/work/`，已写入仓库 `.gitignore` |
| 每条用例的参考结果、RTL 结果和比对结论 | `crypto/verify/work/results/<用例>/` |

签核对象是 `crypto_top`。RTL 只读，验证不改 `crypto/rtl`。

当前 RTL 可以用本机 Verilator 5.020 编译。字节 0 放在总线最高位。加密流做 EVP 加密，解密流做 EVP 解密。两条流可以在同一拍各自收发。`out_ready` 在定向用例里保持为 1。比对不对 OpenSSL 的周期。

## 2.1 结果文件

算法用例先用标准向量核对 OpenSSL。通过之后，参考侧写入 `ref.txt`，RTL 采样写入 `rtl.txt`。通过与否只看这两个文件读回来是否逐字节相同，结论写在同目录的 `cmp.txt`。

`ref.txt` 里加密结果是 OpenSSL 密文，解密结果是 OpenSSL 解回的明文。两边都记录输出字节、`out_keep`、`out_last` 和 8 个错误标志。错误标志顺序是加密流的 `err_mode`、`err_no_key`、`err_keep`、`err_ecb_tail`，然后解密流同样四位。

复位没有 OpenSSL 输出。`reset` 的 `ref.txt` 是规格规定的复位值：`algo_q=0`、`algo_ready=1`、两条流 `in_ready=0`、错误标志全 0。

## 3. 回归用例

复位后检查：`algo_q` 为 AES-256，`algo_ready=1`，两条流都还没有密钥所以 `in_ready=0`，四个错误标志为 0。

每条算法用例都在两条流上同时做：加密流输入明文，解密流输入同一密钥下的密文。标准向量先用来核对 OpenSSL 自身，再拿 OpenSSL 的结果核对 RTL。

| 用例 | 算法 | 模式 | 长度 | 标准向量 |
| --- | --- | --- | --- | --- |
| AES-256 ECB 单分组 | AES-256 | ECB | 16 字节 | FIPS-197 C.3 |
| AES-256 CTR 单分组 | AES-256 | CTR | 16 字节 | NIST SP 800-38A F.5.5 第一块 |
| AES-256 ECB 满拍 | AES-256 | ECB | 128 字节 | 无，只对 OpenSSL |
| SM4 ECB 单分组 | SM4 | ECB | 16 字节 | GB/T 32907 附录示例 |
| SM4 CTR 单分组 | SM4 | CTR | 16 字节 | 无，只对 OpenSSL |

通过条件：上述用例的 RTL 输出与 OpenSSL 一致，`out_last=1`，`out_keep` 从 `keep[127]` 起连续置位，错误标志保持 0。

## 4. 运行

入口是 `make TOOL=<仿真器> TEST=<用例>`。`TOOL` 默认是 `verilator`。在 `crypto/verify/test` 下执行，或从仓库根目录加 `-C`。

```bash
make -C crypto/verify/test TEST=regress
make -C crypto/verify/test TOOL=verilator TEST=aes256_ecb_16
make -C crypto/verify/test TOOL=vcs TEST=regress
make -C crypto/verify/test list
```

`TOOL=verilator` 用 Verilator `--binary --timing` 编译 SystemVerilog，并链上 DPI-C。`TOOL=vcs` 用 `vcs -sverilog` 编译同一批 RTL、`tb_crypto_top.sv`、`case/*.sv` 和 `ossl_dpi.c`。用例名通过 `+TEST=` 传入，结果目录通过 `+RESULTS=` 传入。

每次仿真开始前先删除 `crypto/verify/work/results`。这次命令结束时，该目录里只保留本次重新跑出来的结果。

`TEST=regress` 跑完后写 `crypto/verify/work/results/regress.log`。每一行是一个用例的比对结果，`pass` 或 `fail`。最后一行是这次回归的总结。

| TEST | 内容 |
| --- | --- |
| `regress` | 复位，再跑第 3 节全部算法用例，并写 `regress.log` |
| `reset` | 只检查复位 |
| `aes256_ecb_16` | AES-256 ECB 16 字节 |
| `aes256_ctr_16` | AES-256 CTR 16 字节 |
| `aes256_ecb_128` | AES-256 ECB 128 字节 |
| `sm4_ecb_16` | SM4 ECB 16 字节 |
| `sm4_ctr_16` | SM4 CTR 16 字节 |

第一次会下载并编译钉住的 OpenSSL，再综合 RTL。编译产物和结果文件都在 `crypto/verify/work/`。

## 5. 本阶段不做

覆盖率门禁、CTR 尾块、ECB 跨拍余数、密钥或 IV 保持、反压、错误注入，以及随机回归。这些留到 regress 跑通之后。
