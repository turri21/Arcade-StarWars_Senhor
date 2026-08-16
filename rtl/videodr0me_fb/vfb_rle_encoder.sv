// ============================================================================
// Line-local RLE encoder for canonical Star Wars pixels.
// Written 2026 by Videodr0me
//
// Colored runs carry the RGB mask, nine-bit intensity, and a count of one to
// sixteen. Color zero selects a black or repeat token with a count of one to
// 2048. Every line starts with a black previous sample.
// ============================================================================

module vfb_rle_encoder (
	input  logic        clk_sys,
	input  logic        reset,

	input  logic        pixel_valid,
	input  logic [15:0] canonical_in,
	input  logic        line_end,

	output logic        token_valid,
	input  logic        token_ready,
	output logic [15:0] token_data,
	output logic        token_eol,

	output logic        overflow
);

	localparam integer RUN_FIFO_DEPTH = 16;
	localparam integer RUN_FIFO_AW = $clog2(RUN_FIFO_DEPTH);
	localparam integer RUN_ENTRY_W = 1 + 13 + 16;

	typedef enum logic [1:0] {
		EMIT_IDLE,
		EMIT_BLACK,
		EMIT_COLOR,
		EMIT_REPEAT
	} emit_state_t;

	function automatic logic [15:0] canonicalize(
		input logic [15:0] sample
	);
		logic [15:0] normalized;
		begin
			normalized = {sample[15:13], 4'd0, sample[8:0]};
			canonicalize = ((sample[15:13] == 0) || (sample[8:0] == 0)) ?
				16'd0 : normalized;
		end
	endfunction

	function automatic logic [10:0] count_m1_2048(
		input logic [12:0] count
	);
		count_m1_2048 = (count >= 13'd2048) ?
			11'h7ff : count[10:0] - 11'd1;
	endfunction

	function automatic logic [3:0] count_m1_16(
		input logic [4:0] count
	);
		count_m1_16 = (count >= 5'd16) ? 4'd15 : count[3:0] - 4'd1;
	endfunction

	logic        input_valid;
	logic [15:0] input_sample;
	logic        input_line_end;
	logic        run_valid;
	logic [15:0] run_sample;
	logic [12:0] run_count;

	(* ramstyle = "logic" *) logic [RUN_ENTRY_W-1:0]
		run_fifo [0:RUN_FIFO_DEPTH-1];
	logic [RUN_FIFO_AW:0] run_fifo_used;
	logic [RUN_FIFO_AW-1:0] run_fifo_rd_ptr;
	logic [RUN_FIFO_AW-1:0] run_fifo_wr_ptr;
	logic pending_valid;
	logic [RUN_ENTRY_W-1:0] pending_entry;
	logic prefetch_valid;
	logic [RUN_ENTRY_W-1:0] prefetch_entry;

	emit_state_t emit_state;
	logic [15:0] emit_sample;
	logic [12:0] emit_remaining;
	logic emit_eol;

	wire run_fifo_empty = (run_fifo_used == 0);
	wire run_fifo_full = (run_fifo_used == RUN_FIFO_DEPTH);
	wire [RUN_ENTRY_W-1:0] run_fifo_head = run_fifo[run_fifo_rd_ptr];
	wire emit_can_write = !token_valid || token_ready;
	wire emit_busy = (emit_state != EMIT_IDLE);
	wire emit_finishes = emit_can_write && emit_busy &&
		(((emit_state == EMIT_COLOR) && (emit_remaining <= 13'd16)) ||
		 ((emit_state != EMIT_COLOR) && (emit_remaining <= 13'd2048)));
	wire emit_available = !emit_busy || emit_finishes;
	wire run_fifo_pop = !prefetch_valid && !run_fifo_empty;
	wire start_prefetch = emit_available && prefetch_valid;
	wire start_fifo_head = emit_available && !prefetch_valid && run_fifo_pop;
	wire start_emit = start_prefetch || start_fifo_head;
	wire [RUN_ENTRY_W-1:0] start_entry =
		prefetch_valid ? prefetch_entry : run_fifo_head;
	wire start_eol = start_entry[29];
	wire [12:0] start_count = start_entry[28:16];
	wire [15:0] start_sample = start_entry[15:0];
	wire [4:0] emit_color_count = (emit_remaining >= 13'd16) ?
		5'd16 : {1'b0, emit_remaining[3:0]};

	wire run_fifo_can_push = !run_fifo_full || run_fifo_pop;
	wire run_fifo_push = pending_valid && run_fifo_can_push;
	wire pixel_extends_run = input_valid && run_valid &&
		(input_sample == run_sample) && (run_count < 13'd4096);
	wire pixel_finishes_run = input_valid && run_valid && !pixel_extends_run;
	wire line_finishes_run = input_line_end && run_valid;
	wire run_close_request = pixel_finishes_run || line_finishes_run;
	wire pending_ready = !pending_valid || run_fifo_can_push;
	wire run_close_accept = run_close_request && pending_ready;
	wire [RUN_ENTRY_W-1:0] completed_run = {
		line_finishes_run, run_count, run_sample
	};

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			token_valid <= 1'b0;
			token_data <= 16'd0;
			token_eol <= 1'b0;
			input_valid <= 1'b0;
			input_sample <= 16'd0;
			input_line_end <= 1'b0;
			run_valid <= 1'b0;
			run_sample <= 16'd0;
			run_count <= 13'd0;
			run_fifo_used <= '0;
			run_fifo_rd_ptr <= '0;
			run_fifo_wr_ptr <= '0;
			pending_valid <= 1'b0;
			pending_entry <= '0;
			prefetch_valid <= 1'b0;
			prefetch_entry <= '0;
			emit_state <= EMIT_IDLE;
			emit_sample <= 16'd0;
			emit_remaining <= 13'd0;
			emit_eol <= 1'b0;
			overflow <= 1'b0;
		end else begin
			input_valid <= pixel_valid;
			input_sample <= canonicalize(canonical_in);
			input_line_end <= line_end;

			if (token_valid && token_ready)
				token_valid <= 1'b0;

			if (emit_busy && emit_can_write) begin
				token_valid <= 1'b1;
				case (emit_state)
					EMIT_BLACK: begin
						token_data <= {3'd0, 2'b00,
							count_m1_2048(emit_remaining)};
						if (emit_remaining > 13'd2048) begin
							emit_remaining <= emit_remaining - 13'd2048;
							token_eol <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol <= emit_eol;
						end
					end

					EMIT_COLOR: begin
						token_data <= {
							emit_sample[15:13], emit_sample[8:0],
							count_m1_16(emit_color_count)
						};
						if (emit_remaining > 13'd16) begin
							emit_remaining <= emit_remaining - 13'd16;
							emit_state <= EMIT_REPEAT;
							token_eol <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol <= emit_eol;
						end
					end

					EMIT_REPEAT: begin
						token_data <= {3'd0, 2'b01,
							count_m1_2048(emit_remaining)};
						if (emit_remaining > 13'd2048) begin
							emit_remaining <= emit_remaining - 13'd2048;
							token_eol <= 1'b0;
						end else begin
							emit_state <= EMIT_IDLE;
							token_eol <= emit_eol;
						end
					end

					default: begin
						token_valid <= 1'b0;
						token_data <= 16'd0;
						token_eol <= 1'b0;
						emit_state <= EMIT_IDLE;
					end
				endcase
			end

			if (start_emit) begin
				emit_sample <= start_sample;
				emit_remaining <= start_count;
				emit_eol <= start_eol;
				emit_state <= (start_sample == 0) ?
					EMIT_BLACK : EMIT_COLOR;
			end

			if (start_prefetch)
				prefetch_valid <= 1'b0;
			if (run_fifo_pop) begin
				if (!start_fifo_head) begin
					prefetch_entry <= run_fifo_head;
					prefetch_valid <= 1'b1;
				end
				run_fifo_rd_ptr <= run_fifo_rd_ptr + 1'b1;
			end
			if (run_fifo_push) begin
				run_fifo[run_fifo_wr_ptr] <= pending_entry;
				run_fifo_wr_ptr <= run_fifo_wr_ptr + 1'b1;
			end
			case ({run_fifo_push, run_fifo_pop})
				2'b10: run_fifo_used <= run_fifo_used + 1'b1;
				2'b01: run_fifo_used <= run_fifo_used - 1'b1;
				default: run_fifo_used <= run_fifo_used;
			endcase

			if (run_fifo_push)
				pending_valid <= 1'b0;
			if (run_close_request) begin
				if (pending_ready) begin
					pending_entry <= completed_run;
					pending_valid <= 1'b1;
				end else begin
					overflow <= 1'b1;
				end
			end

			if (line_finishes_run && run_close_accept) begin
				run_valid <= 1'b0;
				run_count <= 13'd0;
			end

			if (input_valid) begin
				if (!run_valid) begin
					run_valid <= 1'b1;
					run_sample <= input_sample;
					run_count <= 13'd1;
				end else if (pixel_extends_run) begin
					run_count <= run_count + 1'b1;
				end else begin
					run_valid <= 1'b1;
					run_sample <= input_sample;
					run_count <= 13'd1;
				end
			end
		end
	end

endmodule
