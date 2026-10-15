task automatic case_sm4_ecb_16;
    run_case("sm4_ecb_16", 1, 0,
             "0123456789abcdeffedcba9876543210",
             "",
             "0123456789abcdeffedcba9876543210",
             "681edf34d206965e86b3e94f536e4246",
             16);
endtask
