module interface_tag #
(
  // OpenCAPI 3.0 parameters
  parameter addr_width      = 64, // OpenCAPI 3.0 address with to index main memory.
  parameter data_width      = 1024, // OpenCAPI 3.0 data width.

  // Stream cache parameters
  parameter nstrms          = 64,
  parameter nstrms_width    = $clog2(nstrms),
  parameter tag             = 256, // Number of tags to be issued.
  parameter tag_width       = $clog2(tag),
  parameter l2_ncl          = 256,
  parameter l2_ncl_width    = $clog2(l2_ncl)
)
(
  input                     clk,
  input                     reset,

/*
  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  input                     i_rst_v,
  output                    i_rst_r,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output [nstrms-1:0]       o_rst_v,
  input  [nstrms-1:0]       o_rst_r,
*/

  // REQUEST INPUT INTERFACE
  input                     i_req_v,
  output                    i_req_r,
  input  [nstrms_width-1:0] i_req_sid,
  input  [addr_width-1:0]   i_req_ea,

  // RESPONSE OUTPUT INTERFACE
  output                    o_rsp_v,
  input                     o_rsp_r,
  output [data_width-1:0]   o_rsp_d, //TODO: call this _data like i_rsp_data
  output [nstrms_width-1:0] o_rsp_sid,
  output [l2_ncl_width-1:0] o_rsp_ptr,

  // REQUEST OUTPUT INTERFACE
  output                    o_req_v,
  input                     o_req_r,
  output [addr_width-1:0]   o_req_ea,
  output [tag_width-1:0]    o_req_tag,

  // RESPONSE INPUT INTERFACE
  input                     i_rsp_v,
  output                    i_rsp_r,
  input  [tag_width-1:0]    i_rsp_tag,
  input  [data_width-1:0]   i_rsp_data
);

  // request input interface
  wire s0_req_v = i_req_v;
  wire i_req_r = s0_req_r;
  wire [nstrms_width-1:0] s0_req_sid = i_req_sid;
  wire [addr_width-1:0] s0_req_ea = i_req_ea;
  wire s1_req_v;
  wire s1_req_r;
  wire [nstrms_width-1:0] s1_req_sid;
  wire [addr_width-1:0] s1_req_ea;

  base_areg # (
    .width  (nstrms_width+addr_width),
    .lbl    (3'b110)
    ) is0_req_reg (
    .clk    (clk),
    .reset  (reset),
    .i_v    (s0_req_v),
    .i_r    (s0_req_r),
    .i_d    ({s0_req_sid, s0_req_ea}),
    .o_v    (s1_req_v),
    .o_r    (s1_req_r),
    .o_d    ({s1_req_sid, s1_req_ea})
  );

  wire s1_res_o_v;
  wire s1_res_o_r;
  wire [tag_width-1:0] s1_res_o_tag;
  wire s2_res_i_v;
  wire s2_res_i_r;
  wire [tag_width-1:0] s2_res_i_tag = s2_rsp_tag;
  base_res_mgr # (
    .width(tag_width)
    ) is1_res_mgr (
    .clk    (clk),
    .reset  (reset),
    .i_v    (s2_res_i_v),
    .i_r    (s2_res_i_r),
    .i_d    (s2_res_i_tag),
    .o_v    (s1_res_o_v),
    .o_r    (s1_res_o_r),
    .o_d    (s1_res_o_tag)
  );

  wire s1_comb_v;
  wire s1_comb_r;
  base_acombine # (
    .ni   (2),
    .no   (1)
    ) is1_req_cmb (
    .i_v  ({s1_req_v, s1_res_o_v}),
    .i_r  ({s1_req_r, s1_res_o_r}),
    .o_v  (s1_comb_v),
    .o_r  (s1_comb_r)
  );

  assign o_req_v   = s1_comb_v;
  assign s1_comb_r = o_req_r;
  assign o_req_ea  = s1_req_ea;
  assign o_req_tag = s1_res_o_tag;

  // respsonse input interface
  wire s0_rsp_v = i_rsp_v;
  wire i_rsp_r = s0_rsp_r;
  wire [tag_width-1:0]  s0_rsp_tag  = i_rsp_tag;
  wire [data_width-1:0] s0_rsp_data = i_rsp_data;
  wire s1_rsp_v;
  wire s1_rsp_r;
  wire [tag_width-1:0]  s1_rsp_tag;
  wire [data_width-1:0] s1_rsp_data;

  // If this reg is not used, the loop reg in the testbench should be more than 1 cycle. Otherwise the write operation to the SRAM is not yet finished when a read operation is started on the same address. This results in undefined and incorrect output.
  base_areg # (
    .width  (tag_width+data_width),
    .lbl    (3'b000)
    ) is0_rsp_reg (
    .clk    (clk),
    .reset  (reset),
    .i_v    (s0_rsp_v),
    .i_r    (s0_rsp_r),
    .i_d    ({s0_rsp_tag, s0_rsp_data}),
    .o_v    (s1_rsp_v),
    .o_r    (s1_rsp_r),
    .o_d    ({s1_rsp_tag, s1_rsp_data})
  );

  // SRAM
  localparam sram_width = nstrms_width+l2_ncl_width;
  wire s1_comb_act = s1_comb_v & s1_comb_r;
  wire [sram_width-1:0] s1_sram_wd = {s1_req_sid, s1_req_ea[l2_ncl_width-1:0]};
  wire s2_rsp_v;
  wire s2_rsp_r;
  wire [tag_width-1:0] s2_rsp_tag;
  wire [data_width-1:0] s2_rsp_data;
  wire s2_sram_en;

  base_alatch_oe # (
    .width     (0),
    .del_width (data_width+tag_width)
    ) is1_alatch_oe (
    .clk   (clk),
    .reset (reset),
    .i_v   (s1_rsp_v),
    .i_r   (s1_rsp_r),
    .i_d   ({s1_rsp_tag, s1_rsp_data}), // all del (aux) data
    .o_v   (s2_rsp_v),
    .o_r   (s2_rsp_r),
    .o_d   ({s2_rsp_tag, s2_rsp_data}),
    .o_en  (s2_sram_en)
  );

  // TODO: is it possible that a conflict occurs? (read & write from same address)
  wire [nstrms_width-1:0] s2_req_sid;
  wire [l2_ncl_width-1:0] s2_req_ptr;
  base_mem # (
    .width      (sram_width),
    .addr_width (l2_ncl_width),
    .wdelay     (1), // cycles of write delay
    .bypass     (0)
    ) is1_sram (
    .clk (clk),
    .we  (s1_comb_act),
    .wa  (s1_res_o_tag),
    .wd  (s1_sram_wd), //{s1_req_sid, s1_req_ea[l2_ncl_width-1:0]}
    .re  (s2_sram_en),
    .ra  (s1_rsp_tag),
    .rd  ({s2_req_sid, s2_req_ptr})
  );

  // Synchronize SRAM output with resource manager and L2 response interface.
  wire s2_comb_rsp_v;
  wire s2_comb_rsp_r;
  base_acombine # (
    .ni   (1),
    .no   (2)
    ) is1_rsp_cmb (
    .i_v  (s2_rsp_v),
    .i_r  (s2_rsp_r),
    .o_v  ({s2_res_i_v, s2_comb_rsp_v}),
    .o_r  ({s2_res_i_r, s2_comb_rsp_r})
  );

  assign o_rsp_v = s2_comb_rsp_v;
  assign s2_comb_rsp_r = o_rsp_r;
  assign o_rsp_d = s2_rsp_data;
  assign o_rsp_sid = s2_req_sid;
  assign o_rsp_ptr = s2_req_ptr;

endmodule
