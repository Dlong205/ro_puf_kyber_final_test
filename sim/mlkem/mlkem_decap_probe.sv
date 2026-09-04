`timescale 1ns/1ps

// Decapsulation harness for the NIST KeyGen tgId=1/tcId=1 key pair.  The
// software driver requests/discards ek, supplies an independently generated
// reference ciphertext, and checks the resulting shared key.
module mlkem_decap_probe (
    input  wire         clk,
    input  wire         ct_valid,
    input  wire [31:0]  ct_word,
    output wire         ct_req,
    output wire [255:0] shared_key,
    output wire         server_done,
    output wire [5:0]   server_state,
    output wire         server_equal,
    output wire [8:0]   pk_word_count
);
    reg rst_n = 1'b0;
    reg start_reg = 1'b0;
    reg [8:0] pk_words = 9'd0;
    integer cycle_count = 0;

    localparam [255:0] SEED_D =
        256'h0a661a028afb14161d47fbb503858eaf5329b34fe42eb1e492ba72464793b847;
    localparam [255:0] SEED_Z =
        256'ha9a044b803773157fa60f78d0117b27f18b1848840c50d8a45bc309e9eb38c1f;

    wire ready_pk;
    wire server_valid;
    wire server_valid_out;
    wire [31:0] unused_pk_word;

    assign server_state = server_inst.state;
    assign server_equal = server_inst.equal;
    assign pk_word_count = pk_words;

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            start_reg <= 1'b0;
            pk_words <= 9'd0;
        end else begin
            cycle_count <= cycle_count + 1;
            start_reg <= (cycle_count == 0);
            if (server_valid_out)
                pk_words <= pk_words + 1'b1;
        end
    end

    Kyber_Server server_inst (
        .clk(clk), .rst(~rst_n), .start(start_reg),
        .wen(ct_valid), .k(3'd2), .ready_c(1'b1),
        // Keep requesting throughout the transmit state.  The Server's last
        // marker and state gate terminate the synchronous FIFO read exactly.
        .req_pk(ready_pk), .din(ct_word), .ready_pk(ready_pk),
        .req_c(ct_req), .valid(server_valid),
        .valid_out(server_valid_out), .dout(unused_pk_word),
        .seed_d(SEED_D), .seed_z(SEED_Z), .K(shared_key),
        .done(server_done)
    );
endmodule
