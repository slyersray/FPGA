task automatic case_sm4_ctr_16;
    run_case("sm4_ctr_16", 1, 1,
             "0123456789abcdeffedcba9876543210",
             "000102030405060708090a0b0c0d0e0f",
             "0123456789abcdeffedcba9876543210",
             "", 16);
endtask
