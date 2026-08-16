//============================================================================
//  Star Wars video timing, geometry, and framebuffer integration
//
//  Written 2026 by Videodr0me
//============================================================================

`default_nettype none

module starwars_video
#(
	parameter logic [24:0] HEIGHT_STABLE_CYCLES = 25'd25_000_000
)
(
	input  wire        clk_source,
	input  wire        clk_50,
	input  wire        clk_125,
	input  wire        reset,
	input  wire        upload_reset,

	input  wire        direct_video,
	input  wire        direct_video_31khz,
	input  wire        crt_15khz_480i,
	input  wire  [2:0] crt_vertical_position,
	input  wire [11:0] hdmi_height,
	input  wire  [1:0] aspect_ratio,
	input  wire  [2:0] orientation,
	input  wire        zoom_wide,

	input  wire signed [13:0] vec_x,
	input  wire signed [13:0] vec_y,
	input  wire  [7:0] vec_z,
	input  wire  [2:0] vec_rgb,
	input  wire        vec_is_dot,
	input  wire        vec_beam,
	input  wire        vec_beam_inhibit,
	input  wire        frame_done,

	input  wire  [7:0] osd_flash_param,
	input  wire        osd_120hz,
	input  wire  [1:0] osd_buffer_mode,
	input  wire  [2:0] profile,
	input  wire  [2:0] off_dot_mode,
	input  wire  [1:0] off_tone_mapping,
	input  wire  [1:0] off_phosphor_mode,
	input  wire [22:0] custom_1_settings,
	input  wire [22:0] custom_2_settings,

	output wire  [1:0] tone_mapping,
	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output wire         ce_pixel,
	output wire         hblank,
	output wire         vblank,
	output wire   [7:0] video_r,
	output wire   [7:0] video_g,
	output wire   [7:0] video_b,
	output wire         hsync,
	output wire         vsync,
	output wire         field,
	output wire         mode_supports_120hz,
	output wire         mode_is_15khz,
	output wire         mode_is_480line,
	output wire         mode_is_240p,
	output wire         video_mode_toggle,
	output wire         video_freeze,
	output wire         fifo_full,

	output wire         ddram_clk,
	input  wire         ddram_busy,
	output wire   [7:0] ddram_burst_count,
	output wire  [28:0] ddram_address,
	input  wire  [63:0] ddram_data_out,
	input  wire         ddram_data_ready,
	output wire         ddram_read,
	output wire  [63:0] ddram_data_in,
	output wire   [7:0] ddram_byte_enable,
	output wire         ddram_write,

	input  wire  [15:0] sdram_data_in,
	output wire  [15:0] sdram_data_out,
	output wire         sdram_data_oe,
	output wire         sdram_cke,
	output wire         sdram_ncs,
	output wire         sdram_nras,
	output wire         sdram_ncas,
	output wire         sdram_nwe,
	output wire   [1:0] sdram_dqm,
	output wire  [12:0] sdram_address,
	output wire   [1:0] sdram_bank
);

	// The framework height settles after core startup. Direct Video selects
	// its render class explicitly because HDMI height is not meaningful there.
	logic [11:0] height_meta_50 = 12'd0;
	logic [11:0] height_sync_50 = 12'd0;
	logic [11:0] height_candidate_50 = 12'd0;
	logic [11:0] height_stable_50 = 12'd0;
	logic [24:0] height_timer_50 = 25'd0;
	logic direct_video_meta_50 = 1'b0;
	logic direct_video_sync_50 = 1'b0;
	logic direct_31khz_meta_50 = 1'b0;
	logic direct_31khz_sync_50 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic upload_reset_50_meta = 1'b1;
	logic upload_reset_50 = 1'b1;
	wire [11:0] requested_height_50 = direct_video_sync_50 ?
		(direct_31khz_sync_50 ? 12'd480 : 12'd240) : hdmi_height;

	always_ff @(posedge clk_50) begin
		upload_reset_50_meta <= upload_reset;
		upload_reset_50 <= upload_reset_50_meta;
		direct_video_meta_50 <= direct_video;
		direct_video_sync_50 <= direct_video_meta_50;
		direct_31khz_meta_50 <= direct_video_31khz;
		direct_31khz_sync_50 <= direct_31khz_meta_50;
		height_meta_50 <= requested_height_50;
		height_sync_50 <= height_meta_50;

		if (upload_reset_50) begin
			height_candidate_50 <= 12'd0;
			height_stable_50 <= 12'd0;
			height_timer_50 <= 25'd0;
		end else if ((height_sync_50 <= 12'd200) ||
		             (height_sync_50 != height_candidate_50)) begin
			height_candidate_50 <= height_sync_50;
			height_timer_50 <= 25'd0;
		end else if (height_candidate_50 != height_stable_50) begin
			if (height_timer_50 < HEIGHT_STABLE_CYCLES - 1'd1)
				height_timer_50 <= height_timer_50 + 1'd1;
			else begin
				height_stable_50 <= height_candidate_50;
				height_timer_50 <= 25'd0;
			end
		end else begin
			height_timer_50 <= 25'd0;
		end
	end

	wire [23:0] control_in = {
		crt_vertical_position,
		height_stable_50,
		osd_120hz,
		(profile == 3'd0),
		direct_video,
		direct_video_31khz,
		crt_15khz_480i,
		orientation,
		zoom_wide
	};
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [23:0] control_meta = '0;
	logic [23:0] control_sync = '0;
	logic [23:0] control_sync_d = '0;
	logic [23:0] control_stable = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic upload_reset_125_meta = 1'b1;
	logic upload_reset_125 = 1'b1;

	always_ff @(posedge clk_125) begin
		upload_reset_125_meta <= upload_reset;
		upload_reset_125 <= upload_reset_125_meta;
		control_meta <= control_in;
		control_sync <= control_meta;
		control_sync_d <= control_sync;
		if (control_sync == control_sync_d)
			control_stable <= control_sync;
	end

	typedef struct packed {
		logic [11:0] height;
		logic        mode_120hz;
		logic        interlaced;
		logic  [2:0] crt_position;
	} mode_key_t;

	localparam logic [1:0] PIXEL_FULL = 2'd0;
	localparam logic [1:0] PIXEL_HALF = 2'd1;
	localparam logic [1:0] PIXEL_FRACTIONAL = 2'd2;

	function automatic logic signed [4:0] decode_crt_position(
		input logic [2:0] position,
		input logic       is_240p
	);
		begin
			if (is_240p) begin
				case (position)
					3'd1: decode_crt_position = 5'sd2;
					3'd2: decode_crt_position = 5'sd4;
					3'd3: decode_crt_position = 5'sd6;
					3'd4: decode_crt_position = -5'sd2;
					3'd5: decode_crt_position = -5'sd4;
					3'd6: decode_crt_position = -5'sd6;
					default: decode_crt_position = 5'sd0;
				endcase
			end else begin
				case (position)
					3'd1: decode_crt_position = 5'sd4;
					3'd2: decode_crt_position = 5'sd8;
					3'd3: decode_crt_position = 5'sd12;
					3'd4: decode_crt_position = -5'sd4;
					3'd5: decode_crt_position = -5'sd8;
					3'd6: decode_crt_position = -5'sd10;
					default: decode_crt_position = 5'sd0;
				endcase
			end
		end
	endfunction

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] center_x;
		logic [11:0] center_y;
		logic [12:0] optimized_arx;
		logic [12:0] optimized_ary;
		logic [11:0] h_total;
		logic [11:0] v_total;
		logic [11:0] hs_start;
		logic [11:0] hs_end;
		logic [11:0] vs_start;
		logic [11:0] vs_end;
		logic  [1:0] pixel_mode;
		logic [17:0] pixel_step;
		logic [17:0] pixel_wrap;
		logic        is_1080p;
		logic        is_480p;
		logic        is_240p;
		logic        is_interlaced;
		logic signed [4:0] crt_vertical_offset;
	} video_mode_t;

	function automatic video_mode_t decode_video_mode(
		input logic [11:0] height,
		input logic        requested_120hz,
		input logic        requested_interlace,
		input logic  [2:0] requested_crt_position
	);
		video_mode_t mode;
		logic signed [4:0] vertical_offset;
		logic signed [12:0] shifted_vs_start;
		logic signed [12:0] shifted_vs_end;
		begin
			mode = '0;
			vertical_offset = 5'sd0;
			shifted_vs_start = 13'sd0;
			shifted_vs_end = 13'sd0;
			mode.fb_width = 12'd980;
			mode.fb_height = 12'd720;
			mode.center_x = 12'd490;
			mode.center_y = 12'd350;
			mode.optimized_arx = (height >= 12'd1440) ?
				(13'h1000 | 13'd1960) : (13'h1000 | 13'd980);
			mode.optimized_ary = (height >= 12'd1440) ?
				(13'h1000 | 13'd1440) : (13'h1000 | 13'd720);
			mode.h_total = 12'd1388;
			mode.v_total = 12'd749;
			mode.hs_start = 12'd1108;
			mode.hs_end = 12'd1196;
			mode.vs_start = 12'd728;
			mode.vs_end = 12'd733;
			mode.pixel_mode = requested_120hz ? PIXEL_FULL : PIXEL_HALF;
			if ((height >= 12'd1080) && (height < 12'd1400)) begin
				mode.fb_width = 12'd1472;
				mode.fb_height = 12'd1080;
				mode.center_x = 12'd736;
				mode.center_y = 12'd525;
				mode.optimized_arx = 13'h1000 | 13'd1472;
				mode.optimized_ary = 13'h1000 | 13'd1080;
				mode.h_total = 12'd1851;
				mode.v_total = 12'd1124;
				mode.hs_start = 12'd1600;
				mode.hs_end = 12'd1688;
				mode.vs_start = 12'd1088;
				mode.vs_end = 12'd1093;
				mode.pixel_mode = PIXEL_FULL;
				mode.is_1080p = 1'b1;
			end else if (height < 12'd480) begin
				vertical_offset = decode_crt_position(
					requested_crt_position, 1'b1);
				shifted_vs_start = 13'sd246 - vertical_offset;
				shifted_vs_end = 13'sd249 - vertical_offset;
				mode.fb_width = 12'd720;
				mode.fb_height = 12'd240;
				mode.center_x = 12'd360;
				mode.center_y = 12'd121;
				mode.optimized_arx = 13'h1000 | 13'd720;
				mode.optimized_ary = 13'h1000 | 13'd240;
				mode.h_total = 12'd883;
				mode.v_total = 12'd263;
				mode.hs_start = 12'd755;
				mode.hs_end = 12'd821;
				mode.vs_start = shifted_vs_start[11:0];
				mode.vs_end = shifted_vs_end[11:0];
				mode.pixel_mode = PIXEL_FRACTIONAL;
				mode.pixel_step = 18'd2448;
				mode.pixel_wrap = 18'd19427;
				mode.is_240p = 1'b1;
				mode.crt_vertical_offset = vertical_offset;
			end else if (height < 12'd720) begin
				vertical_offset = decode_crt_position(
					requested_crt_position, 1'b0);
				shifted_vs_start = 13'sd493 - vertical_offset;
				shifted_vs_end = 13'sd499 - vertical_offset;
				mode.fb_width = 12'd720;
				mode.fb_height = 12'd480;
				mode.center_x = 12'd360;
				mode.center_y = 12'd241;
				mode.optimized_arx = 13'h1000 | 13'd720;
				mode.optimized_ary = 13'h1000 | 13'd480;
				mode.h_total = 12'd883;
				mode.v_total = 12'd528;
				mode.hs_start = 12'd755;
				mode.hs_end = 12'd821;
				mode.vs_start = shifted_vs_start[11:0];
				mode.vs_end = shifted_vs_end[11:0];
				mode.pixel_mode = PIXEL_FRACTIONAL;
				mode.pixel_step = 18'd53958;
				mode.pixel_wrap = 18'd186667;
				mode.is_480p = 1'b1;
				mode.is_interlaced = requested_interlace;
				mode.crt_vertical_offset = vertical_offset;
			end

			decode_video_mode = mode;
		end
	endfunction

	function automatic logic [1:0] height_class(input logic [11:0] height);
		begin
			if (height < 12'd480)
				height_class = 2'd0;
			else if (height < 12'd720)
				height_class = 2'd1;
			else if ((height >= 12'd1080) && (height < 12'd1400))
				height_class = 2'd3;
			else
				height_class = 2'd2;
		end
	endfunction

	wire [2:0] stable_crt_position = control_stable[23:21];
	wire [11:0] stable_height = control_stable[20:9];
	wire stable_120hz = control_stable[8];
	wire request_bypass = control_stable[7];
	wire stable_direct_video = control_stable[6];
	wire stable_direct_31khz = control_stable[5];
	wire stable_480i = control_stable[4];
	wire [2:0] stable_orientation = control_stable[3:1];
	wire stable_zoom_wide = control_stable[0];
	wire height_supports_120hz = !stable_direct_video &&
	                             (stable_height >= 12'd720) &&
	                             (stable_height <= 12'd768);
	logic [11:0] request_height;
	logic request_interlaced;

	always_comb begin
		request_height = stable_height;
		request_interlaced = 1'b0;
		if (stable_direct_video) begin
			request_height = stable_direct_31khz ? 12'd480 :
			                 (stable_480i ? 12'd480 : 12'd240);
			request_interlaced = !stable_direct_31khz && stable_480i;
		end else if (stable_height < 12'd480) begin
			request_height = stable_480i ? 12'd480 : 12'd240;
			request_interlaced = stable_480i;
		end
	end

	wire request_120hz = stable_120hz && height_supports_120hz;
	wire request_valid = stable_height > 12'd200;
	wire [2:0] request_crt_position = (request_height < 12'd720) ?
		stable_crt_position : 3'd0;
	mode_key_t request_key;
	video_mode_t requested_mode;
	assign request_key = {
		request_height,
		request_120hz,
		request_interlaced,
		request_crt_position
	};
	always_comb requested_mode = decode_video_mode(
		request_height, request_120hz, request_interlaced,
		request_crt_position);

	typedef enum logic [2:0] {
		MODE_WAIT_START,
		MODE_START_TIMING,
		MODE_START_HOLD,
		MODE_RUN,
		MODE_WAIT_ACTIVE_VBLANK,
		MODE_WAIT_TIMING_WRAP,
		MODE_WAIT_TARGET_VBLANK,
		MODE_HOLD_TARGET_FRAME
	} mode_state_t;

	mode_state_t mode_state = MODE_WAIT_START;
	mode_key_t key_active_q = '{12'd480, 1'b0, 1'b0, 3'd0};
	mode_key_t key_pending_q = '{12'd480, 1'b0, 1'b0, 3'd0};
	video_mode_t mode_q = decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0);
	video_mode_t pending_mode_q = decode_video_mode(
		12'd480, 1'b0, 1'b0, 3'd0);
	logic mode_ready = 1'b0;
	logic video_mode_toggle_q = 1'b0;
	logic video_freeze_q = 1'b1;
	logic active_bypass_q = 1'b0;
	logic pending_bypass_q = 1'b0;
	logic transition_timing_q = 1'b0;
	logic transition_restart_q = 1'b0;
	logic mode_restart_q = 1'b0;
	logic frame_wrap;
	logic raw_path_vblank;
	logic processed_path_vblank;
	logic raw_path_vblank_q = 1'b1;
	logic processed_path_vblank_q = 1'b1;
	logic output_vblank_q = 1'b1;
	logic output_vblank_entry_q = 1'b0;

	wire raw_path_vblank_entry = raw_path_vblank && !raw_path_vblank_q;
	wire processed_path_vblank_entry =
		processed_path_vblank && !processed_path_vblank_q;
	wire progressive_active_vblank_entry = active_bypass_q ?
		raw_path_vblank_entry : processed_path_vblank_entry;
	wire progressive_target_vblank_entry = pending_bypass_q ?
		raw_path_vblank_entry : processed_path_vblank_entry;
	wire active_path_vblank_entry = key_active_q.interlaced ?
		output_vblank_entry_q : progressive_active_vblank_entry;
	wire target_path_vblank_entry = key_pending_q.interlaced ?
		output_vblank_entry_q : progressive_target_vblank_entry;
	wire request_changed = (request_key != key_active_q) ||
	                       (request_bypass != active_bypass_q);
	wire profile_path_commit =
		(mode_state == MODE_WAIT_TARGET_VBLANK) &&
		!transition_restart_q && target_path_vblank_entry &&
		(pending_bypass_q != active_bypass_q);
	wire mode_commit = (mode_state == MODE_WAIT_TIMING_WRAP) && frame_wrap;
	wire timing_reset = !mode_ready;
	logic [1:0] renderer_reset_sync = 2'b11;

	always_ff @(posedge clk_125)
		renderer_reset_sync <= {
			renderer_reset_sync[0], reset || !mode_ready || mode_restart_q
		};
	wire renderer_reset = renderer_reset_sync[1];

	assign video_mode_toggle = video_mode_toggle_q;
	assign video_freeze = video_freeze_q;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || !mode_ready) begin
			raw_path_vblank_q <= 1'b1;
			processed_path_vblank_q <= 1'b1;
			output_vblank_q <= 1'b1;
			output_vblank_entry_q <= 1'b0;
		end else begin
			raw_path_vblank_q <= raw_path_vblank;
			processed_path_vblank_q <= processed_path_vblank;
			output_vblank_entry_q <= ce_pixel && vblank && !output_vblank_q;
			if (ce_pixel)
				output_vblank_q <= vblank;
		end
	end

	always_ff @(posedge clk_125) begin
		if (upload_reset_125) begin
			key_active_q <= '{12'd480, 1'b0, 1'b0, 3'd0};
			key_pending_q <= '{12'd480, 1'b0, 1'b0, 3'd0};
			mode_q <= decode_video_mode(12'd480, 1'b0, 1'b0, 3'd0);
			pending_mode_q <= decode_video_mode(
				12'd480, 1'b0, 1'b0, 3'd0);
			active_bypass_q <= 1'b0;
			pending_bypass_q <= 1'b0;
			transition_timing_q <= 1'b0;
			transition_restart_q <= 1'b0;
			mode_restart_q <= 1'b0;
			mode_state <= MODE_WAIT_START;
			mode_ready <= 1'b0;
			video_mode_toggle_q <= 1'b0;
			video_freeze_q <= 1'b1;
		end else begin
			case (mode_state)
				MODE_WAIT_START: begin
					mode_ready <= 1'b0;
					video_freeze_q <= 1'b1;
					mode_restart_q <= 1'b0;
					if (request_valid) begin
						key_active_q <= request_key;
						key_pending_q <= request_key;
						mode_q <= requested_mode;
						pending_mode_q <= requested_mode;
						active_bypass_q <= request_bypass;
						pending_bypass_q <= request_bypass;
						mode_state <= MODE_START_TIMING;
					end
				end

				MODE_START_TIMING: begin
					mode_ready <= 1'b1;
					video_freeze_q <= 1'b1;
					mode_state <= MODE_START_HOLD;
				end

				MODE_START_HOLD: begin
					if (frame_wrap) begin
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end
				end

				MODE_RUN: begin
					video_freeze_q <= 1'b0;
					mode_restart_q <= 1'b0;
					transition_restart_q <= 1'b0;
					if (request_valid && request_changed) begin
						key_pending_q <= request_key;
						pending_mode_q <= requested_mode;
						pending_bypass_q <= request_bypass;
						mode_state <= MODE_WAIT_ACTIVE_VBLANK;
					end
				end

				MODE_WAIT_ACTIVE_VBLANK: begin
					if (request_valid && !request_changed) begin
						mode_state <= MODE_RUN;
					end else if (request_valid) begin
						key_pending_q <= request_key;
						pending_mode_q <= requested_mode;
						pending_bypass_q <= request_bypass;
						if (active_path_vblank_entry) begin
							transition_timing_q <= request_key != key_active_q;
							transition_restart_q <=
								height_class(request_key.height) !=
								height_class(key_active_q.height);
							video_freeze_q <= 1'b1;
							mode_state <= (request_key != key_active_q) ?
								MODE_WAIT_TIMING_WRAP : MODE_WAIT_TARGET_VBLANK;
						end
					end
				end

				MODE_WAIT_TIMING_WRAP: begin
					video_freeze_q <= 1'b1;
					if (frame_wrap) begin
						key_active_q <= key_pending_q;
						mode_q <= pending_mode_q;
						video_mode_toggle_q <= !video_mode_toggle_q;
						mode_restart_q <= transition_restart_q;
						mode_state <= MODE_WAIT_TARGET_VBLANK;
					end
				end

				MODE_WAIT_TARGET_VBLANK: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						mode_restart_q <= 1'b0;
						active_bypass_q <= pending_bypass_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end else if (!transition_restart_q &&
					             target_path_vblank_entry) begin
						active_bypass_q <= pending_bypass_q;
						if (!transition_timing_q)
							video_mode_toggle_q <= !video_mode_toggle_q;
						mode_state <= MODE_HOLD_TARGET_FRAME;
					end
				end

				MODE_HOLD_TARGET_FRAME: begin
					video_freeze_q <= 1'b1;
					if (transition_restart_q && frame_wrap) begin
						transition_restart_q <= 1'b0;
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end else if (!transition_restart_q &&
					             target_path_vblank_entry) begin
						video_freeze_q <= 1'b0;
						mode_state <= MODE_RUN;
					end
				end

				default: mode_state <= MODE_WAIT_START;
			endcase
		end
	end

	wire [11:0] fb_width = mode_q.fb_width;
	wire [11:0] fb_height = mode_q.fb_height;
	wire [11:0] x_center = mode_q.center_x;
	wire [11:0] y_center = mode_q.center_y;
	logic half_rate_phase = 1'b0;
	logic [17:0] fractional_phase = 18'd0;
	logic [10:0] h_counter = 11'd0;
	logic [10:0] v_counter = 11'd0;
	logic progressive_ce_pixel = 1'b0;
	logic v_end_q = 1'b0;
	logic raw_hsync;
	logic raw_vsync;
	logic raw_hblank;
	logic raw_vblank;

	wire h_end = h_counter >= mode_q.h_total[10:0];
	wire v_end = v_end_q;
	assign frame_wrap = progressive_ce_pixel && h_end && v_end;

	always_ff @(posedge clk_125) begin
		if (timing_reset || mode_commit)
			v_end_q <= 1'b0;
		else
			v_end_q <= v_counter >= mode_q.v_total[10:0];
	end

	always_ff @(posedge clk_125) begin
		if (timing_reset) begin
			half_rate_phase <= 1'b0;
			fractional_phase <= 18'd0;
			h_counter <= mode_q.h_total[10:0];
			v_counter <= mode_q.fb_height[10:0] + 11'd2;
			progressive_ce_pixel <= 1'b0;
		end else if (mode_commit) begin
			half_rate_phase <= 1'b0;
			fractional_phase <= 18'd0;
			h_counter <= 11'd0;
			v_counter <= 11'd0;
			progressive_ce_pixel <= 1'b0;
		end else begin
			half_rate_phase <= !half_rate_phase;
			case (mode_q.pixel_mode)
				PIXEL_FULL: progressive_ce_pixel <= 1'b1;
				PIXEL_HALF: progressive_ce_pixel <= half_rate_phase;
				default: begin
					if (fractional_phase >= mode_q.pixel_wrap) begin
						fractional_phase <= fractional_phase -
						                    mode_q.pixel_wrap;
						progressive_ce_pixel <= 1'b1;
					end else begin
						fractional_phase <= fractional_phase +
						                    mode_q.pixel_step;
						progressive_ce_pixel <= 1'b0;
					end
				end
			endcase

			if (progressive_ce_pixel) begin
				if (h_end) begin
					h_counter <= 11'd0;
					v_counter <= v_end ? 11'd0 : v_counter + 1'd1;
				end else begin
					h_counter <= h_counter + 1'd1;
				end
			end
		end
	end

	always_comb begin
		raw_hsync = !((h_counter >= mode_q.hs_start[10:0]) &&
		              (h_counter < mode_q.hs_end[10:0]));
		raw_vsync = !((v_counter >= mode_q.vs_start[10:0]) &&
		              (v_counter < mode_q.vs_end[10:0]));
		raw_hblank = h_counter >= mode_q.fb_width[10:0];
		raw_vblank = v_counter >= mode_q.fb_height[10:0];
	end

	always_comb begin
		case (aspect_ratio)
			2'd0: begin
				video_arx = mode_q.optimized_arx;
				video_ary = mode_q.optimized_ary;
			end
			2'd1: begin
				video_arx = 13'd0;
				video_ary = 13'd0;
			end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	assign mode_supports_120hz = mode_ready && height_supports_120hz;
	assign mode_is_15khz = mode_ready &&
	                       (mode_q.is_240p || mode_q.is_interlaced);
	assign mode_is_480line = mode_ready && mode_q.is_480p;
	assign mode_is_240p = mode_ready && mode_q.is_240p;

	logic [2:0] effective_dot_mode;
	logic [1:0] effective_tone_mapping;
	logic [2:0] effective_bloom_width;
	logic [2:0] effective_bloom_curve;
	logic [2:0] effective_halo_filter;
	logic [1:0] effective_halo_spread;
	logic [1:0] effective_phosphor_mode;
	logic       effective_color_space;
	logic [2:0] effective_color_channels;
	logic       effective_slot_mask;

	vfb_profile_resolver profile_resolver (
		.profile(profile),
		.fb_height(fb_height),
		.off_dot_mode(off_dot_mode),
		.off_tonemapping(off_tone_mapping),
		.off_phosphor_mode(off_phosphor_mode),
		.custom1_settings(custom_1_settings),
		.custom2_settings(custom_2_settings),
		.dot_mode(effective_dot_mode),
		.tonemapping(effective_tone_mapping),
		.bloom_width(effective_bloom_width),
		.bloom_curve(effective_bloom_curve),
		.halo_filter(effective_halo_filter),
		.halo_spread(effective_halo_spread),
		.phosphor_mode(effective_phosphor_mode),
		.color_space(effective_color_space),
		.color_channels(effective_color_channels),
		.slot_mask(effective_slot_mask)
	);

	assign tone_mapping = effective_tone_mapping;

	// Mode fields cross once as a stable packet into the AVG source domain.
	wire [54:0] geometry_control_in = {
		fb_width,
		fb_height,
		x_center,
		y_center,
		mode_q.is_1080p,
		mode_q.is_480p,
		mode_q.is_240p,
		stable_orientation,
		stable_zoom_wide
	};
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [54:0] geometry_control_meta = '0;
	logic [54:0] geometry_control_sync = '0;
	logic [54:0] geometry_control_sync_d = '0;
	logic [54:0] geometry_control_stable = '0;

	always_ff @(posedge clk_source) begin
		geometry_control_meta <= geometry_control_in;
		geometry_control_sync <= geometry_control_meta;
		geometry_control_sync_d <= geometry_control_sync;
		if (geometry_control_sync == geometry_control_sync_d)
			geometry_control_stable <= geometry_control_sync;
	end

	wire [11:0] geometry_width = geometry_control_stable[54:43];
	wire [11:0] geometry_height = geometry_control_stable[42:31];
	wire [11:0] geometry_center_x = geometry_control_stable[30:19];
	wire [11:0] geometry_center_y = geometry_control_stable[18:7];
	wire geometry_1080p = geometry_control_stable[6];
	wire geometry_480p = geometry_control_stable[5];
	wire geometry_240p = geometry_control_stable[4];
	wire [2:0] geometry_orientation = geometry_control_stable[3:1];
	wire geometry_zoom_wide = geometry_control_stable[0];
	wire slot_mask_rows = (stable_orientation == 3'd1) ||
	                      (stable_orientation == 3'd3) ||
	                      (stable_orientation == 3'd6) ||
	                      (stable_orientation == 3'd7);

	wire [10:0] raster_x;
	wire [10:0] raster_y;
	wire raster_in_bounds;

	starwars_geometry geometry (
		.source_x(vec_x),
		.source_y(vec_y),
		.mode_1080p(geometry_1080p),
		.mode_480p(geometry_480p),
		.mode_240p(geometry_240p),
		.center_x(geometry_center_x),
		.center_y(geometry_center_y),
		.render_width(geometry_width),
		.render_height(geometry_height),
		.orientation(geometry_orientation),
		.zoom_wide(geometry_zoom_wide),
		.raster_x(raster_x),
		.raster_y(raster_y),
		.beam_in_bounds(raster_in_bounds)
	);

	wire [2:0] auto_dot_mode = (fb_height >= 12'd1000) ? 3'd2 :
	                            (fb_height >= 12'd700)  ? 3'd1 : 3'd0;
	wire [2:0] actual_dot_mode =
		(effective_dot_mode == 3'd0) ? auto_dot_mode :
		(effective_dot_mode == 3'd1) ? 3'd0 :
		(effective_dot_mode == 3'd2) ? 3'd1 :
		(effective_dot_mode == 3'd3) ? 3'd2 : 3'd0;

	wire [7:0] progressive_video_r;
	wire [7:0] progressive_video_g;
	wire [7:0] progressive_video_b;
	wire progressive_hsync;
	wire progressive_vsync;
	wire progressive_hblank;
	wire progressive_vblank;

	vfb_top renderer (
		.clk_sys(clk_125),
		.clk_12(clk_source),
		.reset(renderer_reset),
		.video_timing_reset(timing_reset),

		.X_VECTOR(raster_x),
		.Y_VECTOR(raster_y),
		.Z_VECTOR(vec_z),
		.RGB(vec_rgb),
		.IS_DOT(vec_is_dot),
		.BEAM_ON(vec_beam && raster_in_bounds && !vec_beam_inhibit),

		.DDRAM_CLK(ddram_clk),
		.DDRAM_BUSY(ddram_busy),
		.DDRAM_BURSTCNT(ddram_burst_count),
		.DDRAM_ADDR(ddram_address),
		.DDRAM_DOUT(ddram_data_out),
		.DDRAM_DOUT_READY(ddram_data_ready),
		.DDRAM_RD(ddram_read),
		.DDRAM_DIN(ddram_data_in),
		.DDRAM_BE(ddram_byte_enable),
		.DDRAM_WE(ddram_write),

		.SDRAM_DQ_IN(sdram_data_in),
		.SDRAM_DQ_OUT(sdram_data_out),
		.SDRAM_DQ_OE(sdram_data_oe),
		.SDRAM_CKE(sdram_cke),
		.SDRAM_nCS(sdram_ncs),
		.SDRAM_nRAS(sdram_nras),
		.SDRAM_nCAS(sdram_ncas),
		.SDRAM_nWE(sdram_nwe),
		.SDRAM_DQM(sdram_dqm),
		.SDRAM_A(sdram_address),
		.SDRAM_BA(sdram_bank),

		.RENDER_WIDTH(fb_width),
		.RENDER_HEIGHT(fb_height),

		.VGA_R(progressive_video_r),
		.VGA_G(progressive_video_g),
		.VGA_B(progressive_video_b),
		.VGA_HS(progressive_hsync),
		.VGA_VS(progressive_vsync),
		.VGA_HBLANK(progressive_hblank),
		.VGA_VBLANK(progressive_vblank),

		.h_cnt(h_counter),
		.v_cnt(v_counter),
		.ce_pix(progressive_ce_pixel),
		.hsync(raw_hsync),
		.vsync(raw_vsync),
		.hblank(raw_hblank),
		.vblank(raw_vblank),

		.FLASH_PARAM(osd_flash_param),
		.FRAME_DONE(frame_done),
		.BUFFER_MODE(osd_buffer_mode),
		.DOT_MODE(actual_dot_mode),
		.FIFO_FULL_LED(fifo_full),

		.osd_bloom_width(effective_bloom_width),
		.osd_bloom_curve(effective_bloom_curve),
		.osd_halo_filter(effective_halo_filter),
		.osd_phosphor_mode(effective_phosphor_mode),
		.osd_halo_spread(effective_halo_spread),
		.osd_color_space(effective_color_space),
		.osd_color_channels(effective_color_channels),
		.osd_slot_mask(effective_slot_mask),
		.osd_slot_mask_rows(slot_mask_rows),
		.full_bypass_active(active_bypass_q),
		.raw_path_vblank(raw_path_vblank),
		.processed_path_vblank(processed_path_vblank),
		.arbiter_reset_busy()
	);

	localparam logic [1:0] INTERLACER_PATH_RESTART_CYCLES = 2'd3;
	logic [1:0] interlacer_restart_count = 2'd0;
	logic interlacer_mode_commit_q = 1'b0;

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset)
			interlacer_mode_commit_q <= 1'b0;
		else
			interlacer_mode_commit_q <= mode_commit;
	end

	always_ff @(posedge clk_125) begin
		if (upload_reset_125 || timing_reset || !mode_q.is_interlaced)
			interlacer_restart_count <= 2'd0;
		else if (profile_path_commit)
			interlacer_restart_count <= INTERLACER_PATH_RESTART_CYCLES;
		else if (interlacer_restart_count != 2'd0)
			interlacer_restart_count <= interlacer_restart_count - 1'd1;
	end

	vfb_interlacer interlacer (
		.clk_sys(clk_125),
		.reset(timing_reset || interlacer_mode_commit_q ||
		       mode_restart_q || !mode_q.is_interlaced ||
		       (interlacer_restart_count != 2'd0)),
		.enable(mode_q.is_interlaced),
		.vertical_offset(mode_q.crt_vertical_offset),
		.ce_pix_in(progressive_ce_pixel),
		.r_in(progressive_video_r),
		.g_in(progressive_video_g),
		.b_in(progressive_video_b),
		.hsync_in(progressive_hsync),
		.vsync_in(progressive_vsync),
		.hblank_in(progressive_hblank),
		.vblank_in(progressive_vblank),
		.ce_pix_out(ce_pixel),
		.r_out(video_r),
		.g_out(video_g),
		.b_out(video_b),
		.hsync_out(hsync),
		.vsync_out(vsync),
		.hblank_out(hblank),
		.vblank_out(vblank),
		.field_out(field)
	);

endmodule

`default_nettype wire
