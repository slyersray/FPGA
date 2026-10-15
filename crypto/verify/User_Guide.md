# 仿真使用说明

在仓库根目录执行。仿真入口是 `crypto/verify/test` 下的 Makefile。

## 1. 命令

```bash
make -C crypto/verify/test TOOL=<仿真器> TEST=<用例>
```

`TOOL` 默认是 `verilator`，也可以写成 `vcs`。不写 `TEST` 时命令会退出，并打印可选用例。

```bash
make -C crypto/verify/test TEST=regress
make -C crypto/verify/test TOOL=verilator TEST=aes256_ecb_16
make -C crypto/verify/test TOOL=vcs TEST=regress
make -C crypto/verify/test list
```

也可以先进入目录再执行：

```bash
cd crypto/verify/test
make TEST=regress
make TOOL=vcs TEST=reset
make list
```

`list` 只打印用例名，不编译、不仿真。

## 2. 用例

| TEST | 做什么 |
| --- | --- |
| `regress` | 按顺序跑下面全部用例，并写回归日志 |
| `reset` | 只检查复位 |
| `aes256_ecb_16` | AES-256 ECB，16 字节 |
| `aes256_ctr_16` | AES-256 CTR，16 字节 |
| `aes256_ecb_128` | AES-256 ECB，128 字节 |
| `sm4_ecb_16` | SM4 ECB，16 字节 |
| `sm4_ctr_16` | SM4 CTR，16 字节 |

`regress` 的顺序是 `reset`、`aes256_ecb_16`、`aes256_ctr_16`、`aes256_ecb_128`、`sm4_ecb_16`、`sm4_ctr_16`。单独指定某个用例时，只跑那一条。

## 3. 第一次运行

第一次会下载并编译设计说明钉住的 OpenSSL，再编译 RTL 和 SystemVerilog 测试平台。这两步都比较慢。OpenSSL 已经编好、RTL 和用例没有改动时，后面的 `make` 直接跑已有的仿真程序。

本机默认用 Verilator。`TOOL=vcs` 需要本机能执行 `vcs`。

## 4. 结果

每次仿真开始前会删除 `crypto/verify/work/results`。命令结束后，这个目录里只有本次重新跑出来的结果。

每个用例一个子目录：

```text
crypto/verify/work/results/<用例>/ref.txt
crypto/verify/work/results/<用例>/rtl.txt
crypto/verify/work/results/<用例>/cmp.txt
```

`ref.txt` 是参考侧，`rtl.txt` 是 RTL 采样。`cmp.txt` 第一行是 `result pass` 或 `result fail`。比对不一致时，后面几行给出第一处差异。

`TEST=regress` 还会写 `crypto/verify/work/results/regress.log`。每一行是一个用例的 `pass` 或 `fail`，最后一行是这次回归的总结，例如：

```text
reset pass
aes256_ecb_16 pass
aes256_ctr_16 pass
aes256_ecb_128 pass
sm4_ecb_16 pass
sm4_ctr_16 pass
regress pass
```

终端里每个通过的用例打印 `通过 <用例名>`。全部通过时最后一行是 `<TEST> 通过`，进程退出码为 0。有失败时打印 `失败`，退出码非 0。

`crypto/verify/work/` 已在仓库 `.gitignore` 中，仿真产物不入库。

## 5. 清理编译产物

```bash
make -C crypto/verify/test clean
```

这会删除 Verilator 和 VCS 的编译目录。下一次仿真会重新编译。OpenSSL 的安装目录还在，不会重新下载。
