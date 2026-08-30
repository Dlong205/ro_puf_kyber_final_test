module THETA1 (
    input wire Clk,
    input wire reset,
    input wire enable,
    input wire en_ctr,
    input wire [1599:0] Thta1_in,
    input wire [4:0] RC_id_in,
    output reg [1599:0] Thta1_str_out,
    output reg [4:0] RC_id_out,
    output reg en_out,
    output reg [319:0] Thta1_blk_out
);
    wire [1599:0] A;
    wire [319:0] C;
    wire [319:0] Thta1_out_tmp;

    assign A = Thta1_in;

    assign C[63:0] = A[63:0] ^ A[383:320] ^ A[703:640] ^ A[1023:960] ^ A[1343:1280];
    assign C[127:64] = A[127:64] ^ A[447:384] ^ A[767:704] ^ A[1087:1024] ^ A[1407:1344];
    assign C[191:128] = A[191:128] ^ A[511:448] ^ A[831:768] ^ A[1151:1088] ^ A[1471:1408];
    assign C[255:192] = A[255:192] ^ A[575:512] ^ A[895:832] ^ A[1215:1152] ^ A[1535:1472];
    assign C[319:256] = A[319:256] ^ A[639:576] ^ A[959:896] ^ A[1279:1216] ^ A[1599:1536];

    assign Thta1_out_tmp[63:0] = {C[126:64], C[127]} ^ C[319:256];
    assign Thta1_out_tmp[127:64] = {C[190:128], C[191]} ^ C[63:0];
    assign Thta1_out_tmp[191:128] = {C[254:192], C[255]} ^ C[127:64];
    assign Thta1_out_tmp[255:192] = {C[318:256], C[319]} ^ C[191:128];
    assign Thta1_out_tmp[319:256] = {C[62:0], C[63]} ^ C[255:192];

    always @(*) begin
        if (reset == 1'b0 || en_ctr == 1'b0) begin
            Thta1_str_out = 1600'b0;
            Thta1_blk_out = 320'b0;
            en_out = 1'b0;
            RC_id_out = 5'b0;
        end else if (enable == 1'b1 && en_ctr == 1'b1) begin
            Thta1_str_out = Thta1_in;
            Thta1_blk_out = Thta1_out_tmp;
            RC_id_out = RC_id_in;
            en_out = enable;
        end else begin
            Thta1_str_out = 1600'b0;
            Thta1_blk_out = 320'b0;
            RC_id_out = RC_id_in;
            en_out = 1'b0;
        end
    end
endmodule
