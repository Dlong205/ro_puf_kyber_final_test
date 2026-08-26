`timescale 1ns / 1ps

module puf_axi_lite_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
    // System signals
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]                        S_AXI_BRESP,
    output wire                              S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,

    // AXI4-Lite Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                        S_AXI_RRESP,
    output wire                              S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    //----------------------------------------------
    // Register Map Definition
    //----------------------------------------------
    // 0x00: REG_CTRL (W/R)
    //       [0] : start (pulse to start PUF)
    //       [1] : reset (active high reset for PUF core)
    // 0x04: REG_STATUS (R)
    //       [0] : puf_done
    //       [1] : error_corr_ready
    //       [2] : digest_valid
    // 0x08: REG_CHALLENGE (W/R)
    //       [7:0] : challenge value
    // 0x10 - 0x2C: REG_DIGEST_0 to REG_DIGEST_7 (R)
    //       8x 32-bit registers containing the 256-bit digest

    localparam ADDR_CTRL       = 6'h00;
    localparam ADDR_STATUS     = 6'h04;
    localparam ADDR_CHALLENGE  = 6'h08;
    localparam ADDR_DIGEST_0   = 6'h10;
    // ... up to 6'h2C

    //----------------------------------------------
    // AXI4-Lite Internal Signals
    //----------------------------------------------
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready;
    reg                          axi_wready;
    reg [1:0]                    axi_bresp;
    reg                          axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                    axi_rresp;
    reg                          axi_rvalid;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    wire slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
    wire slv_reg_rden = axi_arready && S_AXI_ARVALID && ~axi_rvalid;

    //----------------------------------------------
    // User Registers
    //----------------------------------------------
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_ctrl;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_challenge;

    wire puf_done;
    wire error_corr_ready;
    wire digest_valid;
    wire [255:0] digest;

    // AXI Write Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            
            reg_ctrl      <= 32'b0;
            reg_challenge <= 32'b0;
        end else begin
            // AWREADY
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= S_AXI_AWADDR;
            end else begin
                axi_awready <= 1'b0;
            end

            // WREADY
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Register Writes
            if (slv_reg_wren) begin
                case (axi_awaddr[5:2])
                    ADDR_CTRL[5:2]:       reg_ctrl      <= S_AXI_WDATA;
                    ADDR_CHALLENGE[5:2]:  reg_challenge <= S_AXI_WDATA;
                    default: ;
                endcase
            end else begin
                // Auto-clear start bit (pulse)
                if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;
            end

            // BVALID
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI Read Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'b0;
        end else begin
            // ARREADY
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end

            // RVALID and RDATA
            if (slv_reg_rden) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY
                
                case (axi_araddr[5:2])
                    ADDR_CTRL[5:2]:       axi_rdata <= reg_ctrl;
                    ADDR_STATUS[5:2]:     axi_rdata <= {29'b0, digest_valid, error_corr_ready, puf_done};
                    ADDR_CHALLENGE[5:2]:  axi_rdata <= reg_challenge;
                    6'h04: axi_rdata <= digest[31:0];   // 0x10
                    6'h05: axi_rdata <= digest[63:32];  // 0x14
                    6'h06: axi_rdata <= digest[95:64];  // 0x18
                    6'h07: axi_rdata <= digest[127:96]; // 0x1C
                    6'h08: axi_rdata <= digest[159:128];// 0x20
                    6'h09: axi_rdata <= digest[191:160];// 0x24
                    6'h0A: axi_rdata <= digest[223:192];// 0x28
                    6'h0B: axi_rdata <= digest[255:224];// 0x2C
                    default:              axi_rdata <= 32'b0;
                endcase
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    //----------------------------------------------
    // Instantiation of PUF Core
    //----------------------------------------------
    puf_core u_puf_core (
        .clk             (S_AXI_ACLK),
        .reset           (reg_ctrl[1] | ~S_AXI_ARESETN),
        .start           (reg_ctrl[0]),
        .challenge       (reg_challenge[7:0]),
        .digest          (digest),
        .digest_valid    (digest_valid),
        .puf_done        (puf_done),
        .error_corr_ready(error_corr_ready)
    );

endmodule
