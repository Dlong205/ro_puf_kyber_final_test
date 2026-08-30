module riscv_soc #(
    parameter CLKS_PER_BIT = 868
)(
    input clk,
    input rstn,
    
    input  rx,
    output tx,
    output tx_active,

    output         kyber_done,
    output [255:0] kyber_shared_secret,

    // PUF, FE, KDF control
    output puf_start,
    output fe_start,
    output fe_mode,
    output kdf_start,
    input  puf_done,
    input  fe_done,
    input  fe_success,
    input  kdf_done,

    output [263:0] helper_out,
    input  [263:0] helper_in,
    
    input  [511:0] kdf_seed
);

    // PicoRV32 Native Memory Interface
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    // Address Decoding
    wire sel_bram = (mem_addr < 32'h10000000);
    wire sel_periph_native = (mem_addr >= 32'h10000000 && mem_addr < 32'h10000100);
    wire sel_kyber = (mem_addr >= 32'h10000100 && mem_addr < 32'h10000200);

    wire        bram_ready;
    wire [31:0] bram_rdata;
    wire        periph_ready;
    wire [31:0] periph_rdata;
    wire        kyber_ready;
    wire [31:0] kyber_rdata;

    assign mem_ready = sel_bram ? bram_ready : (sel_periph_native ? periph_ready : (sel_kyber ? kyber_ready : 1'b0));
    assign mem_rdata = sel_bram ? bram_rdata : (sel_periph_native ? periph_rdata : (sel_kyber ? kyber_rdata : 32'h0));

    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_4000),
        .BARREL_SHIFTER(1),
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(0),
        .ENABLE_DIV(0)
    ) cpu (
        .clk         (clk        ),
        .resetn      (rstn       ),
        .mem_valid   (mem_valid  ),
        .mem_instr   (mem_instr  ),
        .mem_ready   (mem_ready  ),
        .mem_addr    (mem_addr   ),
        .mem_wdata   (mem_wdata  ),
        .mem_wstrb   (mem_wstrb  ),
        .mem_rdata   (mem_rdata  ),
        .trap        (),
        .mem_la_read (),
        .mem_la_write(),
        .mem_la_addr (),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid  (),
        .pcpi_insn   (),
        .pcpi_rs1    (),
        .pcpi_rs2    (),
        // PCPI and interrupts are disabled for this firmware build. Tie all
        // unused inputs explicitly so simulation and synthesis agree.
        .pcpi_wr     (1'b0),
        .pcpi_rd     (32'b0),
        .pcpi_wait   (1'b0),
        .pcpi_ready  (1'b0),
        .irq         (32'b0),
        .eoi         (),
        .trace_valid (),
        .trace_data  ()
    );

    soc_bram #(
        .MEM_WORDS(4096)
    ) memory_inst (
        .clk         (clk),
        .rstn        (rstn),
        .mem_valid   (mem_valid && sel_bram),
        .mem_ready   (bram_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (bram_rdata)
    );

    soc_peripherals #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_peripherals (
        .clk         (clk),
        .rstn        (rstn),
        .mem_valid   (mem_valid && sel_periph_native),
        .mem_ready   (periph_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (periph_rdata),
        .rx          (rx),
        .tx          (tx),
        .tx_active   (tx_active),
        .puf_start   (puf_start),
        .fe_start    (fe_start),
        .fe_mode     (fe_mode),
        .kdf_start   (kdf_start),
        .puf_done    (puf_done),
        .fe_done     (fe_done),
        .fe_success  (fe_success),
        .kdf_done    (kdf_done),
        .kdf_seed    (kdf_seed),
        .helper_out_data (helper_out),
        .helper_in_data  (helper_in)
    );

    // ==========================================
    // Native-to-AXI4-Lite Bridge & Kyber AXI Wrapper
    // ==========================================
    wire axi_awvalid, axi_wvalid, axi_bready;
    wire axi_arvalid, axi_rready;
    wire [31:0] axi_awaddr, axi_wdata, axi_araddr;
    wire [3:0] axi_wstrb;
    wire axi_awready, axi_wready, axi_bvalid;
    wire axi_arready, axi_rvalid;
    wire [1:0] axi_bresp, axi_rresp;
    wire [31:0] axi_rdata;

    localparam [2:0] BRIDGE_IDLE       = 3'd0;
    localparam [2:0] BRIDGE_WRITE_REQ  = 3'd1;
    localparam [2:0] BRIDGE_WRITE_RESP = 3'd2;
    localparam [2:0] BRIDGE_READ_REQ   = 3'd3;
    localparam [2:0] BRIDGE_READ_RESP  = 3'd4;
    localparam [2:0] BRIDGE_WAIT_DROP  = 3'd5;

    reg [2:0] bridge_state;
    reg [31:0] bridge_addr;
    reg [31:0] bridge_wdata;
    reg [3:0] bridge_wstrb;

    // Latch each native request once, complete exactly one AXI transaction,
    // then wait for PicoRV32 to drop mem_valid. This prevents a held native
    // request from being accepted twice by the AXI peripheral.
    always @(posedge clk) begin
        if (!rstn) begin
            bridge_state <= BRIDGE_IDLE;
            bridge_addr <= 0;
            bridge_wdata <= 0;
            bridge_wstrb <= 0;
        end else begin
            case (bridge_state)
                BRIDGE_IDLE: begin
                    if (mem_valid && sel_kyber) begin
`ifdef KYBER_AXI_DEBUG
                        if (|mem_wstrb)
                            $display("[BRIDGE @%0t] write request addr=%h data=%h", $time,
                                     mem_addr - 32'h10000100, mem_wdata);
`endif
                        bridge_addr <= mem_addr - 32'h10000100;
                        bridge_wdata <= mem_wdata;
                        bridge_wstrb <= mem_wstrb;
                        bridge_state <= (|mem_wstrb) ? BRIDGE_WRITE_REQ : BRIDGE_READ_REQ;
                    end
                end
                BRIDGE_WRITE_REQ:
                    if (axi_awready && axi_wready)
                        bridge_state <= BRIDGE_WRITE_RESP;
                BRIDGE_WRITE_RESP:
                    if (axi_bvalid)
                        bridge_state <= BRIDGE_WAIT_DROP;
                BRIDGE_READ_REQ:
                    if (axi_arready)
                        bridge_state <= BRIDGE_READ_RESP;
                BRIDGE_READ_RESP:
                    if (axi_rvalid)
                        bridge_state <= BRIDGE_WAIT_DROP;
                BRIDGE_WAIT_DROP:
                    if (!mem_valid)
                        bridge_state <= BRIDGE_IDLE;
                default:
                    bridge_state <= BRIDGE_IDLE;
            endcase
        end
    end

    assign axi_awvalid = (bridge_state == BRIDGE_WRITE_REQ);
    assign axi_wvalid  = (bridge_state == BRIDGE_WRITE_REQ);
    assign axi_awaddr  = bridge_addr;
    assign axi_wdata   = bridge_wdata;
    assign axi_wstrb   = bridge_wstrb;
    assign axi_bready  = (bridge_state == BRIDGE_WRITE_RESP);

    assign axi_arvalid = (bridge_state == BRIDGE_READ_REQ);
    assign axi_araddr  = bridge_addr;
    assign axi_rready  = (bridge_state == BRIDGE_READ_RESP);

    assign kyber_ready = ((bridge_state == BRIDGE_WRITE_RESP) && axi_bvalid) ||
                         ((bridge_state == BRIDGE_READ_RESP) && axi_rvalid);
    assign kyber_rdata = axi_rdata;

    kyber_axi_wrapper u_kyber_axi (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (rstn),
        .S_AXI_AWADDR  (axi_awaddr),
        .S_AXI_AWPROT  (3'b000),
        .S_AXI_AWVALID (axi_awvalid),
        .S_AXI_AWREADY (axi_awready),
        .S_AXI_WDATA   (axi_wdata),
        .S_AXI_WSTRB   (axi_wstrb),
        .S_AXI_WVALID  (axi_wvalid),
        .S_AXI_WREADY  (axi_wready),
        .S_AXI_BRESP   (axi_bresp),
        .S_AXI_BVALID  (axi_bvalid),
        .S_AXI_BREADY  (axi_bready),
        .S_AXI_ARADDR  (axi_araddr),
        .S_AXI_ARPROT  (3'b000),
        .S_AXI_ARVALID (axi_arvalid),
        .S_AXI_ARREADY (axi_arready),
        .S_AXI_RDATA   (axi_rdata),
        .S_AXI_RRESP   (axi_rresp),
        .S_AXI_RVALID  (axi_rvalid),
        .S_AXI_RREADY  (axi_rready),
        .kem_done      (kyber_done),
        .kem_key       (kyber_shared_secret)
    );

endmodule
