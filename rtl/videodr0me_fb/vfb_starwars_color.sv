// ============================================================================
// Star Wars canonical pixel to RGB conversion.
// Written 2026 by Videodr0me
// ============================================================================

module vfb_starwars_color (
	input  logic [15:0] canonical_in,
	output logic [7:0]  red,
	output logic [7:0]  green,
	output logic [7:0]  blue
);

	localparam logic [7:0] OVERFLOW_MAIN_CEIL = 8'd232;
	localparam logic [8:0] OVERFLOW_SPILL_BASE = 9'd232;
	localparam logic [8:0] OVERFLOW_SPILL_CAP = 9'd64;

	wire [2:0] color = canonical_in[15:13];
	wire [8:0] intensity = canonical_in[8:0];
	wire [8:0] overflow_rest =
		intensity[8] ? (intensity - OVERFLOW_SPILL_BASE) : 9'd0;
	wire [8:0] spill_half_raw = overflow_rest >> 1;
	wire [7:0] spill_full =
		(overflow_rest > OVERFLOW_SPILL_CAP) ? 8'd64 : overflow_rest[7:0];
	wire [7:0] spill_half =
		(spill_half_raw > OVERFLOW_SPILL_CAP) ? 8'd64 : spill_half_raw[7:0];

	always_comb begin
		red = 8'd0;
		green = 8'd0;
		blue = 8'd0;

		if (!intensity[8]) begin
			red = color[2] ? intensity[7:0] : 8'd0;
			green = color[1] ? intensity[7:0] : 8'd0;
			blue = color[0] ? intensity[7:0] : 8'd0;
		end else begin
			unique case (color)
				3'b001: begin
					red = spill_half;
					green = spill_half;
					blue = OVERFLOW_MAIN_CEIL;
				end
				3'b010: begin
					red = spill_half;
					green = OVERFLOW_MAIN_CEIL;
					blue = spill_half;
				end
				3'b011: begin
					red = spill_full;
					green = OVERFLOW_MAIN_CEIL;
					blue = OVERFLOW_MAIN_CEIL;
				end
				3'b100: begin
					red = OVERFLOW_MAIN_CEIL;
					green = spill_half;
					blue = spill_half;
				end
				3'b101: begin
					red = OVERFLOW_MAIN_CEIL;
					green = spill_full;
					blue = OVERFLOW_MAIN_CEIL;
				end
				3'b110: begin
					red = OVERFLOW_MAIN_CEIL;
					green = OVERFLOW_MAIN_CEIL;
					blue = spill_full;
				end
				3'b111: begin
					red = 8'd255;
					green = 8'd255;
					blue = 8'd255;
				end
				default: begin
					red = 8'd0;
					green = 8'd0;
					blue = 8'd0;
				end
			endcase
		end
	end

endmodule
