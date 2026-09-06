// kat_wrapper.sv — Loopback testbench matching kyber_axi_wrapper.v wiring
// Server ↔ Client connected back-to-back, just pulse start and wait for valid
module kat_wrapper(
    input clk
);
    logic rst_n = 0;
    
    initial begin
        $display("=== Kyber Loopback Testbench (k=2) ===");
        repeat (5) @(posedge clk);
        rst_n = 1;
    end

    //---------------------------------------------------------
    // Loopback wires (same as kyber_axi_wrapper.v)
    //---------------------------------------------------------
    wire ready_pk, ready_c;
    wire req_pk, req_c;
    wire [31:0] dout_server, dout_client;
    wire server_valid_out, client_valid_out;
    wire server_valid, client_valid;
    wire server_done, client_done;
    wire [255:0] K_server, K_client;

    //---------------------------------------------------------
    // Test seeds
    //---------------------------------------------------------
    logic [255:0] seed_d = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
    logic [255:0] seed_z = 256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
    logic [255:0] seed_m = 256'h00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;

    //---------------------------------------------------------
    // Control
    //---------------------------------------------------------
    reg start_reg = 0;
    reg saw_server_done = 0;
    reg saw_client_done = 0;
    reg server_done_d = 0;
    reg client_done_d = 0;
    integer cycle_count = 0;
    reg invalid_ct_mode = 0;
    reg ciphertext_corrupted = 0;

    // Independent Python hashlib.shaKE_256 oracle for z=00..1f and the
    // deterministic loopback ciphertext with byte 0 XORed by 1.  The RTL
    // register is displayed most-significant byte first, hence the reverse of
    // the byte-stream digest 0636f19d...1ed73589.
    localparam [255:0] EXPECTED_INVALID_K =
        256'h8935d71e4cb00edd68ec2add0e03d4830683d11016d8dd629332fb819df13606;

    initial invalid_ct_mode = $test$plusargs("INVALID_CT");

    wire corrupt_this_word = invalid_ct_mode && !ciphertext_corrupted &&
                             client_valid_out &&
                             (server_inst.state == 6'h23);
    wire [31:0] client_to_server = corrupt_this_word ?
                                   (dout_client ^ 32'h00000001) : dout_client;

    always @(posedge clk) begin
        if (!rst_n || start_reg)
            ciphertext_corrupted <= 1'b0;
        else if (corrupt_this_word)
            ciphertext_corrupted <= 1'b1;
    end

`ifdef KYBER_KAT_DEBUG
    integer compare_count = 0;
    integer compare_mismatches = 0;
    integer server_noise_words = 0;
    integer server_raw_noise_words = 0;
    integer client_t_words = 0;
    integer server_t_words = 0;
    integer pk_fifo_reads = 0;
    integer pk_fifo_requeues = 0;
    integer pk_fifo_seed_reads = 0;
    integer final_hash_enqueued = 0;
    integer final_hash_accepted = 0;
    reg cca_enc_d = 0;
    always @(posedge clk) begin
        cca_enc_d <= server_inst.CCA_enc;
        if (!rst_n || start_reg) begin
            pk_fifo_reads <= 0;
            pk_fifo_requeues <= 0;
            pk_fifo_seed_reads <= 0;
            final_hash_enqueued <= 0;
            final_hash_accepted <= 0;
        end else begin
            if (!server_inst.DFIFO0_load_b && server_inst.OFIFO_req &&
                !server_inst.OFIFO_empty)
                pk_fifo_reads <= pk_fifo_reads + 1;
            if (server_inst.state == 6'h1b && server_inst.OFIFO_wen)
                pk_fifo_requeues <= pk_fifo_requeues + 1;
            if (!server_inst.DFIFO0_load_b && server_inst.OFIFO_req_r1 &&
                !server_inst.OFIFO_empty_r1 && server_inst.OFIFO_dout[32])
                pk_fifo_seed_reads <= pk_fifo_seed_reads + 1;
            if (server_inst.final_kdf_active && server_inst.ififo_wen) begin
                $display("J_ENQ idx=%0d data=%08x last=%b state=%h replay=%0d",
                    final_hash_enqueued, server_inst.ififo_din,
                    server_inst.ififo_last, server_inst.state,
                    server_inst.j_replay_ctr);
                final_hash_enqueued <= final_hash_enqueued + 1;
            end
            if (server_inst.final_kdf_active &&
                server_inst.hash.core_word_accept) begin
                $display("J_ACCEPT idx=%0d data=%08x last=%b wr_idx=%0d",
                    final_hash_accepted, server_inst.hash.core_din,
                    server_inst.hash.core_last,
                    server_inst.hash.sponge.wr_idx);
                final_hash_accepted <= final_hash_accepted + 1;
            end
        end
        if (!cca_enc_d && server_inst.CCA_enc)
            $display("PK_FIFO_AT_CCA cyc=%0d count=%0d rd_ptr=%0d wr_ptr=%0d reads=%0d requeues=%0d seed_reads=%0d head=%09h",
                cycle_count, server_inst.OFIFO.inst.wr_count,
                server_inst.OFIFO.inst.rd_ptr, server_inst.OFIFO.inst.wr_ptr,
                pk_fifo_reads, pk_fifo_requeues, pk_fifo_seed_reads,
                server_inst.OFIFO.inst.mem[server_inst.OFIFO.inst.rd_ptr[8:0]]);
        if (!server_inst.DFIFO0_load_b &&
            (server_inst.state != server_inst.next_state) &&
            (server_inst.next_state == 6'h30))
            $display("PK_FIFO_BEFORE_RELOAD cyc=%0d count=%0d rd_ptr=%0d wr_ptr=%0d head=%09h",
                cycle_count, server_inst.OFIFO.inst.wr_count,
                server_inst.OFIFO.inst.rd_ptr, server_inst.OFIFO.inst.wr_ptr,
                server_inst.OFIFO.inst.mem[server_inst.OFIFO.inst.rd_ptr[8:0]]);
        if (!rst_n || start_reg) begin
            compare_count <= 0;
            compare_mismatches <= 0;
        end else if ((server_inst.req_D0_r1 && !server_inst.ready_t) ||
                     (server_inst.req_D1_r1 && server_inst.CCA_enc)) begin
            if ((server_inst.cmp0 != server_inst.cmp1) &&
                (compare_mismatches < 16))
                $display("CMP_MISMATCH cyc=%0d idx=%0d kind=%s state=%h ntt=%h got=%06h expected=%06h",
                    cycle_count, compare_count,
                    server_inst.req_D1_r1 ? "v" : "u",
                    server_inst.state, server_inst.ntt.state_r13,
                    server_inst.cmp1, server_inst.cmp0);
            compare_count <= compare_count + 1;
            if (server_inst.cmp0 != server_inst.cmp1)
                compare_mismatches <= compare_mismatches + 1;
        end
        if (!rst_n || start_reg)
            server_noise_words <= 0;
        else if (server_inst.hash.ofifo1_wen) begin
            if ((server_noise_words < 12) ||
                ((server_noise_words % 64) < 4))
                $display("SERVER_NOISE cyc=%0d idx=%0d state=%h kc=%0d nonce=%0d patt=%b eta=%b data=%07h",
                    cycle_count, server_noise_words, server_inst.state,
                    server_inst.keccak_ctr, server_inst.nonce,
                    server_inst.hash.decode_patt,
                    server_inst.hash.decode_eta3,
                    server_inst.hash.ofifo1_din);
            server_noise_words <= server_noise_words + 1;
        end
        if (!rst_n || start_reg)
            server_raw_noise_words <= 0;
        else if (server_inst.CCA_enc && server_inst.hash.ofifo_wen &&
                 (server_inst.hash.stream_patt ||
                  server_inst.hash.stream_eta3)) begin
            $display("SERVER_RAW_NOISE cyc=%0d idx=%0d state=%h kc=%0d sc=%0d patt=%b eta=%b data=%08h",
                cycle_count, server_raw_noise_words, server_inst.state,
                server_inst.keccak_ctr, server_inst.squeeze_ctr,
                server_inst.hash.stream_patt,
                server_inst.hash.stream_eta3,
                server_inst.keccak_dout);
            server_raw_noise_words <= server_raw_noise_words + 1;
        end
        if (server_inst.CCA_enc && server_inst.hash.ofifo_full &&
            server_inst.hash.keccak_squeeze && server_inst.ofifo_ena)
            $display("SERVER_RAW_FULL cyc=%0d state=%h kc=%0d sc=%0d patt=%b eta=%b count=%0d",
                cycle_count, server_inst.state, server_inst.keccak_ctr,
                server_inst.squeeze_ctr, server_inst.hash.stream_patt,
                server_inst.hash.stream_eta3,
                server_inst.hash.ofifo_inst.inst.wr_count);
        if (server_inst.CCA_enc &&
            (server_inst.state != server_inst.next_state))
            $display("SERVER_STATE cyc=%0d %h->%h kc=%0d nonce=%0d patt=%b eta=%b ntt=%h noise_count=%0d",
                cycle_count, server_inst.state, server_inst.next_state,
                server_inst.keccak_ctr, server_inst.nonce,
                server_inst.patt_bit, server_inst.eta3_bit,
                server_inst.ntt.state,
                server_inst.hash.ofifo1_inst.inst.wr_count);
        if (server_inst.CCA_enc && server_inst.hash.sponge_done)
            $display("SERVER_HASH_DONE cyc=%0d state=%h kc=%0d rate=%0d patt=%b eta=%b patt_head=%b eta_head=%b",
                cycle_count, server_inst.state, server_inst.keccak_ctr,
                server_inst.hash.sponge_output_rate,
                server_inst.patt_bit, server_inst.eta3_bit,
                server_inst.patt_r[72], server_inst.eta3_r[72]);
        if (!rst_n || start_reg) begin
            client_t_words <= 0;
            server_t_words <= 0;
        end else begin
            if (client_inst.DFIFO_wen) begin
                if (client_t_words < 300)
                    $display("CLIENT_T idx=%0d data=%06h",
                        client_t_words, client_inst.DFIFO_din);
                client_t_words <= client_t_words + 1;
            end
            if (server_inst.CCA_enc && server_inst.DFIFO0_load_b &&
                server_inst.DFIFO0_wen) begin
                if (server_t_words < 300)
                    $display("SERVER_T idx=%0d data=%06h",
                        server_t_words, server_inst.DFIFO0_din);
                server_t_words <= server_t_words + 1;
            end
        end
    end
`endif

    //---------------------------------------------------------
    // Server (KeyGen + Decap)
    //---------------------------------------------------------
    Kyber_Server server_inst (
        .clk        (clk),
        .rst        (~rst_n),
        .start      (start_reg),
        .wen        (client_valid_out),     // Fed by Client's valid_out
        .k          (3'd2),                 // Kyber-512
        .ready_c    (ready_c),              // From Client
        .req_pk     (req_pk),               // From Client
        .din        (client_to_server),      // KAT may flip one ciphertext bit
        .ready_pk   (ready_pk),             // To Client
        .req_c      (req_c),                // To Client
        .valid      (server_valid),
        .valid_out  (server_valid_out),
        .dout       (dout_server),
        .seed_d     (seed_d),
        .seed_z     (seed_z),
        .K          (K_server),
        .done       (server_done)
    );

    //---------------------------------------------------------
    // Client (Encap)
    //---------------------------------------------------------
    Kyber_Client client_inst (
        .clk        (clk),
        .rst        (~rst_n),
        .start      (start_reg),
        .wen        (server_valid_out),     // Fed by Server's valid_out
        .k          (3'd2),                 // Kyber-512
        .ready_pk   (ready_pk),             // From Server
        .req_c      (req_c),                // From Server
        .din        (dout_server),           // From Server's dout
        .ready_c    (ready_c),              // To Server
        .req_pk     (req_pk),               // To Server
        .valid      (client_valid),
        .valid_out  (client_valid_out),
        .dout       (dout_client),
        .seed_m     (seed_m),
        .K          (K_client),
        .done       (client_done)
    );

    //---------------------------------------------------------
    // Main test sequence
    //---------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            saw_server_done <= 0;
            saw_client_done <= 0;
            server_done_d <= 0;
            client_done_d <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            server_done_d <= server_done;
            client_done_d <= client_done;

            if (server_done)
                saw_server_done <= 1;
            if (client_done)
                saw_client_done <= 1;

            if (server_done && server_done_d)
                $fatal(1, "server_done must be a one-cycle pulse");
            if (client_done && client_done_d)
                $fatal(1, "client_done must be a one-cycle pulse");
            
            // Pulse start for 1 cycle
            if (cycle_count == 0) begin
                start_reg <= 1;
                $display("[%0d] START pulse", cycle_count);
            end else begin
                start_reg <= 0;
            end
            
            // Progress reports
            if (cycle_count % 50000 == 0 && cycle_count > 0) begin
                $display("[%0d] server.state=%h client.state=%h",
                    cycle_count, server_inst.state, client_inst.state);
            end

            // Check completion: Wait until both FSMs return to state 0 (Idle) after starting
            if (cycle_count > 100 && server_inst.state == 0 && client_inst.state == 0) begin
                $display("\n=== PROTOCOL COMPLETE at cycle %0d ===", cycle_count);
                $display("K_server = %h", K_server);
                $display("K_client = %h", K_client);
                $display("decap equal=%b", server_inst.equal);
                $display("m_server = %h", server_inst.m);
                $display("m_client = %h", client_inst.m);
                $display("r_client = %h", client_inst.r);
                if (!saw_server_done || !saw_client_done) begin
                    $fatal(1, "Protocol returned to idle without both completion pulses");
                end else if (invalid_ct_mode) begin
                    if (!ciphertext_corrupted)
                        $fatal(1, "Invalid-ciphertext KAT did not corrupt a word");
                    if (server_inst.equal)
                        $fatal(1, "Modified ciphertext was accepted");
                    if (server_inst.ciphertext_wr_ctr != 8'd192)
                        $fatal(1, "Stored ciphertext has %0d words, expected 192",
                            server_inst.ciphertext_wr_ctr);
                    if (K_server != EXPECTED_INVALID_K)
                        $fatal(1, "J(z || c) mismatch: got %h expected %h",
                            K_server, EXPECTED_INVALID_K);
                    $display("*** MODIFIED CIPHERTEXT REJECTED; J(z || c) PASS ***");
                end else if (K_server == K_client && K_server != 0) begin
                    $display("*** SHARED KEY MATCH — PROTOCOL SUCCESS! ***");
                end else begin
                    $display("*** SHARED KEY MISMATCH — PROTOCOL FAILURE! ***");
                    $display("  Server hash_pk = %h", server_inst.hash_pk);
                    $display("  Client hash_pk = %h", client_inst.hash_pk);
                    $display("  Server hash_c  = %h", server_inst.hash_c);
                    $display("  Client hash_c  = %h", client_inst.hash_c);
                    $fatal(1, "Kyber shared-key mismatch");
                end
                $finish;
            end
            
            // Timeout
            if (cycle_count > 500000) begin
                $display("\n=== TIMEOUT at cycle %0d ===", cycle_count);
                $display("server.state=%h client.state=%h", server_inst.state, client_inst.state);
                $display("server hash: kc=%h sc=%h extend=%b ififo_empty=%b ififo_count=%0d req=%b pend=%b busy=%b",
                    server_inst.keccak_ctr, server_inst.squeeze_ctr,
                    server_inst.extend, server_inst.ififo_empty,
                    server_inst.hash.ififo_inst.inst.wr_count,
                    server_inst.hash.ififo_req, server_inst.hash.word_pend,
                    server_inst.hash.core_busy);
                $display("server sponge: have=%b ready=%b wr=%h rd=%h/%h(out=%h) perm=%h done=%b",
                    server_inst.hash.sponge.have_block,
                    server_inst.hash.sponge.ready_flag,
                    server_inst.hash.sponge.wr_idx,
                    server_inst.hash.sponge.rd_idx,
                    server_inst.hash.sponge.rate_words,
                    server_inst.hash.sponge.output_rate_words,
                    server_inst.hash.sponge.perm_state,
                    server_inst.hash.sponge_done);
                $display("server NTT: state=%h delayed=%h ctr_NTT=%h ctr_k=%h ctr_col=%h finish=%b equal=%b",
                    server_inst.ntt.state, server_inst.ntt.state_r13,
                    server_inst.ntt.ctr_NTT, server_inst.ntt.ctr_k,
                    server_inst.ntt.ctr_col, server_inst.NTT_finish,
                    server_inst.equal);
                $display("server hash FIFOs: matrix empty=%b count=%0d active=%b id=%h seen=%h; noise empty=%b count=%0d",
                    server_inst.ofifo0_empty,
                    server_inst.hash.ofifo0_inst.inst.wr_count,
                    server_inst.matrix_stream_active,
                    server_inst.hash.matrix_stream_id,
                    server_inst.hash.matrix_stream_seen,
                    server_inst.ofifo1_empty,
                    server_inst.hash.ofifo1_inst.inst.wr_count);
                $display("client hash: kc=%h sc=%h patt=%b eta3=%b absorb=%h route=%b ififo_empty=%b",
                    client_inst.keccak_ctr, client_inst.squeeze_ctr,
                    client_inst.patt_bit, client_inst.eta3_bit,
                    client_inst.absorb_ctr, client_inst.ofifo_ena,
                    client_inst.ififo_empty);
                $display("client sponge: have=%b ready=%b wr=%h rd=%h/%h(out=%h) perm=%h busy=%b word_pend=%b",
                    client_inst.hash.sponge.have_block,
                    client_inst.hash.sponge.ready_flag,
                    client_inst.hash.sponge.wr_idx,
                    client_inst.hash.sponge.rd_idx,
                    client_inst.hash.sponge.rate_words,
                    client_inst.hash.sponge.output_rate_words,
                    client_inst.hash.sponge.perm_state,
                    client_inst.hash.core_busy,
                    client_inst.hash.word_pend);
                $display("client NTT: state=%h delayed=%h ctr_NTT=%h ctr_k=%h ctr_col=%h ready_c=%b",
                    client_inst.ntt.state, client_inst.ntt.state_r13,
                    client_inst.ntt.ctr_NTT, client_inst.ntt.ctr_k,
                    client_inst.ntt.ctr_col, client_inst.ready_c);
                $display("client hash FIFOs: matrix empty=%b count=%0d; noise empty=%b count=%0d",
                    client_inst.ofifo0_empty,
                    client_inst.hash.ofifo0_inst.inst.wr_count,
                    client_inst.ofifo1_empty,
                    client_inst.hash.ofifo1_inst.inst.wr_count);
                $display("K_server = %h", K_server);
                $display("K_client = %h", K_client);
                $fatal(1, "Kyber protocol timeout");
            end
        end
    end

    // State transition debug (enable explicitly with +define+KYBER_TB_DEBUG).
`ifdef KYBER_TB_DEBUG
    always @(posedge clk) begin
        if (server_inst.state != server_inst.next_state)
            $display("[%0d] SERVER: %h -> %h  kc=%h sctr=%h", cycle_count, server_inst.state, server_inst.next_state, server_inst.keccak_ctr, server_inst.squeeze_ctr);
        if (client_inst.state != client_inst.next_state)
            $display("[%0d] CLIENT: %h -> %h  kc=%h sctr=%h", cycle_count, client_inst.state, client_inst.next_state, client_inst.keccak_ctr, client_inst.squeeze_ctr);
        if (client_inst.keccak_ready)
            $display("[%0d] CLIENT READY state=%h kc=%h patt=%b eta3=%b rd=%0d out_rate=%0d have=%b",
                cycle_count, client_inst.state, client_inst.keccak_ctr,
                client_inst.patt_bit, client_inst.eta3_bit,
                client_inst.hash.sponge.rd_idx,
                client_inst.hash.sponge.output_rate_words,
                client_inst.hash.sponge.have_block);
            
        if (server_inst.state == 6'h 1b || server_inst.state == 6'h 1d || server_inst.state == 6'h 1e || server_inst.state == 6'h 1f) begin
            if (server_inst.ififo_wen)
                $display("[%0d] SERVER PK ABSORB: %h", cycle_count, server_inst.ififo_din);
        end

        // Trace for Client's hash_pk absorb (states 19, 1a, 1c, 1d, 1e)
        if (client_inst.state == 6'h 19 || client_inst.state == 6'h 1a || client_inst.state == 6'h 1c || client_inst.state == 6'h 1d || client_inst.state == 6'h 1e) begin
            if (client_inst.ififo_wen)
                $display("[%0d] CLIENT PK ABSORB: %h", cycle_count, client_inst.ififo_din);
        end
    end
`endif

endmodule
