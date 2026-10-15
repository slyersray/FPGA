// AES-256 密钥扩展，输出 15 个 128 bit 轮密钥。
// rk[1919:1792] 是第 0 轮，rk[127:0] 是第 14 轮。
module aes256_key_expand (
    input  wire [255:0]  key,
    output reg  [1919:0] rk
);
    integer i;
    integer n;
    reg [31:0] w [0:59];
    reg [31:0] temp;

    `include "aes_sbox.vh"

    function [31:0] rotword;
        input [31:0] x;
        begin
            rotword = {x[23:0], x[31:24]};
        end
    endfunction

    function [31:0] subword;
        input [31:0] x;
        begin
            subword = {aes_sbox(x[31:24]), aes_sbox(x[23:16]),
                       aes_sbox(x[15:8]), aes_sbox(x[7:0])};
        end
    endfunction

    function [7:0] rcon;
        input integer idx;
        begin
            case (idx)
                1: rcon = 8'h01;
                2: rcon = 8'h02;
                3: rcon = 8'h04;
                4: rcon = 8'h08;
                5: rcon = 8'h10;
                6: rcon = 8'h20;
                7: rcon = 8'h40;
                8: rcon = 8'h80;
                9: rcon = 8'h1b;
                10: rcon = 8'h36;
                default: rcon = 8'h00;
            endcase
        end
    endfunction

    always @(*) begin
        w[0] = key[255:224];
        w[1] = key[223:192];
        w[2] = key[191:160];
        w[3] = key[159:128];
        w[4] = key[127:96];
        w[5] = key[95:64];
        w[6] = key[63:32];
        w[7] = key[31:0];
        for (i = 8; i < 60; i = i + 1) begin
            temp = w[i - 1];
            if ((i % 8) == 0)
                temp = subword(rotword(temp)) ^ {rcon(i / 8), 24'h0};
            else if ((i % 8) == 4)
                temp = subword(temp);
            w[i] = w[i - 8] ^ temp;
        end
        for (n = 0; n < 15; n = n + 1) begin
            rk[1919 - 128 * n -: 128] = {w[4 * n], w[4 * n + 1],
                                          w[4 * n + 2], w[4 * n + 3]};
        end
    end
endmodule
