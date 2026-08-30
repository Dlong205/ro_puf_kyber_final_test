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
        .din        (dout_client),           // From Client's dout
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
                if (!saw_server_done || !saw_client_done) begin
                    $fatal(1, "Protocol returned to idle without both completion pulses");
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
