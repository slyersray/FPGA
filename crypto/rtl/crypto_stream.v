// 一条 1024 bit 流。IS_DEC=0 为加密流，IS_DEC=1 为解密流。
// 整块输入在 out_ready 为 1 时每拍接收一次。AES 结果延迟 15 拍，SM4 延迟 32 拍。
// CTR 尾块不足 16 字节时，本流停手，直到该块密钥流走出流水线。
module crypto_stream #(
    parameter IS_DEC = 0
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1:0]    algo,
    input  wire          init,
    input  wire [1:0]    mode,
    input  wire          key_valid,
    input  wire [255:0]  key,
    input  wire          iv_valid,
    input  wire [127:0]  iv,
    input  wire          in_valid,
    output wire          in_ready,
    input  wire [1023:0] in_data,
    input  wire [127:0]  in_keep,
    input  wire          in_last,
    output wire          out_valid,
    input  wire          out_ready,
    output wire [1023:0] out_data,
    output wire [127:0]  out_keep,
    output wire          out_last,
    output reg           err_mode,
    output reg           err_no_key,
    output reg           err_keep,
    output reg           err_ecb_tail,
    output wire          idle
);
    localparam ALGO_AES = 2'd0;
    localparam ALGO_SM4 = 2'd1;
    localparam MODE_ECB = 2'd0;
    localparam MODE_CTR = 2'd1;
    localparam [4:0] AES_TAP = 5'd14;
    localparam [4:0] SM4_TAP = 5'd31;

    reg [1:0]    mode_q;
    reg          key_set;
    reg [255:0]  key_q;
    reg [127:0]  ctr;
    reg [4:0]    ctr_num;
    reg [127:0]  ecount;
    reg [3:0]    ecb_n;
    reg [119:0]  ecb_hold;
    reg          wait_ks;

    reg          sb_v      [0:31];
    reg          sb_last   [0:31];
    reg          sb_ctr    [0:31];
    reg          sb_ks     [0:31];
    reg [2:0]    sb_plane   [0:31];
    reg [4:0]    sb_num     [0:31];
    reg [3:0]    sb_nblocks [0:31];
    reg [7:0]    sb_pre_len [0:31];
    reg [7:0]    sb_out_len [0:31];
    reg [1023:0] sb_pre     [0:31];
    reg [1023:0] sb_in      [0:31];
    reg [39:0]   sb_nbytes  [0:31];
    reg [63:0]   sb_src     [0:31];

    wire [1919:0] aes_rk;
    wire [1023:0] sm4_rk;
    wire [1023:0] aes_fwd_dout;
    wire [1023:0] aes_inv_dout;
    wire [1023:0] sm4_dout;

    integer si;
    reg any_sb;
    wire [4:0] tap;

    aes256_key_expand u_aes_kex (
        .key(key_q),
        .rk (aes_rk)
    );
    sm4_key_expand u_sm4_kex (
        .key(key_q[255:128]),
        .rk (sm4_rk)
    );

    always @(*) begin
        any_sb = 1'b0;
        for (si = 0; si < 32; si = si + 1)
            if (sb_v[si])
                any_sb = 1'b1;
    end

    assign tap = (algo == ALGO_SM4) ? SM4_TAP : AES_TAP;

    assign idle      = !any_sb && !wait_ks;
    assign out_valid = sb_v[tap];
    assign out_data  = assembled;
    assign out_keep  = sb_v[tap] ? prefix_keep(sb_out_len[tap]) : 128'h0;
    assign out_last  = sb_v[tap] && sb_last[tap];
    wire pipe_en     = !out_valid || out_ready;
    wire mode_ok     = (mode_q == MODE_ECB) || (mode_q == MODE_CTR);
    assign in_ready  = pipe_en && key_set && !wait_ks && mode_ok;

    function automatic [7:0] getb;
        input [1023:0] bus;
        input integer idx;
        begin
            getb = bus[1023 - 8 * idx -: 8];
        end
    endfunction

    function automatic [127:0] ctr_add;
        input [127:0] base;
        input [3:0] add;
        integer bi;
        reg [8:0] sum;
        begin
            ctr_add = base;
            sum = {1'b0, base[7:0]} + {5'b0, add};
            ctr_add[7:0] = sum[7:0];
            for (bi = 1; bi < 16; bi = bi + 1) begin
                sum = {1'b0, base[8 * bi +: 8]} + {8'h00, sum[8]};
                ctr_add[8 * bi +: 8] = sum[7:0];
            end
        end
    endfunction

    function automatic keep_bad;
        input [127:0] keep;
        integer ki;
        reg seen0;
        begin
            keep_bad = 1'b0;
            seen0 = 1'b0;
            for (ki = 0; ki < 128; ki = ki + 1) begin
                if (seen0 && keep[127 - ki])
                    keep_bad = 1'b1;
                if (!keep[127 - ki])
                    seen0 = 1'b1;
            end
        end
    endfunction

    function automatic [7:0] keep_len;
        input [127:0] keep;
        integer ki;
        begin
            keep_len = 8'd0;
            for (ki = 0; ki < 128; ki = ki + 1)
                if (keep[127 - ki])
                    keep_len = keep_len + 8'd1;
        end
    endfunction

    function automatic [127:0] prefix_keep;
        input [7:0] len;
        integer ki;
        begin
            prefix_keep = 128'h0;
            for (ki = 0; ki < 128; ki = ki + 1)
                if (ki < len)
                    prefix_keep[127 - ki] = 1'b1;
        end
    endfunction

    function automatic [7:0] hold_byte;
        input [119:0] hold;
        input integer idx;
        begin
            hold_byte = hold[119 - 8 * idx -: 8];
        end
    endfunction

    function automatic [127:0] lane_of;
        input [1023:0] bus;
        input integer idx;
        begin
            lane_of = bus[1023 - 128 * idx -: 128];
        end
    endfunction

    integer pi, psrc, ppos, pnb, plen, take_n;
    reg [4:0] pnum;
    reg [7:0] qbyte [0:142];
    reg [1023:0] p_lane, p_pre;
    reg [39:0] p_nbytes;
    reg [63:0] p_src;
    reg [7:0] p_pre_len, p_out_len;
    reg [3:0] p_nblocks;
    reg [127:0] p_ctr;
    reg [4:0] p_num;
    reg p_ks;
    reg [2:0] p_plane;
    reg [3:0] p_ecb_n;
    reg [119:0] p_ecb_hold;
    reg p_err_tail;
    reg [7:0] beat_len;

    always @(*) begin
        beat_len = keep_len(in_keep);
        p_lane = 1024'h0;
        p_pre = 1024'h0;
        p_nbytes = 40'h0;
        p_src = 64'h0;
        p_pre_len = 8'd0;
        p_out_len = 8'd0;
        p_nblocks = 4'd0;
        p_ctr = ctr;
        p_num = ctr_num;
        p_ks = 1'b0;
        p_plane = 3'd0;
        p_ecb_n = ecb_n;
        p_ecb_hold = ecb_hold;
        p_err_tail = 1'b0;
        psrc = 0;
        ppos = 0;
        pnb = 0;
        take_n = 0;
        plen = {{24{1'b0}}, beat_len};
        pnum = ctr_num;
        for (pi = 0; pi < 143; pi = pi + 1)
            qbyte[pi] = 8'h00;

        if (mode_q == MODE_CTR) begin
            while ((psrc < plen) && (pnum != 0)) begin
                p_pre[1023 - 8 * ppos -: 8] =
                    getb(in_data, psrc) ^ ecount[127 - 8 * pnum -: 8];
                ppos = ppos + 1;
                psrc = psrc + 1;
                if (pnum == 5'd15)
                    pnum = 5'd0;
                else
                    pnum = pnum + 5'd1;
            end
            p_pre_len = ppos[7:0];
            while ((psrc < plen) && (pnb < 8)) begin
                p_lane[1023 - 128 * pnb -: 128] = ctr_add(ctr, pnb[3:0]);
                p_src[8 * pnb +: 8] = psrc[7:0];
                if ((plen - psrc) >= 16) begin
                    p_nbytes[5 * pnb +: 5] = 5'd16;
                    psrc = psrc + 16;
                end else begin
                    take_n = plen - psrc;
                    p_nbytes[5 * pnb +: 5] = take_n[4:0];
                    psrc = plen;
                end
                pnb = pnb + 1;
            end
            p_nblocks = pnb[3:0];
            p_out_len = beat_len;
            p_ctr = ctr_add(ctr, pnb[3:0]);
            if (pnb != 0 && p_nbytes[5 * (pnb - 1) +: 5] != 5'd16) begin
                p_num = {1'b0, p_nbytes[5 * (pnb - 1) +: 4]};
                p_ks = 1'b1;
                p_plane = pnb[2:0] - 3'd1;
            end else begin
                p_num = pnum;
                p_ks = 1'b0;
            end
        end else if (mode_q == MODE_ECB) begin
            for (pi = 0; pi < ecb_n; pi = pi + 1)
                qbyte[pi] = hold_byte(ecb_hold, pi);
            for (pi = 0; pi < plen; pi = pi + 1)
                qbyte[pi + {{28{1'b0}}, ecb_n}] = getb(in_data, pi);
            plen = {{28{1'b0}}, ecb_n} + {{24{1'b0}}, beat_len};
            pnb = plen / 16;
            if (pnb > 8)
                pnb = 8;
            for (pi = 0; pi < pnb; pi = pi + 1) begin
                p_lane[1023 - 128 * pi -: 128] = {
                    qbyte[16 * pi + 0], qbyte[16 * pi + 1],
                    qbyte[16 * pi + 2], qbyte[16 * pi + 3],
                    qbyte[16 * pi + 4], qbyte[16 * pi + 5],
                    qbyte[16 * pi + 6], qbyte[16 * pi + 7],
                    qbyte[16 * pi + 8], qbyte[16 * pi + 9],
                    qbyte[16 * pi + 10], qbyte[16 * pi + 11],
                    qbyte[16 * pi + 12], qbyte[16 * pi + 13],
                    qbyte[16 * pi + 14], qbyte[16 * pi + 15]
                };
                p_nbytes[5 * pi +: 5] = 5'd16;
            end
            p_nblocks = pnb[3:0];
            p_out_len = pnb[7:0] * 8'd16;
            p_ecb_n = plen[3:0];
            p_ecb_hold = 120'h0;
            for (pi = 0; pi < (plen % 16); pi = pi + 1)
                p_ecb_hold[119 - 8 * pi -: 8] = qbyte[16 * pnb + pi];
            p_err_tail = in_last && ((plen % 16) != 0);
        end
    end

    wire take = in_valid && in_ready && !keep_bad(in_keep);
    wire push = take && (p_out_len != 8'd0);
    wire use_fwd = (IS_DEC == 0) || (mode_q == MODE_CTR);
    wire sm4_dec = (IS_DEC != 0) && (mode_q == MODE_ECB);

    wire [7:0] lane_hit;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_lane
            assign lane_hit[gi] = push && (gi < p_nblocks);
            aes256_pipe #(.DECRYPT(0)) u_fwd (
                .clk(clk), .rst_n(rst_n), .en(pipe_en),
                .valid_in(lane_hit[gi] && (algo == ALGO_AES) && use_fwd),
                .din(p_lane[1023 - 128 * gi -: 128]),
                .rk(aes_rk),
                .valid_out(),
                .dout(aes_fwd_dout[1023 - 128 * gi -: 128])
            );
            if (IS_DEC != 0) begin : g_inv
                aes256_pipe #(.DECRYPT(1)) u_inv (
                    .clk(clk), .rst_n(rst_n), .en(pipe_en),
                    .valid_in(lane_hit[gi] && (algo == ALGO_AES) && (mode_q == MODE_ECB)),
                    .din(p_lane[1023 - 128 * gi -: 128]),
                    .rk(aes_rk),
                    .valid_out(),
                    .dout(aes_inv_dout[1023 - 128 * gi -: 128])
                );
            end else begin : g_no_inv
                assign aes_inv_dout[1023 - 128 * gi -: 128] = 128'h0;
            end
            sm4_pipe u_sm4 (
                .clk(clk), .rst_n(rst_n), .en(pipe_en),
                .valid_in(lane_hit[gi] && (algo == ALGO_SM4)),
                .decrypt(sm4_dec),
                .din(p_lane[1023 - 128 * gi -: 128]),
                .rk(sm4_rk),
                .valid_out(),
                .dout(sm4_dout[1023 - 128 * gi -: 128])
            );
        end
    endgenerate

    function automatic [127:0] pick_lane;
        input integer idx;
        begin
            if (algo == ALGO_SM4)
                pick_lane = lane_of(sm4_dout, idx);
            else if ((IS_DEC != 0) && (mode_q == MODE_ECB))
                pick_lane = lane_of(aes_inv_dout, idx);
            else
                pick_lane = lane_of(aes_fwd_dout, idx);
        end
    endfunction

    integer ai, aj, apos;
    reg [1023:0] assembled;
    reg [1023:0] dout_touch;
    reg [127:0] ks;
    reg [4:0] nb;
    reg [7:0] src0;
    reg [127:0] ks_cap;

    // dout_touch 把三组流水线输出都放进敏感列表。函数里的条件读取不会自动带上。
    always @(*) begin
        dout_touch = aes_fwd_dout ^ aes_inv_dout ^ sm4_dout;
        assembled = 1024'h0;
        ks = 128'h0;
        nb = 5'd0;
        src0 = 8'd0;
        apos = 0;
        ks_cap = pick_lane({{29{1'b0}}, sb_plane[tap]});
        if (sb_v[tap] && sb_ctr[tap]) begin
            for (ai = 0; ai < sb_pre_len[tap]; ai = ai + 1)
                assembled[1023 - 8 * ai -: 8] = sb_pre[tap][1023 - 8 * ai -: 8];
            apos = {{24{1'b0}}, sb_pre_len[tap]};
            for (ai = 0; ai < sb_nblocks[tap]; ai = ai + 1) begin
                ks = pick_lane(ai);
                nb = sb_nbytes[tap][5 * ai +: 5];
                src0 = sb_src[tap][8 * ai +: 8];
                for (aj = 0; aj < 16; aj = aj + 1) begin
                    if (aj < nb) begin
                        assembled[1023 - 8 * apos -: 8] =
                            getb(sb_in[tap], {{24{1'b0}}, src0} + aj) ^ ks[127 - 8 * aj -: 8];
                        apos = apos + 1;
                    end
                end
            end
        end else if (sb_v[tap]) begin
            for (ai = 0; ai < sb_nblocks[tap]; ai = ai + 1) begin
                ks = pick_lane(ai);
                for (aj = 0; aj < 16; aj = aj + 1)
                    assembled[1023 - 8 * (16 * ai + aj) -: 8] = ks[127 - 8 * aj -: 8];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            mode_q <= MODE_ECB;
            key_set <= 1'b0;
            key_q <= 256'h0;
            ctr <= 128'h0;
            ctr_num <= 5'd0;
            ecount <= 128'h0;
            ecb_n <= 4'd0;
            ecb_hold <= 120'h0;
            wait_ks <= 1'b0;
            err_mode <= 1'b0;
            err_no_key <= 1'b0;
            err_keep <= 1'b0;
            err_ecb_tail <= 1'b0;
        end else begin
            if (in_valid && keep_bad(in_keep))
                err_keep <= 1'b1;
            if (in_valid && !key_set)
                err_no_key <= 1'b1;

            if (init && idle) begin
                mode_q <= mode;
                ctr_num <= 5'd0;
                ecb_n <= 4'd0;
                ecb_hold <= 120'h0;
                wait_ks <= 1'b0;
                err_mode <= (mode > MODE_CTR);
                err_no_key <= 1'b0;
                err_keep <= 1'b0;
                err_ecb_tail <= 1'b0;
                if (key_valid) begin
                    key_q <= key;
                    key_set <= 1'b1;
                end
                if (iv_valid && (mode == MODE_CTR))
                    ctr <= iv;
            end else if (pipe_en) begin
                if (take && p_err_tail)
                    err_ecb_tail <= 1'b1;
                if (take && (mode_q == MODE_ECB)) begin
                    ecb_n <= p_ecb_n;
                    ecb_hold <= p_ecb_hold;
                end
                if (take && (mode_q == MODE_CTR)) begin
                    ctr <= p_ctr;
                    if (!p_ks)
                        ctr_num <= p_num;
                    else
                        wait_ks <= 1'b1;
                end
                if (sb_v[tap] && sb_ks[tap]) begin
                    ecount <= ks_cap;
                    ctr_num <= sb_num[tap];
                    wait_ks <= 1'b0;
                end
            end
        end
    end

    // 旁路每级单独 always。init 被采样时保持，与上面的 if (init && idle) 一致。
    wire sb_shift = pipe_en && !(init && idle);
    genvar si_g;
    generate
        for (si_g = 0; si_g < 32; si_g = si_g + 1) begin : g_sb
            if (si_g == 0) begin : g_in
                always @(posedge clk) begin
                    if (!rst_n) begin
                        sb_v[0] <= 1'b0;
                        sb_last[0] <= 1'b0;
                        sb_ctr[0] <= 1'b0;
                        sb_ks[0] <= 1'b0;
                        sb_plane[0] <= 3'd0;
                        sb_num[0] <= 5'd0;
                        sb_nblocks[0] <= 4'd0;
                        sb_pre_len[0] <= 8'd0;
                        sb_out_len[0] <= 8'd0;
                        sb_pre[0] <= 1024'h0;
                        sb_in[0] <= 1024'h0;
                        sb_nbytes[0] <= 40'h0;
                        sb_src[0] <= 64'h0;
                    end else if (sb_shift) begin
                        sb_v[0] <= push;
                        sb_last[0] <= push && in_last && !p_err_tail;
                        sb_ctr[0] <= (mode_q == MODE_CTR);
                        sb_ks[0] <= p_ks;
                        sb_plane[0] <= p_plane;
                        sb_num[0] <= p_num;
                        sb_nblocks[0] <= p_nblocks;
                        sb_pre_len[0] <= p_pre_len;
                        sb_out_len[0] <= p_out_len;
                        sb_pre[0] <= p_pre;
                        sb_in[0] <= in_data;
                        sb_nbytes[0] <= p_nbytes;
                        sb_src[0] <= p_src;
                    end
                end
            end else begin : g_sh
                always @(posedge clk) begin
                    if (!rst_n) begin
                        sb_v[si_g] <= 1'b0;
                        sb_last[si_g] <= 1'b0;
                        sb_ctr[si_g] <= 1'b0;
                        sb_ks[si_g] <= 1'b0;
                        sb_plane[si_g] <= 3'd0;
                        sb_num[si_g] <= 5'd0;
                        sb_nblocks[si_g] <= 4'd0;
                        sb_pre_len[si_g] <= 8'd0;
                        sb_out_len[si_g] <= 8'd0;
                        sb_pre[si_g] <= 1024'h0;
                        sb_in[si_g] <= 1024'h0;
                        sb_nbytes[si_g] <= 40'h0;
                        sb_src[si_g] <= 64'h0;
                    end else if (sb_shift) begin
                        if (si_g == ({1'b0, tap} + 6'd1))
                            sb_v[si_g] <= 1'b0;
                        else
                            sb_v[si_g] <= sb_v[si_g - 1];
                        sb_last[si_g] <= sb_last[si_g - 1];
                        sb_ctr[si_g] <= sb_ctr[si_g - 1];
                        sb_ks[si_g] <= sb_ks[si_g - 1];
                        sb_plane[si_g] <= sb_plane[si_g - 1];
                        sb_num[si_g] <= sb_num[si_g - 1];
                        sb_nblocks[si_g] <= sb_nblocks[si_g - 1];
                        sb_pre_len[si_g] <= sb_pre_len[si_g - 1];
                        sb_out_len[si_g] <= sb_out_len[si_g - 1];
                        sb_pre[si_g] <= sb_pre[si_g - 1];
                        sb_in[si_g] <= sb_in[si_g - 1];
                        sb_nbytes[si_g] <= sb_nbytes[si_g - 1];
                        sb_src[si_g] <= sb_src[si_g - 1];
                    end
                end
            end
        end
    endgenerate
endmodule
