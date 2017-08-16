// TODO: change module to only have control and memories. Interface can be attached seperately to easily change between OpenCAPI 3.0 and AXI for example.
// TODO: add reset out to AFU interface. Also on L1 control and AFU interface (8x read port & this reset interface decoded)

module apl_top #
(
    // TODO: organize parameters
    parameter nstrms            = 64,
    parameter nstrms_width      = $clog2(nstrms), // TODO: duplicate of sid_width
    parameter nports            = 8,                        // number of read ports

    // TODO: rename to l1_xxx
    parameter ncl               = 16,                       // number of cachelines per stream
    parameter clid_width        = $clog2(ncl),              // number of bits needed to identify a cache line
    parameter cl_size           = 8,                        // number of reads per cacheline - must be at least as big as the number of read ports
    parameter clofs_width       = $clog2(cl_size),          // number of bits needed to represent an offset within a cacheline
    parameter sid_width         = $clog2(nstrms),           // number of bits needed to represent the number of streams
    parameter ptr_width         = clid_width+clofs_width,   // number of bits needed to represent a stream pointer

    parameter l2_nstrms         = 16,
    parameter l2_nstrms_width   = $clog2(l2_nstrms),
    parameter l2_ncl            = 256,
    parameter l2_ncl_width      = $clog2(l2_ncl),
    parameter TILES             = nstrms/l2_nstrms
)
(
    input                               clk,
    input                               reset,

    // FUNCTIONAL STREAM RESET INPUT INTERFACE
    input 								i_rst_v,
    output 								i_rst_r,
    input  [nstrms_width-1:0]			i_rst_sid,

    // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
    output [nstrms-1:0]					o_rst_v,
    input  [nstrms-1:0]					o_rst_r,

    // AFU READ INTERFACE
    input  [nports-1:0] 		        i_rd_v,
    output [nports-1:0] 	            i_rd_r,
    input  [nports*sid_width-1:0]       i_rd_sid,

    // L1 READ INTERFACE
    output [nports-1:0] 		        o_l1_addr_v,
    input  [nports-1:0] 	            o_l1_addr_r,
    output [nports*sid_width-1:0]       o_l1_addr_sid,
    output [nports*ptr_width-1:0]       o_l1_addr_ptr,

    // L2 READ INTERFACE
    output [TILES-1:0]					o_l2_addr_v,
    input  [TILES-1:0]					o_l2_addr_r,
    output [TILES*l2_nstrms_width-1:0]	o_l2_addr_sid,
    output [TILES*l2_ncl_width-1:0] 	o_l2_addr_ptr,

    // OPENCAPI 3.0 REQUEST INTERFACE
    output 								o_req_v,
    input  								o_req_r,
    output [nstrms_width-1:0]			o_req_sid,

    // OPENCAPI 3.0 RESPONSE INTERFACE
    input  								i_rsp_v,
    output 								i_rsp_r,
    input  [nstrms_width-1:0]			i_rsp_sid,

    // TODO: remove in future iteration
    input  [nstrms-1:0]                 i_rsp_uram_v,
    output [nstrms-1:0]                 i_rsp_uram_r

    // TODO: OPENCAPI 3.0 INTERFACE
);

    // Wires
    wire [nstrms-1:0] s0_rst_v, s0_rst_r;
    wire [nstrms-1:0] s0_req_v, s0_req_r;

    l2_ctrl_top is0_l2_ctrl_top (
        .clk            (clk),
        .reset          (reset),
        .i_rst_v        (i_rst_v),
        .i_rst_r        (i_rst_r),
        .i_rst_sid      (i_rst_sid), // TODO: move demux up to this module
        .o_rst_v        (s0_rst_v),
        .o_rst_r        (s0_rst_r),
        .i_rd_v         (s0_req_v),
        .i_rd_r         (s0_req_r),
        .o_addr_v       (o_l2_addr_v),
        .o_addr_r       (o_l2_addr_r),
        .o_addr_sid     (o_l2_addr_sid),
        .o_addr_ptr     (o_l2_addr_ptr),
        .o_req_v        (o_req_v),
        .o_req_r        (o_req_r),
        .o_req_sid      (o_req_sid),
        .i_rsp_v        (i_rsp_v),
        .i_rsp_r        (i_rsp_r),
        .i_rsp_sid      (i_rsp_sid)
    );

    l1_ctrl_top is0_rd_ctrl_top (
        .clk            (clk),
        .reset          (reset),
        .i_rst_v        (s0_rst_v),
        .i_rst_r        (s0_rst_r),
        .o_rst_v        (o_rst_v),
        .o_rst_r        (o_rst_r),
        .i_rd_v         (i_rd_v),
        .i_rd_r         (i_rd_r),
        .i_rd_sid       (i_rd_sid),
        .o_addr_v       (o_l1_addr_v),
        .o_addr_r       (o_l1_addr_r),
        .o_addr_sid     (o_l1_addr_sid),
        .o_addr_ptr     (o_l1_addr_ptr),
        .o_req_v        (s0_req_v),
        .o_req_r        (s0_req_r),
        .i_rsp_v        (i_rsp_uram_v),
        .i_rsp_r        (i_rsp_uram_r)
    );

endmodule
