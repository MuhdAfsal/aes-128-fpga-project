`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Muhammed Afsal
// 
// Create Date: 2026/06/11
// Design Name: AES-128 AXI-Lite Peripheral
// Module Name: aes_axi_lite
// Target Devices: Zybo Z7-10
// Tool Versions: Vivado 2020+
// Description: AXI4-Lite Slave Register interface wrapping the AES core.
//              Maps 14 registers for processor access.
// 
// Dependencies: aes_128_core.v
// 
//////////////////////////////////////////////////////////////////////////////////

module aes_coprocessor_slave_lite_v1_0_S00_AXI # (
    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    // Width of S_AXI address bus (needs to hold 14 registers -> 6 bits)
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    // AXI Clock and Reset
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,

    // Write Address Channel
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,

    // Write Data Channel
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,

    // Write Response Channel
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,

    // Read Address Channel
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,

    // Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // AXI4LITE internal signals
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_awaddr;
    reg                             axi_awready;
    reg                             axi_wready;
    reg [1 : 0]                     axi_bresp;
    reg                             axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_araddr;
    reg                             axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0]  axi_rdata;
    reg [1 : 0]                     axi_rresp;
    reg                             axi_rvalid;

    // Address LSBs: for 32-bit registers, the lower 2 bits of the byte address are 0.
    localparam integer ADDR_LSB = 2;
    // Number of registers we use: 14 registers, so we need 4 index bits (16 locations)
    localparam integer USER_NUM_REGS = 14;

    // Registers declarations
    // slv_reg0 to slv_reg3: Plaintext (Writeable)
    // slv_reg4 to slv_reg7: Key (Writeable)
    // slv_reg8 to slv_reg11: Ciphertext (Read-only from fabric)
    // slv_reg12: Control (Writeable - Bit 0: Start, Bit 1: Reset)
    // slv_reg13: Status (Read-only - Bit 0: Done)
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg5;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg6;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg7;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg12;

    wire	 slv_reg_rden;
    wire	 slv_reg_wren;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    integer	 byte_index;
    reg	     aw_en;

    // Assign handshake outputs
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // Write Address Handshake
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // Latch Write Address
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awaddr <= 0;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awaddr <= S_AXI_AWADDR;
            end
        end
    end

    // Write Data Handshake
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    // Write to Register Logic
    assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0  <= 0;
            slv_reg1  <= 0;
            slv_reg2  <= 0;
            slv_reg3  <= 0;
            slv_reg4  <= 0;
            slv_reg5  <= 0;
            slv_reg6  <= 0;
            slv_reg7  <= 0;
            slv_reg12 <= 0;
        end else begin
            if (slv_reg_wren) begin
                case (axi_awaddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB])
                    4'h0: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h1: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h2: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h3: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h4: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h5: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h6: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg6[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'h7: begin
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg7[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    4'hC: begin // Control register at offset 0x30
                        for (byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index] == 1) slv_reg12[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    end
                    default : begin
                        slv_reg0 <= slv_reg0;
                        slv_reg1 <= slv_reg1;
                        slv_reg2 <= slv_reg2;
                        slv_reg3 <= slv_reg3;
                        slv_reg4 <= slv_reg4;
                        slv_reg5 <= slv_reg5;
                        slv_reg6 <= slv_reg6;
                        slv_reg7 <= slv_reg7;
                        slv_reg12 <= slv_reg12;
                    end
                endcase
            end
        end
    end

    // Write Response Channel Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b00; // OKAY response
        end else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;
            end else begin
                if (S_AXI_BREADY && axi_bvalid) begin
                    axi_bvalid <= 1'b0;
                end
            end
        end
    end

    // Read Address Channel Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 32'b0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // Read Response Valid
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 0;
            axi_rresp  <= 0;
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY response
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Connect wires to AES module
    wire [127:0] aes_plaintext = {slv_reg0, slv_reg1, slv_reg2, slv_reg3};
    wire [127:0] aes_key       = {slv_reg4, slv_reg5, slv_reg6, slv_reg7};
    wire [127:0] aes_ciphertext;
    wire         aes_done;
    
    // Internal signals map to registers
    wire aes_start = slv_reg12[0];
    // Active low soft reset from register bit 1, or global reset
    wire aes_rst_n = S_AXI_ARESETN && (~slv_reg12[1]);

    // Instantiate AES encryption core
    aes_128_core aes_core_inst (
        .clk(S_AXI_ACLK),
        .rst_n(aes_rst_n),
        .start(aes_start),
        .plaintext(aes_plaintext),
        .key(aes_key),
        .ciphertext(aes_ciphertext),
        .done(aes_done)
    );

    // Read Address Decoder
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    always @(*) begin
        case (axi_araddr[C_S_AXI_ADDR_WIDTH-1 : ADDR_LSB])
            4'h0   : reg_data_out = slv_reg0;
            4'h1   : reg_data_out = slv_reg1;
            4'h2   : reg_data_out = slv_reg2;
            4'h3   : reg_data_out = slv_reg3;
            4'h4   : reg_data_out = slv_reg4;
            4'h5   : reg_data_out = slv_reg5;
            4'h6   : reg_data_out = slv_reg6;
            4'h7   : reg_data_out = slv_reg7;
            4'h8   : reg_data_out = aes_ciphertext[127:96];
            4'h9   : reg_data_out = aes_ciphertext[95:64];
            4'hA   : reg_data_out = aes_ciphertext[63:32];
            4'hB   : reg_data_out = aes_ciphertext[31:0];
            4'hC   : reg_data_out = slv_reg12;
            4'hD   : reg_data_out = {31'b0, aes_done}; // status register
            default : reg_data_out = 32'h00000000;
        endcase
    end

    // Output read data
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rdata  <= 0;
        end else begin
            if (slv_reg_rden) begin
                axi_rdata <= reg_data_out;     // register read data
            end
        end
    end

endmodule
