module l1_ctrl_top #
(
  parameter nports                = 8,                        // number of read ports
  parameter nstrms                = 64,                       // total number of streams
  parameter ncl                   = 16,                       // number of cachelines per stream
  parameter cl_size               = 8,                        // number of reads per cacheline - must be at least as big as the number of read ports
  parameter clid_width            = $clog2(ncl),              // number of bits needed to identify a cache line
  parameter clofs_width           = $clog2(cl_size),          // number of bits needed to represent an offset within a cacheline
  parameter sid_width             = $clog2(nstrms),           // number of bits needed to represent the number of streams
  parameter ptr_width             = clid_width+clofs_width,   // number of bits needed to represent a stream pointer
  parameter channels              = 4 // 64 streams / 16 streams / BRAM tile = 4 blocks
)
(
  input                           clk,
  input                           reset,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  input  [nstrms-1:0]             i_rst_v,
  output [nstrms-1:0]             i_rst_r,
  input  [nstrms*clid_width-1:0]  i_rst_ea_b,
  input  [nstrms-1:0]             i_rst_end,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output [nstrms-1:0]             o_rst_v, // Valid reset passes through, but does not stay asserted.
  input  [nstrms-1:0]             o_rst_r,
  // TODO: o_rst_end per stream. this signal comes from a reg and stays high.

  // AFU INTERFACE
  input  [nports-1:0]             i_rd_v,
  output [nports-1:0]             i_rd_r,
  input  [nports*sid_width-1:0]   i_rd_sid,

  // L1 BRAM READ PORT INTERFACE
  output [nports-1:0]             o_addr_v,
  input  [nports-1:0]             o_addr_r,
  output [nports*sid_width-1:0]   o_addr_sid,
  output [nports*ptr_width-1:0]   o_addr_ptr,

  // L2 REQUEST INTERFACE
  output [nstrms-1:0]             o_req_v,
  input  [nstrms-1:0]             o_req_r,

  // L2 RESPONSE INTERFACE
  input  [nstrms-1:0]             i_rsp_v,
  output [nstrms-1:0]             i_rsp_r
);

  // PARSE INITIALIZATION INTERFACE DATA
  // TODO: merge with genvar j.
  wire [nstrms-1:0] s1_rst_v, s1_rst_r;
  wire [nstrms*clid_width-1:0] s1_rst_ea_b;

  genvar m;
  generate
    for(m=0; m<nstrms; m=m+1) begin : GEN_REGS
      base_areg # (
        .lbl        (3'b000),
        .width      (clid_width)
        ) is1_rst_reg (
        .clk        (clk),
        .reset      (reset),
        .i_v        (i_rst_v[m]),
        .i_r        (i_rst_r[m]),
        .i_d        (i_rst_ea_b[(m+1)*clid_width-1:m*clid_width]),
        .o_v        (s1_rst_v[m]),
        .o_r        (s1_rst_r[m]),
        .o_d        (s1_rst_ea_b[(m+1)*clid_width-1:m*clid_width])
      );
  end
  endgenerate

  // COMPARE STREAM IDS AND CALCULATE BRAM ADDRESSES
  wire [nstrms*ptr_width-1:0] s1_ptrs; // holds all current pointers. assigned in l1_stream_ptr module.
  wire [nports*nstrms-1:0] s1_rd_v, s1_rd_r; // request signal between read port and l1_stream_ptr.

  // INPUT READ REGISTER
  // TODO: move this inside the l1_rd_port module.
  wire [nports-1:0] s1_v, s1_r;
  wire [nports*sid_width-1:0] s1_sid;

  genvar d;
  generate
    for(d=0; d<nports; d=d+1) begin : GEN_INIT
      base_areg # (
        .lbl(3'b110),
        .width(sid_width)
      ) is1_lat (
        .clk(clk),.reset(reset),
        .i_v(i_rd_v[d]),
        .i_r(i_rd_r[d]),
        .i_d(i_rd_sid[(d+1)*sid_width-1:d*sid_width]),
        .o_v(s1_v[d]),
        .o_r(s1_r[d]),
        .o_d(s1_sid[(d+1)*sid_width-1:d*sid_width])
      );
    end
  endgenerate

  // global read port act signal
  wire [nports-1:0] s0_rd_acts;
  wire [nstrms-1:0] o_single_v;
  wire [nstrms-1:0] l1_end;

  // Compare input stream ids.
  // - send which streams are used (one-hot) to l1_stream_ptr modules.
  // - calculate address for each respective read port to interface with L1 BRAMs.
  genvar i;
  generate
    for(i=0; i<nports; i=i+1) begin : gen1
      l1_rd_port # (
        .nstrms(nstrms),
        .nports(nports),
        .portid(i),
        .ptr_width(ptr_width)
        ) iport (
        .i_l1_end           (l1_end),
        .i_single_v         (o_single_v),
        .clk                (clk),
        .reset              (reset),
        .i_rst_end          (i_rst_end),
        .i_rd_v             (s1_v[i]),
        .i_rd_r             (s1_r[i]),
        .i_rd_sid           (s1_sid[(i+1)*sid_width-1:i*sid_width]),
        .i_rd_acts          (s0_rd_acts),
        .i_rd_sids          (s1_sid), // array with all stream id read requests
        .o_rd_act           (s0_rd_acts[i]),
        .i_ptrs             (s1_ptrs), // array with all current stream pointers
        .o_req_v            (s1_rd_v[(i+1)*nstrms-1:i*nstrms]),
        .o_req_r            (s1_rd_r[(i+1)*nstrms-1:i*nstrms]), // which stream id is requested for this read port (one-hot). used for transpose.
        .o_addr_v           (o_addr_v[i]),
        .o_addr_r           (o_addr_r[i]),
        .o_addr_ptr         (o_addr_ptr[ptr_width*(i+1)-1:ptr_width*i]),
        .o_addr_sid         (o_addr_sid[sid_width*(i+1)-1:sid_width*i]) // addr to index the BRAM for this particular read port
      );
    end
  endgenerate

  // UPDATE CURRENT STREAM POINTERS
  // transpose the ready and valid signals for consumption by the streams
  // first each entry shows which stream is requested as one-hot. by transposing each entry shows how often each stream is requested.
  wire [nports*nstrms-1:0] s1_rd_xpose_v, s1_rd_xpose_r;
  base_transpose#(.w(1),.rs(nports),.cs(nstrms)) is1_xpose_v(.din(s1_rd_v),.dout(s1_rd_xpose_v)); //why are these different? because they go in opposite directions. look more into this.
  base_transpose#(.w(1),.rs(nstrms),.cs(nports)) is1_xpose_r(.din(s1_rd_xpose_r),.dout(s1_rd_r));

  // Generate as many l1_stream_ptr modules as there are streams since each stream has to keep track of its own pointer.
  wire [nstrms-1:0] s1_clreq_v, s1_clreq_r; // Requests a cache line from L2.
  wire [nstrms-1:0] s2_clreq_v, s2_clreq_r; // Response from L2, cache line received.

  genvar j;
  generate
    for(j=0; j<nstrms; j=j+1) begin : gen2
      l1_stream_ptr # (
        .nports(nports),.ncl(ncl),.cl_size(cl_size)
        ) i_stream_ptr (
        .o_single_v(o_single_v[j]),
        .clk(clk), .reset(reset),
        .i_rst_v(s1_rst_v[j]),.i_rst_r(s1_rst_r[j]),
        .i_rst_ea_b(s1_rst_ea_b[(j+1)*clid_width-1:j*clid_width]),
        .i_rst_end(i_rst_end[j]),
        .o_rst_v(o_rst_v[j]),.o_rst_r(o_rst_r[j]),
        .o_rst_end(l1_end[j]),
        .i_rd_v(s1_rd_xpose_v[(j+1)*nports-1:j*nports]), // Valid signals for this stream.
        .i_rd_r(s1_rd_xpose_r[(j+1)*nports-1:j*nports]), // Ready signals for this stream.
        .o_d(s1_ptrs[(j+1)*ptr_width-1:j*ptr_width]), // Outputs current (not updated) pointer.
        .o_clreq_v(s1_clreq_v[j]), // Request a new cache line for this stream from L2 URAM.
        .o_clreq_r(s1_clreq_r[j]),
        .i_clrsp_v(s2_clreq_v[j]), // The new cache line has been received from L2 URAM.
        .i_clrsp_r(s2_clreq_r[j])
      );
    end
  endgenerate

  // L2 REQUEST INTERFACE
  assign o_req_v = s1_clreq_v;
  assign s1_clreq_r = o_req_r;

  // L2 RESPONSE INTERFACE
  assign s2_clreq_v = i_rsp_v;
  assign i_rsp_r = s2_clreq_r;

endmodule // l1_ctrl_top
