//============================================================================
//  Arcade: Star Wars Port to MiSTer FPGA by Videodr0me 2026
//
//  Implements the original Atari Star Wars PCB: main 6809 CPU, audio 6809 CPU,
//  4x POKEY, RIOT, TMS5220 speech, Mathbox, PROM-driven AVG vector generator,
//  ADC, inter-CPU latches, and analog audio mixing/filtering.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
// Slapstick and Empire Strikes Back support by derpyder
//============================================================================

module starwars #(
	parameter HIT_FLASH_ENABLE = 1'b1
) (
	input         clk_12,
	input         clk_50,
	input         clk_vid,
	input         reset,

	// OSD Settings
	input   [1:0] osd_buffer_mode,
	input         osd_audio_filter,   // 1=On (TL084 LPF active), 0=Off (bypass)
	input         osd_audio_delay,    // 1=On (Reticon delay/stereo active), 0=Off (bypass)
	input         osd_120hz_mode,
	input   [2:0] osd_crt_profile,
	input   [2:0] osd_off_dot_mode,
	input   [1:0] osd_off_tonemapping,    // 0=Linear 1, 1=Linear 2, 2=Bright, 3=Off
	input   [1:0] osd_off_phosphor_mode,
	input  [22:0] osd_custom1_settings,
	input  [22:0] osd_custom2_settings,

	// Mod selector: 0 = Star Wars (default), 1 = Empire Strikes Back.
	// ESB extends the SW main map with a slapstic-protected page at
	// $8000-$9FFF and a wider main ROM (64KB vs SW's 32KB).
	input         mod_esb,
	input         upload_reset,
	input         direct_video,
	input         direct_video_31khz,
	input         crt_15khz_480i,
	input   [2:0] crt_vertical_position,
	input  [11:0] HDMI_HEIGHT,
	input  [1:0]  ar,
	input  [2:0]  orientation,
	input         zoom_wide,
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,
	output        VGA_F1,
	output        mode_supports_120hz,
	output        mode_is_15khz,
	output        mode_is_480line,
	output        mode_is_240p,
	output        video_mode_toggle,
	output        video_freeze,

	// DDRAM Framebuffer Interface
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	// SDRAM for the compressed primary-video delay
	input  [15:0] SDRAM_DQ_IN,
	output [15:0] SDRAM_DQ_OUT,
	output        SDRAM_DQ_OE,
	output        SDRAM_CKE,
	output        SDRAM_nCS,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_nWE,
	output  [1:0] SDRAM_DQM,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,

	output        CE_PIXEL,
	// Audio (pseudo-stereo: dry +/- wet from BBD delay)
	output [15:0] audio_out_l,
	output [15:0] audio_out_r,

	// Video timing (active pixel data goes through FB/DDRAM path)
	output [7:0]  VGA_R,
	output [7:0]  VGA_G,
	output [7:0]  VGA_B,
	output        hsync,    // Used for Video timing
	output        vsync,
	output        vblank,
	output        hblank,


	// Inputs
	input  [7:0]  dsw0,
	input  [7:0]  dsw1,
	input         coin1,
	input         coin2,
	input         aux_coin,
	input         fire_l,
	input         fire_r,
	input         shield_l,
	input         shield_r,
	input         test_mode,
	input  [7:0]  analog_x,
	input  [7:0]  analog_y,

	// LEDs
	output [2:0]  led,

	// ROM Download
	input [24:0]  dn_addr,
	input  [7:0]  dn_data,
	input         dn_wr,

	// NVRAM IOCTL
	output        nvram_write_pulse,
	input         nvram_wr_ext,
	input  [7:0]  nvram_addr_ext,
	input  [7:0]  nvram_din_ext,
	output reg [7:0]  nvram_dout_ext
);

	// CPU Main (6809)
	wire [15:0] main_addr;
	wire [7:0]  main_din;
	wire [7:0]  main_dout;
	wire        main_rw;
	wire        main_vma;
	reg         main_irq_reg;
	wire        main_irq;
	wire        main_firq;
	wire        main_nmi;
	assign      main_irq = main_irq_reg;
	assign      main_firq = 1'b0;
	assign      main_nmi = 1'b0;

	// CDC Reset Synchronizer for clk_12
	reg [1:0] rst_12_sync = 2'b11;
	always @(posedge clk_12) rst_12_sync <= {rst_12_sync[0], reset};
	wire rst_12 = rst_12_sync[1];

	wire [1:0] effective_tonemapping;

	// ~246.09Hz Timer for Main IRQ
	// clk_12 is 12.096 MHz. Hardware divider is 4096 * 12 = 49152 cycles.
	// 12096000 / 49152 = 246.09375 Hz.
	reg [15:0] irq_timer;
	wire irq_ack = (main_addr >= 16'h4660 && main_addr <= 16'h467F) && !main_rw && main_vma;

	always @(posedge clk_12) begin
		if (rst_12) begin
			irq_timer <= 16'd0;
			main_irq_reg <= 1'b0;
		end else begin
			if (irq_timer >= 16'd49151) begin
				irq_timer <= 16'd0;
				main_irq_reg <= 1'b1; // Trigger IRQ
			end else begin
				irq_timer <= irq_timer + 16'd1;
			end

			if (irq_ack) begin
				main_irq_reg <= 1'b0; // Clear IRQ
			end
		end
	end

	// 1.5 MHz Clock Enable for CPUs
	reg [2:0] ce_div = 0;
	reg       ce_1m5 = 0;
	always @(posedge clk_12) begin
		if (rst_12) begin
			ce_div <= 0;
			ce_1m5 <= 0;
		end else begin
			ce_div <= ce_div + 3'd1;
			ce_1m5 <= (ce_div == 0);
		end
	end

	cpu09 main_cpu(
		.clk(clk_12),
		.ce(ce_1m5),
		.rst(rst_12),
		.rw(main_rw),
		.vma(main_vma),
		.addr(main_addr),
		.data_in(main_din),
		.data_out(main_dout),
		.halt(1'b0),
		.irq(main_irq),
		.firq(main_firq),
		.nmi(main_nmi)
	);

	// CPU Audio (6809)
	wire [15:0] aud_addr;
	wire [7:0]  aud_din;
	wire [7:0]  aud_dout;
	wire        aud_rw;
	wire        aud_vma;
	// Sound Reset and Latches clear (0x46E0)
	wire soundrst_we = (main_addr == 16'h46E0) && !main_rw && main_vma;

	reg [7:0] aud_rst_cnt;
	always @(posedge clk_12) begin
		if (rst_12) begin
			aud_rst_cnt <= 8'h0;
		end else if (soundrst_we) begin
			aud_rst_cnt <= 8'hFF;
		end else if (ce_1m5 && aud_rst_cnt > 0) begin
			aud_rst_cnt <= aud_rst_cnt - 8'd1;
		end
	end

	wire        aud_reset = rst_12 | (aud_rst_cnt > 0); // Assert reset if global reset OR during extended software reset
	wire        aud_irq_n; // Driven by A6532 RIOT (Active Low)
	wire        aud_irq = ~aud_irq_n; // Invert for CPU09
	wire        aud_nmi = 1'b0; // No NMI on Audio CPU

	cpu09 audio_cpu(
		.clk(clk_12),
		.ce(ce_1m5),
		.rst(aud_reset),
		.rw(aud_rw),
		.vma(aud_vma),
		.addr(aud_addr),
		.data_in(aud_din),
		.data_out(aud_dout),
		.halt(1'b0),
		.irq(aud_irq),
		.firq(1'b0),
		.nmi(aud_nmi)
	);

	// --- ROM Download Address Decoding ---
	// ----- SW-mode dn_addr decoders -----
	// MRA ROM layout (index 0), based on actual file sizes:
	//   0x00000-0x03FFF: Banked ROM (16KB: 136021.214.1f, two 8K bank pages)
	//   0x04000-0x0BFFF: Main ROM  (32KB: 4x 8KB files)
	//   0x0C000-0x0CFFF: Vector ROM (4KB: 136021-105.1l)
	//   0x0D000-0x10FFF: Audio ROM (16KB: 2x 8KB files)
	//   0x11000-0x110FF: AVG PROM  (256B: 136021-109.4b)
	//   0x11100-0x120FF: Mathbox PROMs (4KB: 4x 1KB files)
	// These fire only when mod_esb=0.  Loading ROMs while ESB is selected
	wire dn_banked_cs   = !mod_esb && dn_wr && (dn_addr < 25'h04000);
	wire dn_main_cs     = !mod_esb && dn_wr && (dn_addr >= 25'h04000) && (dn_addr < 25'h0C000);
	wire dn_sw_vec_cs   = !mod_esb && dn_wr && (dn_addr >= 25'h0C000) && (dn_addr < 25'h0D000);
	wire dn_sw_aud_cs   = !mod_esb && dn_wr && (dn_addr >= 25'h0D000) && (dn_addr < 25'h11000);
	wire dn_avg_prom_cs = dn_wr && (dn_addr >= 25'h11000) && (dn_addr < 25'h11100);
	// Mathbox PROMs land at the SAME dn_addr offset in both mods (the
	// ESB MRA pads ahead of slapstic to keep this slot aligned with SW).
	wire dn_mb_cs       = dn_wr && (dn_addr >= 25'h11100) && (dn_addr < 25'h12100);

	// ----- ESB-mode dn_addr decoders -----
	// New regions added by the ESB MRA layout.  Main ROM is 64KB (vs
	// SW's 32KB), the slapstic ROM is 32KB (no SW equivalent), and the
	// vector / audio ROMs move to higher offsets.
	wire dn_esb_main_cs = mod_esb && dn_wr && (dn_addr < 25'h10000);
	wire dn_esb_slap_cs = mod_esb && dn_wr && (dn_addr >= 25'h14000) && (dn_addr < 25'h1C000);
	wire dn_esb_vec_cs  = mod_esb && dn_wr && (dn_addr >= 25'h1C000) && (dn_addr < 25'h1D000);
	wire dn_esb_aud_cs  = mod_esb && dn_wr && (dn_addr >= 25'h1E000) && (dn_addr < 25'h26000);

	// vec_rom (4KB) is shared between mods (same size/structure; only one
	// game loads per session).  Audio is NOT shared: SW audio is 16KB,
	// ESB audio is 32KB with a different low/high CPU mapping.
	wire dn_vec_cs = dn_sw_vec_cs || dn_esb_vec_cs;
	wire dn_aud_cs = dn_sw_aud_cs;

	// Compute base-relative addresses for each ROM region
	wire [13:0] dn_banked_addr = dn_addr[13:0];                         // 0x0000 base, naturally aligned
	wire [14:0] dn_main_addr   = (dn_addr[14:0] - 15'h4000);             // 0x4000 base -> 0x0000-0x7FFF
	wire [11:0] dn_vec_addr    = dn_addr[11:0];                          // 0xC000 or 0x1C000 base — both 4KB-aligned
	wire [13:0] dn_aud_addr    = (dn_addr[13:0] - 14'h1000);             // SW: 0xD000 base -> 0x0000-0x3FFF (16KB)
	wire  [7:0] dn_avg_prom_addr = dn_addr[7:0];                         // 0x11000 base -> 0x00-0xFF
	wire [11:0] dn_mb_addr     = (dn_addr[11:0] - 12'h100);              // 0x11100 base -> 0x000-0xFFF

	// ESB-specific relative addresses
	wire [15:0] dn_esb_main_addr = dn_addr[15:0];                         // 0x00000-0x0FFFF → 0x0000-0xFFFF
	wire [14:0] dn_esb_slap_addr = dn_addr[14:0] - 15'h4000;              // 0x14000-0x1BFFF → 0x0000-0x7FFF (32KB)
	wire [14:0] dn_esb_aud_addr  = dn_addr[14:0] - 15'h6000;              // 0x1E000-0x25FFF → 0x0000-0x7FFF (32KB)

	// Outlatch (0x4680 - 0x4687)
	reg [7:0] outlatch;

	// Mathbox (Matrix Processor)
	wire math_run;
	wire [7:0] math_dout;

	mathbox mbox (
		.clk(clk_12),
		.ce(ce_1m5),
		.reset(rst_12),
		.prng_reset(~outlatch[5]),
		.cpu_addr(main_addr),
		.cpu_din(main_dout),
		.cpu_dout(math_dout),
		.cpu_rw(main_rw),
		.cpu_vma(main_vma),
		.math_run(math_run),
		// ROM Download (address offset from 0x11100 base)
		.dn_addr({13'd0, dn_mb_addr}),
		.dn_data(dn_data),
		.dn_wr(dn_mb_cs)
	);

	// ADC (Analog Controls) - MiSTer joystick to arcade pot mapping
	reg [7:0] adc_data;
	wire adc_start_0 = (main_addr == 16'h46C0) && !main_rw && main_vma; // Pitch (Y)
	wire adc_start_1 = (main_addr == 16'h46C1) && !main_rw && main_vma; // Yaw (X)

	// MiSTer joystick analog is signed -128..+127.
	// Arcade expects 0x00..0xFF centered at 0x80.
	wire signed [8:0] analog_y_s = $signed(analog_y);
	wire signed [8:0] analog_x_s = $signed(analog_x);

	// Add offset to center (0x80 = 0)
	wire signed [8:0] digital_y_w = analog_y_s + 9'sd128;
	wire signed [8:0] digital_x_w = analog_x_s + 9'sd128;
	wire [7:0] digital_y = digital_y_w[7:0];
	wire [7:0] digital_x = digital_x_w[7:0];

	always @(posedge clk_12) begin
		if (adc_start_0) adc_data <= digital_y;
		else if (adc_start_1) adc_data <= digital_x;
	end

	wire adc_cs = (main_addr >= 16'h4380 && main_addr <= 16'h439F) && main_vma;

	// Outlatch (0x4680 - 0x4687)
	wire outlatch_we = (main_addr >= 16'h4680 && main_addr <= 16'h4687) && !main_rw && main_vma;
	always @(posedge clk_12) begin
		if (rst_12) outlatch <= 8'h00;
		else if (outlatch_we) outlatch[main_addr[2:0]] <= main_dout[7];
	end

	// Bank select is bit 4
	reg rom_bank;
	always @(*) rom_bank = outlatch[4];

	// =========================================================================
	// INTER-CPU COMMUNICATION LATCHES
	// =========================================================================

	reg [7:0] mainlatch;
	reg [7:0] soundlatch;
	reg       mainlatch_full;
	reg       soundlatch_full;

	// Main CPU writes to Soundlatch (0x4400)
	wire soundlatch_we = (main_addr == 16'h4400) && !main_rw && main_vma;

	// Audio CPU reads from Soundlatch (0x0800 - 0x0FFF)
	wire soundlatch_re = (aud_addr >= 16'h0800 && aud_addr <= 16'h0FFF) && aud_rw && aud_vma;

	// Audio CPU writes to Mainlatch (0x0000 - 0x07FF)
	wire mainlatch_we = (aud_addr >= 16'h0000 && aud_addr <= 16'h07FF) && !aud_rw && aud_vma;

	// Main CPU reads from Mainlatch (0x4400)
	wire mainlatch_re = (main_addr == 16'h4400) && main_rw && main_vma;

	always @(posedge clk_12) begin
		if (rst_12) begin
			mainlatch_full <= 1'b0;
			soundlatch_full <= 1'b0;
			mainlatch <= 8'h00;
			soundlatch <= 8'h00;
		end else if (ce_1m5 && soundrst_we) begin
			mainlatch_full <= 1'b0;
			soundlatch_full <= 1'b0;
		end else if (ce_1m5) begin
			if (soundlatch_we) begin
				soundlatch <= main_dout;
				soundlatch_full <= 1'b1;
			end else if (soundlatch_re) begin
				soundlatch_full <= 1'b0;
			end

			if (mainlatch_we) begin
				mainlatch <= aud_dout;
				mainlatch_full <= 1'b1;
			end else if (mainlatch_re) begin
				mainlatch_full <= 1'b0;
			end
		end
	end

	// =========================================================================
	// AVG DECLARATIONS
	// =========================================================================
	wire        avg_halted;
	wire        cpu_avg_halted;
	wire [13:0] avg_x;
	wire [13:0] avg_y;
	wire [7:0]  avg_z_raw;
	wire [7:0]  avg_z;
	wire [2:0]  avg_rgb;
	wire [15:0] avg_addr;
	wire  [7:0] avg_din;

	// =========================================================================
	// MEMORY SUBSYSTEM
	// =========================================================================

	// Main RAM (0x0000 - 0x2FFF, 12KB used, 16KB allocated)
	// Shared between Main CPU (Port A) and AVG (Port B)
	(* ramstyle = "M10K" *) reg [7:0] main_ram [0:16383];
	wire main_ram_cs = (main_addr < 16'h3000) && main_vma;
	reg [7:0] main_ram_dout;
	reg [7:0] avg_ram_dout;

	always @(posedge clk_12) begin
		if (main_ram_cs && ~main_rw) main_ram[main_addr[13:0]] <= main_dout;
		main_ram_dout <= main_ram[main_addr[13:0]];
		avg_ram_dout <= main_ram[avg_addr[13:0]];
	end

	// CPU Math RAM (2KB: 0x4800 - 0x4FFF)
	(* ramstyle = "M10K" *) reg [7:0] cpu_math_ram [0:2047];
	wire cpu_math_ram_cs = (main_addr >= 16'h4800 && main_addr <= 16'h4FFF) && main_vma;
	reg [7:0] cpu_math_ram_dout;

	always @(posedge clk_12) begin
		if (cpu_math_ram_cs && ~main_rw) cpu_math_ram[main_addr[10:0]] <= main_dout;
		cpu_math_ram_dout <= cpu_math_ram[main_addr[10:0]];
	end

	// Vector ROM (4KB: 0x3000 - 0x3FFF)
	wire [7:0] vec_rom_dout_cpu;
	wire [7:0] vec_rom_dout_avg;
	rom_download #(12) vec_rom (
		.clk(clk_12),
		.dn_addr(dn_vec_addr), .dn_data(dn_data), .dn_wr(dn_vec_cs),
		.cpu_addr_a(main_addr[11:0]), .cpu_dout_a(vec_rom_dout_cpu),
		.cpu_addr_b(avg_addr[11:0]),  .cpu_dout_b(vec_rom_dout_avg)
	);

	// Banked ROM (8KB window at 0x6000-0x7FFF, 2 x 8KB pages = 16KB total)
	wire [7:0] banked_rom_dout;
	rom_download #(14) banked_rom (
		.clk(clk_12),
		.dn_addr(dn_banked_addr), .dn_data(dn_data), .dn_wr(dn_banked_cs),
		.cpu_addr_a({rom_bank, main_addr[12:0]}), .cpu_dout_a(banked_rom_dout),
		.cpu_addr_b(14'h0), .cpu_dout_b() // Unused
	);

	// Main ROM (32KB: 0x8000 - 0xFFFF) — Star Wars only.  ESB uses
	// esb_main_rom instead (different size and CPU-address mapping).
	wire [7:0] main_rom_dout;
	rom_download #(15) main_rom (
		.clk(clk_12),
		.dn_addr(dn_main_addr), .dn_data(dn_data), .dn_wr(dn_main_cs),
		.cpu_addr_a(main_addr[14:0]), .cpu_dout_a(main_rom_dout),
		.cpu_addr_b(15'h0), .cpu_dout_b() // Unused
	);

	// ESB main ROM (64KB = 4 x 16KB files: 101, 102, 203, 104).
	// ESB main ROM map and banked pages:
	//   $6000-$7FFF  bank1  — 136031.101, 2 pages (8KB each)
	//   $8000-$9FFF  slapstic (separate ROM, see below)
	//   $A000-$FFFF  bank2  — 102/203/104, 2 pages (24KB each)
	// BOTH bank1 and bank2 are switched together by outlatch[4].
	// page 0 = file LOW halves (boot view), page 1 = HIGH halves (game code).
	wire        esb_page = rom_bank;   // = outlatch[4], shared bank1/bank2 page
	wire [7:0]  esb_main_rom_dout;
	reg  [15:0] esb_main_rom_cpu_addr;
	always @(*) begin
		case (main_addr[15:13])
			3'b011:  esb_main_rom_cpu_addr = {2'b00, esb_page, main_addr[12:0]};  // $6000 bank1 -> 0x0000
			3'b101:  esb_main_rom_cpu_addr = {2'b01, esb_page, main_addr[12:0]};  // $A000 102   -> 0x4000
			3'b110:  esb_main_rom_cpu_addr = {2'b10, esb_page, main_addr[12:0]};  // $C000 203   -> 0x8000
			3'b111:  esb_main_rom_cpu_addr = {2'b11, esb_page, main_addr[12:0]};  // $E000 104   -> 0xC000
			default: esb_main_rom_cpu_addr = 16'h0000;
		endcase
	end
	rom_download #(16) esb_main_rom (
		.clk(clk_12),
		.dn_addr(dn_esb_main_addr), .dn_data(dn_data), .dn_wr(dn_esb_main_cs),
		.cpu_addr_a(esb_main_rom_cpu_addr), .cpu_dout_a(esb_main_rom_dout),
		.cpu_addr_b(16'h0), .cpu_dout_b()
	);

	// Slapstic 137412-101 bank-select for the $8000-$9FFF page.
	// CRITICAL: type-101 ALTERNATE banking (which ESB GAMEPLAY uses)
	// requires the slapstic to see an access OUTSIDE $8000-$9FFF (the
	// 6809 $FFFF dummy/VMA cycle = alt2).  So we step it once per 6809
	// bus cycle with the FULL 16-bit address, NOT gated to the bank region.
	// mod_esb keeps it inert for Star Wars.
	//
	// STROBE PHASE: the wrapper latches safe_addr/safe_vma at phase_cnt
	// 1->2 and holds them stable for the rest of the 1.5 MHz cycle.
	// We delay ce_1m5 by 4 clk_12 (ce_dly[3]) so the step lands ~phase 3-4,
	// after the phase-2 address latch, when main_addr is valid and stable.
	wire [1:0] slap_bs;
	reg  [3:0] ce_dly;
	always @(posedge clk_12) ce_dly <= {ce_dly[2:0], ce_1m5};
	wire       slap_step = mod_esb && main_vma && ce_dly[3];
	slapstic101 u_slapstic (
		.I_CK   (clk_12),
		.I_STEP (slap_step),
		.I_RESET(rst_12),
		.I_A    (main_addr),       // FULL 16-bit address (in- and out-of-range)
		.O_BS   (slap_bs)
	);

	// Slapstic ROM (32KB = 4 banks x 8KB).  CPU sees $8000-$9FFF (8KB)
	// from one of the 4 banks selected by slap_bs.
	wire [7:0] slap_rom_dout;
	rom_download #(15) slap_rom (
		.clk(clk_12),
		.dn_addr(dn_esb_slap_addr), .dn_data(dn_data), .dn_wr(dn_esb_slap_cs),
		.cpu_addr_a({slap_bs, main_addr[12:0]}), .cpu_dout_a(slap_rom_dout),
		.cpu_addr_b(15'h0), .cpu_dout_b()
	);

	// Audio ROM (16KB: 0x4000 - 0x7FFF, mirrored at 0xC000 - 0xFFFF) - Star Wars.
	wire [7:0] aud_rom_dout;
	rom_download #(14) aud_rom (
		.clk(clk_12),
		.dn_addr(dn_aud_addr), .dn_data(dn_data), .dn_wr(dn_aud_cs),
		.cpu_addr_a(aud_addr[13:0]), .cpu_dout_a(aud_rom_dout),
		.cpu_addr_b(14'h0), .cpu_dout_b() // Unused
	);

	// ESB audio ROM (32KB = 136031.113 + 136031.112).  ESB's audio map
	// is NOT a simple 16KB mirror like SW — it's two 16KB files each
	// split low/high:
	//   audio $4000-$5FFF  136031.113 low   (ROM 0x0000-0x1FFF)
	//   audio $6000-$7FFF  136031.112 low   (ROM 0x4000-0x5FFF)
	//   audio $C000-$DFFF  136031.113 high  (ROM 0x2000-0x3FFF)
	//   audio $E000-$FFFF  136031.112 high  (ROM 0x6000-0x7FFF)
	wire [7:0]  esb_aud_rom_dout;
	reg  [14:0] esb_aud_rom_cpu_addr;
	always @(*) begin
		case (aud_addr[15:13])
			3'b010:  esb_aud_rom_cpu_addr = {2'b00, aud_addr[12:0]};  // $4000 113 low  -> 0x0000
			3'b011:  esb_aud_rom_cpu_addr = {2'b10, aud_addr[12:0]};  // $6000 112 low  -> 0x4000
			3'b110:  esb_aud_rom_cpu_addr = {2'b01, aud_addr[12:0]};  // $C000 113 high -> 0x2000
			3'b111:  esb_aud_rom_cpu_addr = {2'b11, aud_addr[12:0]};  // $E000 112 high -> 0x6000
			default: esb_aud_rom_cpu_addr = 15'h0000;
		endcase
	end
	rom_download #(15) esb_aud_rom (
		.clk(clk_12),
		.dn_addr(dn_esb_aud_addr), .dn_data(dn_data), .dn_wr(dn_esb_aud_cs),
		.cpu_addr_a(esb_aud_rom_cpu_addr), .cpu_dout_a(esb_aud_rom_dout),
		.cpu_addr_b(15'h0), .cpu_dout_b()
	);

	// Audio RAM (2KB: 0x2000 - 0x27FF)
	reg [7:0] aud_ram [0:2047];
	wire aud_ram_cs = (aud_addr >= 16'h2000 && aud_addr <= 16'h27FF) && aud_vma;
	reg [7:0] aud_ram_dout;

	always @(posedge clk_12) begin
		if (aud_ram_cs && ~aud_rw) aud_ram[aud_addr[10:0]] <= aud_dout;
		aud_ram_dout <= aud_ram[aud_addr[10:0]];
	end

	// NVRAM (256 bytes: 0x4500 - 0x45FF)
	(* ramstyle = "M10K, no_rw_check" *) reg [7:0] nvram [0:255];
	wire nvram_cs = (main_addr >= 16'h4500 && main_addr <= 16'h45FF) && main_vma;
	reg [7:0] nvram_dout;

	always @(posedge clk_12) begin
		if (nvram_cs && ~main_rw) nvram[main_addr[7:0]] <= main_dout;
		nvram_dout <= nvram[main_addr[7:0]];
	end

	always @(posedge clk_12) begin
		if (nvram_wr_ext) nvram[nvram_addr_ext] <= nvram_din_ext;
		nvram_dout_ext <= nvram[nvram_addr_ext];
	end

	reg old_nvram_wr;
	always @(posedge clk_12) old_nvram_wr <= (nvram_cs && ~main_rw);
	assign nvram_write_pulse = (nvram_cs && ~main_rw) & ~old_nvram_wr;

	// AVG Memory Mux
	assign avg_din = (avg_addr < 16'h3000) ? avg_ram_dout : vec_rom_dout_avg;

	// CPU Data In Mux
	reg [7:0] main_din_mux;
	always @(*) begin
		main_din_mux = 8'hFF;
		if (main_addr < 16'h3000) main_din_mux = main_ram_dout;
		else if (main_addr >= 16'h3000 && main_addr <= 16'h3FFF) main_din_mux = vec_rom_dout_cpu;
		else if (main_addr >= 16'h4700 && main_addr <= 16'h4707) main_din_mux = math_dout;
		else if (main_addr >= 16'h4500 && main_addr <= 16'h45FF) main_din_mux = nvram_dout;
		else if (main_addr >= 16'h4800 && main_addr <= 16'h4FFF) main_din_mux = cpu_math_ram_dout;
		else if (main_addr >= 16'h5000 && main_addr <= 16'h5FFF) main_din_mux = math_dout;
		// ESB takes over $6000-$FFFF with a different memory map:
		//   $6000-$7FFF  ESB main ROM (bank1, page-switched)
		//   $8000-$9FFF  slapstic-protected page (bank selected by slap_bs)
		//   $A000-$FFFF  ESB main ROM (bank2, page-switched)
		// SW paths are unchanged (fall through when mod_esb=0).
		else if (mod_esb && main_addr >= 16'h6000 && main_addr <= 16'h7FFF) main_din_mux = esb_main_rom_dout;
		else if (mod_esb && main_addr >= 16'h8000 && main_addr <= 16'h9FFF) main_din_mux = slap_rom_dout;
		else if (mod_esb && main_addr >= 16'hA000)                          main_din_mux = esb_main_rom_dout;
		else if (main_addr >= 16'h6000 && main_addr <= 16'h7FFF) main_din_mux = banked_rom_dout;
		else if (main_addr >= 16'h8000) main_din_mux = main_rom_dout;
		else if (adc_cs) main_din_mux = adc_data;

		// Communication
		else if (main_addr == 16'h4400) main_din_mux = mainlatch;
		else if (main_addr == 16'h4401) main_din_mux = {soundlatch_full, mainlatch_full, 6'h00};

		// Input ports are active-low; unused bits read high.
		// IN0: D7=L.Fire D6=R.Fire D5=Spare(1) D4=SelfTest D3=Slam(1) D2=AuxCoin D1=CoinL D0=CoinR
		else if (main_addr >= 16'h4300 && main_addr <= 16'h431F) main_din_mux = {~fire_l, ~fire_r, 1'b1, ~test_mode, 1'b1, ~aux_coin, ~coin1, ~coin2}; // IN0
		// IN1: D7=MathRun D6=VGHalt D5=L.Shield D4=R.Shield D3=Spare(1) D2=Diag(1) D1,D0=unused(1)
		else if (main_addr >= 16'h4320 && main_addr <= 16'h433F) main_din_mux = {math_run, avg_halted, ~shield_l, ~shield_r, 1'b1, 1'b1, 1'b1, 1'b1}; // IN1
		else if (main_addr >= 16'h4340 && main_addr <= 16'h435F) main_din_mux = dsw0; // DSW0
		else if (main_addr >= 16'h4360 && main_addr <= 16'h437F) main_din_mux = dsw1; // DSW1
	end
	assign main_din = main_din_mux;

	// AVG (Analog Vector Generator)
	wire avg_go = (main_addr >= 16'h4600 && main_addr <= 16'h461F) && !main_rw && main_vma;
	wire avg_rst_cmd = (main_addr >= 16'h4620 && main_addr <= 16'h463F) && !main_rw && main_vma;
	wire avg_is_dot;

	avg vector_generator (
		.clk(clk_12),
		.clken(ce_1m5),

		// CPU Interface (Internal registers / GO / RST)
		.cpu_addr(main_addr[13:0]),
		// Bus arbitration: on real hardware, EVMEM gates the AVG state machine
		// clock via NOR gate 3E (LS02) on the AVG board (schematic p.24 Fig.3).
		// .cpu_cs_l(~(main_vma && (main_addr < 16'h4000))),
		.cpu_cs_l(1'b1),
		.cpu_rw_l(main_rw),
		.cpu_data_in(),
		.cpu_data_out(main_dout),

		.vgrst(rst_12 | avg_rst_cmd),
		.vggo(avg_go),
		.halted(avg_halted),

		// External Memory for Vector Instructions
		.avg_addr_out(avg_addr),
		.avg_data_in(avg_din),

		// Vector Outputs
		.xout(avg_x),
		.yout(avg_y),
		.zout(avg_z_raw),
		.rgbout(avg_rgb),
		.is_dot(avg_is_dot),

		.dn_addr(dn_avg_prom_addr),
		.dn_data(dn_data),
		.dn_wr(dn_avg_prom_cs)
	);

	// Audio Chips (POKEY x4)
	wire [7:0] pokey0_dout, pokey1_dout, pokey2_dout, pokey3_dout;
	wire [7:0] pokey0_out, pokey1_out, pokey2_out, pokey3_out;

	// Star Wars POKEY interleaved mapping (0x1800 - 0x183F)
	wire [1:0] pokey_num = aud_addr[4:3];
	wire [3:0] pokey_reg = {aud_addr[5], aud_addr[2:0]};
	wire pokey_area = (aud_addr >= 16'h1800 && aud_addr <= 16'h183F) && aud_vma;

	wire pokey0_cs = pokey_area && (pokey_num == 2'd0);
	wire pokey1_cs = pokey_area && (pokey_num == 2'd1);
	wire pokey2_cs = pokey_area && (pokey_num == 2'd2);
	wire pokey3_cs = pokey_area && (pokey_num == 2'd3);

	// POKEY 0
	POKEY pokey0 (
		.CLK(clk_12),
		.ENA(ce_1m5),
		.ADDR(pokey_reg),
		.DIN(aud_dout),
		.RW_L(aud_rw),
		.CS(pokey0_cs),
		.CS_L(~pokey0_cs),
		.PIN(8'hFF),
		.DOUT(pokey0_dout),
		.DOUT_OE_L(),
		.AUDIO_OUT(pokey0_out)
	);

	// POKEY 1
	POKEY pokey1 (
		.CLK(clk_12),
		.ENA(ce_1m5),
		.ADDR(pokey_reg),
		.DIN(aud_dout),
		.RW_L(aud_rw),
		.CS(pokey1_cs),
		.CS_L(~pokey1_cs),
		.PIN(8'hFF),
		.DOUT(pokey1_dout),
		.DOUT_OE_L(),
		.AUDIO_OUT(pokey1_out)
	);

	// POKEY 2
	POKEY pokey2 (
		.CLK(clk_12),
		.ENA(ce_1m5),
		.ADDR(pokey_reg),
		.DIN(aud_dout),
		.RW_L(aud_rw),
		.CS(pokey2_cs),
		.CS_L(~pokey2_cs),
		.PIN(8'hFF),
		.DOUT(pokey2_dout),
		.DOUT_OE_L(),
		.AUDIO_OUT(pokey2_out)
	);

	// POKEY 3
	POKEY pokey3 (
		.CLK(clk_12),
		.ENA(ce_1m5),
		.ADDR(pokey_reg),
		.DIN(aud_dout),
		.RW_L(aud_rw),
		.CS(pokey3_cs),
		.CS_L(~pokey3_cs),
		.PIN(8'hFF),
		.DOUT(pokey3_dout),
		.DOUT_OE_L(),
		.AUDIO_OUT(pokey3_out)
	);

	// RIOT (MOS 6532) for TMS5220
	wire [7:0] riot_d_out;
	wire [7:0] riot_pa_out;
	wire [7:0] riot_pb_out;
	wire [7:0] riot_pa_in;
	wire [7:0] riot_pb_in;
	wire riot_cs = (aud_addr >= 16'h1000 && aud_addr <= 16'h109F) && aud_vma;
	wire riot_rs = (aud_addr >= 16'h1080); // 1 = IO, 0 = RAM

	A6532 riot (
		.clk(clk_12),
		.ph2_en(ce_1m5),
		.r(aud_rw),
		.rs(riot_rs),
		.cs(riot_cs),
		.irq(aud_irq_n),
		.d_in(aud_dout),
		.d_out(riot_d_out),
		.pa_in(riot_pa_in),
		.pa_out(riot_pa_out),
		.pb_in(riot_pb_in),
		.pb_out(riot_pb_out),
		.pa7(soundlatch_full),
		.a(aud_addr[6:0])
	);

	// TMS5220 Speech
	wire tms_ready_n;
	wire [7:0] tms_data_out;
	wire signed [13:0] tms_audio;

	assign riot_pa_in = {soundlatch_full, mainlatch_full, 3'b111, tms_ready_n, 2'b00}; // PA7=soundlatch_full, PA6=mainlatch_full, PA2=tms_ready_n
	assign riot_pb_in = tms_data_out; // Direct connect from TMS O_DBUS

	// TMS Clock Generation (~672kHz pulse)
	reg [4:0] tms_clk_div;
	reg tms_ena;
	always @(posedge clk_12) begin
		tms_ena <= 1'b0; // Default low
		if (tms_clk_div == 5'd17) begin
			tms_clk_div <= 5'd0;
			tms_ena <= 1'b1; // Pulse high for 1 cycle
		end else begin
			tms_clk_div <= tms_clk_div + 5'd1;
		end
	end

	TMS5220 tms (
		.I_OSC(clk_12),
		.I_ENA(tms_ena),
		.I_WSn(riot_pa_out[0]),
		.I_RSn(riot_pa_out[1]),
		.I_DATA(1'b0),
		.I_TEST(1'b0),
		.I_DBUS(riot_pb_out),
		.O_DBUS(tms_data_out),
		.O_RDYn(tms_ready_n),
		.O_INTn(),
		.O_SPKR(tms_audio)
	);

	// CPU Audio Data In Mux
	reg [7:0] aud_din_mux;
	always @(*) begin
		aud_din_mux = 8'hFF;
		if (pokey0_cs) aud_din_mux = pokey0_dout;
		else if (pokey1_cs) aud_din_mux = pokey1_dout;
		else if (pokey2_cs) aud_din_mux = pokey2_dout;
		else if (pokey3_cs) aud_din_mux = pokey3_dout;
		else if (riot_cs) aud_din_mux = riot_d_out;
		else if (aud_addr >= 16'h2000 && aud_addr <= 16'h27FF) aud_din_mux = aud_ram_dout;
		// ESB audio: $4000-$7FFF + $C000-$FFFF map to the 32KB esb_aud_rom
		// (113/112 low+high halves).  SW path unchanged below.
		else if (mod_esb && ((aud_addr >= 16'h4000 && aud_addr <= 16'h7FFF) || aud_addr >= 16'hC000))
			aud_din_mux = esb_aud_rom_dout;
		else if (aud_addr >= 16'h4000 && aud_addr <= 16'h7FFF) aud_din_mux = aud_rom_dout;
		else if (aud_addr >= 16'hB000) aud_din_mux = aud_rom_dout; // SW mirrored
		else if (aud_addr >= 16'h0800 && aud_addr <= 16'h0FFF) aud_din_mux = soundlatch;
	end
	assign aud_din = aud_din_mux;

	// =========================================================================
	// AUDIO MIXING (Based on original Atari schematic SP-225 Sheet 16A/16B)
	// =========================================================================
	// Summing Amplifier: TL084 (1/4 4C), Feedback R30 = 12K
	// POKEY 0, 1 (CO0, CO1): R21, R23 = 47K -> Gain = 12/47 = 0.255
	// POKEY 2, 3 (CO2, CO3): R25, R27 = 82K -> Gain = 12/82 = 0.146
	// TMS5220 (SPEECH):      R29 = 15K      -> Gain = 12/15 = 0.800

	// 1. Convert POKEYs to signed (remove DC offset)
	wire signed [8:0] p0_s = $signed({1'b0, pokey0_out}) - 9'sd128;
	wire signed [8:0] p1_s = $signed({1'b0, pokey1_out}) - 9'sd128;
	wire signed [8:0] p2_s = $signed({1'b0, pokey2_out}) - 9'sd128;
	wire signed [8:0] p3_s = $signed({1'b0, pokey3_out}) - 9'sd128;

	// 2. Pair sums
	wire signed [9:0] pair_p01 = p0_s + p1_s;
	wire signed [9:0] pair_p23 = p2_s + p3_s;

	// 3. Apply weights using shift-and-add
	// POKEY 0,1: x24 = (<<4) + (<<3)
	wire signed [16:0] mix_p01 = ({{3{pair_p01[9]}}, pair_p01, 4'b0})    // <<4
	                            + ({{4{pair_p01[9]}}, pair_p01, 3'b0});   // <<3

	// POKEY 2,3: x14 = (<<4) - (<<1)
	wire signed [16:0] mix_p23 = ({{3{pair_p23[9]}}, pair_p23, 4'b0})    // <<4
	                            - ({{6{pair_p23[9]}}, pair_p23, 1'b0});   // <<1

	// TMS5220: x2 = (<<1)
	wire signed [16:0] tms_ext = {{3{tms_audio[13]}}, tms_audio};
	wire signed [16:0] mix_tms = tms_ext <<< 1;                           // x2

	// 4. Raw mix (17-bit signed, max ~26110, fits within 16-bit mostly)
	wire signed [16:0] raw_mix = mix_p01 + mix_p23 + mix_tms;

	// =========================================================================
	// AUDIO PROCESSING (Sheet 16B: Filter + Reticon R5106 Delay/Stereo)
	// =========================================================================

	// --- 48 kHz clock enable from 12 MHz (divide by 250) ---
	reg [7:0] aud_div;
	reg       ce_48k;
	always @(posedge clk_12) begin
		ce_48k <= 1'b0;
		if (aud_div == 8'd249) begin
			aud_div <= 8'd0;
			ce_48k  <= 1'b1;
		end else begin
			aud_div <= aud_div + 8'd1;
		end
	end

	// --- TL084 MFB Low-Pass Filter (~4.9 kHz) ---
	wire signed [16:0] filtered_mix;
	audio_filter_tl084 pcb_filter (
		.clk(clk_12),
		.reset(rst_12),
		.ce(ce_48k),
		.enable(osd_audio_filter),
		.audio_in(raw_mix),
		.audio_out(filtered_mix)
	);

	// Reticon R5106 Delay (13.5 ms) - Pseudo-Stereo
	// The original PCB routes the delayed signal to stereo summing amps
	// (Sheet 16B, fig 2) alongside the dry signal. My interpretation:
	// Left = dry + wet, Right = dry - wet ("synthesized stereo" per SWSIG.DOC).
	wire signed [16:0] final_mix_l;
	wire signed [16:0] delay_wet;
	reticon_r5106 pcb_delay (
		.clk(clk_12),
		.reset(rst_12),
		.ce(ce_48k),
		.enable(osd_audio_delay),
		.audio_in(filtered_mix),
		.audio_out(final_mix_l),
		.audio_wet(delay_wet)
	);

	// Right channel: dry - wet
	wire signed [16:0] final_mix_r = filtered_mix - delay_wet;

	// =========================================================================
	// AUDIO OUTPUT (16-bit signed, saturating clip, stereo)
	// =========================================================================
	reg signed [15:0] audio_out_l_reg;
	reg signed [15:0] audio_out_r_reg;
	always @(posedge clk_12) begin
		if (ce_48k) begin
			// Left channel (dry + wet)
			if (final_mix_l > 17'sd32767)
				audio_out_l_reg <= 16'sd32767;
			else if (final_mix_l < -17'sd32768)
				audio_out_l_reg <= 16'h8000;
			else
				audio_out_l_reg <= final_mix_l[15:0];

			// Right channel (dry - wet)
			if (final_mix_r > 17'sd32767)
				audio_out_r_reg <= 16'sd32767;
			else if (final_mix_r < -17'sd32768)
				audio_out_r_reg <= 16'h8000;
			else
				audio_out_r_reg <= final_mix_r[15:0];
		end
	end
	assign audio_out_l = audio_out_l_reg;
	assign audio_out_r = audio_out_r_reg;

	// Z-Axis Intensity Tone Mapping
	(* romstyle = "logic" *) reg [7:0] z_lut[0:255] = '{default:0};
	initial begin
		z_lut[0] = 8'd0; z_lut[1] = 8'd2; z_lut[2] = 8'd3; z_lut[3] = 8'd5; z_lut[4] = 8'd7;
		z_lut[5] = 8'd9; z_lut[6] = 8'd10; z_lut[7] = 8'd12; z_lut[8] = 8'd14; z_lut[9] = 8'd15;
		z_lut[10] = 8'd17; z_lut[11] = 8'd19; z_lut[12] = 8'd21; z_lut[13] = 8'd22; z_lut[14] = 8'd24;
		z_lut[15] = 8'd26; z_lut[16] = 8'd27; z_lut[17] = 8'd29; z_lut[18] = 8'd31; z_lut[19] = 8'd33;
		z_lut[20] = 8'd34; z_lut[21] = 8'd36; z_lut[22] = 8'd38; z_lut[23] = 8'd39; z_lut[24] = 8'd41;
		z_lut[25] = 8'd43; z_lut[26] = 8'd45; z_lut[27] = 8'd46; z_lut[28] = 8'd48; z_lut[29] = 8'd50;
		z_lut[30] = 8'd52; z_lut[31] = 8'd54; z_lut[32] = 8'd56; z_lut[33] = 8'd58; z_lut[34] = 8'd60;
		z_lut[35] = 8'd62; z_lut[36] = 8'd64; z_lut[37] = 8'd66; z_lut[38] = 8'd68; z_lut[39] = 8'd70;
		z_lut[40] = 8'd72; z_lut[41] = 8'd74; z_lut[42] = 8'd76; z_lut[43] = 8'd78; z_lut[44] = 8'd80;
		z_lut[45] = 8'd82; z_lut[46] = 8'd84; z_lut[47] = 8'd86; z_lut[48] = 8'd88; z_lut[49] = 8'd90;
		z_lut[50] = 8'd92; z_lut[51] = 8'd94; z_lut[52] = 8'd96; z_lut[53] = 8'd98; z_lut[54] = 8'd100;
		z_lut[55] = 8'd102; z_lut[56] = 8'd104; z_lut[57] = 8'd106; z_lut[58] = 8'd108; z_lut[59] = 8'd110;
		z_lut[60] = 8'd112; z_lut[61] = 8'd114; z_lut[62] = 8'd116; z_lut[63] = 8'd118; z_lut[64] = 8'd120;
		z_lut[65] = 8'd122; z_lut[66] = 8'd124; z_lut[67] = 8'd126; z_lut[68] = 8'd128; z_lut[69] = 8'd130;
		z_lut[70] = 8'd132; z_lut[71] = 8'd134; z_lut[72] = 8'd136; z_lut[73] = 8'd138; z_lut[74] = 8'd140;
		z_lut[75] = 8'd142; z_lut[76] = 8'd144; z_lut[77] = 8'd146; z_lut[78] = 8'd148; z_lut[79] = 8'd150;
		z_lut[80] = 8'd152; z_lut[81] = 8'd154; z_lut[82] = 8'd156; z_lut[83] = 8'd158; z_lut[84] = 8'd160;
		z_lut[85] = 8'd162; z_lut[86] = 8'd164; z_lut[87] = 8'd166; z_lut[88] = 8'd168; z_lut[89] = 8'd170;
		z_lut[90] = 8'd172; z_lut[91] = 8'd174; z_lut[92] = 8'd176; z_lut[93] = 8'd178; z_lut[94] = 8'd180;
		z_lut[95] = 8'd182; z_lut[96] = 8'd184; z_lut[97] = 8'd186; z_lut[98] = 8'd188; z_lut[99] = 8'd190;
		z_lut[100] = 8'd192; z_lut[101] = 8'd194; z_lut[102] = 8'd196; z_lut[103] = 8'd198; z_lut[104] = 8'd200;
		z_lut[105] = 8'd202; z_lut[106] = 8'd204; z_lut[107] = 8'd206; z_lut[108] = 8'd208; z_lut[109] = 8'd210;
		z_lut[110] = 8'd212; z_lut[111] = 8'd214; z_lut[112] = 8'd216; z_lut[113] = 8'd216; z_lut[114] = 8'd217;
		z_lut[115] = 8'd217; z_lut[116] = 8'd217; z_lut[117] = 8'd217; z_lut[118] = 8'd218; z_lut[119] = 8'd218;
		z_lut[120] = 8'd218; z_lut[121] = 8'd219; z_lut[122] = 8'd219; z_lut[123] = 8'd219; z_lut[124] = 8'd219;
		z_lut[125] = 8'd220; z_lut[126] = 8'd220; z_lut[127] = 8'd220; z_lut[128] = 8'd221; z_lut[129] = 8'd221;
		z_lut[130] = 8'd221; z_lut[131] = 8'd221; z_lut[132] = 8'd222; z_lut[133] = 8'd222; z_lut[134] = 8'd222;
		z_lut[135] = 8'd223; z_lut[136] = 8'd223; z_lut[137] = 8'd223; z_lut[138] = 8'd223; z_lut[139] = 8'd224;
		z_lut[140] = 8'd224; z_lut[141] = 8'd224; z_lut[142] = 8'd225; z_lut[143] = 8'd225; z_lut[144] = 8'd225;
		z_lut[145] = 8'd225; z_lut[146] = 8'd226; z_lut[147] = 8'd226; z_lut[148] = 8'd226; z_lut[149] = 8'd227;
		z_lut[150] = 8'd227; z_lut[151] = 8'd227; z_lut[152] = 8'd227; z_lut[153] = 8'd228; z_lut[154] = 8'd228;
		z_lut[155] = 8'd228; z_lut[156] = 8'd229; z_lut[157] = 8'd229; z_lut[158] = 8'd229; z_lut[159] = 8'd229;
		z_lut[160] = 8'd230; z_lut[161] = 8'd230; z_lut[162] = 8'd230; z_lut[163] = 8'd231; z_lut[164] = 8'd231;
		z_lut[165] = 8'd231; z_lut[166] = 8'd231; z_lut[167] = 8'd232; z_lut[168] = 8'd232; z_lut[169] = 8'd233;
		z_lut[170] = 8'd233; z_lut[171] = 8'd234; z_lut[172] = 8'd234; z_lut[173] = 8'd235; z_lut[174] = 8'd235;
		z_lut[175] = 8'd236; z_lut[176] = 8'd236; z_lut[177] = 8'd237; z_lut[178] = 8'd237; z_lut[179] = 8'd238;
		z_lut[180] = 8'd239; z_lut[181] = 8'd239; z_lut[182] = 8'd240; z_lut[183] = 8'd240; z_lut[184] = 8'd241;
		z_lut[185] = 8'd241; z_lut[186] = 8'd242; z_lut[187] = 8'd242; z_lut[188] = 8'd243; z_lut[189] = 8'd244;
		z_lut[190] = 8'd244; z_lut[191] = 8'd245; z_lut[192] = 8'd245; z_lut[193] = 8'd246; z_lut[194] = 8'd246;
		z_lut[195] = 8'd247; z_lut[196] = 8'd247; z_lut[197] = 8'd248; z_lut[198] = 8'd248; z_lut[199] = 8'd249;
		z_lut[200] = 8'd250; z_lut[201] = 8'd250; z_lut[202] = 8'd251; z_lut[203] = 8'd251; z_lut[204] = 8'd252;
		z_lut[205] = 8'd252; z_lut[206] = 8'd253; z_lut[207] = 8'd253; z_lut[208] = 8'd254; z_lut[209] = 8'd254;
		z_lut[210] = 8'd255; z_lut[211] = 8'd255; z_lut[212] = 8'd255; z_lut[213] = 8'd255; z_lut[214] = 8'd255;
		z_lut[215] = 8'd255; z_lut[216] = 8'd255; z_lut[217] = 8'd255; z_lut[218] = 8'd255; z_lut[219] = 8'd255;
		z_lut[220] = 8'd255; z_lut[221] = 8'd255; z_lut[222] = 8'd255; z_lut[223] = 8'd255; z_lut[224] = 8'd255;
		z_lut[225] = 8'd255; z_lut[226] = 8'd255; z_lut[227] = 8'd255; z_lut[228] = 8'd255; z_lut[229] = 8'd255;
		z_lut[230] = 8'd255; z_lut[231] = 8'd255; z_lut[232] = 8'd255; z_lut[233] = 8'd255; z_lut[234] = 8'd255;
		z_lut[235] = 8'd255; z_lut[236] = 8'd255; z_lut[237] = 8'd255; z_lut[238] = 8'd255; z_lut[239] = 8'd255;
		z_lut[240] = 8'd255; z_lut[241] = 8'd255; z_lut[242] = 8'd255; z_lut[243] = 8'd255; z_lut[244] = 8'd255;
		z_lut[245] = 8'd255; z_lut[246] = 8'd255; z_lut[247] = 8'd255; z_lut[248] = 8'd255; z_lut[249] = 8'd255;
		z_lut[250] = 8'd255; z_lut[251] = 8'd255; z_lut[252] = 8'd255; z_lut[253] = 8'd255; z_lut[254] = 8'd255;
		z_lut[255] = 8'd255;
	end

	// Magnetic Inertia (Hotspot at line start)
	wire raw_beam_on = (|avg_z_raw && (avg_rgb != 3'b000));
	reg raw_beam_on_d = 0;
	always @(posedge clk_12) begin
		raw_beam_on_d <= raw_beam_on;
	end

	wire [8:0] z_base = {1'b0, avg_z_raw};
	wire [8:0] z_inertia_soft = (raw_beam_on && !raw_beam_on_d) ? (z_base + (z_base >> 1)) : z_base;
	assign avg_z = (z_inertia_soft > 9'd232) ? 8'd232 : z_inertia_soft[7:0];

	// Linear 1 (x1.21 expansion, maps 0-210 to 0-255)
	wire [16:0] linear1_mult = avg_z * 17'd311;
	wire [7:0] linear1_final_z = (avg_z >= 8'd210) ? 8'd255 : linear1_mult[15:8];

	// Linear 2 (x1.52 expansion)
	wire [16:0] linear2_mult = avg_z * 17'd389;
	wire [7:0] linear2_final_z = (avg_z >= 8'd168) ? 8'd255 : linear2_mult[15:8];

	wire [7:0] final_z =
		(effective_tonemapping == 2'd0) ? linear1_final_z : // Linear 1
		(effective_tonemapping == 2'd1) ? linear2_final_z : // Linear 2
		(effective_tonemapping == 2'd2) ? z_lut[avg_z] :    // Bright (LUT)
		avg_z; // Off

	// Detect the VJFCWN flash and suppress its off-screen border before geometry.
	wire x_match = ($signed(avg_x) >= 14'sd7678 && $signed(avg_x) <= 14'sd7682) ||
	               ($signed(avg_x) >= -14'sd7682 && $signed(avg_x) <= -14'sd7678);
	wire y_match = ($signed(avg_y) >= -14'sd8191 && $signed(avg_y) <= -14'sd8190);
	wire flash_sample = (avg_rgb == 3'd7) && (avg_z_raw == 8'd223) &&
	                    !avg_is_dot && !avg_halted;
	wire is_flash = (x_match || y_match) && flash_sample;
	wire hit_flash_active = HIT_FLASH_ENABLE && is_flash;
	wire flash_line = HIT_FLASH_ENABLE && flash_sample &&
		(($signed(avg_x) >= 14'sd7678) || ($signed(avg_x) <= -14'sd7678) ||
		 ($signed(avg_y) >= 14'sd8182) || ($signed(avg_y) <= -14'sd8190));

	// Resolution-independent flash accumulator in the machine domain.
	reg [7:0] flash_param = 0;
	reg [3:0] flash_sub = 0;
	reg [16:0] flash_tick_cnt = 0;
	wire flash_tick = (flash_tick_cnt == 17'd99999);

	always @(posedge clk_12) begin
		if (rst_12) begin
			flash_param <= 0;
			flash_sub <= 0;
			flash_tick_cnt <= 0;
		end else begin
			flash_tick_cnt <= flash_tick ? 17'd0 : flash_tick_cnt + 17'd1;

			if (flash_tick) begin
				if (flash_param > 8'd2)
					flash_param <= flash_param - 8'd2;
				else
					flash_param <= 0;
			end else if (hit_flash_active) begin
				flash_sub <= flash_sub + 1'b1;
				if ((flash_sub == 4'd12) && (flash_param < 8'd21))
					flash_param <= flash_param + 1'b1;
			end
		end
	end

	reg [7:0] flash_param_s1 = 0;
	reg [7:0] flash_param_s2 = 0;
	reg [7:0] flash_param_stable = 0;
	always @(posedge clk_vid) begin
		flash_param_s1 <= flash_param;
		flash_param_s2 <= flash_param_s1;
		if (flash_param_s1 == flash_param_s2)
			flash_param_stable <= flash_param_s2;
	end

	wire fifo_full_led;

	starwars_video video (
		.clk_source(clk_12),
		.clk_50(clk_50),
		.clk_125(clk_vid),
		.reset(reset),
		.upload_reset(upload_reset),

		.direct_video(direct_video),
		.direct_video_31khz(direct_video_31khz),
		.crt_15khz_480i(crt_15khz_480i),
		.crt_vertical_position(crt_vertical_position),
		.hdmi_height(HDMI_HEIGHT),
		.aspect_ratio(ar),
		.orientation(orientation),
		.zoom_wide(zoom_wide),

		.vec_x($signed(avg_x)),
		.vec_y($signed(avg_y)),
		.vec_z(final_z),
		.vec_rgb(avg_rgb),
		.vec_is_dot(avg_is_dot),
		.vec_beam(raw_beam_on),
		.vec_beam_inhibit(flash_line),
		.frame_done(avg_halted),

		.osd_flash_param(flash_param_stable),
		.osd_120hz(osd_120hz_mode),
		.osd_buffer_mode(osd_buffer_mode),
		.profile(osd_crt_profile),
		.off_dot_mode(osd_off_dot_mode),
		.off_tone_mapping(osd_off_tonemapping),
		.off_phosphor_mode(osd_off_phosphor_mode),
		.custom_1_settings(osd_custom1_settings),
		.custom_2_settings(osd_custom2_settings),

		.tone_mapping(effective_tonemapping),
		.video_arx(VIDEO_ARX),
		.video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(hblank),
		.vblank(vblank),
		.video_r(VGA_R),
		.video_g(VGA_G),
		.video_b(VGA_B),
		.hsync(hsync),
		.vsync(vsync),
		.field(VGA_F1),
		.mode_supports_120hz(mode_supports_120hz),
		.mode_is_15khz(mode_is_15khz),
		.mode_is_480line(mode_is_480line),
		.mode_is_240p(mode_is_240p),
		.video_mode_toggle(video_mode_toggle),
		.video_freeze(video_freeze),
		.fifo_full(fifo_full_led),

		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),

		.sdram_data_in(SDRAM_DQ_IN),
		.sdram_data_out(SDRAM_DQ_OUT),
		.sdram_data_oe(SDRAM_DQ_OE),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(SDRAM_DQM),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign led = {fifo_full_led, 1'b0, 1'b0};

endmodule
