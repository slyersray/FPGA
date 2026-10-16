# 验证入口：make TEST=<用例>
# 仿真器：make TOOL=verilator（默认）或 make TOOL=vcs
# 例：make TEST=regress
#     make TOOL=vcs TEST=aes256_ecb_16
REPO := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
RTL  := $(REPO)/crypto/rtl
TEST_DIR := $(REPO)/crypto/verify/test
WORK := $(REPO)/crypto/verify/work
OSSL := $(WORK)/openssl-install
RESULTS := $(WORK)/results

TOOL ?= verilator
VERILATOR ?= verilator
VCS ?= vcs

# 与 case/suite.sv 里的用例名保持一致。
TESTS := regress reset aes256_ecb_16 aes256_ctr_16 aes256_ecb_128 sm4_ecb_16 sm4_ctr_16
CASE_SV := $(wildcard $(TEST_DIR)/case/*.sv)

RTL_SRCS := \
	$(RTL)/crypto_top.v \
	$(RTL)/crypto_stream.v \
	$(RTL)/aes256_key_expand.v \
	$(RTL)/aes256_pipe.v \
	$(RTL)/sm4_key_expand.v \
	$(RTL)/sm4_pipe.v

TB_SV := $(TEST_DIR)/tb_crypto_top.sv
DPI_C := $(TEST_DIR)/ossl_dpi.c

ifeq ($(TOOL),verilator)
BIN := $(WORK)/obj_dir/crypto_tb
else ifeq ($(TOOL),vcs)
BIN := $(WORK)/vcs/simv
else
$(error 未知仿真器: $(TOOL)，可选 verilator vcs)
endif

.PHONY: run list openssl clean
.DEFAULT_GOAL := run

run: $(BIN)
	@if [ -z "$(TEST)" ]; then \
		echo "用法: make TOOL=$(TOOL) TEST=<用例>"; \
		echo "可选 TOOL: verilator vcs"; \
		echo "可选 TEST: $(TESTS)"; \
		exit 1; \
	fi
	@if ! printf '%s' "$(TEST)" | grep -Eq '^[A-Za-z0-9_]+$$'; then \
		echo "未知用例: $(TEST)"; \
		echo "可选: $(TESTS)"; \
		exit 1; \
	fi
	@case " $(TESTS) " in \
		*" $(TEST) "*) ;; \
		*) echo "未知用例: $(TEST)"; echo "可选: $(TESTS)"; exit 1 ;; \
	esac
	rm -rf $(RESULTS)
	mkdir -p $(RESULTS)
	$(BIN) +TEST=$(TEST) +RESULTS=$(RESULTS) $(if $(filter vcs,$(TOOL)),+FSDB=$(WORK)/crypto.fsdb,)

list:
	@printf '%s\n' $(TESTS)

openssl: $(OSSL)/lib/libcrypto.a

$(OSSL)/lib/libcrypto.a:
	bash $(TEST_DIR)/build_openssl.sh

ifeq ($(TOOL),verilator)
$(BIN): $(OSSL)/lib/libcrypto.a $(TB_SV) $(DPI_C) $(RTL_SRCS) $(CASE_SV)
	mkdir -p $(WORK)
	$(VERILATOR) --binary --timing -sv -j 8 -O1 \
		--output-split 8000 \
		--timescale 1ns/1ps \
		-Wno-fatal \
		-Wno-PINCONNECTEMPTY \
		-I$(RTL) \
		-I$(TEST_DIR) \
		-I$(TEST_DIR)/case \
		--top-module tb_crypto_top \
		--Mdir $(WORK)/obj_dir \
		-CFLAGS "-O1 -I$(OSSL)/include" \
		-LDFLAGS "-ldl -lpthread" \
		-o crypto_tb \
		$(RTL_SRCS) $(TB_SV) $(DPI_C) $(OSSL)/lib/libcrypto.a
else
$(BIN): $(OSSL)/lib/libcrypto.a $(TB_SV) $(DPI_C) $(RTL_SRCS) $(CASE_SV)
	@if [ -z "$(VERDI_HOME)" ]; then \
		echo "FSDB 需要在编译前设置 VERDI_HOME，例如 export VERDI_HOME=/tools/eda/verdi/W-2024.09-SP2"; \
		exit 1; \
	fi
	mkdir -p $(WORK)/vcs
	$(VCS) -full64 -sverilog -timescale=1ns/1ps -debug_access+all \
		+incdir+$(RTL) \
		+incdir+$(TEST_DIR) \
		+incdir+$(TEST_DIR)/case \
		-o $(BIN) \
		-Mdir=$(WORK)/vcs/csrc \
		-CFLAGS "-O1 -I$(OSSL)/include" \
		-LDFLAGS "-L$(OSSL)/lib -Xlinker --whole-archive -lcrypto -Xlinker --no-whole-archive -ldl -lpthread -lm" \
		$(RTL_SRCS) $(TB_SV) $(DPI_C)
endif

clean:
	rm -rf $(WORK)/obj_dir $(WORK)/vcs
