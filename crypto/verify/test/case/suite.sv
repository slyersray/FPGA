// 用例调度。regress 按下面的顺序连续跑，单个用例自己先复位。
task automatic run_and_record(input string id, input bit do_reset);
    int mark;
    if (do_reset)
        cold_reset();
    mark = n_fail;
    if (id == "reset")
        case_reset();
    else if (id == "aes256_ecb_16")
        case_aes256_ecb_16();
    else if (id == "aes256_ctr_16")
        case_aes256_ctr_16();
    else if (id == "aes256_ecb_128")
        case_aes256_ecb_128();
    else if (id == "sm4_ecb_16")
        case_sm4_ecb_16();
    else if (id == "sm4_ctr_16")
        case_sm4_ctr_16();
    if (test_name == "regress")
        record_case(id, n_fail == mark);
endtask

task automatic run_selected(input string name);
    bit known;
    known = 0;
    if (name == "regress" || name == "reset") begin
        known = 1;
        run_and_record("reset", 0);
    end
    if (name == "regress" || name == "aes256_ecb_16") begin
        known = 1;
        run_and_record("aes256_ecb_16", name != "regress");
    end
    if (name == "regress" || name == "aes256_ctr_16") begin
        known = 1;
        run_and_record("aes256_ctr_16", name != "regress");
    end
    if (name == "regress" || name == "aes256_ecb_128") begin
        known = 1;
        run_and_record("aes256_ecb_128", name != "regress");
    end
    if (name == "regress" || name == "sm4_ecb_16") begin
        known = 1;
        run_and_record("sm4_ecb_16", name != "regress");
    end
    if (name == "regress" || name == "sm4_ctr_16") begin
        known = 1;
        run_and_record("sm4_ctr_16", name != "regress");
    end
    if (!known) begin
        $display("未知用例 %s", name);
        $fatal(2);
    end
    if (name == "regress")
        write_regress_log();
endtask
