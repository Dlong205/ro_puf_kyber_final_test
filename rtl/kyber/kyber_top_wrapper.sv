`timescale 1ns / 1ps

module kyber_top_wrapper (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [2:0]  k,
    output logic        ready_pk,
    output logic        ready_c,
    output logic        req_pk,
    output logic        req_c,
    output logic        valid_server,
    output logic        valid_client,
    output logic [31:0] dout_server,
    output logic [31:0] dout_client
);

    logic clk_int;
    logic rst_int;
    
    assign clk_int = clk;
    assign rst_int = ~rst_n;

    Kyber_top kyber_inst (
        .clk        (clk_int),
        .rst        (rst_int),
        .start      (start),
        .k          (k),
        .ready_pk   (ready_pk),
        .ready_c    (ready_c),
        .req_pk     (req_pk),
        .req_c      (req_c),
        .valid_server (valid_server),
        .valid_client (valid_client),
        .dout_server  (dout_server),
        .dout_client  (dout_client)
    );

endmodule