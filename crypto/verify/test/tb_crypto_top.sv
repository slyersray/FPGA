// crypto_top 的 SystemVerilog 测试平台。不使用 UVM。
// 参考模型通过 DPI-C 调用钉住提交的 OpenSSL。
// 采样 init 的那一拍不拉高同一条流的 in_valid。
`timescale 1ns/1ps

import "DPI-C" function int ossl_init();
import "DPI-C" function int ossl_crypt(
    input int is_enc,
    input int cipher_id,
    input bit [255:0] key,
    input int key_len,
    input bit [127:0] iv,
    input int iv_valid,
    input bit [1023:0] din,
    input int nbytes,
    output bit [1023:0] dout
);
import "DPI-C" function int ensure_dir(input string path);
import "DPI-C" function int clear_results(input string path);
import "DPI-C" function int results_match(
    input string ref_path,
    input string rtl_path,
    input string cmp_path
);

module tb_crypto_top;
    logic          clk;
    logic          rst_n;
    logic          algo_load;
    logic [1:0]    algo;
    wire           algo_ready;
    wire  [1:0]    algo_q;

    logic          enc_init;
    logic [1:0]    enc_mode;
    logic          enc_key_valid;
    logic [255:0]  enc_key;
    logic          enc_iv_valid;
    logic [127:0]  enc_iv;
    logic          enc_in_valid;
    wire           enc_in_ready;
    logic [1023:0] enc_in_data;
    logic [127:0]  enc_in_keep;
    logic          enc_in_last;
    wire           enc_out_valid;
    logic          enc_out_ready;
    wire  [1023:0] enc_out_data;
    wire  [127:0]  enc_out_keep;
    wire           enc_out_last;
    wire           enc_err_mode;
    wire           enc_err_no_key;
    wire           enc_err_keep;
    wire           enc_err_ecb_tail;

    logic          dec_init;
    logic [1:0]    dec_mode;
    logic          dec_key_valid;
    logic [255:0]  dec_key;
    logic          dec_iv_valid;
    logic [127:0]  dec_iv;
    logic          dec_in_valid;
    wire           dec_in_ready;
    logic [1023:0] dec_in_data;
    logic [127:0]  dec_in_keep;
    logic          dec_in_last;
    wire           dec_out_valid;
    logic          dec_out_ready;
    wire  [1023:0] dec_out_data;
    wire  [127:0]  dec_out_keep;
    wire           dec_out_last;
    wire           dec_err_mode;
    wire           dec_err_no_key;
    wire           dec_err_keep;
    wire           dec_err_ecb_tail;

    int cycle;
    int n_fail;
    int regress_nfail;
    string test_name;
    string results_root;
    string regress_body;

    crypto_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .algo_load(algo_load),
        .algo(algo),
        .algo_ready(algo_ready),
        .algo_q(algo_q),
        .enc_init(enc_init),
        .enc_mode(enc_mode),
        .enc_key_valid(enc_key_valid),
        .enc_key(enc_key),
        .enc_iv_valid(enc_iv_valid),
        .enc_iv(enc_iv),
        .enc_in_valid(enc_in_valid),
        .enc_in_ready(enc_in_ready),
        .enc_in_data(enc_in_data),
        .enc_in_keep(enc_in_keep),
        .enc_in_last(enc_in_last),
        .enc_out_valid(enc_out_valid),
        .enc_out_ready(enc_out_ready),
        .enc_out_data(enc_out_data),
        .enc_out_keep(enc_out_keep),
        .enc_out_last(enc_out_last),
        .enc_err_mode(enc_err_mode),
        .enc_err_no_key(enc_err_no_key),
        .enc_err_keep(enc_err_keep),
        .enc_err_ecb_tail(enc_err_ecb_tail),
        .dec_init(dec_init),
        .dec_mode(dec_mode),
        .dec_key_valid(dec_key_valid),
        .dec_key(dec_key),
        .dec_iv_valid(dec_iv_valid),
        .dec_iv(dec_iv),
        .dec_in_valid(dec_in_valid),
        .dec_in_ready(dec_in_ready),
        .dec_in_data(dec_in_data),
        .dec_in_keep(dec_in_keep),
        .dec_in_last(dec_in_last),
        .dec_out_valid(dec_out_valid),
        .dec_out_ready(dec_out_ready),
        .dec_out_data(dec_out_data),
        .dec_out_keep(dec_out_keep),
        .dec_out_last(dec_out_last),
        .dec_err_mode(dec_err_mode),
        .dec_err_no_key(dec_err_no_key),
        .dec_err_keep(dec_err_keep),
        .dec_err_ecb_tail(dec_err_ecb_tail)
    );

    function automatic int nibble(input byte unsigned c);
        if (c >= "0" && c <= "9")
            return c - "0";
        if (c >= "a" && c <= "f")
            return c - "a" + 10;
        if (c >= "A" && c <= "F")
            return c - "A" + 10;
        return -1;
    endfunction

    function automatic logic [1023:0] hex_to_bus(input string hex, input int width);
        logic [1023:0] bus;
        int nbytes;
        int lsb;
        int hi;
        int lo;
        bus = '0;
        nbytes = hex.len() / 2;
        for (int i = 0; i < nbytes; i++) begin
            hi = nibble(hex[i * 2]);
            lo = nibble(hex[i * 2 + 1]);
            lsb = width - 8 * (i + 1);
            bus[lsb +: 8] = {hi[3:0], lo[3:0]};
        end
        return bus;
    endfunction

    function automatic logic [1023:0] seq_bus(input int nbytes);
        logic [1023:0] bus;
        bus = '0;
        for (int i = 0; i < nbytes; i++)
            bus[(1024 - 8 * (i + 1)) +: 8] = i[7:0];
        return bus;
    endfunction

    function automatic string u8_hex(input logic [7:0] b);
        return $sformatf("%02x", b);
    endfunction

    function automatic string bytes_hex(input logic [1023:0] bus, input int nbytes, input int width);
        string s;
        s = "";
        for (int i = 0; i < nbytes; i++)
            s = {s, u8_hex(bus[(width - 8 * (i + 1)) +: 8])};
        return s;
    endfunction

    function automatic string keep_hex(input logic [127:0] keep);
        logic [1023:0] ext;
        ext = '0;
        ext[127:0] = keep;
        return bytes_hex(ext, 16, 128);
    endfunction

    function automatic logic [127:0] keep_prefix(input int nbytes);
        logic [127:0] keep;
        keep = '0;
        for (int i = 0; i < nbytes; i++)
            keep[127 - i] = 1'b1;
        return keep;
    endfunction

    function automatic string err_text();
        return {enc_err_mode ? "1" : "0",
                enc_err_no_key ? "1" : "0",
                enc_err_keep ? "1" : "0",
                enc_err_ecb_tail ? "1" : "0",
                dec_err_mode ? "1" : "0",
                dec_err_no_key ? "1" : "0",
                dec_err_keep ? "1" : "0",
                dec_err_ecb_tail ? "1" : "0"};
    endfunction

    function automatic int cipher_code(input int algo_i, input int mode_i);
        if (algo_i == 0 && mode_i == 0)
            return 0;
        if (algo_i == 0 && mode_i == 1)
            return 1;
        if (algo_i == 1 && mode_i == 0)
            return 2;
        return 3;
    endfunction

    function automatic string cipher_label(input int algo_i, input int mode_i);
        if (algo_i == 0 && mode_i == 0)
            return "AES-256-ECB";
        if (algo_i == 0 && mode_i == 1)
            return "AES-256-CTR";
        if (algo_i == 1 && mode_i == 0)
            return "SM4-ECB";
        return "SM4-CTR";
    endfunction

    function automatic string crypto_text(
        input string id,
        input string cipher,
        input int nbytes,
        input int enc_valid,
        input string enc_hex,
        input int dec_valid,
        input string dec_hex,
        input string enc_keep_s,
        input string dec_keep_s,
        input int enc_last,
        input int dec_last,
        input string err
    );
        return $sformatf("test %s\ncipher %s\nnbytes %0d\nenc_valid %0d\nenc %s\ndec_valid %0d\ndec %s\nenc_keep %s\ndec_keep %s\nenc_last %0d\ndec_last %0d\nerr %s\n",
                         id, cipher, nbytes, enc_valid, enc_hex, dec_valid, dec_hex,
                         enc_keep_s, dec_keep_s, enc_last, dec_last, err);
    endfunction

    task automatic tick;
        clk = 1'b0;
        #5;
        clk = 1'b1;
        #5;
        cycle = cycle + 1;
    endtask

    task automatic drive_idle;
        algo_load = 1'b0;
        algo = 2'd0;
        enc_init = 1'b0;
        enc_mode = 2'd0;
        enc_key_valid = 1'b0;
        enc_iv_valid = 1'b0;
        enc_in_valid = 1'b0;
        enc_in_last = 1'b0;
        enc_out_ready = 1'b1;
        dec_init = 1'b0;
        dec_mode = 2'd0;
        dec_key_valid = 1'b0;
        dec_iv_valid = 1'b0;
        dec_in_valid = 1'b0;
        dec_in_last = 1'b0;
        dec_out_ready = 1'b1;
        enc_key = '0;
        enc_iv = '0;
        enc_in_data = '0;
        enc_in_keep = '0;
        dec_key = '0;
        dec_iv = '0;
        dec_in_data = '0;
        dec_in_keep = '0;
    endtask

    task automatic dump_status;
        $display("  cycle=%0d algo_q=%0d algo_ready=%0d", cycle, algo_q, algo_ready);
        $display("  enc ready=%0d valid_in=%0d valid_out=%0d err=%0d%0d%0d%0d",
                 enc_in_ready, enc_in_valid, enc_out_valid,
                 enc_err_mode, enc_err_no_key, enc_err_keep, enc_err_ecb_tail);
        $display("  dec ready=%0d valid_in=%0d valid_out=%0d err=%0d%0d%0d%0d",
                 dec_in_ready, dec_in_valid, dec_out_valid,
                 dec_err_mode, dec_err_no_key, dec_err_keep, dec_err_ecb_tail);
    endtask

    task automatic fail(input string msg);
        $display("失败 %s", msg);
        dump_status();
        n_fail = n_fail + 1;
    endtask

    task automatic write_text(input string path, input string body, output int ok);
        int fd;
        fd = $fopen(path, "w");
        if (fd == 0) begin
            ok = 0;
        end else begin
            $fwrite(fd, "%s", body);
            $fclose(fd);
            ok = 1;
        end
    endtask

    task automatic cold_reset;
        drive_idle();
        rst_n = 1'b0;
        clk = 1'b0;
        repeat (4)
            tick();
        rst_n = 1'b1;
        tick();
    endtask

    task automatic wait_algo_ready(output bit ok);
        ok = 1'b0;
        for (int i = 0; i < 80; i++) begin
            if (algo_ready) begin
                ok = 1'b1;
                break;
            end
            tick();
        end
    endtask

    task automatic load_algo(input int algo_i);
        bit ready;
        if (algo_q == algo_i[1:0])
            return;
        wait_algo_ready(ready);
        if (!ready) begin
            fail("换算法前两条流没有同时空闲");
            return;
        end
        algo = algo_i[1:0];
        algo_load = 1'b1;
        enc_in_valid = 1'b0;
        dec_in_valid = 1'b0;
        tick();
        algo_load = 1'b0;
        if (algo_q != algo_i[1:0])
            fail(algo_i ? "algo_q 没有变成 SM4" : "algo_q 没有变成 AES-256");
    endtask

    task automatic compare_dir(input string dir, input string id);
        if (!results_match({dir, "/ref.txt"}, {dir, "/rtl.txt"}, {dir, "/cmp.txt"})) begin
            fail({id, " 结果文件不一致 ", dir});
        end else begin
            $display("通过 %s", id);
            $display("结果 %s", dir);
        end
    endtask

    task automatic run_case(
        input string id,
        input int algo_i,
        input int mode_i,
        input string key_hex,
        input string iv_hex,
        input string pt_hex,
        input string ct_hex,
        input int pt_len
    );
        int key_len;
        int wr_ok;
        int mark;
        int enc_valid;
        int dec_valid;
        int enc_last;
        int dec_last;
        bit ready;
        bit iv_on;
        string dir;
        string cname;
        string keep_s;
        string enc_keep_s;
        string dec_keep_s;
        string ref_s;
        string rtl_s;
        logic [1023:0] key_bus;
        logic [1023:0] iv_bus;
        logic [1023:0] pt_bus;
        bit [1023:0] ct_bus;
        bit [1023:0] back_bus;
        logic [1023:0] enc_got;
        logic [1023:0] dec_got;

        key_len = (algo_i == 0) ? 32 : 16;
        cname = cipher_label(algo_i, mode_i);
        dir = {results_root, "/", id};
        iv_on = (mode_i == 1);
        enc_valid = 0;
        dec_valid = 0;
        enc_last = 0;
        dec_last = 0;
        enc_got = '0;
        dec_got = '0;
        enc_keep_s = "00000000000000000000000000000000";
        dec_keep_s = "00000000000000000000000000000000";

        if (!ensure_dir(dir)) begin
            fail({id, " 无法创建结果目录"});
            return;
        end
        if (key_hex.len() != key_len * 2) begin
            fail({id, " 密钥长度不对"});
            return;
        end
        if (iv_on && iv_hex.len() != 32) begin
            fail({id, " CTR 需要 16 字节 IV"});
            return;
        end
        if (pt_hex.len() != 0 && pt_hex.len() != pt_len * 2) begin
            fail({id, " 明文长度不对"});
            return;
        end

        key_bus = hex_to_bus(key_hex, 256);
        iv_bus = iv_on ? hex_to_bus(iv_hex, 128) : '0;
        pt_bus = (pt_hex.len() != 0) ? hex_to_bus(pt_hex, 1024) : seq_bus(pt_len);

        if (!ossl_crypt(1, cipher_code(algo_i, mode_i), key_bus[255:0], key_len,
                        iv_bus[127:0], iv_on ? 1 : 0, pt_bus, pt_len, ct_bus)
            || !ossl_crypt(0, cipher_code(algo_i, mode_i), key_bus[255:0], key_len,
                           iv_bus[127:0], iv_on ? 1 : 0, ct_bus, pt_len, back_bus)
            || bytes_hex(back_bus, pt_len, 1024) != bytes_hex(pt_bus, pt_len, 1024)) begin
            fail({id, " OpenSSL 自身加解密没有闭合"});
            return;
        end
        if (ct_hex.len() != 0 && bytes_hex(ct_bus, pt_len, 1024) != ct_hex) begin
            fail({id, " OpenSSL 与标准向量不一致，得到 ", bytes_hex(ct_bus, pt_len, 1024)});
            return;
        end

        keep_s = keep_hex(keep_prefix(pt_len));
        ref_s = crypto_text(id, cname, pt_len, 1, bytes_hex(ct_bus, pt_len, 1024),
                            1, bytes_hex(pt_bus, pt_len, 1024), keep_s, keep_s, 1, 1, "00000000");
        write_text({dir, "/ref.txt"}, ref_s, wr_ok);
        if (!wr_ok) begin
            fail({id, " 写参考结果失败"});
            return;
        end

        mark = n_fail;
        load_algo(algo_i);
        wait_algo_ready(ready);
        if (n_fail != mark || !ready) begin
            if (n_fail == mark)
                fail({id, " 送数前没有空闲"});
            rtl_s = crypto_text(id, cname, pt_len, 0, "", 0, "", enc_keep_s, dec_keep_s, 0, 0, err_text());
            write_text({dir, "/rtl.txt"}, rtl_s, wr_ok);
            write_text({dir, "/cmp.txt"}, "result fail\n", wr_ok);
            return;
        end

        enc_mode = mode_i[1:0];
        dec_mode = mode_i[1:0];
        enc_key = key_bus[255:0];
        dec_key = key_bus[255:0];
        enc_iv = iv_bus[127:0];
        dec_iv = iv_bus[127:0];
        enc_key_valid = 1'b1;
        dec_key_valid = 1'b1;
        enc_iv_valid = iv_on;
        dec_iv_valid = iv_on;
        enc_init = 1'b1;
        dec_init = 1'b1;
        enc_in_valid = 1'b0;
        dec_in_valid = 1'b0;
        tick();
        enc_init = 1'b0;
        dec_init = 1'b0;
        enc_key_valid = 1'b0;
        dec_key_valid = 1'b0;
        enc_iv_valid = 1'b0;
        dec_iv_valid = 1'b0;

        ready = 1'b0;
        for (int i = 0; i < 8; i++) begin
            if (enc_in_ready && dec_in_ready) begin
                ready = 1'b1;
                break;
            end
            tick();
        end

        if (ready) begin
            enc_in_data = pt_bus;
            dec_in_data = ct_bus;
            enc_in_keep = keep_prefix(pt_len);
            dec_in_keep = keep_prefix(pt_len);
            enc_in_last = 1'b1;
            dec_in_last = 1'b1;
            enc_in_valid = 1'b1;
            dec_in_valid = 1'b1;
            tick();
            enc_in_valid = 1'b0;
            dec_in_valid = 1'b0;

            for (int i = 0; i < 80 && !(enc_valid && dec_valid); i++) begin
                tick();
                if (!enc_valid && enc_out_valid) begin
                    enc_got = enc_out_data;
                    enc_keep_s = keep_hex(enc_out_keep);
                    enc_last = enc_out_last ? 1 : 0;
                    enc_valid = 1;
                end
                if (!dec_valid && dec_out_valid) begin
                    dec_got = dec_out_data;
                    dec_keep_s = keep_hex(dec_out_keep);
                    dec_last = dec_out_last ? 1 : 0;
                    dec_valid = 1;
                end
            end
        end

        rtl_s = crypto_text(id, cname, pt_len, enc_valid,
                            enc_valid ? bytes_hex(enc_got, pt_len, 1024) : "",
                            dec_valid, dec_valid ? bytes_hex(dec_got, pt_len, 1024) : "",
                            enc_keep_s, dec_keep_s, enc_last, dec_last, err_text());
        write_text({dir, "/rtl.txt"}, rtl_s, wr_ok);
        if (!wr_ok) begin
            fail({id, " 写 RTL 结果失败"});
            return;
        end
        compare_dir(dir, id);
    endtask

    task automatic record_case(input string id, input bit passed);
        regress_body = {regress_body, id, " ", passed ? "pass" : "fail", "\n"};
        if (!passed)
            regress_nfail = regress_nfail + 1;
    endtask

    task automatic write_regress_log;
        int wr_ok;
        string body;
        if (regress_nfail == 0)
            body = {regress_body, "regress pass\n"};
        else
            body = {regress_body, $sformatf("regress fail %0d\n", regress_nfail)};
        write_text({results_root, "/regress.log"}, body, wr_ok);
        if (!wr_ok)
            fail("写 regress.log 失败");
        else
            $display("回归日志 %s/regress.log", results_root);
    endtask

    `include "case/all.sv"

    initial begin
        cycle = 0;
        n_fail = 0;
        regress_nfail = 0;
        regress_body = "";
        drive_idle();
        clk = 1'b0;
        rst_n = 1'b0;

        if (!$value$plusargs("TEST=%s", test_name) || !$value$plusargs("RESULTS=%s", results_root)) begin
            $display("用法: 仿真可执行文件 +TEST=<用例> +RESULTS=<目录>");
            $fatal(2);
        end
        if (!ossl_init()) begin
            $display("失败 无法加载 OpenSSL default provider");
            $fatal(1);
        end
        if (!clear_results(results_root)) begin
            $display("失败 无法清空结果目录 %s", results_root);
            $fatal(1);
        end

        run_selected(test_name);

        if (n_fail != 0) begin
            $display("%s 失败 %0d", test_name, n_fail);
            $fatal(1);
        end
        $display("%s 通过", test_name);
        $finish;
    end
endmodule
