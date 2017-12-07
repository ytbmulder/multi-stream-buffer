module l1_rd_port #
(
  parameter nstrms                  = 64,
  parameter nstrms_width            = $clog2(nstrms),
  parameter nports                  = 8,
  parameter portid                  = 0,
  parameter ptr_width               = 1,
  parameter cl_size                 = 8, // number of reads per cacheline - must be at least as big as the number of read ports
  parameter clofs_width             = $clog2(cl_size)
)
(
  input                             clk,
  input                             reset,

  //
  input  [nstrms-1:0]               i_rst_end, // L2 signals stream has ended when high.
  input  [nstrms-1:0]               i_l1_end, // L1 signals stream has ended when high.
  input  [nstrms-1:0]               i_single_v, // L1 signals there is only one valid cache line when high.

  // input - which stream id is requested.
  input                             i_rd_v,
  output                            i_rd_r,
  input  [nstrms_width-1:0]         i_rd_sid,

  // input - array of sid for each read port.
  input  [nports-1:0]               i_rd_acts,
  input  [nports*nstrms_width-1:0]  i_rd_sids,
  output                            o_rd_act, // Is this read port servicing a L1 read request?

  // input - array with the current pointer of each stream.
  input  [nstrms*ptr_width-1:0]     i_ptrs,

  // output - calculated addr for this particular read port to interface with L1 BRAM.
  output                            o_addr_v,
  input                             o_addr_r,
  output [ptr_width-1:0]            o_addr_ptr,
  output [nstrms_width-1:0]         o_addr_sid,

  // output - which stream id is used for this read port? that signal is valid (one-hot). Used for transpose in l1_ctrl_top module.
  output [nstrms-1:0]               o_req_v, // Global pointer update vector.
  input  [nstrms-1:0]               o_req_r
);

  // INPUT READ REGISTER
  wire s1_v, s1_r;
  wire [nstrms_width-1:0] s1_sid;
  base_areg # (
    .lbl(3'b110),
    .width(nstrms_width)
  ) is1_lat (
    .clk(clk),.reset(reset),
    .i_v(i_rd_v),
    .i_r(i_rd_r),
    .i_d(i_rd_sid),
    .o_v(s1_v),
    .o_r(s1_r),
    .o_d(s1_sid)
  );

  // Is this read port servicing a L1 read request?
  assign o_rd_act = s1_v & s1_r;

  // Make sure rd_ports does not end up in a deadlock by invalidating reqs in this module.
  // Reqs are invalidated by not asserting the input valid signal of the acombine module.
  // This ensures that both o_req_v and o_addr_v will not be asserted.
  // The input valid of the acombine module is invalidated in the following cases:
  // - If the L1 stream (which implies also L2) has ended and therefore has no valid data anymore. This is done using the invalidate_rd and i_l1_end signals.
  // - If during a single cycle multiple reqs are made for the same stream, but after a subset of the reqs the stream ends and has no more valid data.
  // Implication of this approach is that if the AFU makes a req, but the req is invalidated, there is no way of knowing in the current implementation (solution could be to assert the output valid signal and have a second signal which indicates that the req was discarded. This can be done because the reads by the AFU and the data returned by L1 are quarnteed to be in-order. Another solution could be to associate an id with each AFU read. Then the id can be returned immediately to the AFU with a signal indicating the read was discarded. This makes the read port out-of-order. At least with respect to discards. Full out-of-order is also interesting to mention, especially to see what the performance gain would be.), it is just discarded.
  // In the case that not all reqs in the same cycle are invalidated, the AFU couldn't have known that the stream has ended because the vlat has to be updated. In the other case that a req is invalidated, that is when the L1 stream has ended, this is apparent to the AFU since the appropriate end of stream signal in l1_ctrl_top is asserted (since it is driven by a vlat and therefore stays asserted).
  // TODO: add discarded output signal (o_addr_discard) per read port and assert output address valid in that case.
  // TODO: BRAM we = ~o_addr_discard & o_addr_v and send _discard as aux data as well in latch_oe module since it is presented to the AFU. AFU interface: valid, ready, data and discard.
  wire s1_rd_v = s1_v & ~invalidate_rd;
  wire s1_rd_v_test = out_of_bounds_rd_port ? 1'b0 : s1_rd_v;

  // Synchronize the control between the calculated L1 address and the update vector for the L1 stream controllers.
  wire [1:0] s1a_v, s1a_r; // 0: global pointer update vector, 1: L1 address
  base_acombine#(.ni(1),.no(2)) is1a_cmb(.i_v(s1_rd_v_test),.i_r(s1_r),.o_v(s1a_v),.o_r(s1a_r));

  // GLOBAL POINTER UPDATE VECTOR
  // demux valid and ready signals of flow[0] based on the stream id.
  wire [nstrms-1:0] s1_sid_dec;
  base_decode_le # (.enc_width(nstrms_width),.dec_width(nstrms)) is1_sid_dec (
    .din(s1_sid),.dout(s1_sid_dec),.en(1'b1)); // decodes the input stream id from a read port.
  wire [nstrms-1:0] s1_req_v;
  base_ademux # (.ways(nstrms)) is1_demux (
    .i_v(s1a_v[0]),.i_r(s1a_r[0]),.o_v(o_req_v),.o_r(o_req_r),.sel(s1_sid_dec));

  // L1 ADDRESS CALCULATION
  // select the current pointer for this stream based on the stream id.
  wire [ptr_width-1:0] s1_ptr;
  base_emux_le # (.ways(nstrms),.width(ptr_width)) is1_ptr_mux (
    .din(i_ptrs),       // array with all current (not updated) pointers.
    .dout(s1_ptr),      // current (not updated) pointer for stream s1_sid.
    .sel(s1_sid)
  );

  // Generate which stream ids to compare for a particular read port.
  genvar i;
  generate
    if (portid>0) begin : GEN_ADDR_PTR
      localparam inc_width = $clog2(portid+1);
      wire [portid-1:0] s1_hit;

      for(i=0; i<portid; i=i+1) begin : GEN_HIT
        assign s1_hit[i] = i_rd_acts[i] & (s1_sid == i_rd_sids[(i+1)*nstrms_width-1:i*nstrms_width]); // compare stream id for this read port to stream id from the previous read ports.
      end

      wire [inc_width-1:0] s1_ptr_inc;
      base_cenc#(.enc_width(inc_width),.dec_width(portid)) is1_inc_dec(.din(s1_hit),.dout(s1_ptr_inc)); // count number of '1's in s1_hit array.
      assign o_addr_ptr = o_rd_act ? s1_ptr + s1_ptr_inc : {ptr_width{1'b0}}; // use if statement to save power
    end
    else if (portid==0) begin
      assign o_addr_ptr = o_rd_act ? s1_ptr : {ptr_width{1'b0}}; // use if statement to save power
    end
  endgenerate

  assign o_addr_sid = s1_sid;
  //assign o_addr_sid = o_rd_act ? i_rd_sid : {nstrms_width{1'b0}}; // TODO: add condition to either output i_rd_sid or zero. Also for o_addr_ptr.
  assign o_addr_v = s1a_v[1];
  assign s1a_r[1] = o_addr_r;

  // not valid L1 read (out of bounds) when L2 stream has ended & when reading last valid line (thus L1 has not yet ended) & when we carry and thus want to read the next valid line which doesnt exist.
  // TODO: use emux_le module for i_rst_end[] and i_single_v
  wire out_of_bounds_rd_port = i_rst_end[s1_sid] & i_single_v[s1_sid] & o_addr_ptr[clofs_width];

  // invalidate input reads when the requested L1 stream has ended.
  wire invalidate_rd = i_l1_end[s1_sid];

endmodule // l1_rd_port
