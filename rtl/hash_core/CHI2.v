module CHI2 (
    input wire Clk,
    input wire reset,
    input wire enable,
    input wire en_ctr,
    input wire [1599:0] Chi2_str_in,
    input wire [575:0] Chi2_chi1_in,
    input wire [4:0] RC_id_in,
    output reg [1599:0] Chi2_str_out,
    output reg [511:0] Chi2_data_out,
    output reg [4:0] RC_id_out,
    output reg [4:0] RC_flag,
    output reg en_out,
    output reg [575:0] Chi2_chi1_out
);
    wire [511:0] chi2_tmp;
    wire [575:0] chi1_tmp;
    wire [4:0] RC_id_tmp;
    wire [1599:0] A_in;

    ADDER ADDER_ID (
        .a(1'b1),
        .b(RC_id_in),
        .Y(RC_id_tmp)
    );

    assign A_in = Chi2_str_in;
    assign chi1_tmp = Chi2_chi1_in;

    assign chi2_tmp[63:0] = A_in[639:576] ^ (~A_in[383:320] & A_in[447:384]);
    assign chi2_tmp[127:64] = A_in[703:640] ^ (~A_in[767:704] & A_in[831:768]);
    assign chi2_tmp[191:128] = A_in[767:704] ^ (~A_in[831:768] & A_in[895:832]);
    assign chi2_tmp[255:192] = A_in[831:768] ^ (~A_in[895:832] & A_in[959:896]);
    assign chi2_tmp[319:256] = A_in[895:832] ^ (~A_in[959:896] & A_in[703:640]);
    assign chi2_tmp[383:320] = A_in[959:896] ^ (~A_in[703:640] & A_in[767:704]);
    assign chi2_tmp[447:384] = A_in[1023:960] ^ (~A_in[1087:1024] & A_in[1151:1088]);
    assign chi2_tmp[511:448] = A_in[1087:1024] ^ (~A_in[1151:1088] & A_in[1215:1152]);

    always @(*) begin
        if (reset == 1'b0 || en_ctr == 1'b0) begin
            Chi2_data_out = 512'b0;
            Chi2_chi1_out = 576'b0;
            Chi2_str_out = 1600'b0;
            RC_flag = 5'b0;
            en_out = 1'b0;
            RC_id_out = 5'b0;
        end else if (enable == 1'b1 && en_ctr == 1'b1) begin
            Chi2_data_out = chi2_tmp;
            Chi2_chi1_out = chi1_tmp;
            Chi2_str_out = Chi2_str_in;
            RC_id_out = RC_id_in;
            RC_flag = RC_id_tmp;
            en_out = enable;
        end else begin
            Chi2_data_out = 512'b0;
            Chi2_chi1_out = 576'b0;
            Chi2_str_out = 1600'b0;
            RC_flag = 5'b0;
            RC_id_out = RC_id_in;
            en_out = 1'b0;
        end
    end
endmodule
