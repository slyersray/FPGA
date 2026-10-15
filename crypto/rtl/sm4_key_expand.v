// SM4 密钥扩展。key 是 16 字节，字节 0 在 key[127:120]。
// rk[1023:992] 是第 0 轮，rk[31:0] 是第 31 轮。
module sm4_key_expand (
    input  wire [127:0] key,
    output reg  [1023:0] rk
);
    integer i;
    reg [31:0] k0, k1, k2, k3;
    reg [31:0] nxt;
    reg [31:0] words [0:31];

    `include "sm4_sbox.vh"

    function [31:0] fk;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: fk = 32'ha3b1bac6;
                2'd1: fk = 32'h56aa3350;
                2'd2: fk = 32'h677d9197;
                default: fk = 32'hb27022dc;
            endcase
        end
    endfunction

    function [31:0] ck;
        input [4:0] idx;
        reg [15:0] base;
        begin
            base = 16'd28 * idx;
            ck = {base[7:0], base[7:0] + 8'd7, base[7:0] + 8'd14, base[7:0] + 8'd21};
        end
    endfunction

    function [31:0] tau;
        input [31:0] x;
        begin
            tau = {sm4_sbox(x[31:24]), sm4_sbox(x[23:16]),
                   sm4_sbox(x[15:8]), sm4_sbox(x[7:0])};
        end
    endfunction

    function [31:0] key_sub;
        input [31:0] x;
        reg [31:0] t;
        begin
            t = tau(x);
            key_sub = t ^ {t[18:0], t[31:19]} ^ {t[8:0], t[31:9]};
        end
    endfunction

    always @(*) begin
        k0 = key[127:96] ^ fk(2'd0);
        k1 = key[95:64]  ^ fk(2'd1);
        k2 = key[63:32]  ^ fk(2'd2);
        k3 = key[31:0]   ^ fk(2'd3);
        for (i = 0; i < 32; i = i + 1) begin
            nxt = k0 ^ key_sub(k1 ^ k2 ^ k3 ^ ck(i[4:0]));
            k0 = k1;
            k1 = k2;
            k2 = k3;
            k3 = nxt;
            words[i] = nxt;
        end
        for (i = 0; i < 32; i = i + 1)
            rk[1023 - 32 * i -: 32] = words[i];
    end
endmodule
