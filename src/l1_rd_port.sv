module l1_rd_port #
(
  parameter nstrms                  = 64,
  parameter nstrms_width            = $clog2(nstrms),
  parameter nports                  = 8,
  parameter portid                  = 0,
  parameter ptr_width               = 1
)
(
  input                             clk,
  input                             reset,

  // input - which stream id is requested.
  input                             i_rd_v,
  output                            i_rd_r,
  input  [nstrms_width-1:0]         i_rd_sid,

  // input - array of sid for each read port.
  input  [nports-1:0]               i_rd_acts,
  input  [nports*nstrms_width-1:0]  i_rd_sids,
  output                            o_rd_act,

  // input - array with the current pointer of each stream.
  input  [nstrms*ptr_width-1:0]     i_ptrs,

  // output - calculated addr for this particular read port to interface with L1 BRAM.
  output                            o_addr_v,
  input                             o_addr_r,
  output [ptr_width-1:0]            o_addr_ptr,
  output [nstrms_width-1:0]         o_addr_sid,

  // output - which stream id is used for this read port? that signal is valid (one-hot). Used for transpose in l1_ctrl_top module.
  output [nstrms-1:0]               o_req_v,
  input  [nstrms-1:0]               o_req_r
);

  // Is this rd port servicing a L1 read request?
  assign o_rd_act = i_rd_v & i_rd_r;

  // split the control into two streams (sync inputs and outputs of this module)
  wire [1:0] s1a_v, s1a_r; // 0: to demux, 1: to output
  base_acombine#(.ni(1),.no(2)) is1a_cmb(.i_v(i_rd_v),.i_r(i_rd_r),.o_v(s1a_v),.o_r(s1a_r));

  // demux valid and ready signals of flow[0] based on the stream id.
  wire [nstrms-1:0] s1_sid_dec;
  base_decode_le#(.enc_width(nstrms_width),.dec_width(nstrms)) is1_sid_dec(.din(i_rd_sid),.dout(s1_sid_dec),.en(1'b1)); // decodes the input stream id from a read port.
  base_ademux#(.ways(nstrms)) is1_demux(.i_v(s1a_v[0]),.i_r(s1a_r[0]),.o_v(o_req_v),.o_r(o_req_r),.sel(s1_sid_dec));

  // select the current pointer for this stream based on the stream id.
  wire [ptr_width-1:0] s1_ptr;
  base_emux_le # (.ways(nstrms),.width(ptr_width)) is1_ptr_mux (
    .din(i_ptrs),       // array with all current (not updated) pointers.
    .dout(s1_ptr),      // current (not updated) pointer for stream s1_sid.
    .sel(i_rd_sid)
  );

  // Generate which stream ids to compare for a particular read port.
  genvar i;
  generate
    if (portid>0) begin : GEN_ADDR_PTR
      localparam inc_width = $clog2(portid+1);
      wire [portid-1:0] s1_hit;

      for(i=0; i<portid; i=i+1) begin : GEN_HIT
        assign s1_hit[i] = i_rd_acts[i] & (i_rd_sid == i_rd_sids[(i+1)*nstrms_width-1:i*nstrms_width]); // compare stream id for this read port to stream id from the previous read ports.
      end

      wire [inc_width-1:0] s1_ptr_inc;
      base_cenc#(.enc_width(inc_width),.dec_width(portid)) is1_inc_dec(.din(s1_hit),.dout(s1_ptr_inc)); // counter number of '1's in s1_hit array.
      assign o_addr_ptr = i_rd_acts[portid] ? s1_ptr + s1_ptr_inc : {ptr_width{1'b0}}; // use if statement to save power
    end
    else begin
      assign o_addr_ptr = i_rd_acts[portid] ? s1_ptr : {ptr_width{1'b0}}; // use if statement to save power
    end
    // else: !if(portid>0) TODO: print error or terminate compilation?
  endgenerate

  assign o_addr_sid = i_rd_sid;
  assign o_addr_v = s1a_v[1];
  assign s1a_r[1] = o_addr_r;

endmodule // l1_rd_port
