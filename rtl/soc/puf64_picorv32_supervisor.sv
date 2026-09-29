`timescale 1ns / 1ps
`default_nettype none

// PicoRV32 control-plane supervisor for the operational PUF64 image.
// The CPU can observe only public lifecycle/status bits. Raw PUF response,
// FE key, KCV digest, KDF seed and ML-KEM shared secret never enter its bus.
// A valid UART record can launch the chain only after this CPU has booted and
// explicitly approved the pending request with the fixed MMIO protocol.
module puf64_picorv32_supervisor #(
    parameter FIRMWARE_HEX = "puf64_supervisor.hex"
) (
    input  wire clk,
    input  wire rst_n,
    input  wire transport_start,
    input  wire transport_zeroize,
    input  wire command_ok,
    input  wire trusted_kcv_valid,
    input  wire mmcm_locked,
    input  wire core_busy,
    output reg  authorized_start,
    output reg  cpu_ready,
    output wire cpu_trap,
    output reg  request_pending
);
    localparam [31:0] READY_MAGIC   = 32'h5256_3332; // "RV32"
    localparam [31:0] APPROVE_MAGIC = 32'h4150_5052; // "APPR"
    localparam [31:0] IDENT_VALUE   = 32'h5055_4632; // "PUF2"

    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    wire sel_bram = mem_addr < 32'h1000_0000;
    wire sel_mmio = mem_addr[31:8] == 24'h100000;
    wire bram_ready;
    wire [31:0] bram_rdata;
    reg mmio_ready;
    reg [31:0] mmio_rdata;

    wire core_idle = !core_busy;
    wire [31:0] status_word = {
        26'd0, cpu_ready, core_idle, mmcm_locked, trusted_kcv_valid,
        command_ok, request_pending
    };

    assign mem_ready = sel_bram ? bram_ready : (sel_mmio ? mmio_ready : 1'b1);
    assign mem_rdata = sel_bram ? bram_rdata : (sel_mmio ? mmio_rdata : 32'd0);

    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_DUALPORT(0),
        .BARREL_SHIFTER(0),
        .COMPRESSED_ISA(0),
        .ENABLE_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_1000)
    ) u_cpu (
        .clk(clk), .resetn(rst_n), .trap(cpu_trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(),
        .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0),
        .pcpi_ready(1'b0), .irq(32'd0), .eoi(),
        .trace_valid(), .trace_data()
    );

    soc_bram #(
        .MEM_WORDS(1024),
        .INIT_FILE(FIRMWARE_HEX)
    ) u_firmware (
        .clk(clk), .rstn(rst_n),
        .mem_valid(mem_valid && sel_bram), .mem_ready(bram_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_rdata(bram_rdata)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            mmio_ready      <= 1'b0;
            mmio_rdata      <= 32'd0;
            authorized_start <= 1'b0;
            cpu_ready       <= 1'b0;
            request_pending <= 1'b0;
        end else begin
            mmio_ready       <= 1'b0;
            authorized_start <= 1'b0;

            if (transport_zeroize)
                request_pending <= 1'b0;
            else if (transport_start && command_ok)
                request_pending <= 1'b1;

            if (mem_valid && sel_mmio && !mmio_ready) begin
                mmio_ready <= 1'b1;
                if (|mem_wstrb) begin
                    case (mem_addr[7:0])
                        8'h04: begin
                            if (mem_wdata == READY_MAGIC)
                                cpu_ready <= 1'b1;
                        end
                        8'h08: begin
                            if (mem_wdata == APPROVE_MAGIC && cpu_ready &&
                                request_pending && command_ok &&
                                trusted_kcv_valid && mmcm_locked && core_idle) begin
                                authorized_start <= 1'b1;
                                request_pending <= 1'b0;
                            end
                        end
                        default: begin end
                    endcase
                end else begin
                    case (mem_addr[7:0])
                        8'h00: mmio_rdata <= status_word;
                        8'h0c: mmio_rdata <= IDENT_VALUE;
                        default: mmio_rdata <= 32'd0;
                    endcase
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (authorized_start && (!cpu_ready || !command_ok ||
            !trusted_kcv_valid || !mmcm_locked || core_busy))
            $error("PicoRV32 supervisor authorized an unsafe launch");
    end
`endif

    wire unused_mem_instr = mem_instr;
endmodule

`default_nettype wire
