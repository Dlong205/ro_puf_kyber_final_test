`timescale 1ns / 1ps

module kyber_axi_wrapper (
    // Clock and Reset
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input  wire [31:0] S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    // AXI4-Lite Read Address Channel
    input  wire [31:0] S_AXI_ARADDR,
    input  wire [2:0]  S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,

    // AXI4-Lite Read Data Channel
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY
);

    //----------------------------------------------
    // 1. AXI4-Lite Interface Logic
    //----------------------------------------------
    reg awready, wready, bvalid;
    reg arready, rvalid;
    reg [31:0] rdata;
    
    assign S_AXI_AWREADY = awready;
    assign S_AXI_WREADY  = wready;
    assign S_AXI_BRESP   = 2'b00; // OKAY
    assign S_AXI_BVALID  = bvalid;
    
    assign S_AXI_ARREADY = arready;
    assign S_AXI_RDATA   = rdata;
    assign S_AXI_RRESP   = 2'b00; // OKAY
    assign S_AXI_RVALID  = rvalid;

    wire slv_reg_wren = wready && S_AXI_WVALID && awready && S_AXI_AWVALID;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
        end else begin
            if (~awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                awready <= 1'b1;
                wready  <= 1'b1;
            end else begin
                awready <= 1'b0;
                wready  <= 1'b0;
            end
            
            if (slv_reg_wren) begin
                bvalid <= 1'b1;
            end else if (S_AXI_BREADY && bvalid) begin
                bvalid <= 1'b0;
            end
        end
    end

    wire slv_reg_rden = arready && S_AXI_ARVALID && ~rvalid;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            arready <= 1'b0;
            rvalid  <= 1'b0;
        end else begin
            if (~arready && S_AXI_ARVALID) begin
                arready <= 1'b1;
            end else begin
                arready <= 1'b0;
            end
            
            if (arready && S_AXI_ARVALID && ~rvalid) begin
                rvalid <= 1'b1;
            end else if (rvalid && S_AXI_RREADY) begin
                rvalid <= 1'b0;
            end
        end
    end

    //----------------------------------------------
    // 2. Memory Mapped Registers
    //----------------------------------------------
    reg [31:0] reg_seed_d [0:7];
    reg [31:0] reg_seed_z [0:7];
    reg [31:0] reg_seed_m [0:7];
    reg        reg_start;
    reg [2:0]  reg_k;
    
    integer i;
    initial begin
        for (i=0; i<8; i=i+1) begin
            reg_seed_d[i] = 0;
            reg_seed_z[i] = 0;
            reg_seed_m[i] = 0;
        end
        reg_start = 0;
        reg_k = 3'd2;
    end

    wire [7:0] awaddr_offset = S_AXI_AWADDR[7:0];
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            reg_start <= 1'b0;
        end else begin
            reg_start <= 1'b0; // Auto clear
            
            if (slv_reg_wren) begin
                if (awaddr_offset >= 8'h00 && awaddr_offset <= 8'h1C) begin
                    reg_seed_d[awaddr_offset[4:2]] <= S_AXI_WDATA;
                end
                else if (awaddr_offset >= 8'h20 && awaddr_offset <= 8'h3C) begin
                    reg_seed_z[(awaddr_offset - 8'h20)>>2] <= S_AXI_WDATA;
                end
                else if (awaddr_offset >= 8'h80 && awaddr_offset <= 8'h9C) begin
                    reg_seed_m[(awaddr_offset - 8'h80)>>2] <= S_AXI_WDATA;
                end
                else if (awaddr_offset == 8'h40) begin
                    reg_start <= S_AXI_WDATA[0];
                end
                else if (awaddr_offset == 8'h48) begin
                    reg_k <= S_AXI_WDATA[2:0];
                end
            end
        end
    end

    wire [7:0] araddr_offset = S_AXI_ARADDR[7:0];
    wire [255:0] kyber_K_server;
    wire [255:0] kyber_K_client;
    wire kyber_valid_server;
    wire kyber_valid_client;
    // Done when Server valid (Decapsulation finished)
    reg kyber_done_sticky;
    reg kyber_valid_client_sticky;
    reg kyber_valid_server_sticky;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            kyber_done_sticky <= 0;
            kyber_valid_client_sticky <= 0;
            kyber_valid_server_sticky <= 0;
        end else begin
            if (kyber_valid_server) kyber_valid_server_sticky <= 1;
            if (kyber_valid_client) kyber_valid_client_sticky <= 1;
            if (kyber_valid_server) kyber_done_sticky <= 1;
            
            // Clear when starting a new operation (write to 0x40)
            if (slv_reg_wren && awaddr_offset == 8'h40) begin
                kyber_done_sticky <= 0;
                kyber_valid_client_sticky <= 0;
                kyber_valid_server_sticky <= 0;
            end
        end
    end
    
    always @(*) begin
        rdata = 32'h0;
        if (slv_reg_rden) begin
            if (araddr_offset >= 8'h00 && araddr_offset <= 8'h1C) begin
                rdata = reg_seed_d[araddr_offset[4:2]];
            end
            else if (araddr_offset >= 8'h20 && araddr_offset <= 8'h3C) begin
                rdata = reg_seed_z[(araddr_offset - 8'h20)>>2];
            end
            else if (araddr_offset >= 8'h80 && araddr_offset <= 8'h9C) begin
                rdata = reg_seed_m[(araddr_offset - 8'h80)>>2];
            end
            else if (araddr_offset == 8'h44) begin
                rdata = {29'h0, kyber_done_sticky, kyber_valid_client_sticky, kyber_valid_server_sticky};
            end
            else if (araddr_offset >= 8'h60 && araddr_offset <= 8'h7C) begin
                case ((araddr_offset - 8'h60)>>2)
                    3'd0: rdata = kyber_K_server[31:0];
                    3'd1: rdata = kyber_K_server[63:32];
                    3'd2: rdata = kyber_K_server[95:64];
                    3'd3: rdata = kyber_K_server[127:96];
                    3'd4: rdata = kyber_K_server[159:128];
                    3'd5: rdata = kyber_K_server[191:160];
                    3'd6: rdata = kyber_K_server[223:192];
                    3'd7: rdata = kyber_K_server[255:224];
                endcase
            end
            else if (araddr_offset >= 8'hA0 && araddr_offset <= 8'hBC) begin
                case ((araddr_offset - 8'hA0)>>2)
                    3'd0: rdata = kyber_K_client[31:0];
                    3'd1: rdata = kyber_K_client[63:32];
                    3'd2: rdata = kyber_K_client[95:64];
                    3'd3: rdata = kyber_K_client[127:96];
                    3'd4: rdata = kyber_K_client[159:128];
                    3'd5: rdata = kyber_K_client[191:160];
                    3'd6: rdata = kyber_K_client[223:192];
                    3'd7: rdata = kyber_K_client[255:224];
                endcase
            end
        end
    end

    //----------------------------------------------
    // 3. Kyber KEM Loopback Instantiation
    //----------------------------------------------
    wire [255:0] flat_seed_d = {
        reg_seed_d[7], reg_seed_d[6], reg_seed_d[5], reg_seed_d[4],
        reg_seed_d[3], reg_seed_d[2], reg_seed_d[1], reg_seed_d[0]
    };
    wire [255:0] flat_seed_z = {
        reg_seed_z[7], reg_seed_z[6], reg_seed_z[5], reg_seed_z[4],
        reg_seed_z[3], reg_seed_z[2], reg_seed_z[1], reg_seed_z[0]
    };
    wire [255:0] flat_seed_m = {
        reg_seed_m[7], reg_seed_m[6], reg_seed_m[5], reg_seed_m[4],
        reg_seed_m[3], reg_seed_m[2], reg_seed_m[1], reg_seed_m[0]
    };

    wire ready_pk, ready_c;
    wire req_pk, req_c;
    wire [31:0] dout_server, dout_client;
    wire kyber_valid_server;
    wire kyber_valid_client;
    wire server_valid_out;
    wire client_valid_out;

    Kyber_Server S (
        .clk        (S_AXI_ACLK),
        .rst        (~S_AXI_ARESETN),
        .start      (reg_start),
        .wen        (client_valid_out), // Server IFIFO gets written when Client OFIFO reads
        .k          (3'd3), // Kyber-768
        .ready_c    (ready_c),
        .req_pk     (req_pk),
        .din        (dout_client),
        .ready_pk   (ready_pk),
        .req_c      (req_c),
        .valid      (kyber_valid_server), 
        .valid_out  (server_valid_out),
        .dout       (dout_server),
        .seed_d     (flat_seed_d),
        .seed_z     (flat_seed_z),
        .K          (kyber_K_server)
    );

    Kyber_Client C (
        .clk        (S_AXI_ACLK),
        .rst        (~S_AXI_ARESETN),
        .start      (reg_start),
        .wen        (server_valid_out), // Client IFIFO gets written when Server OFIFO reads
        .k          (3'd3),
        .ready_pk   (ready_pk),
        .req_c      (req_c),
        .din        (dout_server),
        .ready_c    (ready_c),
        .req_pk     (req_pk),
        .valid      (kyber_valid_client),
        .valid_out  (client_valid_out),
        .dout       (dout_client),
        .seed_m     (flat_seed_m),
        .K          (kyber_K_client)
    );

endmodule
