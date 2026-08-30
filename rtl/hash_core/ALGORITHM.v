module ALGORITHM (
    input wire Clk,
    input wire reset,
    input wire en_in,
    input wire en_ctr,
    input wire [1599:0] padding_in,
    input wire [4:0] RC_id_in,
    output wire [4:0] RC_flag,
    output wire [1599:0] data_out
);
    wire [1599:0] Thta1_str_tmp;
    wire [1599:0] Rho_str_tmp;
    wire [1599:0] Chi1_str_tmp;
    wire [1599:0] Chi2_str_tmp;
    wire [319:0] Thta1_blk_tmp;
    wire [1599:0] Rho_blk_tmp;
    wire [575:0] Chi1_blk_tmp;
    wire [575:0] Chi1_blk_tmp2;
    wire [511:0] Chi2_blk_tmp;
    wire [4:0] RC_index;
    wire [4:0] RC_id_tmp1;
    wire [4:0] RC_id_tmp2;
    wire [4:0] RC_id_tmp3;
    wire en1, en2, en3, en4;

    THETA1 STEP_MAPPING_1 (
        .Clk(Clk),
        .reset(reset),
        .enable(en_in),
        .en_ctr(en_ctr),
        .Thta1_in(padding_in),
        .RC_id_in(RC_id_in),
        .RC_id_out(RC_id_tmp1),
        .Thta1_str_out(Thta1_str_tmp),
        .en_out(en1),
        .Thta1_blk_out(Thta1_blk_tmp)
    );
    
    THETA2_RHO_PI STEP_MAPPING_2 (
        .Clk(Clk),
        .reset(reset),
        .enable(en1),
        .en_ctr(en_ctr),
        .Rho_str_in(Thta1_str_tmp),
        .Rho_data_in(Thta1_blk_tmp),
        .RC_id_in(RC_id_tmp1),
        .RC_id_out(RC_id_tmp2),
        .String_out(Rho_str_tmp),
        .en_out(en2),
        .Rho_data_out(Rho_blk_tmp)
    );
    
    CHI1 STEP_MAPPING_3 (
        .Clk(Clk),
        .reset(reset),
        .enable(en2),
        .en_ctr(en_ctr),
        .Chi1_data_in(Rho_blk_tmp),
        .Chi1_str_in(Rho_str_tmp),
        .RC_id_in(RC_id_tmp2),
        .RC_id_out(RC_id_tmp3),
        .Chi1_data_out(Chi1_blk_tmp),
        .en_out(en3),
        .Chi1_str_out(Chi1_str_tmp)
    );
    
    CHI2 STEP_MAPPING_4 (
        .Clk(Clk),
        .reset(reset),
        .enable(en3),
        .en_ctr(en_ctr),
        .Chi2_str_in(Chi1_str_tmp),
        .Chi2_chi1_in(Chi1_blk_tmp),
        .RC_id_in(RC_id_tmp3),
        .RC_flag(RC_flag),
        .RC_id_out(RC_index),
        .Chi2_str_out(Chi2_str_tmp),
        .Chi2_data_out(Chi2_blk_tmp),
        .en_out(en4),
        .Chi2_chi1_out(Chi1_blk_tmp2)
    );
    
    IOTA STEP_MAPPING_5 (
        .Clk(Clk),
        .reset(reset),
        .en_ctr(en_ctr),
        .enable(en4),
        .Str_in(Chi2_str_tmp),
        .Chi1_data(Chi1_blk_tmp2),
        .Chi2_data(Chi2_blk_tmp),
        .RC_index(RC_index),
        .Str_out(data_out)
    );
endmodule
