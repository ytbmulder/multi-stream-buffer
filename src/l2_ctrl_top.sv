// TODO: build queue after merge for OpenCAPI.
// TODO: move is1_rst_reg and is1_rd_reg into l2_stream_ptr module.

module l2_ctrl_top #
(
  // Host parameters
  parameter addr_width                  = 64,                 // Host address width in bits.
  parameter cache_line                  = 128,                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line),

  // L1 parameters
  parameter l1_ncl                      = 16,                 // Number of cache lines per stream in L1.
  parameter clid_width                  = $clog2(l1_ncl),

  // Stream cache parameters
  parameter nstrms                      = 64,
  parameter nstrms_width                = $clog2(nstrms),
  parameter l2_nstrms                   = 16,
  parameter l2_nstrms_width             = $clog2(l2_nstrms),
  parameter l2_ncl                      = 256,                // Number of cache lines per stream in L2.
  parameter l2_ncl_width                = $clog2(l2_ncl),
  parameter channels                    = nstrms/l2_nstrms
)
(
  input                                 clk,
  input                                 reset,

  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  input  [nstrms-1:0]                   i_rst_v,
  output [nstrms-1:0]                   i_rst_r,
  input  [addr_width-1:0]               i_rst_ea_b,
  input  [addr_width-1:0]               i_rst_ea_e,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output [nstrms-1:0]                   o_rst_v,
  input  [nstrms-1:0]                   o_rst_r,
  output [nstrms*clid_width-1:0]        o_rst_ea_b,
  output [nstrms-1:0]                   o_rst_end,

  // L1 REQUEST INTERFACE
  input  [nstrms-1:0]                   i_rd_v,
  output [nstrms-1:0]                   i_rd_r,

  // L2 URAM READ INTERFACE
  output [channels-1:0]                 o_addr_v,
  input  [channels-1:0]                 o_addr_r,
  output [channels*l2_nstrms_width-1:0] o_addr_sid,
  output [channels*l2_ncl_width-1:0]    o_addr_ptr,

  // HOST REQUEST INTERFACE
  output                                o_req_v,
  input                                 o_req_r,
  output [nstrms_width-1:0]             o_req_sid,
  output [addr_width-1:0]               o_req_ea,

  // HOST RESPONSE INTERFACE
  input                                 i_rsp_v,
  output                                i_rsp_r,
  input  [nstrms_width-1:0]             i_rsp_sid
);

  // FUNCTIONAL STREAM RESET INTERFACE
  // Use reduction OR to have only one i_rst_ea register instead of nstreams.
  wire s0_rst_ea_v = | i_rst_v;
  wire [addr_width-1:0] s0_rst_ea_b, s0_rst_ea_e;
  base_areg # (.lbl(3'b110),.width(2*addr_width)) is1_rstea_reg (
    .clk    (clk),
    .reset  (reset),
    .i_v    (s0_rst_ea_v),
    .i_r    (),
    .i_d    ({i_rst_ea_b, i_rst_ea_e}),
    .o_v    (),
    .o_r    (1'b1), // this module is always ready to accept new data.
    .o_d    ({s0_rst_ea_b, s0_rst_ea_e})
  );

  // Address merge signals.
  wire [nstrms-1:0] s1_addr_v, s1_addr_r;
  wire [nstrms*l2_ncl_width-1:0] s1_addr_ptr;

  wire [channels*l2_ncl_width-1:0] s2_addr_ptr;
  wire [channels*nstrms_width-1:0] s2_addr_sid;
  wire [channels-1:0] s2_addr_v, s2_addr_r;

  // Request merge signals.
  wire [nstrms-1:0] s1_req_v, s1_req_r;
  wire [nstrms*addr_width-1:0] s1_req_ea;

  wire [channels-1:0] s3_req_v, s3_req_r;

  // Demux response signals.
  wire [nstrms-1:0] s1_rsp_v, s1_rsp_r;

  wire [channels*(addr_width+l2_nstrms_width)-1:0] s3_req_channels;

  genvar i;
  generate
    for(i=0; i<nstrms; i=i+1) begin : GEN_PTR
      // Functional reset input register.
      wire s1_rst_v, s1_rst_r;
      base_areg # (.lbl(3'b110),.width(1)) is1_rst_reg (
        .clk    (clk),
        .reset  (reset),
        .i_v    (i_rst_v[i]),
        .i_r    (i_rst_r[i]),
        .i_d    (1'b0), // not used
        .o_v    (s1_rst_v),
        .o_r    (s1_rst_r),
        .o_d    () // not used
      );

      // Read request input register.
      wire s1_rd_v, s1_rd_r;
      base_areg # (.lbl(3'b110),.width(1)) is1_rd_reg (
        .clk    (clk),
        .reset  (reset),
        .i_v    (i_rd_v[i]),
        .i_r    (i_rd_r[i]),
        .i_d    (1'b0), // not used
        .o_v    (s1_rd_v),
        .o_r    (s1_rd_r),
        .o_d    () // not used
      );

      l2_stream_ptr # (
        .addr_width (addr_width),
        .cache_line (cache_line),
        .l1_ncl     (l1_ncl),
        .l2_ncl     (l2_ncl)
        ) is0_stream_control (
        .clk        (clk),
        .reset      (reset),
        .i_rst_v    (s1_rst_v),
        .i_rst_r    (s1_rst_r),
        .i_rst_ea_b (s0_rst_ea_b),
        .i_rst_ea_e (s0_rst_ea_e),
        .o_rst_v    (o_rst_v[i]),
        .o_rst_r    (o_rst_r[i]),
        .o_rst_ea_b (o_rst_ea_b[(i+1)*clid_width-1:i*clid_width]),
        .o_rst_end  (o_rst_end[i]),
        .i_rd_v     (s1_rd_v),
        .i_rd_r     (s1_rd_r),
        .o_addr_v   (s1_addr_v[i]),
        .o_addr_r   (s1_addr_r[i]),
        .o_addr_ptr (s1_addr_ptr[(i+1)*l2_ncl_width-1:i*l2_ncl_width]),
        .o_req_v    (s1_req_v[i]),
        .o_req_r    (s1_req_r[i]),
        .o_req_ea   (s1_req_ea[(i+1)*addr_width-1:i*addr_width]),
        .i_rsp_v    (s1_rsp_v[i]),
        .i_rsp_r    (s1_rsp_r[i])
      );
    end
  endgenerate

  genvar j;
  generate
    for(j=0; j<channels; j=j+1) begin : GEN_MERGE
      localparam RRWAYS = 4; // 4 inputs per RR MUX.
      l2_merge # (
        .WAYS   (l2_nstrms),
        .RRWAYS (RRWAYS),
        .WIDTH  (l2_ncl_width)
        ) is1_addr_merge (
        .clk    (clk),
        .reset  (reset),
        .i_v    (s1_addr_v[(j+1)*l2_nstrms-1:j*l2_nstrms]),
        .i_r    (s1_addr_r[(j+1)*l2_nstrms-1:j*l2_nstrms]),
        .i_d    (s1_addr_ptr[(j+1)*l2_nstrms*l2_ncl_width-1:j*l2_nstrms*l2_ncl_width]),
        .o_v    (s2_addr_v[j]),
        .o_r    (s2_addr_r[j]),
        .o_d    (s2_addr_ptr[(j+1)*l2_ncl_width-1:j*l2_ncl_width]),
        .o_sel  (s2_addr_sid[(j+1)*l2_nstrms_width-1:j*l2_nstrms_width])
      );

      // Merge requests for OpenCAPI 3.0.
      // Concatenate the EA and SID to have all request aux data together.
      wire [addr_width-1:0] s2_req_ea;
      wire [l2_nstrms_width-1:0] s2_req_sid;
      wire [addr_width+l2_nstrms_width-1:0] s2_req_concat = {s2_req_ea, s2_req_sid};
      wire [addr_width+l2_nstrms_width-1:0] s3_req_concat;

      wire s2_req_v, s2_req_r;
      l2_merge # (
        .WAYS   (l2_nstrms),
        .RRWAYS (RRWAYS),
        .WIDTH  (addr_width)
        ) is1_req_merge (
        .clk    (clk),
        .reset  (reset),
        .i_v    (s1_req_v[(j+1)*l2_nstrms-1:j*l2_nstrms]),
        .i_r    (s1_req_r[(j+1)*l2_nstrms-1:j*l2_nstrms]),
        .i_d    (s1_req_ea[(j+1)*l2_nstrms*addr_width-1:j*l2_nstrms*addr_width]),
        .o_v    (s2_req_v),
        .o_r    (s2_req_r),
        .o_d    (s2_req_ea),
        .o_sel  (s2_req_sid)
      );

      base_areg # (.lbl(3'b110),.width(addr_width+l2_nstrms_width)) is2_req_merge_reg (
        .clk    (clk),
        .reset  (reset),
        .i_v    (s2_req_v),
        .i_r    (s2_req_r),
        .i_d    (s2_req_concat),
        .o_v    (s3_req_v[j]),
        .o_r    (s3_req_r[j]),
        .o_d    (s3_req_concat)
      );

      assign s3_req_channels[(j+1)*(addr_width+l2_nstrms_width)-1:j*(addr_width+l2_nstrms_width)] = s3_req_concat;
    end
  endgenerate

  // URAM read address assign.
  assign o_addr_v = s2_addr_v;
  assign s2_addr_r = o_addr_r;
  assign o_addr_sid = s2_addr_sid;
  assign o_addr_ptr = s2_addr_ptr;

  // Final request merge.
  wire [addr_width-1:0] s3_req_ea_winner;
  wire [l2_nstrms_width-1:0] s3_req_sid_winner;
  wire [channels-1:0] s3_req_sid_tile;
  wire [$clog2(channels)-1:0] s3_req_sid_tile_enc;
  base_arr_mux # (
    .ways     (channels),
    .width    (addr_width+l2_nstrms_width)
    ) is0_l2_final_req_merge (
      .clk    (clk),
      .reset  (reset),
      .i_v    (s3_req_v),
      .i_r    (s3_req_r),
      .i_d    (s3_req_channels),
      .o_v    (o_req_v),
      .o_r    (o_req_r),
      .o_d    ({s3_req_ea_winner, s3_req_sid_winner}),
      .o_sel  (s3_req_sid_tile)
  );
  base_encode_le # (
    .dec_width  (channels),
    .enc_width  ($clog2(channels))
    ) is0_gen_enc (
    .i_d        (s3_req_sid_tile),
    .o_d        (s3_req_sid_tile_enc),
    .o_v        ()
  );

  assign o_req_sid = {s3_req_sid_tile_enc, s3_req_sid_winner};
  assign o_req_ea = s3_req_ea_winner;

  // Response demux logic.
  wire [nstrms-1:0] s1_rsp_sid_dec;
  base_decode_le#(.enc_width(nstrms_width),.dec_width(nstrms)) is1_rsp_dec (
    .din    (i_rsp_sid),
    .dout   (s1_rsp_sid_dec),
    .en     (1'b1)
  );
  base_ademux # (.ways(nstrms)) is1_rsp_demux (
    .i_v    (i_rsp_v),
    .i_r    (i_rsp_r),
    .o_v    (s1_rsp_v),
    .o_r    (s1_rsp_r),
    .sel    (s1_rsp_sid_dec)
  );

  assign i_rsp_r = 1'b1;

endmodule
