task automatic case_reset;
    string dir;
    string expect_s;
    string got_s;
    int wr_ok;
    dir = {results_root, "/reset"};
    cold_reset();
    if (!ensure_dir(dir)) begin
        fail({"无法创建结果目录 ", dir});
        return;
    end
    expect_s = "test reset\nalgo_q 0\nalgo_ready 1\nenc_in_ready 0\ndec_in_ready 0\nerr 00000000\n";
    got_s = $sformatf("test reset\nalgo_q %0d\nalgo_ready %0d\nenc_in_ready %0d\ndec_in_ready %0d\nerr %s\n",
                      algo_q, algo_ready, enc_in_ready, dec_in_ready, err_text());
    write_text({dir, "/ref.txt"}, expect_s, wr_ok);
    if (wr_ok)
        write_text({dir, "/rtl.txt"}, got_s, wr_ok);
    if (!wr_ok) begin
        fail("reset 写结果文件失败");
        return;
    end
    compare_dir(dir, "reset");
endtask
