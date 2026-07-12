//============================================================================
//  Arcade: Star Wars
//
//  Port to MiSTer FPGA by Videodr0me 2026
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
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

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

wire [15:0] sdram_dq_out;
wire        sdram_dq_oe;
wire  [1:0] sdram_dqm;

// Commands and write data change on the 125 MHz video/core clock rising edge.
// Driving SDRAM with the inverted clock gives them half a cycle to settle
// before the chip's active edge.
assign SDRAM_DQ   = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;
assign SDRAM_DQML = sdram_dqm[0];
assign SDRAM_DQMH = sdram_dqm[1];

assign VGA_F1    = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign VGA_SL = 0;
assign USER_OUT  = '1;
wire [2:0] core_led;
assign LED_USER  = core_led[2] | ioctl_download;
// assign LED_POWER = {1'b1, core_led[1]};
// assign LED_DISK  = {1'b1, core_led[0]};
assign LED_POWER = 0; // Let system control
assign LED_DISK  = 0; // Let system control
assign BUTTONS   = 0;
assign AUDIO_MIX = 0;
assign HDMI_FREEZE = 0;

assign CLK_VIDEO = clk_125; // Direct PLL output (125 MHz)
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = ~(hblank | vblank);

wire [1:0] ar = status[15:14];

// Stable transition to and from 120Hz Mode.
// ASCAL still does not like transitions to and from 120Hz and occasionally hangs.
// Double-flop and s1==s2 check for safe multi-bit domain crossing
reg [11:0] h_s1 = 0, h_s2 = 0;
reg [11:0] hdmi_height_candidate = 0;
reg [11:0] stable_height_reg = 0;
reg [24:0] hdmi_height_timer = 0;

always @(posedge clk_50) begin
	h_s1 <= HDMI_HEIGHT;
	h_s2 <= h_s1;

	if (h_s1 == h_s2) begin
		if (h_s2 > 12'd200 && h_s2 == hdmi_height_candidate) begin
			if (hdmi_height_timer < 25'd25_000_000) begin
				hdmi_height_timer <= hdmi_height_timer + 1'd1;
			end else begin
				stable_height_reg <= hdmi_height_candidate;
			end
		end else begin
			hdmi_height_candidate <= h_s2;
			hdmi_height_timer <= 0;
			stable_height_reg <= 0; // Go to 0 while stabilizing
		end
	end
end

reg hz_s1 = 0, hz_s2 = 0;
reg osd_120hz_latched = 0;
reg [24:0] hz_timer = 0;

always @(posedge clk_50) begin
	hz_s1 <= status[25];
	hz_s2 <= hz_s1;

	if (hz_s1 == hz_s2) begin
		if (hz_s2 != osd_120hz_latched) begin
			if (hz_timer < 25'd25_000_000) begin
				hz_timer <= hz_timer + 1'd1;
			end else begin
				osd_120hz_latched <= hz_s2;
				hz_timer <= 0;
			end
		end else begin
			hz_timer <= 0;
		end
	end
end

// Force STABLE_HEIGHT to 0 during 120Hz toggle debouncing, forcing a soft reset in starwars.sv
wire is_120hz_changing = (hz_s2 != osd_120hz_latched) || (hz_timer > 0);
wire [11:0] STABLE_HEIGHT = is_120hz_changing ? 12'd0 : stable_height_reg;
wire STABLE_120HZ = osd_120hz_latched & (STABLE_HEIGHT == 12'd720);

// Profile Management has per resolution presets and offers two custom option sets.
//
// Status Bit Map:
//             Upper                             Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX  XXXXXXX
`include "build_id.v"
localparam CONF_STR = {
	"Star Wars;;",
	"-;",
	"P3,Video Options;",
	"P3-;",
	"P3O[15:14],Aspect ratio,Optimized,Stretched,Pixel Perfect;",
	"D3P3O[25],120Hz (720p only),Off,On;",
	"P3O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
	"P3-;",
	"P3O[68:66],Profile,Off,A Touch of CRT,80s Cruise Control,80s Overdrive,Neon Fever Dream,Pink Flamingo ESB,Custom 1,Custom 2;",
	"h7P3O[30:28],Dot Scale,Auto,Pixel,2x,2.5x;",
	"h7P3O[38:37],Tone Mapping,Linear 2,Bright,Off,Linear 1;",
	"h7P3O[56:55],Phosphor Decay,Off,LUT A,LUT B,LUT C;",
	"h7P3-;",
	"h7P3-, For advanced settings;",
	"h7P3-, select Custom Profiles 1/2;",
	"h8P3-;",
	"h8P3-,This profile adds a subtle;",
	"h8P3-,CRT halo and bloom effect,;",
	"h8P3-,to modern AA vector drawing;",
	"h8P3-;",
	"h8P3-,   Use Custom Profiles 1/2;",
	"h8P3-, to create your own effects;",
	"h9P3-;",
	"h9P3-,Step away from the modern..;",
	"h9P3-,The Amplifone Slot-Mask adds;",
	"h9P3-,faint vertical CRT stripes +;",
	"h9P3-,richer halos and blooming.;",
	"h9P3-,A new color space setting;",
	"h9P3-,delivers authentic blues.;",
	"h9P3-;",
	"h9P3-,Warning: Overdrive is next;",
	"hAP3-;",
	"hAP3-,A remote arcade in the 80s:;",
	"hAP3-,CRTs overdriven and abused;",
	"hAP3-,pulsate with vector glow.;",
	"hAP3-;",
	"hAP3-,Phosphor decay simulation;",
	"hAP3-,depends highly on your;",
	"hAP3-,monitor's panel type and;",
	"hAP3-,settings;",
	"hAP3-;",
	"hBP3-;",
	"hBP3-,     Epilepsy warning:;",
	"hBP3-,    excessive flashing;",
	"hBP3-,       bright lights;",
	"hBP3-;",
	"hBP3-,   Use Custom Profiles 1/2;",
	"hBP3-, to create your own effects;",
	"hDP3O[71:69],> Dot Scale,Auto,Pixel,2x,2.5x;",
	"hDP3O[73:72],> Tone Mapping,Linear 2,Bright,Off,Linear 1;",
	"hDP3O[76:74],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
	"hDD5P3O[79:77],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hDP3O[82:80],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
	"hDD6P3O[84:83],> Halo Spread,Original,Wide 1,Wide 2,Wide 3;",
	"hDP3O[86:85],> Phosphor Decay,Off,LUT A,LUT B,LUT C;",
	"hDP3O[87],> Color Space,Off,Amp709;",
	"hDP3O[90:88],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
	"hDP3O[91],> Slot Mask,Off,On;",
	"hEP3O[94:92],> Dot Scale,Auto,Pixel,2x,2.5x;",
	"hEP3O[96:95],> Tone Mapping,Linear 2,Bright,Off,Linear 1;",
	"hEP3O[99:97],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
	"hED5P3O[102:100],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
	"hEP3O[105:103],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
	"hED6P3O[107:106],> Halo Spread,Original,Wide 1,Wide 2,Wide 3;",
	"hEP3O[109:108],> Phosphor Decay,Off,LUT A,LUT B,LUT C;",
	"hEP3O[110],> Color Space,Off,Amp709;",
	"hEP3O[113:111],> Color Channels,RGB,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
	"hEP3O[114],> Slot Mask,Off,On;",
	 "-;",
	"P2,Cabinet Audio Hardware;",
	"P2-;",
	"P2O5,TL 084 Filter,On,Off;",
	"P2O6,Reticon Del/Rev,On,Off;",
	"-;",
	"P4,Input Controls;",
	"P4o01,Input,Analog,Digital,Auto;",
	"D4P4o23,Digital Sensitivity,Medium,Low,High,Max;",
	"P4-;",
	"P4o4,Y-Axis,Normal,Inverted;",
	"-;",
	"P1,DIP Settings;",
	"P1-,* Change setup via Testmode;",
	"P1-,* in Demo Loop - not DIPs!;",
	"P1O1,Test Mode,Off,On;",
	"P1-;",
	// Star Wars DIPs
	"h1P1O78,Starting Shields,8,9,6,7;",
	"h1P1O9A,Difficulty,Moderate,Hard,Hardest,Easy;",
	"h1P1OBC,Bonus Shields,1,2,3,0;",
	"h1P1OD,Demo Sounds,On,Off;",
	"h1P1OHI,Coinage,1 Play/Coin,2 Coins/Play,Free Play,2 Plays/Coin;",
	"h1P1OJK,Right Coin,x1,x4,x5,x6;",
	"h1P1OL,Left Coin,x1,x2;",
	"h1P1OMNO,Bonus Coin Adder,None,2 gives 1,4 gives 1,4 gives 2,5 gives 1,3 gives 1;",
	"h1P1OG,Freeze,Off,On;",
	// Empire Strikes Back DIPs
	"h2P1O78,Starting Shields,4,5,2,3;",
	"h2P1O9A,Difficulty,Hard,Hardest,Easy,Moderate;",
	"h2P1OBC,JEDI Letter Mode,Increment,Level,Inc. Only,Level Only;",
	"h2P1OD,Demo Sounds,On,Off;",
	"h2P1OHI,Coinage,1 Play/Coin,2 Coins/Play,Free Play,2 Plays/Coin;",
	"h2P1OJK,Right Coin,x1,x4,x5,x6;",
	"h2P1OL,Left Coin,x1,x2;",
	"h2P1OMNO,Bonus Coin Adder,None,2 gives 1,4 gives 1,4 gives 2,5 gives 1,3 gives 1;",
	"h2P1OG,Freeze,Off,On;",
	"P1-;",
	"P1-,* DIPs need Clear & Reset !;",
	"P1T3,Clear NVRAM;",
	"-;",
	"OR,Autosave NVRAM,Off,On;",
	"T4,Save NVRAM;",
	"-;",
	"P5,Core Info;",
	"P5-;",
	"P5-,Atari Star Wars / ESB core;",
	"P5-,     by Videodr0me 2026;",
	"P5-;",
	"P5-,If you enjoy reliving the;",
	"P5-,golden age of arcade games,;",
	"P5-,please support my work and;",
	"P5-,future updates:;",
	"P5-;",
	"P5-,buymeacoffee.com/videodr0me;",
	"-;",
	"R0,Reset;",
	"J1,Fire L,Shield L,Aux Coin,Coin L,Coin R,Fire R,Shield R;",
	"jn,A,B,Start,R,L,Y,Z;",
	"V,v2.00.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_12, clk_50, clk_125;
assign SDRAM_CLK = ~clk_125;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_50),
	.outclk_1(clk_12),
	.outclk_2(clk_6),
	.outclk_3(clk_125),
	.locked(pll_locked)
);


///////////////////////////////////////////////////

wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire        ioctl_wr;
wire        ioctl_rd;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire  [7:0] ioctl_index;

wire [15:0] joy_0, joy_1;
wire [15:0] joy = joy_0 | joy_1;
wire [15:0] joy_l_analog_0;
wire        rom_download = ioctl_download && !ioctl_index;
wire        nvram_download = ioctl_download && (ioctl_index == 8'd4);
wire [24:0] dl_addr = ioctl_addr;

// Profile Management
wire [2:0] crt_profile = status[68:66];
wire       crt_profile_off        = (crt_profile == 3'd0);
wire       crt_profile_touch      = (crt_profile == 3'd1);
wire       crt_profile_typical    = (crt_profile == 3'd2);
wire       crt_profile_overdriven = (crt_profile == 3'd3);
wire       crt_profile_neon       = (crt_profile == 3'd4);
wire       crt_profile_pink       = (crt_profile == 3'd5);
wire       crt_profile_custom1    = (crt_profile == 3'd6);
wire       crt_profile_custom2    = (crt_profile == 3'd7);
wire       crt_profile_flashing   = crt_profile_neon | crt_profile_pink;

wire [2:0] crt_custom_bloom_width =
	crt_profile_custom2 ? status[99:97] : status[76:74];
wire [2:0] crt_custom_halo =
	crt_profile_custom2 ? status[105:103] : status[82:80];
wire       crt_custom_active = crt_profile_custom1 | crt_profile_custom2;
wire       crt_custom_bloom_width_off =
	crt_custom_active && (crt_custom_bloom_width == 3'd0);
wire       crt_custom_halo_off =
	crt_custom_active && (crt_custom_halo == 3'd0);
wire [1:0] osd_off_tonemapping = status[38:37] + 2'd1;
wire [1:0] osd_custom1_tonemapping = status[73:72] + 2'd1;
wire [1:0] osd_custom2_tonemapping = status[96:95] + 2'd1;

wire [22:0] crt_custom1_settings = {
	status[71:69],  // Dot Scale
	osd_custom1_tonemapping,  // Tone Mapping
	status[76:74],  // Bloom Width
	status[79:77],  // Bloom Curve
	status[82:80],  // Halo
	status[84:83],  // Halo Spread
	status[86:85],  // Phosphor Decay
	status[87],     // Color Space
	status[90:88],  // Color Channels
	status[91]      // Slot Mask
};

wire [22:0] crt_custom2_settings = {
	status[94:92],    // Dot Scale
	osd_custom2_tonemapping,  // Tone Mapping
	status[99:97],    // Bloom Width
	status[102:100],  // Bloom Curve
	status[105:103],  // Halo
	status[107:106],  // Halo Spread
	status[109:108],  // Phosphor Decay
	status[110],      // Color Space
	status[113:111],  // Color Channels
	status[114]       // Slot Mask
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_12),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_menumask({
		1'b0,                         // F: unused
		crt_profile_custom2,          // E: show Custom 2 editable bank
		crt_profile_custom1,          // D: show Custom 1 editable bank
		1'b0,                         // C: unused
		crt_profile_flashing,         // B: show Neon/Pink flashing warning
		crt_profile_overdriven,       // A: show 80s Overdrive info rows
		crt_profile_typical,          // 9: show 80s Cruise Control info rows
		crt_profile_touch,            // 8: show A Touch of CRT info rows
		crt_profile_off,              // 7: show Off editable rows
		crt_custom_halo_off,          // 6: disable Custom halo spread if halo is Off
		crt_custom_bloom_width_off,   // 5: disable Custom bloom curve if bloom is Off
		is_analog_input,              // 4: disable digital sensitivity in analog mode
		STABLE_HEIGHT != 12'd720,     // 3: disable 120Hz outside 720p
		mod_esb,                      // 2: hide Star Wars DIP rows
		mod_starwars,                 // 1: hide ESB DIP rows
		direct_video                  // 0: framework direct-video mask
	}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.new_vmode(1'b0),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd4),
	.ioctl_wr(ioctl_wr),
	.ioctl_rd(ioctl_rd),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joy_0),
	.joystick_1(joy_1),
	.joystick_l_analog_0(joy_l_analog_0)
);

wire m_fire_l   = joy[4];          // Left fire (Button A)
wire m_fire_r   = joy[9];          // Right fire (Button Y)
wire m_shield_l = joy[5];          // Left shield/thumb (Button B)
wire m_shield_r = joy[10];         // Right shield/thumb (Button Z)
wire m_auxcoin  = joy[6];          // Aux coin / self-test advance
wire m_coin     = joy[7];
wire m_coin2    = joy[8];

wire m_right = joy[0];
wire m_left  = joy[1];
wire m_down  = joy[2];
wire m_up    = joy[3];

// ESB mod selector.  The MRA's <rom index="1"><part>1</part></rom>
// drives ioctl_index=1 with data=0x01 when ESB is loaded; mod=0 (the
// default at boot) selects Star Wars.  Sticky after rom_download
// completes so the value survives once the MRA is in.
reg [7:0] mod_byte = 8'h00;
always @(posedge clk_12) begin
	if (ioctl_wr && (ioctl_index == 8'd1)) mod_byte <= ioctl_dout;
end
wire mod_esb = (mod_byte == 8'h01);
wire mod_starwars = !mod_esb;

// Video signals
wire hblank, vblank;
wire hs, vs;


wire reset = (RESET | status[0] |  buttons[1] | rom_download | nvram_download);

// Digital Joystick and Y-Axis Inversion Handling
wire [1:0] input_mode = status[33:32];
wire is_analog_input = (input_mode == 2'd0);
wire digital_yoke_forced = (input_mode == 2'd1);
wire [3:0] digital_yoke_step =
	status[35:34] == 2'b01 ? 4'd1 :
	status[35:34] == 2'b10 ? 4'd4 :
	status[35:34] == 2'b11 ? 4'd8 :
	                          4'd2;
wire [7:0] digital_yoke_move_step = {4'd0, digital_yoke_step};
// Separated for future enhancements (e.g., independent auto-centering speed)
wire [7:0] digital_yoke_center_step = digital_yoke_move_step;

function automatic signed [8:0] step_digital_yoke_axis;
	input signed [8:0] current;
	input signed [8:0] target;
	input [7:0] step;
	reg signed [9:0] diff;
	reg signed [9:0] step_s;
	begin
		diff = $signed({target[8], target}) - $signed({current[8], current});
		step_s = $signed({2'd0, step});

		if (diff > step_s)
			step_digital_yoke_axis = current + $signed({1'b0, step});
		else if (diff < -step_s)
			step_digital_yoke_axis = current - $signed({1'b0, step});
		else
			step_digital_yoke_axis = target;
	end
endfunction

wire input_y_reverse = status[36];
wire m_digital_up = input_y_reverse ? m_down : m_up;
wire m_digital_down = input_y_reverse ? m_up : m_down;
wire digital_yoke_x_active = m_left ^ m_right;
wire digital_yoke_y_active = m_digital_up ^ m_digital_down;
wire digital_yoke_direction = m_left | m_right | m_up | m_down;
wire signed [8:0] analog_yoke_x = $signed({joy_l_analog_0[7], joy_l_analog_0[7:0]});
wire signed [8:0] analog_yoke_y = $signed({joy_l_analog_0[15], joy_l_analog_0[15:8]});
wire analog_yoke_active =
	(analog_yoke_x > 9'sd24) || (analog_yoke_x < -9'sd24) ||
	(analog_yoke_y > 9'sd24) || (analog_yoke_y < -9'sd24);
wire signed [8:0] digital_yoke_target_x = (m_left ^ m_right) ? (m_right ? 9'sd127 : -9'sd128) : 9'sd0;
wire signed [8:0] digital_yoke_target_y = digital_yoke_y_active ? (m_digital_down ? 9'sd127 : -9'sd128) : 9'sd0;
reg signed [8:0] digital_yoke_x;
reg signed [8:0] digital_yoke_y;
reg [15:0] digital_yoke_tick_div;
wire digital_yoke_tick = (digital_yoke_tick_div == 16'd0);

reg digital_auto_latched;
wire digital_yoke_mode = (digital_yoke_forced || digital_auto_latched) && !is_analog_input;

always @(posedge clk_12) begin
	if (reset) begin
		digital_auto_latched <= 1'b0;
		digital_yoke_x <= 9'sd0;
		digital_yoke_y <= 9'sd0;
		digital_yoke_tick_div <= 16'd0;
	end else begin
		if (digital_yoke_forced || is_analog_input)
			digital_auto_latched <= 1'b0;
		else if (digital_yoke_direction)
			digital_auto_latched <= 1'b1;
		else if (analog_yoke_active)
			digital_auto_latched <= 1'b0;

		digital_yoke_tick_div <= digital_yoke_tick_div + 16'd1;

		if (!digital_yoke_mode) begin
			digital_yoke_x <= 9'sd0;
			digital_yoke_y <= 9'sd0;
			digital_yoke_tick_div <= 16'd0;
		end else if (digital_yoke_tick) begin
			digital_yoke_x <= step_digital_yoke_axis(
				digital_yoke_x,
				digital_yoke_target_x,
				digital_yoke_x_active ? digital_yoke_move_step : digital_yoke_center_step
			);
			digital_yoke_y <= step_digital_yoke_axis(
				digital_yoke_y,
				digital_yoke_target_y,
				digital_yoke_y_active ? digital_yoke_move_step : digital_yoke_center_step
			);
		end
	end
end

wire [7:0] raw_analog_y = joy_l_analog_0[15:8];
wire [7:0] final_analog_y = input_y_reverse ? ~raw_analog_y : raw_analog_y;
wire [7:0] yoke_x = digital_yoke_mode ? digital_yoke_x[7:0] : joy_l_analog_0[7:0];
wire [7:0] yoke_y = digital_yoke_mode ? digital_yoke_y[7:0] : final_analog_y;

// AUDIO OUT
wire [15:0] audio_l, audio_r;
assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;
assign AUDIO_S = 1;
wire vgade;

// DIP SWITCHES (SW0)
wire [7:0] m_dsw0 = {
	~status[16],                                    // [7] Freeze (OG, 0=Off, 1=On -> ~0 = 1 = Off)
	mod_esb ? ~status[13] : status[13],             // [6] Demo Sounds (OD, 0=On, 1=Off)
	mod_esb ? ((status[12:11] == 2'b00) ? 2'b11 :
			   (status[12:11] == 2'b11) ? 2'b00 : status[12:11]) :
			   (status[12:11] + 2'd1),              // [5:4] Bonus Shields / JEDI Letters (OBC)
	mod_esb ? status[10:9] : (status[10:9] + 2'd1), // [3:2] Difficulty (O9A)
	mod_esb ? ~status[8:7] : (status[8:7] + 2'd2)   // [1:0] Starting Shields (O78)
};
// DIP SWITCHES (SW1)
wire [7:0] m_dsw1 = {
	status[24:22],       // [7:5] Bonus Coin Adder (OMNO)
	status[21],          // [4] Left Coin (OL)
	status[20:19],       // [3:2] Right Coin (OJK)
	status[18:17] + 2'd2 // [1:0] Coinage (OHI, rotated +2: 0=1P/C,1=2C/P,2=Free,3=2P/C)
};

starwars #(
	.HIT_FLASH_ENABLE(1'b1)
) starwars_core
(
	.clk_12(clk_12),
	.clk_50(clk_50),
	.clk_vid(clk_125),
	.reset(reset),

	.osd_buffer_mode(status[40:39]),
	.osd_audio_filter(~status[5]),   // Inverted: OSD 0=On, 1=Off
	.osd_audio_delay(~status[6]),    // Inverted: OSD 0=On, 1=Off
	.osd_crt_profile(crt_profile),
	.osd_off_dot_mode(status[30:28]),
	.osd_off_tonemapping(osd_off_tonemapping),
	.osd_off_phosphor_mode(status[56:55]),
	.osd_custom1_settings(crt_custom1_settings),
	.osd_custom2_settings(crt_custom2_settings),

	.ar(ar),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.STABLE_HEIGHT(STABLE_HEIGHT),
	.osd_120hz_mode_in(STABLE_120HZ),

	.mod_esb(mod_esb),

	.CE_PIXEL(CE_PIXEL),

	// DDRAM Framebuffer Interface
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),

	.SDRAM_DQ_IN(SDRAM_DQ),
	.SDRAM_DQ_OUT(sdram_dq_out),
	.SDRAM_DQ_OE(sdram_dq_oe),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_DQM(sdram_dqm),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),

	.audio_out_l(audio_l),
	.audio_out_r(audio_r),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.hsync(hs),
	.vsync(vs),
	.vblank(vblank),
	.hblank(hblank),

	.dsw0(m_dsw0),
	.dsw1(m_dsw1),
	.coin1(m_coin),
	.coin2(m_coin2),
	.aux_coin(m_auxcoin),
	.fire_l(m_fire_l),
	.fire_r(m_fire_r),
	.shield_l(m_shield_l),
	.shield_r(m_shield_r),
	.test_mode(status[1]),
	.analog_x(yoke_x),
	.analog_y(yoke_y),

	.led(core_led),

	// ROM Download
	.dn_addr(dl_addr),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & rom_download),

	.nvram_write_pulse(nvram_write_pulse),
	.nvram_wr_ext(nvram_wr_ext),
	.nvram_addr_ext(nvram_addr_ext),
	.nvram_din_ext(nvram_din_ext),
	.nvram_dout_ext(nvram_dout_ext)
);

// --- NVRAM Save/Load/Clear Logic ---
wire nvram_cs_ioctl = (ioctl_index == 8'd4);
wire nvram_wr_ioctl = nvram_cs_ioctl && ioctl_download && ioctl_wr;

reg [7:0] clear_addr;
reg clearing;
reg old_clear_req;

always @(posedge clk_12) begin
	old_clear_req <= status[3];
	if (status[3] && !old_clear_req) begin
		clearing <= 1;
		clear_addr <= 0;
	end else if (clearing) begin
		if (clear_addr == 255) clearing <= 0;
		clear_addr <= clear_addr + 8'd1;
	end
end

wire        nvram_wr_ext   = nvram_wr_ioctl || clearing;
wire  [7:0] nvram_addr_ext = clearing ? clear_addr : ioctl_addr[7:0];
wire  [7:0] nvram_din_ext  = clearing ? 8'h00 : ioctl_dout;
wire  [7:0] nvram_dout_ext;
wire        nvram_write_pulse;

// --- NVRAM Auto-Save & Manual Save  ---
reg nvram_dirty;
reg force_save;


always @(posedge clk_12) begin
	if (reset) begin
		nvram_dirty <= 0;
		force_save <= 0;
	end else begin
		if (ioctl_upload && ioctl_index == 8'd4) begin
			nvram_dirty <= 0;
			force_save <= 0;
		end else if (nvram_write_pulse) begin
			nvram_dirty <= 1;
		end

		// If NVRAM is cleared we force a save.
		if (clearing && clear_addr == 255) begin
			force_save <= 1;
		end
	end
end

assign ioctl_upload_req = (status[27] & nvram_dirty) | status[4] | force_save;
assign ioctl_din = (ioctl_index == 8'd4) ? nvram_dout_ext : 8'h00;

endmodule
