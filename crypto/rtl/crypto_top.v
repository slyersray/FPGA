// AES-256 / SM4，ECB / CTR。加密流与解密流同时工作，各 8 路流水线。
// algo 整模块二选一，只在两条流都空闲时装入。
// 字节 0 在总线最高位。keep[127] 是本拍第 1 个字节。
// 上下文语义见 crypto/spec/aes_sm4_design_spec.md。
module crypto_top (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          algo_load,
    input  wire [1:0]    algo,
    output wire          algo_ready,
    output wire [1:0]    algo_q,

    input  wire          enc_init,
    input  wire [1:0]    enc_mode,
    input  wire          enc_key_valid,
    input  wire [255:0]  enc_key,
    input  wire          enc_iv_valid,
    input  wire [127:0]  enc_iv,
    input  wire          enc_in_valid,
    output wire          enc_in_ready,
    input  wire [1023:0] enc_in_data,
    input  wire [127:0]  enc_in_keep,
    input  wire          enc_in_last,
    output wire          enc_out_valid,
    input  wire          enc_out_ready,
    output wire [1023:0] enc_out_data,
    output wire [127:0]  enc_out_keep,
    output wire          enc_out_last,
    output wire          enc_err_mode,
    output wire          enc_err_no_key,
    output wire          enc_err_keep,
    output wire          enc_err_ecb_tail,

    input  wire          dec_init,
    input  wire [1:0]    dec_mode,
    input  wire          dec_key_valid,
    input  wire [255:0]  dec_key,
    input  wire          dec_iv_valid,
    input  wire [127:0]  dec_iv,
    input  wire          dec_in_valid,
    output wire          dec_in_ready,
    input  wire [1023:0] dec_in_data,
    input  wire [127:0]  dec_in_keep,
    input  wire          dec_in_last,
    output wire          dec_out_valid,
    input  wire          dec_out_ready,
    output wire [1023:0] dec_out_data,
    output wire [127:0]  dec_out_keep,
    output wire          dec_out_last,
    output wire          dec_err_mode,
    output wire          dec_err_no_key,
    output wire          dec_err_keep,
    output wire          dec_err_ecb_tail
);
    localparam ALGO_AES = 2'd0;
    localparam ALGO_SM4 = 2'd1;

    reg [1:0] algo_r;
    wire enc_idle;
    wire dec_idle;

    assign algo_q     = algo_r;
    assign algo_ready = enc_idle && dec_idle;

    always @(posedge clk) begin
        if (!rst_n)
            algo_r <= ALGO_AES;
        else if (algo_load && algo_ready && (algo == ALGO_AES || algo == ALGO_SM4))
            algo_r <= algo;
    end

    crypto_stream #(.IS_DEC(0)) u_enc (
        .clk(clk), .rst_n(rst_n), .algo(algo_r),
        .init(enc_init), .mode(enc_mode),
        .key_valid(enc_key_valid), .key(enc_key),
        .iv_valid(enc_iv_valid), .iv(enc_iv),
        .in_valid(enc_in_valid), .in_ready(enc_in_ready),
        .in_data(enc_in_data), .in_keep(enc_in_keep), .in_last(enc_in_last),
        .out_valid(enc_out_valid), .out_ready(enc_out_ready),
        .out_data(enc_out_data), .out_keep(enc_out_keep), .out_last(enc_out_last),
        .err_mode(enc_err_mode), .err_no_key(enc_err_no_key),
        .err_keep(enc_err_keep), .err_ecb_tail(enc_err_ecb_tail),
        .idle(enc_idle)
    );

    crypto_stream #(.IS_DEC(1)) u_dec (
        .clk(clk), .rst_n(rst_n), .algo(algo_r),
        .init(dec_init), .mode(dec_mode),
        .key_valid(dec_key_valid), .key(dec_key),
        .iv_valid(dec_iv_valid), .iv(dec_iv),
        .in_valid(dec_in_valid), .in_ready(dec_in_ready),
        .in_data(dec_in_data), .in_keep(dec_in_keep), .in_last(dec_in_last),
        .out_valid(dec_out_valid), .out_ready(dec_out_ready),
        .out_data(dec_out_data), .out_keep(dec_out_keep), .out_last(dec_out_last),
        .err_mode(dec_err_mode), .err_no_key(dec_err_no_key),
        .err_keep(dec_err_keep), .err_ecb_tail(dec_err_ecb_tail),
        .idle(dec_idle)
    );
endmodule
