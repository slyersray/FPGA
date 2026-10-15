// 一路 SM4 流水线。每级一轮，每拍进入一个分组，32 拍后出结果。
// decrypt=1 时用逆序轮密钥。该信号在分组还在流水线里时必须保持不变。
// 分组字节 0 在 din[127:120]。
module sm4_pipe (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          en,
    input  wire          valid_in,
    input  wire          decrypt,
    input  wire [127:0]  din,
    input  wire [1023:0] rk,
    output wire          valid_out,
    output wire [127:0]  dout
);
    reg [127:0] st [0:31];
    reg         vv [0:31];

    `include "sm4_sbox.vh"

    function automatic [31:0] rk_at;
        input [1023:0] rkeys;
        input integer idx;
        begin
            rk_at = rkeys[1023 - 32 * idx -: 32];
        end
    endfunction

    function automatic [31:0] sm4_t;
        input [31:0] x;
        reg [31:0] t;
        begin
            t = {sm4_sbox(x[31:24]), sm4_sbox(x[23:16]),
                 sm4_sbox(x[15:8]), sm4_sbox(x[7:0])};
            sm4_t = t ^ {t[29:0], t[31:30]} ^ {t[21:0], t[31:22]}
                      ^ {t[13:0], t[31:14]} ^ {t[7:0], t[31:8]};
        end
    endfunction

    function automatic [127:0] sm4_round;
        input [127:0] s;
        input [31:0] rkey;
        reg [31:0] b0, b1, b2, b3, n3;
        begin
            b0 = s[127:96];
            b1 = s[95:64];
            b2 = s[63:32];
            b3 = s[31:0];
            n3 = b0 ^ sm4_t(b1 ^ b2 ^ b3 ^ rkey);
            sm4_round = {b1, b2, b3, n3};
        end
    endfunction

    // 32 轮之后状态是 {B0,B1,B2,B3}，输出反序为 {B3,B2,B1,B0}。
    assign valid_out = vv[31];
    assign dout = {st[31][31:0], st[31][63:32], st[31][95:64], st[31][127:96]};

    // 每级单独 always。Verilator 5.020 不支持在过程 for 里对数组做非阻塞赋值。
    genvar gs;
    generate
        for (gs = 0; gs < 32; gs = gs + 1) begin : g_stage
            always @(posedge clk) begin
                if (!rst_n) begin
                    st[gs] <= 128'h0;
                    vv[gs] <= 1'b0;
                end else if (en) begin
                    if (gs == 0) begin
                        vv[gs] <= valid_in;
                        st[gs] <= sm4_round(din, rk_at(rk, decrypt ? 31 : 0));
                    end else begin
                        vv[gs] <= vv[gs - 1];
                        st[gs] <= sm4_round(st[gs - 1],
                                            rk_at(rk, decrypt ? (31 - gs) : gs));
                    end
                end
            end
        end
    endgenerate
endmodule
