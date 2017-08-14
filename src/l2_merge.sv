// TODO: not very fair Round-Robin MUX. To make it more fair, make the final merge Round-Robin MUX update its pointer after it has serviced four requests. So after it has serviced four requests from one of the first level Round-Robin MUXs, continue to the next first level MUX.
// TODO: write a fully generic multi-cycle Round-Robin MUX. Constraint is power of 2 for number of inputs and amount of inputs per MUX.
// TODO: another option is that each stream supplies its request and/or valid count and based on that, the MUX should have a priority which stream to service first. So if one stream has nearly no valid cache lines, you might want to fetch those sooner from opencapi. but if all have similar amount of valid lines but one stream has a lot of outstanding requests, that one should be serviced first.
// TODO: rename this module to something with arr_mux_mc (mc = multi cycle)

module l2_merge #
(
	parameter WAYS	 	= 16, // number of streams
	parameter WIDTH		= 1, // input data width
	parameter RRWAYS 	= 4, // number of Round-Robin ways per MUX
	parameter NMUX		= WAYS/RRWAYS // number of RRWAYS input Round-Robin MUXs
)
(
	// Global signals.
	input 						clk,
	input 						reset,

	// Input data is 16 streams of request valid signals.
	input  	[WAYS-1:0] 		i_v,
	output 	[WAYS-1:0] 		i_r,
	input   [WAYS*WIDTH-1:0]	i_d,

	// Output ready, valid and data. Data is stream number between 0 and 15.
	output 						o_v,
	input 						o_r,
	output 		[WIDTH-1:0]		o_d,
	output 	[$clog2(WAYS)-1:0] o_sel
);

	// Signal declarations.
	// Use base_areg in the future.
   wire [WAYS-1:0] 				s0_clreq_v = i_v;
   wire [WAYS-1:0]      			s0_clreq_r;
   assign i_r = s0_clreq_r;
   wire [WAYS*WIDTH-1:0]			s0_d = i_d;

/*
	// Input configurable register.
	base_areg # (
		.width			(),
		.lbl			(0),
		.reset_ready 	(0)
	) is0_input_reg (
		.clk	(clk),
		.reset	(reset),
		.i_v	(),
		.i_r	(),
		.i_d	(),
		.o_v	(),
		.o_r	(),
		.o_d	(),
	);
*/

	// Round-Robin MUX to merge 16 stream requests into one queue.
	// Structure consists of two stages with a configurable register between the stages.
	wire [NMUX-1:0] 				s0_gen_v;
	wire [NMUX-1:0] 				s0_gen_r;
	wire [NMUX*WIDTH-1:0]			s0_gen_d;
	wire [NMUX*RRWAYS-1:0] 			s0_gen_sel_dec;
	wire [NMUX*$clog2(RRWAYS)-1:0] 	s0_gen_sel_enc;

	wire [NMUX-1:0] 				s1_gen_v;
	wire [NMUX-1:0] 				s1_gen_r;
	wire [NMUX*WIDTH-1:0]			s1_gen_d;
	wire [NMUX*$clog2(RRWAYS)-1:0] 	s1_gen_sel_enc;

	wire [NMUX*($clog2(RRWAYS)+WIDTH)-1:0] s1_output;

	genvar i;
	generate
		for(i = 0; i<NMUX; i=i+1) begin : GEN_S0_RRMUX
 		    wire [RRWAYS-1:0]		   	s0_gen_sel_dec;
  		    wire [$clog2(RRWAYS)-1:0] 	s0_gen_sel_enc;

			base_arr_mux # (
				.ways	(RRWAYS),
				.width	(WIDTH)
			) is0_l2_req (
				.clk	(clk),
				.reset	(reset),
				.i_v	(s0_clreq_v[(i+1)*RRWAYS-1:i*RRWAYS]),
				.i_r	(s0_clreq_r[(i+1)*RRWAYS-1:i*RRWAYS]),
				.i_d	(s0_d[(i+1)*RRWAYS*WIDTH-1:i*RRWAYS*WIDTH]),
				.o_v	(s0_gen_v[i]),
				.o_r	(s0_gen_r[i]),
				.o_d	(s0_gen_d[(i+1)*WIDTH-1:i*WIDTH]),
				.o_sel	(s0_gen_sel_dec) // used as data input for the final merge RR MUX.
			);

			// Encode the select signals.
			base_encode_le # (
				.dec_width (RRWAYS),
				.enc_width ($clog2(RRWAYS))
			) is0_gen_enc (
				.i_d (s0_gen_sel_dec),
				.o_d (s0_gen_sel_enc),
				.o_v () //TODO: what is this used for?
			);

			// Configurable registers between the two stages.
			base_areg # (
				.width			(WIDTH+$clog2(RRWAYS)),
				.lbl			(3'b110)
			) is0_input_reg (
				.clk	(clk),
				.reset	(reset),
				.i_v	(s0_gen_v[i]),
				.i_r	(s0_gen_r[i]),
				.i_d	({s0_gen_d[(i+1)*WIDTH-1:i*WIDTH], s0_gen_sel_enc}),
				.o_v	(s1_gen_v[i]),
				.o_r	(s1_gen_r[i]),
				//.o_d	({s1_gen_d[(i+1)*WIDTH-1:i*WIDTH], s1_gen_sel_enc[(i+1)*$clog2(RRWAYS)-1:i*$clog2(RRWAYS)]})
				.o_d	(s1_output[(i+1)*($clog2(RRWAYS)+WIDTH)-1:i*($clog2(RRWAYS)+WIDTH)])
			);
		end
	endgenerate

	// Final merge.
	wire [WIDTH+$clog2(RRWAYS)-1:0] 	s1_merge_data; //s1_winner
	wire [RRWAYS-1:0] 			s1_sel_dec;
	wire [$clog2(RRWAYS)-1:0] 	s1_sel_enc;

	base_arr_mux # (
		.ways	(RRWAYS),
		.width	(WIDTH+$clog2(RRWAYS))
	) is0_l2_req (
		.clk	(clk),
		.reset	(reset),
		.i_v	(s1_gen_v),
		.i_r	(s1_gen_r),
		.i_d 	(s1_output),
		//.i_d	({s1_gen_d[NMUX*WIDTH-1:0], s1_gen_sel_enc[NMUX*$clog2(RRWAYS)-1:0]}),
		.o_v	(o_v),
		.o_r	(o_r),
		.o_d	(s1_merge_data),
		.o_sel	(s1_sel_dec)
	);

	// Encode the final select signal.
	base_encode_le # (
		.dec_width (RRWAYS),
		.enc_width ($clog2(RRWAYS))
	) is0_gen_enc (
		.i_d (s1_sel_dec[RRWAYS-1:0]),
		.o_d (s1_sel_enc),
		.o_v ()
	);

	assign o_d = s1_merge_data[$clog2(RRWAYS)+WIDTH-1:$clog2(RRWAYS)];
	assign o_sel = {s1_sel_enc, s1_merge_data[$clog2(RRWAYS)-1:0]}; // concatenate to obtain stream_id to be requested.

endmodule // l2_merge
