// 一路 AES-256 流水线。每级一轮，每拍进入一个分组，15 拍后出结果。
// DECRYPT=0：正变换。DECRYPT=1：逆密码。分组字节 0 在 din[127:120]。
module aes256_pipe #(
    parameter DECRYPT = 0
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          en,
    input  wire          valid_in,
    input  wire [127:0]  din,
    input  wire [1919:0] rk,
    output wire          valid_out,
    output wire [127:0]  dout
);
    reg [127:0] st [0:14];
    reg         vv [0:14];

    `include "aes_sbox.vh"
    `include "aes_inv_sbox.vh"

    function automatic [127:0] rk_at;
        input [1919:0] rkeys;
        input integer idx;
        begin
            rk_at = rkeys[1919 - 128 * idx -: 128];
        end
    endfunction

    function automatic [7:0] xtime;
        input [7:0] a;
        begin
            xtime = {a[6:0], 1'b0} ^ (8'h1b & {8{a[7]}});
        end
    endfunction

    function automatic [7:0] gmul;
        input [7:0] a;
        input [3:0] n;
        reg [7:0] r;
        reg [7:0] p;
        integer k;
        begin
            r = 8'h00;
            p = a;
            for (k = 0; k < 4; k = k + 1) begin
                if (n[k])
                    r = r ^ p;
                p = xtime(p);
            end
            gmul = r;
        end
    endfunction

    function automatic [127:0] sub_bytes;
        input [127:0] s;
        input inv;
        integer j;
        reg [7:0] b;
        begin
            sub_bytes = 128'h0;
            for (j = 0; j < 16; j = j + 1) begin
                b = s[127 - 8 * j -: 8];
                sub_bytes[127 - 8 * j -: 8] = inv ? aes_inv_sbox(b) : aes_sbox(b);
            end
        end
    endfunction

    function automatic [127:0] shift_rows;
        input [127:0] s;
        input inv;
        reg [7:0] b [0:15];
        reg [7:0] o [0:15];
        integer j;
        begin
            for (j = 0; j < 16; j = j + 1)
                b[j] = s[127 - 8 * j -: 8];
            if (!inv) begin
                o[0]=b[0]; o[1]=b[5]; o[2]=b[10]; o[3]=b[15];
                o[4]=b[4]; o[5]=b[9]; o[6]=b[14]; o[7]=b[3];
                o[8]=b[8]; o[9]=b[13]; o[10]=b[2]; o[11]=b[7];
                o[12]=b[12]; o[13]=b[1]; o[14]=b[6]; o[15]=b[11];
            end else begin
                o[0]=b[0]; o[1]=b[13]; o[2]=b[10]; o[3]=b[7];
                o[4]=b[4]; o[5]=b[1]; o[6]=b[14]; o[7]=b[11];
                o[8]=b[8]; o[9]=b[5]; o[10]=b[2]; o[11]=b[15];
                o[12]=b[12]; o[13]=b[9]; o[14]=b[6]; o[15]=b[3];
            end
            shift_rows = 128'h0;
            for (j = 0; j < 16; j = j + 1)
                shift_rows[127 - 8 * j -: 8] = o[j];
        end
    endfunction

    function automatic [31:0] mix_col;
        input [31:0] c;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = c[31:24];
            a1 = c[23:16];
            a2 = c[15:8];
            a3 = c[7:0];
            mix_col[31:24] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3;
            mix_col[23:16] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3;
            mix_col[15:8]  = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3);
            mix_col[7:0]   = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3);
        end
    endfunction

    function automatic [31:0] inv_mix_col;
        input [31:0] c;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = c[31:24];
            a1 = c[23:16];
            a2 = c[15:8];
            a3 = c[7:0];
            inv_mix_col[31:24] = gmul(a0, 4'he) ^ gmul(a1, 4'hb) ^ gmul(a2, 4'hd) ^ gmul(a3, 4'h9);
            inv_mix_col[23:16] = gmul(a0, 4'h9) ^ gmul(a1, 4'he) ^ gmul(a2, 4'hb) ^ gmul(a3, 4'hd);
            inv_mix_col[15:8]  = gmul(a0, 4'hd) ^ gmul(a1, 4'h9) ^ gmul(a2, 4'he) ^ gmul(a3, 4'hb);
            inv_mix_col[7:0]   = gmul(a0, 4'hb) ^ gmul(a1, 4'hd) ^ gmul(a2, 4'h9) ^ gmul(a3, 4'he);
        end
    endfunction

    function automatic [127:0] mix_columns;
        input [127:0] s;
        input inv;
        integer c;
        reg [31:0] col;
        begin
            mix_columns = 128'h0;
            for (c = 0; c < 4; c = c + 1) begin
                col = s[127 - 32 * c -: 32];
                mix_columns[127 - 32 * c -: 32] = inv ? inv_mix_col(col) : mix_col(col);
            end
        end
    endfunction

    function automatic [127:0] enc_round;
        input [127:0] s;
        input [127:0] rkey;
        input last;
        reg [127:0] t;
        begin
            t = shift_rows(sub_bytes(s, 1'b0), 1'b0);
            if (!last)
                t = mix_columns(t, 1'b0);
            enc_round = t ^ rkey;
        end
    endfunction

    function automatic [127:0] dec_round;
        input [127:0] s;
        input [127:0] rkey;
        input last;
        reg [127:0] t;
        begin
            t = sub_bytes(shift_rows(s, 1'b1), 1'b1) ^ rkey;
            if (!last)
                t = mix_columns(t, 1'b1);
            dec_round = t;
        end
    endfunction

    assign valid_out = vv[14];
    assign dout      = st[14];

    // 每级单独 always。Verilator 5.020 不支持在过程 for 里对数组做非阻塞赋值。
    genvar gs;
    generate
        for (gs = 0; gs < 15; gs = gs + 1) begin : g_stage
            always @(posedge clk) begin
                if (!rst_n) begin
                    st[gs] <= 128'h0;
                    vv[gs] <= 1'b0;
                end else if (en) begin
                    if (gs == 0) begin
                        vv[gs] <= valid_in;
                        if (DECRYPT != 0)
                            st[gs] <= din ^ rk_at(rk, 14);
                        else
                            st[gs] <= din ^ rk_at(rk, 0);
                    end else if (gs == 14) begin
                        vv[gs] <= vv[gs - 1];
                        if (DECRYPT != 0)
                            st[gs] <= dec_round(st[gs - 1], rk_at(rk, 0), 1'b1);
                        else
                            st[gs] <= enc_round(st[gs - 1], rk_at(rk, 14), 1'b1);
                    end else begin
                        vv[gs] <= vv[gs - 1];
                        if (DECRYPT != 0)
                            st[gs] <= dec_round(st[gs - 1], rk_at(rk, 14 - gs), 1'b0);
                        else
                            st[gs] <= enc_round(st[gs - 1], rk_at(rk, gs), 1'b0);
                    end
                end
            end
        end
    endgenerate
endmodule
