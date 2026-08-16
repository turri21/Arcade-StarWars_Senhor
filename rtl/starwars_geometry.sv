//============================================================================
//  Star Wars vector geometry
//
//  Written 2026 by Videodr0me
//============================================================================

module starwars_geometry
(
	input  logic signed [13:0] source_x,
	input  logic signed [13:0] source_y,
	input  logic               mode_1080p,
	input  logic               mode_480p,
	input  logic               mode_240p,
	input  logic        [11:0] center_x,
	input  logic        [11:0] center_y,
	input  logic        [11:0] render_width,
	input  logic        [11:0] render_height,
	input  logic         [2:0] orientation,
	input  logic               zoom_wide,
	output logic        [10:0] raster_x,
	output logic        [10:0] raster_y,
	output logic               beam_in_bounds
);

	logic signed [22:0] source_x_ext;
	logic signed [22:0] source_y_ext;
	logic signed [22:0] normal_x_ext;
	logic signed [22:0] normal_y_ext;
	logic signed [22:0] quarter_x_ext;
	logic signed [22:0] quarter_y_ext;
	logic signed [22:0] selected_x_ext;
	logic signed [22:0] selected_y_ext;
	logic signed [22:0] zoom_x_ext;
	logic signed [22:0] zoom_y_ext;
	logic signed [11:0] scaled_x;
	logic signed [11:0] scaled_y;
	logic signed [11:0] oriented_x;
	logic signed [11:0] oriented_y;
	logic signed [11:0] anchor_x;
	logic signed [11:0] anchor_y;
	logic signed [11:0] presented_x;
	logic signed [11:0] presented_y;
	logic        [11:0] visible_width;
	logic               quarter_turn;

	always_comb begin
		source_x_ext = {{9{source_x[13]}}, source_x};
		source_y_ext = {{9{source_y[13]}}, source_y};
		quarter_turn = (orientation == 3'd1) ||
		               (orientation == 3'd3) ||
		               (orientation == 3'd6) ||
		               (orientation == 3'd7);

		if (mode_1080p) begin
			// X 21/128, Y 29/256.
			normal_x_ext = ((source_x_ext << 4) + (source_x_ext << 2) + source_x_ext) >>> 7;
			normal_y_ext = ((source_y_ext << 5) - (source_y_ext << 1) - source_y_ext) >>> 8;
			// Quarter turn: X 197/2048, Y 143/1024.
			quarter_x_ext = ((source_y_ext << 7) + (source_y_ext << 6) +
			                 (source_y_ext << 2) + source_y_ext) >>> 11;
			quarter_y_ext = ((source_x_ext << 7) + (source_x_ext << 4) -
			                 source_x_ext) >>> 10;
		end else if (mode_240p) begin
			// X 369/4096, Y 27/1024.
			normal_x_ext = ((source_x_ext << 8) + (source_x_ext << 6) +
			                (source_x_ext << 5) + (source_x_ext << 4) +
			                source_x_ext) >>> 12;
			normal_y_ext = ((source_y_ext << 4) + (source_y_ext << 3) +
			                (source_y_ext << 1) + source_y_ext) >>> 10;
			// Quarter turn: X 47/1024, Y 63/2048.
			quarter_x_ext = ((source_y_ext << 5) + (source_y_ext << 4) -
			                 source_y_ext) >>> 10;
			quarter_y_ext = ((source_x_ext << 6) - source_x_ext) >>> 11;
		end else if (mode_480p) begin
			// X 369/4096, Y 27/512.
			normal_x_ext = ((source_x_ext << 8) + (source_x_ext << 6) +
			                (source_x_ext << 5) + (source_x_ext << 4) +
			                source_x_ext) >>> 12;
			normal_y_ext = ((source_y_ext << 4) + (source_y_ext << 3) +
			                (source_y_ext << 1) + source_y_ext) >>> 9;
			// Quarter turn: X 47/1024, Y 127/2048.
			quarter_x_ext = ((source_y_ext << 5) + (source_y_ext << 4) -
			                 source_y_ext) >>> 10;
			quarter_y_ext = ((source_x_ext << 7) - source_x_ext) >>> 11;
		end else begin
			// X 7/64, Y 19/256.
			normal_x_ext = ((source_x_ext << 3) - source_x_ext) >>> 6;
			normal_y_ext = ((source_y_ext << 4) + (source_y_ext << 2) - source_y_ext) >>> 8;
			// Quarter turn: X 259/4096, Y 191/2048.
			quarter_x_ext = ((source_y_ext << 8) + (source_y_ext << 1) +
			                 source_y_ext) >>> 12;
			quarter_y_ext = ((source_x_ext << 7) + (source_x_ext << 6) -
			                 source_x_ext) >>> 11;
		end

		selected_x_ext = quarter_turn ? quarter_x_ext : normal_x_ext;
		selected_y_ext = quarter_turn ? quarter_y_ext : normal_y_ext;

		if (zoom_wide && (mode_480p || mode_240p)) begin
			if (quarter_turn) begin
				// Quarter turns use a 27/32 view.
				zoom_x_ext = ((selected_x_ext << 5) - (selected_x_ext << 2) - selected_x_ext) >>> 5;
				zoom_y_ext = ((selected_y_ext << 5) - (selected_y_ext << 2) - selected_y_ext) >>> 5;
			end else begin
				// Normal orientation uses 53/64 so the ESB counter remains complete.
				zoom_x_ext = ((selected_x_ext << 5) + (selected_x_ext << 4) +
				              (selected_x_ext << 2) + selected_x_ext) >>> 6;
				zoom_y_ext = ((selected_y_ext << 5) + (selected_y_ext << 4) +
				              (selected_y_ext << 2) + selected_y_ext) >>> 6;
			end
		end else begin
			zoom_x_ext = zoom_wide ?
				((selected_x_ext << 3) - selected_x_ext) >>> 3 : selected_x_ext;
			zoom_y_ext = zoom_wide ?
				((selected_y_ext << 3) - selected_y_ext) >>> 3 : selected_y_ext;
		end
		scaled_x = zoom_x_ext[11:0];
		scaled_y = zoom_y_ext[11:0];

		visible_width = mode_1080p ? 12'd1470 : render_width;
		case (orientation)
			3'd0: begin
				oriented_x = scaled_x;
				oriented_y = -scaled_y;
				anchor_x = $signed(center_x);
				anchor_y = $signed(center_y) - 12'sd1;
			end
			3'd1: begin
				oriented_x = scaled_x;
				oriented_y = scaled_y;
				anchor_x = $signed({1'b0, visible_width[11:1]});
				anchor_y = $signed({1'b0, render_height[11:1]});
			end
			3'd2: begin
				oriented_x = -scaled_x;
				oriented_y = scaled_y;
				anchor_x = $signed(visible_width) - $signed(center_x) - 12'sd1;
				anchor_y = $signed(render_height) - $signed(center_y);
			end
			3'd3: begin
				oriented_x = -scaled_x;
				oriented_y = -scaled_y;
				anchor_x = $signed({1'b0, visible_width[11:1]}) - 12'sd1;
				anchor_y = $signed({1'b0, render_height[11:1]}) - 12'sd1;
			end
			3'd4: begin
				oriented_x = -scaled_x;
				oriented_y = -scaled_y;
				anchor_x = $signed(visible_width) - $signed(center_x) - 12'sd1;
				anchor_y = $signed(center_y) - 12'sd1;
			end
			3'd5: begin
				oriented_x = scaled_x;
				oriented_y = scaled_y;
				anchor_x = $signed(center_x);
				anchor_y = $signed(render_height) - $signed(center_y);
			end
			3'd6: begin
				oriented_x = scaled_x;
				oriented_y = -scaled_y;
				anchor_x = $signed({1'b0, visible_width[11:1]});
				anchor_y = $signed({1'b0, render_height[11:1]}) - 12'sd1;
			end
			default: begin
				oriented_x = -scaled_x;
				oriented_y = scaled_y;
				anchor_x = $signed({1'b0, visible_width[11:1]}) - 12'sd1;
				anchor_y = $signed({1'b0, render_height[11:1]});
			end
		endcase

		presented_x = anchor_x + oriented_x;
		presented_y = anchor_y + oriented_y;
		raster_x = presented_x[10:0];
		raster_y = presented_y[10:0];
		beam_in_bounds =
			($unsigned(presented_x) < visible_width) &&
			($unsigned(presented_y) < render_height);
	end

endmodule
