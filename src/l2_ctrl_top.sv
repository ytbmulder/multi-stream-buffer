module l2_ctrl_top #
(
	parameter nstrms 			= 64,
	parameter nstrms_width		= $clog2(nstrms),
	parameter l2_ncl 			= 256,
	parameter l2_ncl_width 		= $clog2(l2_ncl),
	parameter l2_nstrms			= 16,
	parameter l2_nstrms_width	= $clog2(l2_nstrms),
	parameter TILES 			= nstrms/l2_nstrms
)
(
	input 								clk,
	input 								reset,

	// FUNCTIONAL STREAM RESET INPUT INTERFACE
	input 								i_rst_v,
	output 								i_rst_r,
	input  [nstrms_width-1:0]			i_rst_sid,
	// TODO: add input for specific address to reset.
	// TODO: change this to nstrms wide v and r signals since demuxing will be in level above this.

	// FUNCTIONAL STREAM RESET OUTPUT INTERFACE
	output [nstrms-1:0]					o_rst_v,
	input  [nstrms-1:0]					o_rst_r,

	// L1 REQUEST INTERFACE
	input  [nstrms-1:0]					i_rd_v,
	output [nstrms-1:0]					i_rd_r,

	// L2 URAM READ INTERFACE
	output [TILES-1:0]					o_addr_v,
	input  [TILES-1:0]					o_addr_r,
	output [TILES*l2_nstrms_width-1:0]	o_addr_sid,
	output [TILES*l2_ncl_width-1:0] 	o_addr_ptr,

	// OPENCAPI 3.0 REQUEST INTERFACE
	output 								o_req_v,
	input  								o_req_r,
	output [nstrms_width-1:0]			o_req_sid,

	// OPENCAPI 3.0 RESPONSE INTERFACE
	input  								i_rsp_v,
	output 								i_rsp_r,
	input  [nstrms_width-1:0]			i_rsp_sid
);

	wire s1_rst_v, s1_rst_r;
	wire [nstrms_width-1:0] s1_rst_sid;
	base_areg # (
		.lbl        (3'b000),
		.width      (nstrms_width)
	) is1_rst_reg (
		.clk        (clk),
		.reset      (reset),
		.i_v        (i_rst_v),
		.i_r        (i_rst_r),
		.i_d        (i_rst_sid),
		.o_v        (s1_rst_v),
		.o_r        (s1_rst_r),
		.o_d        (s1_rst_sid)
	);

	// TODO: move this demux to level above this module.
	// Demux rst interface.
	wire [nstrms-1:0] s1_rst_sid_dec, s1_rst_v_dec, s1_rst_r_dec;
	base_decode_le#(.enc_width(nstrms_width),.dec_width(nstrms)) is1_rst_sid_dec(.din(s1_rst_sid),.dout(s1_rst_sid_dec),.en(1'b1));
	base_ademux#(.ways(nstrms)) is1_rst_demux (.i_v(s1_rst_v),.i_r(s1_rst_r),.o_v(s1_rst_v_dec),.o_r(s1_rst_r_dec),.sel(s1_rst_sid_dec));

	// GENERATE --------------------------------------------------------------------------
	// Address merge signals.
	wire [nstrms-1:0] s1_addr_v, s1_addr_r;
	wire [nstrms*l2_ncl_width-1:0] s1_addr_ptr;

	wire [TILES*l2_ncl_width-1:0] s2_addr_ptr;
	wire [TILES*nstrms_width-1:0] s2_addr_sid;
	wire [TILES-1:0] s2_addr_v, s2_addr_r;

	// Request merge signals.
	wire [nstrms-1:0] s1_req_v, s1_req_r;

	wire [TILES-1:0] s2_req_v, s2_req_r;
	wire [TILES*l2_nstrms_width-1:0] s2_req_sid;

	// Demux response signals.
	wire [nstrms-1:0] s1_rsp_v, s1_rsp_r;

	genvar i;
	generate
		for(i=0; i<nstrms; i=i+1) begin : GEN_CONTROL
			l2_stream_ptr # (
				.l2_ncl			(l2_ncl)
				) is0_stream_control (
				.clk 			(clk),
				.reset 			(reset),
				.i_rst_v 		(s1_rst_v_dec[i]),
				.i_rst_r 		(s1_rst_r_dec[i]),
				.o_rst_v 		(o_rst_v[i]),
				.o_rst_r		(o_rst_r[i]),
				.i_rd_v 		(i_rd_v[i]),
				.i_rd_r 		(i_rd_r[i]),
				.o_addr_v 		(s1_addr_v[i]),
				.o_addr_r 		(s1_addr_r[i]),
				.o_addr_ptr 	(s1_addr_ptr[(i+1)*l2_ncl_width-1:i*l2_ncl_width]),
				.o_req_v 		(s1_req_v[i]),
				.o_req_r 		(s1_req_r[i]),
				.i_rsp_v 		(s1_rsp_v[i]),
				.i_rsp_r 		(s1_rsp_r[i])
			);
		end
	endgenerate

	genvar j;
	generate
		for(j=0; j<TILES; j=j+1) begin : GEN_MERGE
			localparam  RRWAYS = 4;     // 4 inputs per RR MUX.
			l2_merge # (
				.WAYS	  	(l2_nstrms),
				.RRWAYS 	(RRWAYS),
				.WIDTH 		(l2_ncl_width)
				) is1_addr_merge (
				.clk        (clk),
				.reset      (reset),
				.i_v		(s1_addr_v[(j+1)*l2_nstrms-1:j*l2_nstrms]),
				.i_r  		(s1_addr_r[(j+1)*l2_nstrms-1:j*l2_nstrms]),
				.i_d 		(s1_addr_ptr[(j+1)*l2_nstrms*l2_ncl_width-1:j*l2_nstrms*l2_ncl_width]),
				.o_v        (s2_addr_v[j]),
				.o_r        (s2_addr_r[j]),
				.o_d		(s2_addr_ptr[(j+1)*l2_ncl_width-1:j*l2_ncl_width]),
				.o_sel		(s2_addr_sid[(j+1)*l2_nstrms_width-1:j*l2_nstrms_width])
			);

			// Merge requests for OpenCAPI 3.0.
			l2_merge # (
				.WAYS	  	(l2_nstrms),
				.RRWAYS 	(RRWAYS),
				.WIDTH 		(1)
				) is1_req_merge (
				.clk        (clk),
				.reset      (reset),
				.i_v		(s1_req_v[(j+1)*l2_nstrms-1:j*l2_nstrms]),
				.i_r  		(s1_req_r[(j+1)*l2_nstrms-1:j*l2_nstrms]),
				.i_d 		(), // not used
				.o_v        (s2_req_v[j]),
				.o_r        (s2_req_r[j]),
				.o_d		(), // not used
				.o_sel		(s2_req_sid[(j+1)*l2_nstrms_width-1:j*l2_nstrms_width])
			);
		end
	endgenerate

	// URAM read address assign.
	assign o_addr_v = s2_addr_v;
	assign s2_addr_r = o_addr_r;
	assign o_addr_sid = s2_addr_sid;
	assign o_addr_ptr = s2_addr_ptr;

	// Final request merge.
	wire [l2_nstrms_width-1:0] s2_req_sid_winner;
	wire [TILES-1:0] s2_req_sid_tile;
	wire [$clog2(TILES)-1:0] s2_req_sid_tile_enc;
	base_arr_mux # (
		.ways	(TILES),
		.width	(l2_nstrms_width)
	) is0_l2_final_merge (
		.clk	(clk),
		.reset	(reset),
		.i_v	(s2_req_v),
		.i_r	(s2_req_r),
		.i_d	(s2_req_sid),
		.o_v	(o_req_v),
		.o_r	(o_req_r),
		.o_d	(s2_req_sid_winner),
		.o_sel	(s2_req_sid_tile)
	);
	base_encode_le # (
		.dec_width (TILES),
		.enc_width ($clog2(TILES))
	) is0_gen_enc (
		.i_d (s2_req_sid_tile),
		.o_d (s2_req_sid_tile_enc),
		.o_v ()
	);

	assign o_req_sid = {s2_req_sid_tile_enc, s2_req_sid_winner};

	// Response demux logic.
	wire [nstrms-1:0] s1_rsp_sid_dec;
	base_decode_le#(.enc_width(nstrms_width),.dec_width(nstrms)) is1_rsp_dec (
		.din        (i_rsp_sid),
		.dout       (s1_rsp_sid_dec),
		.en         (1'b1)
	);
	base_ademux # (
		.ways(nstrms)
	) is1_rsp_demux (
		.i_v(i_rsp_v),
		.i_r(i_rsp_r),
		.o_v(s1_rsp_v),
		.o_r(s1_rsp_r),
		.sel(s1_rsp_sid_dec)
	);

	assign i_rsp_r = 1'b1;

	// TODO: build queue after merge for OpenCAPI.

endmodule
