module axi_wrapper_tb(input logic clk);
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

    kyber_axi_wrapper dut (
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
        .kem_key(kem_key)
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
    integer tx;
    integer stress_failures;
    integer stress_raw_failures;
    integer stress_retry_recoveries;
    integer stress_max_attempts;
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
            for (attempt = 0; attempt < 16 && !keys_match;
                 attempt = attempt + 1) begin
                local_server_key = 0;
                local_client_key = 0;
                local_seed_m = 0;
                seed_id = tx_id * 16 + attempt;

                // Match firmware retry semantics: zeroize clears every Kyber
                // seed, then stable d/z and a fresh m are reloaded.
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
                    $fatal(1, "TX%0d attempt%0d timed out",
                           tx_id, attempt + 1);

                for (word_id = 0; word_id < 8; word_id = word_id + 1) begin
                    axi_read(8'h60 + word_id*4, key_word);
                    local_server_key[word_id*32 +: 32] = key_word;
                    axi_read(8'ha0 + word_id*4, key_word);
                    local_client_key[word_id*32 +: 32] = key_word;
                end

                keys_match = status_word[5] &&
                             (local_server_key == local_client_key) &&
                             (local_server_key != 0);
                if (!keys_match) begin
                    stress_raw_failures = stress_raw_failures + 1;
                    $display("[AXI RETRY] TX%0d attempt%0d mismatch seed_m=%h server_m=%h client_m=%h e1=%08h/%08h starvation=%0d/%0d",
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
                axi_read(8'h44, status_word);
                if (status_word != 0 || kem_done || kem_key != 0)
                    $fatal(1, "TX%0d attempt%0d zeroize failed: status=%h key=%h",
                           tx_id, attempt + 1, status_word, kem_key);
            end
        end
    endtask

    initial begin
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

        // Readback proves the registered AXI R channel holds the correct data.
        axi_read(8'h00, value);
        if (value != 32'h03020100)
            $fatal(1, "Seed readback failed: %h", value);

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
        if (server_key == 0 || server_key != client_key)
            $fatal(1, "AXI shared-key mismatch: server=%h client=%h", server_key, client_key);
        if (kem_key != server_key)
            $fatal(1, "Direct key mirror differs from AXI key");

        // CTRL[1] must erase all software-visible seeds, completion state and
        // key material retained in the two Kyber cores.
        axi_write(8'h40, 32'd2);
        axi_read(8'h44, value);
        if (value != 0 || kem_done)
            $fatal(1, "Zeroize did not clear status: %h", value);
        axi_read(8'h00, value);
        if (value != 0)
            $fatal(1, "Zeroize did not clear seed registers: %h", value);
        if (kem_key != 0)
            $fatal(1, "Zeroize did not clear Kyber key state: %h", kem_key);

        // Exercise the firmware's real repeated-operation pattern with a
        // changing message seed. The old regression only issued a second
        // start and never waited for or checked its result.
        stress_failures = 0;
        stress_raw_failures = 0;
        stress_retry_recoveries = 0;
        stress_max_attempts = 0;
        for (tx = 0; tx < 32; tx = tx + 1) begin
            run_stress_transaction(tx, saw_valid_before_done);
            if (!saw_valid_before_done)
                stress_failures = stress_failures + 1;
        end
        if (stress_failures != 0)
            $fatal(1, "AXI changing-seed stress had %0d/32 mismatches",
                   stress_failures);

        $display("*** KYBER-512 AXI WRAPPER PASS (%0d polls, 32 logical transactions, raw mismatches=%0d, recovered=%0d, max_attempts=%0d) ***",
                 polls, stress_raw_failures, stress_retry_recoveries,
                 stress_max_attempts);
        $finish;
    end
endmodule
