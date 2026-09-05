`timescale 1ns/1ps

// Isolated ML-KEM-512 encapsulation harness.  A software driver supplies the
// NIST encapsulation key only when the Client requests a word, then drains the
// generated ciphertext.  This separates Client/Encaps failures from the
// Server/Decaps datapath used by the legacy loopback test.
module mlkem_encap_probe (
    input  wire         clk,
    input  wire [255:0] seed_m,
    input  wire         pk_valid,
    input  wire [31:0]  pk_word,
    input  wire         ct_req,
    output wire         pk_req,
    output wire         ready_c,
    output wire         ct_valid,
    output wire [31:0]  ct_word,
    output wire [255:0] shared_key,
    output wire         client_done,
    output wire [5:0]   client_state
);
    reg rst_n = 1'b0;
    reg start_reg = 1'b0;
    integer cycle_count = 0;

    wire unused_valid;
    wire unused_valid_out;

    assign client_state = client_inst.state;

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            start_reg <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            start_reg <= (cycle_count == 0);
        end
    end

`ifdef MLKEM_DEBUG
    integer dbg_ntt_outputs = 0;
    integer dbg_noise_words = 0;
    integer dbg_matrix_reads = 0;
    reg dbg_matrix_read_d = 1'b0;
    reg [4:0] dbg_state_r13_prev = 5'h0;
    integer dbg_u_pre_poly = 0;
    integer dbg_ram_index;
    reg dbg_v_noise_dumped = 1'b0;

    always @(posedge clk) begin
        if (!rst_n)
            dbg_ntt_outputs <= 0;
        else if (client_inst.NTT_valid) begin
            if (dbg_ntt_outputs < 384)
                $display("NTT_OUT cyc=%0d idx=%0d state=%h ready_u=%b data=%06h",
                    cycle_count, dbg_ntt_outputs, client_inst.state,
                    client_inst.ready_u, client_inst.NTT_dout);
            if (dbg_ntt_outputs == 0)
                $display("U0_RAM_HEAD R2=%06h,%06h,%06h,%06h R3=%06h,%06h,%06h,%06h E=%012h,%012h,%012h,%012h",
                    client_inst.ntt.RAM2.inst.mem[0],
                    client_inst.ntt.RAM2.inst.mem[1],
                    client_inst.ntt.RAM2.inst.mem[2],
                    client_inst.ntt.RAM2.inst.mem[3],
                    client_inst.ntt.RAM3.inst.mem[0],
                    client_inst.ntt.RAM3.inst.mem[1],
                    client_inst.ntt.RAM3.inst.mem[2],
                    client_inst.ntt.RAM3.inst.mem[3],
                    client_inst.ntt.RAM4.inst.mem[0],
                    client_inst.ntt.RAM4.inst.mem[1],
                    client_inst.ntt.RAM4.inst.mem[2],
                    client_inst.ntt.RAM4.inst.mem[3]);
            dbg_ntt_outputs <= dbg_ntt_outputs + 1;
        end

        if (!rst_n)
            dbg_noise_words <= 0;
        else if (client_inst.hash.ofifo1_wen) begin
            if ((dbg_noise_words < 8) ||
                ((dbg_noise_words >= 64) && (dbg_noise_words < 72)) ||
                ((dbg_noise_words >= 128) && (dbg_noise_words < 136)) ||
                ((dbg_noise_words >= 192) && (dbg_noise_words < 200)) ||
                ((dbg_noise_words >= 256) && (dbg_noise_words < 264)))
                $display("NOISE cyc=%0d idx=%0d state=%h nonce=%0d eta3=%b data=%07h",
                    cycle_count, dbg_noise_words, client_inst.state,
                    client_inst.nonce, client_inst.hash.decode_eta3,
                    client_inst.hash.ofifo1_din);
            dbg_noise_words <= dbg_noise_words + 1;
        end

        if (!rst_n) begin
            dbg_matrix_reads <= 0;
            dbg_matrix_read_d <= 1'b0;
        end else begin
            dbg_matrix_read_d <= client_inst.ofifo0_req &&
                                 !client_inst.ofifo0_empty;
            if (dbg_matrix_read_d) begin
                if (dbg_matrix_reads < 600)
                    $display("MAT_READ cyc=%0d idx=%0d data=%06h",
                        cycle_count, dbg_matrix_reads,
                        client_inst.ofifo0_dout);
                dbg_matrix_reads <= dbg_matrix_reads + 1;
            end
        end


        if (!rst_n) begin
            dbg_state_r13_prev <= 5'h0;
            dbg_u_pre_poly <= 0;
            dbg_v_noise_dumped <= 1'b0;
        end else begin
            dbg_state_r13_prev <= client_inst.ntt.state_r13;
            if ((client_inst.ntt.state_r13 == 5'hc) &&
                (dbg_state_r13_prev != 5'hc)) begin
                for (dbg_ram_index = 0; dbg_ram_index < 64;
                     dbg_ram_index = dbg_ram_index + 1) begin
                    $display("U_PRE poly=%0d idx=%0d data=%06h",
                        dbg_u_pre_poly, 2 * dbg_ram_index,
                        client_inst.ntt.RAM2.inst.mem[dbg_ram_index]);
                    $display("U_PRE poly=%0d idx=%0d data=%06h",
                        dbg_u_pre_poly, 2 * dbg_ram_index + 1,
                        client_inst.ntt.RAM3.inst.mem[dbg_ram_index]);
                    $display("E_PRE poly=%0d idx=%0d data=%06h",
                        dbg_u_pre_poly, 2 * dbg_ram_index,
                        client_inst.ntt.RAM4.inst.mem[dbg_ram_index][23:0]);
                    $display("E_PRE poly=%0d idx=%0d data=%06h",
                        dbg_u_pre_poly, 2 * dbg_ram_index + 1,
                        client_inst.ntt.RAM4.inst.mem[dbg_ram_index][47:24]);
                end
                dbg_u_pre_poly <= dbg_u_pre_poly + 1;
            end
            if ((client_inst.ntt.state_r13 == 5'h16) &&
                !dbg_v_noise_dumped) begin
                for (dbg_ram_index = 0; dbg_ram_index < 64;
                     dbg_ram_index = dbg_ram_index + 1) begin
                    $display("EPP_PRE idx=%0d data=%06h",
                        2 * dbg_ram_index,
                        client_inst.ntt.RAM4.inst.mem[dbg_ram_index][23:0]);
                    $display("EPP_PRE idx=%0d data=%06h",
                        2 * dbg_ram_index + 1,
                        client_inst.ntt.RAM4.inst.mem[dbg_ram_index][47:24]);
                end
                dbg_v_noise_dumped <= 1'b1;
            end
        end

        if (client_inst.state != client_inst.next_state)
            $display("STATE cyc=%0d %h->%h kc=%h patt_head=%b eta_head=%b patt=%b eta=%b nonce=%0d row=%0d col=%0d",
                cycle_count, client_inst.state, client_inst.next_state,
                client_inst.keccak_ctr, client_inst.patt_r[72],
                client_inst.eta3_r[72], client_inst.patt_bit,
                client_inst.eta3_bit, client_inst.nonce,
                client_inst.row, client_inst.col);
        if (client_inst.ntt.state != client_inst.ntt.next_state)
            $display("NTT_STATE cyc=%0d %h->%h poly=%0d col=%0d kctr=%0d",
                cycle_count, client_inst.ntt.state,
                client_inst.ntt.next_state, client_inst.ntt.ctr_NTT,
                client_inst.ntt.ctr_col, client_inst.ntt.ctr_k);
        if (client_inst.hash.sponge_done)
            $display("HASH_DONE cyc=%0d state=%h kc=%h rate=%0d ext=%b stream=%h patt=%b eta3=%b row=%0d col=%0d",
                cycle_count, client_inst.state, client_inst.keccak_ctr,
                client_inst.hash.sponge_output_rate,
                client_inst.hash.sponge_done_extend,
                client_inst.hash.matrix_stream_id,
                client_inst.patt_bit, client_inst.eta3_bit,
                client_inst.row, client_inst.col);
        if (client_inst.hash.ofifo0_wen)
            $display("MAT cyc=%0d stream=%h ctr=%0d data=%06h",
                cycle_count, client_inst.hash.decode_stream,
                client_inst.hash.fifo_GENA_ctr,
                client_inst.hash.ofifo0_din);
        if (client_inst.hash.ofifo0_wen && client_inst.hash.ofifo0_full)
            $display("MAT_DROP cyc=%0d stream=%h ctr=%0d data=%06h count=%0d",
                cycle_count, client_inst.hash.decode_stream,
                client_inst.hash.fifo_GENA_ctr,
                client_inst.hash.ofifo0_din,
                client_inst.hash.ofifo0_inst.inst.wr_count);
        if (client_inst.ntt.wen_RAM4 &&
            ((client_inst.ntt.state_r13 == 5'ha) ||
             (client_inst.ntt.state_r13 == 5'hb) ||
             (client_inst.ntt.state_r13 == 5'h14) ||
             (client_inst.ntt.state_r13 == 5'h15)))
            $display("NOISE_RAM_WRITE cyc=%0d state=%h addr=%0d data=%012h",
                cycle_count, client_inst.ntt.state_r13,
                client_inst.ntt.waddr_RAM2, client_inst.ntt.wdata_RAM2);
        if (client_inst.ntt.state == 5'h5)
            $display("NTT_DONE cyc=%0d poly=%0d RAM0=%06h,%06h,%06h,%06h RAM1=%06h,%06h,%06h,%06h",
                cycle_count, client_inst.ntt.ctr_NTT,
                client_inst.ntt.RAM0.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd0}],
                client_inst.ntt.RAM0.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd1}],
                client_inst.ntt.RAM0.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd2}],
                client_inst.ntt.RAM0.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd3}],
                client_inst.ntt.RAM1.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd0}],
                client_inst.ntt.RAM1.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd1}],
                client_inst.ntt.RAM1.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd2}],
                client_inst.ntt.RAM1.inst.mem[{client_inst.ntt.ctr_NTT[1:0], 6'd3}]);
    end
`endif

    Kyber_Client client_inst (
        .clk(clk), .rst(~rst_n), .start(start_reg),
        .wen(pk_valid), .k(3'd2), .ready_pk(1'b1),
        .req_c(ct_req), .din(pk_word), .ready_c(ready_c),
        .req_pk(pk_req), .valid(unused_valid),
        .valid_out(ct_valid), .dout(ct_word),
        .seed_m(seed_m), .K(shared_key), .done(client_done)
    );
endmodule
