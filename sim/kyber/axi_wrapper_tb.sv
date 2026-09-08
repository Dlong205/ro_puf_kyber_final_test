module axi_wrapper_tb #(
    parameter integer EXPOSE_SECRETS = 1
) (input logic clk);
    logic resetn = 0;

    logic [31:0] awaddr = 0;
    logic [31:0] wdata = 0;
    logic [3:0]  wstrb = 0;
    logic awvalid = 0;
    logic wvalid = 0;
    wire awready;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    logic bready = 0;

    logic [31:0] araddr = 0;
    logic arvalid = 0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    logic rready = 0;

    wire kem_done;
    wire [255:0] kem_key;
    wire zeroize_busy;
    wire zeroize_done;
    logic secure_zeroize = 1'b0;

    kyber_axi_wrapper #(
        .EXPOSE_SECRETS(EXPOSE_SECRETS),
        .SECURE_SCRUB(1)
    ) dut (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWPROT(3'b0),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),
        .S_AXI_ARPROT(3'b0),
        .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(rready),
        .kem_done(kem_done),
        .kem_key(kem_key),
        .secure_zeroize(secure_zeroize),
        .zeroize_busy(zeroize_busy),
        .zeroize_done(zeroize_done)
    );

    task automatic axi_write(input logic [7:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            awaddr = {24'b0, addr};
            wdata = data;
            wstrb = 4'hf;
            awvalid = 1;
            wvalid = 1;
            while (!(awready && wready)) @(negedge clk);
            // Keep VALID asserted through the next rising edge, where the
            // transfer is actually sampled.
            @(negedge clk);
            awvalid = 0;
            wvalid = 0;
            wstrb = 0;
            while (!bvalid) @(negedge clk);
            if (bresp != 2'b00)
                $fatal(1, "AXI write returned non-OKAY response");
            bready = 1;
            @(negedge clk);
            bready = 0;
        end
    endtask

    task automatic request_direct_zeroize;
        begin
            @(negedge clk);
            secure_zeroize = 1'b1;
            @(negedge clk);
            secure_zeroize = 1'b0;
        end
    endtask

    task automatic wait_for_zeroize;
        integer wait_cycles;
        logic saw_busy;
        begin
            saw_busy = zeroize_busy;
            for (wait_cycles = 0;
                 wait_cycles < 3000 && !zeroize_done;
                 wait_cycles = wait_cycles + 1) begin
                @(negedge clk);
                if (zeroize_busy)
                    saw_busy = 1'b1;
            end
            if (!zeroize_done)
                $fatal(1, "Secure scrub timed out after %0d cycles", wait_cycles);
            if (!saw_busy)
                $fatal(1, "Secure scrub never asserted zeroize_busy");
            if (wait_cycles < 2048)
                $fatal(1, "Secure scrub completed too early: %0d cycles", wait_cycles);
        end
    endtask

    task automatic assert_kyber_storage_zero;
        integer j;
        begin
            for (j = 0; j < 2048; j = j + 1) begin
                if (j < 256) begin
                    if (dut.S.ntt.RAM0.inst.mem[j] !== '0 ||
                        dut.S.ntt.RAM1.inst.mem[j] !== '0 ||
                        dut.C.ntt.RAM0.inst.mem[j] !== '0 ||
                        dut.C.ntt.RAM1.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left NTT RAM0/RAM1 data at address %0d", j);
                    if (dut.S.ciphertext_store.mem[j] !== '0)
                        $fatal(1, "Scrub left ciphertext data at address %0d", j);
                    if (dut.S.hash.ififo_inst.inst.mem[j] !== '0 ||
                        dut.C.hash.ififo_inst.inst.mem[j] !== '0 ||
                        dut.S.hash.ofifo1_inst.inst.mem[j] !== '0 ||
                        dut.C.hash.ofifo1_inst.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left 256-entry hash FIFO data at address %0d", j);
                end
                if (j < 64) begin
                    if (dut.S.ntt.RAM2.inst.mem[j] !== '0 ||
                        dut.S.ntt.RAM3.inst.mem[j] !== '0 ||
                        dut.C.ntt.RAM2.inst.mem[j] !== '0 ||
                        dut.C.ntt.RAM3.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left NTT RAM2/RAM3 data at address %0d", j);
                end
                if (j < 128) begin
                    if (dut.S.ntt.RAM4.inst.mem[j] !== '0 ||
                        dut.C.ntt.RAM4.inst.mem[j] !== '0 ||
                        dut.S.IFIFO.inst.mem[j] !== '0 ||
                        dut.S.DFIFO1.inst.mem[j] !== '0 ||
                        dut.C.IFIFO.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left 128-entry Kyber storage at address %0d", j);
                end
                if (j < 512) begin
                    if (dut.S.OFIFO.inst.mem[j] !== '0 ||
                        dut.S.DFIFO0.inst.mem[j] !== '0 ||
                        dut.C.OFIFO.inst.mem[j] !== '0 ||
                        dut.C.DFIFO.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left 512-entry Kyber FIFO data at address %0d", j);
                end
                if (j < 1024) begin
                    if (dut.S.hash.ofifo_inst.inst.mem[j] !== '0 ||
                        dut.C.hash.ofifo_inst.inst.mem[j] !== '0)
                        $fatal(1, "Scrub left 1024-entry hash FIFO data at address %0d", j);
                end
                if (dut.S.hash.ofifo0_inst.inst.mem[j] !== '0 ||
                    dut.C.hash.ofifo0_inst.inst.mem[j] !== '0)
                    $fatal(1, "Scrub left 2048-entry hash FIFO data at address %0d", j);
            end

            if (dut.S.hash.sponge.block_reg !== '0 ||
                dut.S.hash.sponge.squeeze_reg !== '0 ||
                dut.S.hash.sponge.block_perm_src !== '0 ||
                dut.S.hash.sponge.base_state !== '0 ||
                dut.C.hash.sponge.block_reg !== '0 ||
                dut.C.hash.sponge.squeeze_reg !== '0 ||
                dut.C.hash.sponge.block_perm_src !== '0 ||
                dut.C.hash.sponge.base_state !== '0)
                $fatal(1, "Scrub left SHA-3 sponge state");

            if (dut.S.hash.fifo_data_dropped !== '0 ||
                dut.C.hash.fifo_data_dropped !== '0)
                $fatal(1, "Scrub left SHAKE rejection-sampling staging data");

            if (dut.S.encode.sftreg !== '0 || dut.S.decode.sftreg !== '0 ||
                dut.C.encode.sftreg !== '0 || dut.C.decode.sftreg !== '0 ||
                dut.S.hash.decode.word0 !== '0 ||
                dut.S.hash.decode.word1 !== '0 ||
                dut.S.hash.decode.word2 !== '0 ||
                dut.C.hash.decode.word0 !== '0 ||
                dut.C.hash.decode.word1 !== '0 ||
                dut.C.hash.decode.word2 !== '0)
                $fatal(1, "Scrub left codec/hash staging registers");

            if (dut.S.ntt.in0_butt !== '0 || dut.S.ntt.in1_butt !== '0 ||
                dut.S.ntt.out0_butt_r1 !== '0 ||
                dut.S.ntt.out1_butt_r1 !== '0 ||
                dut.S.ntt.out1_butt_r2 !== '0 ||
                dut.S.ntt.rdata_RAM_mux0_r1 !== '0 ||
                dut.S.ntt.rdata_RAM_mux1_r1 !== '0 ||
                dut.S.ntt.rdata_RAM_mux1_r2 !== '0 ||
                dut.S.ntt.rdata_acc_r8 !== '0 ||
                dut.S.ntt.data_mux0 !== '0 || dut.S.ntt.data_mux1 !== '0 ||
                dut.C.ntt.in0_butt !== '0 || dut.C.ntt.in1_butt !== '0 ||
                dut.C.ntt.out0_butt_r1 !== '0 ||
                dut.C.ntt.out1_butt_r1 !== '0 ||
                dut.C.ntt.out1_butt_r2 !== '0 ||
                dut.C.ntt.rdata_RAM_mux0_r1 !== '0 ||
                dut.C.ntt.rdata_RAM_mux1_r1 !== '0 ||
                dut.C.ntt.rdata_RAM_mux1_r2 !== '0 ||
                dut.C.ntt.rdata_acc_r8 !== '0 ||
                dut.C.ntt.data_mux0 !== '0 || dut.C.ntt.data_mux1 !== '0)
                $fatal(1, "Scrub did not flush NTT data pipeline");

            if (dut.S.ntt.BU.M0.u_mult.product_reg !== '0 ||
                dut.S.ntt.BU.M1.u_mult.product_reg !== '0 ||
                dut.C.ntt.BU.M0.u_mult.product_reg !== '0 ||
                dut.C.ntt.BU.M1.u_mult.product_reg !== '0 ||
                dut.S.ntt.BU.R0.c_reg !== '0 ||
                dut.S.ntt.BU.R1.c_reg !== '0 ||
                dut.C.ntt.BU.R0.c_reg !== '0 ||
                dut.C.ntt.BU.R1.c_reg !== '0)
                $fatal(1, "Scrub did not flush NTT multiplier/reduction pipeline");

            if (dut.S.d !== '0 || dut.S.rho !== '0 || dut.S.sigma !== '0 ||
                dut.S.hash_pk !== '0 || dut.S.hash_c !== '0 ||
                dut.S.m !== '0 || dut.S.z !== '0 || dut.S.K !== '0 ||
                dut.S.dout !== '0 || dut.S.equal !== '0 ||
                dut.C.rho !== '0 || dut.C.r !== '0 ||
                dut.C.hash_pk !== '0 || dut.C.hash_c !== '0 ||
                dut.C.m !== '0 || dut.C.K !== '0 || dut.C.dout !== '0)
                $fatal(1, "Scrub left retained Kyber secret registers");
        end
    endtask

    task automatic axi_read(input logic [7:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            araddr = {24'b0, addr};
            arvalid = 1;
            while (!arready) @(negedge clk);
            @(negedge clk);
            arvalid = 0;
            while (!rvalid) @(negedge clk);
            data = rdata;
            if (rresp != 2'b00)
                $fatal(1, "AXI read returned non-OKAY response");
            rready = 1;
            @(negedge clk);
            rready = 0;
        end
    endtask

    logic [31:0] value;
    logic [255:0] server_key;
    logic [255:0] client_key;
    integer i;
    integer polls;
    integer drain_polls;
    integer tx;
    integer stress_failures;
    integer stress_raw_failures;
    integer stress_retry_recoveries;
    integer stress_max_attempts;
    integer stress_count;
    integer stress_start;
    integer client_noise_reads;
    integer client_noise_empty_reads;
    integer client_noise_overlaps;
    integer server_cca_noise_reads;
    integer server_cca_noise_empty_reads;
    integer server_cca_noise_overlaps;
    integer client_e1_writes;
    integer server_e1_writes;
    integer client_ntt6_cycles;
    integer client_ntt6_empty_cycles;
    integer server_nttb_empty_cycles;
    integer server_ntt26_empty_cycles;
    logic [31:0] client_e1_checksum;
    logic [31:0] server_e1_checksum;
    logic saw_valid_before_done;
    logic strict_raw;
    logic trace_stall;
    logic [5:0] trace_server_state;
    logic [5:0] trace_server_ntt_state;

    always @(posedge clk) begin
        if (trace_stall) begin
            if ((dut.S.state != trace_server_state) &&
                ((dut.S.state == 6'h13) || (dut.S.state == 6'h18) ||
                 (dut.S.state == 6'h2e) || (dut.S.state == 6'h30) ||
                 (trace_server_state == 6'h18) ||
                 (trace_server_state == 6'h2e)))
                $display("[STALL TRACE] t=%0t S %h->%h next=%h gen=%0d sq=%0d kec=%0d patt=%0d/%0d NTT=%h k=%0d empty=%0d",
                         $time, trace_server_state, dut.S.state,
                         dut.S.next_state, dut.S.fifo_GENA_ctr,
                         dut.S.squeeze_ctr, dut.S.keccak_ctr,
                         dut.S.patt_bit, dut.S.eta3_bit,
                         dut.S.ntt.state, dut.S.ntt.ctr_k,
                         dut.S.ofifo0_empty);
            if ((dut.S.ntt.state != trace_server_ntt_state) &&
                ((dut.S.ntt.state == 6'h26) ||
                 (trace_server_ntt_state == 6'h26)))
                $display("[STALL TRACE] t=%0t S_NTT %h->%h gen=%0d k=%0d empty=%0d",
                         $time, trace_server_ntt_state, dut.S.ntt.state,
                         dut.S.fifo_GENA_ctr, dut.S.ntt.ctr_k,
                         dut.S.ofifo0_empty);
        end
        trace_server_state <= dut.S.state;
        trace_server_ntt_state <= dut.S.ntt.state;
    end

    always @(posedge clk) begin
        if (dut.kyber_core_reset) begin
            client_noise_reads <= 0;
            client_noise_empty_reads <= 0;
            client_noise_overlaps <= 0;
            server_cca_noise_reads <= 0;
            server_cca_noise_empty_reads <= 0;
            server_cca_noise_overlaps <= 0;
            client_e1_writes <= 0;
            server_e1_writes <= 0;
            client_ntt6_cycles <= 0;
            client_ntt6_empty_cycles <= 0;
            server_nttb_empty_cycles <= 0;
            server_ntt26_empty_cycles <= 0;
            client_e1_checksum <= 0;
            server_e1_checksum <= 0;
        end else begin
            if (dut.C.ofifo1_req_r1) begin
                client_noise_reads <= client_noise_reads + 1;
                if (dut.C.ofifo1_empty)
                    client_noise_empty_reads <= client_noise_empty_reads + 1;
                if (dut.C.ofifo0_req_r1 || dut.C.req_D_r1)
                    client_noise_overlaps <= client_noise_overlaps + 1;
            end
            if (dut.S.CCA_enc && dut.S.ofifo1_req_r1) begin
                server_cca_noise_reads <= server_cca_noise_reads + 1;
                if (dut.S.ofifo1_empty)
                    server_cca_noise_empty_reads <= server_cca_noise_empty_reads + 1;
                if (dut.S.ofifo0_req_r1 || dut.S.req_D0_r1 || dut.S.req_D1_r1)
                    server_cca_noise_overlaps <= server_cca_noise_overlaps + 1;
            end
            if (dut.C.ntt.wen_RAM4 &&
                ((dut.C.ntt.state_r13 == 5'h0a) ||
                 (dut.C.ntt.state_r13 == 5'h0b))) begin
                client_e1_writes <= client_e1_writes + 1;
                client_e1_checksum <= {client_e1_checksum[30:0],
                                       client_e1_checksum[31]} ^
                                      dut.C.ntt.wdata_RAM2[31:0] ^
                                      {16'h0, dut.C.ntt.wdata_RAM2[47:32]};
            end
            if (dut.S.CCA_enc && dut.S.ntt.wen_RAM4 &&
                ((dut.S.ntt.state_r13 == 6'h2a) ||
                 (dut.S.ntt.state_r13 == 6'h2b))) begin
                server_e1_writes <= server_e1_writes + 1;
                server_e1_checksum <= {server_e1_checksum[30:0],
                                       server_e1_checksum[31]} ^
                                      dut.S.ntt.wdata_RAM2[31:0] ^
                                      {16'h0, dut.S.ntt.wdata_RAM2[47:32]};
            end
            if (dut.C.ntt.state == 5'h06) begin
                client_ntt6_cycles <= client_ntt6_cycles + 1;
                if (dut.C.ofifo0_empty)
                    client_ntt6_empty_cycles <= client_ntt6_empty_cycles + 1;
            end
            if ((dut.S.ntt.state_r2 == 6'h0b) && dut.S.ofifo0_empty)
                server_nttb_empty_cycles <= server_nttb_empty_cycles + 1;
            if ((dut.S.ntt.state_r2 == 6'h26) && dut.S.ofifo0_empty)
                server_ntt26_empty_cycles <= server_ntt26_empty_cycles + 1;
        end
    end

    function automatic [31:0] stress_m_word(input integer tx_id,
                                             input integer word_id);
        reg [31:0] x;
        begin
            x = 32'h6d2b79f5 ^ (tx_id * 32'h9e3779b9) ^
                (word_id * 32'h85ebca6b);
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            stress_m_word = x;
        end
    endfunction

    task automatic run_stress_transaction(input integer tx_id,
                                          output logic keys_match);
        integer word_id;
        integer local_polls;
        integer attempt;
        integer seed_id;
        logic [31:0] status_word;
        logic [31:0] key_word;
        logic [255:0] local_server_key;
        logic [255:0] local_client_key;
        logic [255:0] local_seed_m;
        begin
            keys_match = 0;
            // Every logical transaction is deliberately single-attempt.  A
            // retry would mask a functional RTL failure and does not match
            // the release firmware protocol.
            for (attempt = 0; attempt < 1 && !keys_match;
                 attempt = attempt + 1) begin
                local_server_key = 0;
                local_client_key = 0;
                local_seed_m = 0;
                seed_id = tx_id;

                // Zeroize clears every Kyber seed, then stable d/z and a
                // fresh message seed are reloaded for this transaction.
                for (word_id = 0; word_id < 8; word_id = word_id + 1) begin
                    axi_write(8'h00 + word_id*4,
                              32'h03020100 + word_id*32'h04040404);
                    axi_write(8'h20 + word_id*4,
                              32'h1c1d1e1f - word_id*32'h04040404);
                    key_word = stress_m_word(seed_id, word_id);
                    local_seed_m[word_id*32 +: 32] = key_word;
                    axi_write(8'h80 + word_id*4, key_word);
                end

                axi_write(8'h40, 32'd1);
                axi_read(8'h44, status_word);
                if (!status_word[3] || status_word[2])
                    $fatal(1, "TX%0d attempt%0d bad start status: %h",
                           tx_id, attempt + 1, status_word);

                status_word = 0;
                for (local_polls = 0;
                     local_polls < 100000 && !status_word[2];
                     local_polls = local_polls + 1)
                    axi_read(8'h44, status_word);
                if (!status_word[2])
                    $display("[AXI TIMEOUT] TX%0d seed_m=%h S=%h S_NTT=%h S_k=%0d S_fifo0_empty=%0d S_gen=%0d S_sq=%0d S_kec=%0d S_patt=%0d/%0d C=%h C_NTT=%h C_k=%0d C_fifo0_empty=%0d C_gen=%0d C_sq=%0d C_kec=%0d C_patt=%0d/%0d",
                             tx_id, local_seed_m, dut.S.state,
                             dut.S.ntt.state, dut.S.ntt.ctr_k,
                             dut.S.ofifo0_empty, dut.S.fifo_GENA_ctr,
                             dut.S.squeeze_ctr, dut.S.keccak_ctr,
                             dut.S.patt_bit, dut.S.eta3_bit, dut.C.state,
                             dut.C.ntt.state, dut.C.ntt.ctr_k,
                             dut.C.ofifo0_empty, dut.C.fifo_GENA_ctr,
                             dut.C.squeeze_ctr, dut.C.keccak_ctr,
                             dut.C.patt_bit, dut.C.eta3_bit);
                if (!status_word[2])
                    $fatal(1, "TX%0d attempt%0d timed out",
                           tx_id, attempt + 1);

                for (word_id = 0; word_id < 8; word_id = word_id + 1) begin
                    axi_read(8'h60 + word_id*4, key_word);
                    local_server_key[word_id*32 +: 32] = key_word;
                    axi_read(8'ha0 + word_id*4, key_word);
                    local_client_key[word_id*32 +: 32] = key_word;
                end

                if (EXPOSE_SECRETS)
                    keys_match = status_word[5] &&
                                 (local_server_key == local_client_key) &&
                                 (local_server_key != 0);
                else
                    keys_match = status_word[5] &&
                                 (local_server_key == 0) &&
                                 (local_client_key == 0) &&
                                 (kem_key == 0);
                if (!keys_match) begin
                    stress_raw_failures = stress_raw_failures + 1;
                    $display("[AXI RAW] TX%0d attempt%0d mismatch seed_m=%h server_m=%h client_m=%h e1=%08h/%08h starvation=%0d/%0d",
                             tx_id, attempt + 1, local_seed_m,
                             dut.S.m, dut.C.m, client_e1_checksum,
                             server_e1_checksum, client_ntt6_empty_cycles,
                             client_ntt6_cycles);
                end else begin
                    if (attempt != 0)
                        stress_retry_recoveries = stress_retry_recoveries + 1;
                    if ((attempt + 1) > stress_max_attempts)
                        stress_max_attempts = attempt + 1;
                end

                axi_write(8'h40, 32'd2);
                wait_for_zeroize();
                axi_read(8'h44, status_word);
                if (status_word != 0 || kem_done || kem_key != 0)
                    $fatal(1, "TX%0d attempt%0d zeroize failed: status=%h key=%h",
                           tx_id, attempt + 1, status_word, kem_key);
            end
        end
    endtask

    initial begin
        strict_raw = $test$plusargs("STRICT_RAW");
        trace_stall = $test$plusargs("TRACE_STALL");
        stress_start = 0;
        stress_count = 32;
        if ($value$plusargs("STRESS_START=%d", stress_start)) begin
            if (stress_start < 0)
                $fatal(1, "STRESS_START must not be negative");
        end
        if ($value$plusargs("STRESS_COUNT=%d", stress_count)) begin
            if (stress_count <= 0)
                $fatal(1, "STRESS_COUNT must be greater than zero");
        end
        if (strict_raw)
            $display("[AXI TB] strict single-attempt gate enabled (retry disabled)");
        $display("[AXI TB] secret readback policy=%0d", EXPOSE_SECRETS);
        $display("[AXI TB] changing-seed transaction range=%0d..%0d",
                 stress_start, stress_start + stress_count - 1);

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1;
        $display("[AXI TB] reset released");

        axi_read(8'h48, value);
        $display("[AXI TB] initial k=%0d", value);
        if (value != 32'd2)
            $fatal(1, "Kyber parameter did not reset to k=2: %h", value);
        axi_read(8'h44, value);
        if (value != 0)
            $fatal(1, "Status was not clear after reset: %h", value);

        // Unsupported parameters must never silently change the active mode.
        axi_write(8'h48, 32'd3);
        $display("[AXI TB] invalid-k write completed");
        axi_read(8'h48, value);
        if (value != 32'd2)
            $fatal(1, "Invalid k write changed the active Kyber mode");
        axi_read(8'h44, value);
        if (!value[4])
            $fatal(1, "Invalid k write did not set config_error");
        axi_write(8'h48, 32'd2);

        for (i = 0; i < 8; i = i + 1) begin
            axi_write(8'h00 + i*4, 32'h03020100 + i*32'h04040404);
            axi_write(8'h20 + i*4, 32'h1c1d1e1f - i*32'h04040404);
            axi_write(8'h80 + i*4, 32'h33221100 + i*32'h44444444);
        end
        $display("[AXI TB] seeds loaded");

        // Cover every word in all three seed banks. Diagnostic mode must
        // preserve the registered AXI read channel; locked mode must return
        // zero for d, z and m without affecting status/control reads.
        for (i = 0; i < 8; i = i + 1) begin
            axi_read(8'h00 + i*4, value);
            if (EXPOSE_SECRETS &&
                value != (32'h03020100 + i*32'h04040404))
                $fatal(1, "Seed d[%0d] readback failed: %h", i, value);
            if (!EXPOSE_SECRETS && value != 0)
                $fatal(1, "Seed d[%0d] escaped locked mode: %h", i, value);

            axi_read(8'h20 + i*4, value);
            if (EXPOSE_SECRETS &&
                value != (32'h1c1d1e1f - i*32'h04040404))
                $fatal(1, "Seed z[%0d] readback failed: %h", i, value);
            if (!EXPOSE_SECRETS && value != 0)
                $fatal(1, "Seed z[%0d] escaped locked mode: %h", i, value);

            axi_read(8'h80 + i*4, value);
            if (EXPOSE_SECRETS &&
                value != (32'h33221100 + i*32'h44444444))
                $fatal(1, "Seed m[%0d] readback failed: %h", i, value);
            if (!EXPOSE_SECRETS && value != 0)
                $fatal(1, "Seed m[%0d] escaped locked mode: %h", i, value);
        end

        axi_write(8'h40, 32'd1);
        $display("[AXI TB] start write completed");
        axi_read(8'h44, value);
        if (!value[3] || value[2] || value[4])
            $fatal(1, "Bad status immediately after start: %h", value);

        saw_valid_before_done = 0;
        value = 0;
        for (polls = 0; polls < 100000 && !value[2]; polls = polls + 1) begin
            axi_read(8'h44, value);
            if ((polls % 5000) == 0)
                $display("[AXI TB] poll=%0d status=%h server_state=%h client_state=%h",
                         polls, value, dut.S.state, dut.C.state);
            if ((value[1:0] != 0) && !value[2])
                saw_valid_before_done = 1;
        end
        if (!value[2])
            $fatal(1, "Kyber AXI operation timed out");
        if (!value[5] || value[3] || value[4] || value[1:0] != 2'b11) begin
            $display("[AXI TB] final mismatch detail equal=%b server_m=%h client_m=%h",
                     dut.S.equal, dut.S.m, dut.C.m);
            $fatal(1, "Bad final Kyber status: %h", value);
        end
        if (!saw_valid_before_done)
            $fatal(1, "Test never observed transfer-valid before final done");
        if (!kem_done)
            $fatal(1, "Direct kem_done mirror was not asserted");

        for (i = 0; i < 8; i = i + 1) begin
            axi_read(8'h60 + i*4, value);
            server_key[i*32 +: 32] = value;
            axi_read(8'ha0 + i*4, value);
            client_key[i*32 +: 32] = value;
        end
        if (EXPOSE_SECRETS) begin
            if (server_key == 0 || server_key != client_key)
                $fatal(1, "AXI shared-key mismatch: server=%h client=%h", server_key, client_key);
            if (kem_key != server_key)
                $fatal(1, "Direct key mirror differs from AXI key");
        end else begin
            if (server_key != 0 || client_key != 0 || kem_key != 0)
                $fatal(1, "Shared secret escaped locked policy: server=%h client=%h mirror=%h",
                       server_key, client_key, kem_key);
        end

        // Completed AXI reads must not leave their payload in the response
        // register after RVALID/RREADY. This is especially important for the
        // diagnostic build, where key readback is intentionally enabled.
        if (dut.rdata !== 32'b0)
            $fatal(1, "AXI response register retained completed read data: %h", dut.rdata);

        // Hold one key response stalled while requesting zeroize. AXI requires
        // RDATA to remain stable until the master accepts it, so zeroize must
        // scrub the core but withhold DONE until this response drains.
        @(negedge clk);
        araddr = 32'h00000060;
        arvalid = 1'b1;
        while (!arready) @(negedge clk);
        @(negedge clk);
        arvalid = 1'b0;
        while (!rvalid) @(negedge clk);
        if (rdata !== (EXPOSE_SECRETS ? server_key[31:0] : 32'b0))
            $fatal(1, "Unexpected stalled key response: %h", rdata);
        request_direct_zeroize();
        axi_write(8'h00, 32'hdeadbeef);
        repeat (2100) begin
            @(negedge clk);
            if (zeroize_done)
                $fatal(1, "Zeroize acknowledged before stalled AXI response drained");
            if (!zeroize_busy)
                $fatal(1, "Zeroize busy dropped while AXI response was stalled");
            if (rdata !== (EXPOSE_SECRETS ? server_key[31:0] : 32'b0))
                $fatal(1, "Stalled AXI response changed before RREADY: %h", rdata);
        end
        rready = 1'b1;
        @(negedge clk);
        rready = 1'b0;
        for (drain_polls = 0;
             drain_polls < 10 && !zeroize_done;
             drain_polls = drain_polls + 1)
            @(negedge clk);
        if (!zeroize_done)
            $fatal(1, "Zeroize did not complete after stalled AXI response drained");
        if (dut.rdata !== 32'b0)
            $fatal(1, "Zeroize left drained AXI response data: %h", dut.rdata);

        // CTRL[1] must erase all software-visible seeds, completion state and
        // key material retained in the two Kyber cores.
        axi_read(8'h44, value);
        if (value != 0 || kem_done)
            $fatal(1, "Zeroize did not clear status: %h", value);
        for (i = 0; i < 8; i = i + 1) begin
            axi_read(8'h00 + i*4, value);
            if (value != 0)
                $fatal(1, "Zeroize did not clear seed d[%0d]: %h", i, value);
            axi_read(8'h20 + i*4, value);
            if (value != 0)
                $fatal(1, "Zeroize did not clear seed z[%0d]: %h", i, value);
            axi_read(8'h80 + i*4, value);
            if (value != 0)
                $fatal(1, "Zeroize did not clear seed m[%0d]: %h", i, value);
            axi_read(8'h60 + i*4, value);
            if (value != 0)
                $fatal(1, "Zeroize did not clear server key[%0d]: %h", i, value);
            axi_read(8'ha0 + i*4, value);
            if (value != 0)
                $fatal(1, "Zeroize did not clear client key[%0d]: %h", i, value);
        end
        if (dut.flat_seed_d != 0 || dut.flat_seed_z != 0 ||
            dut.flat_seed_m != 0 || dut.kyber_K_server != 0 ||
            dut.kyber_K_client != 0)
            $fatal(1, "Zeroize left internal seed/key state");
        if (kem_key != 0)
            $fatal(1, "Zeroize did not clear Kyber key state: %h", kem_key);
        assert_kyber_storage_zero();

        // A security request must also abort a live KEM and must not be lost
        // in an arbitrary core phase.
        for (i = 0; i < 8; i = i + 1) begin
            axi_write(8'h00 + i*4, 32'ha5a50000 ^ i);
            axi_write(8'h20 + i*4, 32'h5a5a0000 ^ i);
            axi_write(8'h80 + i*4, 32'hc3c30000 ^ i);
        end
        axi_write(8'h40, 32'd1);
        repeat (200) @(negedge clk);
        axi_read(8'h44, value);
        if (!value[3] || value[2])
            $fatal(1, "KEM was not busy before mid-operation zeroize: %h", value);
        request_direct_zeroize();
        wait_for_zeroize();
        axi_read(8'h44, value);
        if (value != 0 || kem_done || kem_key != 0 ||
            dut.S.state != 0 || dut.C.state != 0)
            $fatal(1, "Mid-operation zeroize failed: status=%h S=%h C=%h",
                   value, dut.S.state, dut.C.state);
        assert_kyber_storage_zero();

        // Exercise the firmware's real repeated-operation pattern with a
        // changing message seed. The old regression only issued a second
        // start and never waited for or checked its result.
        stress_failures = 0;
        stress_raw_failures = 0;
        stress_retry_recoveries = 0;
        stress_max_attempts = 0;
        for (tx = stress_start; tx < stress_start + stress_count; tx = tx + 1) begin
            run_stress_transaction(tx, saw_valid_before_done);
            if (!saw_valid_before_done)
                stress_failures = stress_failures + 1;
            if (((tx - stress_start + 1) % 100) == 0)
                $display("[AXI TB] completed %0d/%0d changing-seed transactions",
                         tx - stress_start + 1, stress_count);
        end
        if (stress_failures != 0) begin
            if (strict_raw)
                $fatal(1, "Strict raw Kyber gate failed: %0d/%0d single-attempt mismatches",
                       stress_failures, stress_count);
            else
                $fatal(1, "AXI changing-seed stress had %0d/%0d mismatches",
                       stress_failures, stress_count);
        end

        $display("*** KYBER-512 AXI WRAPPER PASS (%0d polls, %0d logical transactions, raw mismatches=%0d, recovered=%0d, max_attempts=%0d) ***",
                 polls, stress_count, stress_raw_failures,
                 stress_retry_recoveries, stress_max_attempts);
        $finish;
    end
endmodule
