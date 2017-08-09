module rd_ctrl_top #
(
    parameter nports                = 8,                        // number of read ports
    parameter nstrms                = 64,                       // total number of streams
    parameter ncl                   = 16,                       // number of cachelines per stream
    parameter cl_size               = 8,                        // number of reads per cacheline - must be at least as big as the number of read ports
    parameter clid_width            = $clog2(ncl),              // number of bits needed to identify a cache line
    parameter clofs_width           = $clog2(cl_size),          // number of bits needed to represent an offset within a cacheline
    parameter sid_width             = $clog2(nstrms),           // number of bits needed to represent the number of streams
    parameter ptr_width             = clid_width+clofs_width,   // number of bits needed to represent a stream pointer
    parameter TILES                 = 4                         // 64 streams / 16 streams / BRAM tile = 4 blocks
)
(
    input                           clk,
    input                           reset,

/*
    // INITIALIZATION INTERFACE
    // Start a new stream - used for stream initialization. If high, stored pointer is updated.
    // Read one stream base address per cycle. Repeat for nstreams to complete initialization.
    input                           i_rst_v,
    output 			                i_rst_r,
    input [sid_width-1:0] 	        i_rst_sid, // This is the first unread pointer.
*/

    // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
    input  [nstrms-1:0]			    i_rst_v,
    output [nstrms-1:0]				i_rst_r,

    // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
    output [nstrms-1:0]			    o_rst_v,
    input  [nstrms-1:0]				o_rst_r,

    // AFU INTERFACE
    // read input - requested stream id from each read port.
    input  [nports-1:0] 		    i_rd_v,
    output [nports-1:0] 	        i_rd_r,
    input  [nports*sid_width-1:0]   i_rd_sid,

    // L1 BRAM READ PORT INTERFACE
    output [nports-1:0] 		    o_addr_v,
    input  [nports-1:0] 	        o_addr_r,
    output [nports*sid_width-1:0]   o_addr_sid, // stream id
    output [nports*ptr_width-1:0]   o_addr_ptr, // pointer

/*
    // L2 REQUEST AND RESPONSE INTERFACE (TO URAM)
    // request
    output [TILES-1:0]              o_tile_req_v,
    input  [TILES-1:0]              o_tile_req_r,
    output [clid_width*TILES-1:0]   o_tile_req_clid,

    // response
    input  [TILES-1:0]              i_tile_rsp_v,
    output [TILES-1:0]              i_tile_rsp_r,
    input  [clid_width*TILES-1:0]   i_tile_rsp_clid
*/

    // L2 REQUEST INTERFACE
    output [nstrms-1:0]             o_req_v,
    input  [nstrms-1:0]             o_req_r,

    // L2 RESPONSE INTERFACE
    input  [nstrms-1:0]             i_rsp_v,
    output [nstrms-1:0]             i_rsp_r
);

    // TODO: add agate for reset as done for L2 stream control.

    // COMPARE STREAM IDS AND CALCULATE BRAM ADDRESSES -------------------------------------------------------------------------------------------
    wire [nstrms*ptr_width-1:0] 	s1_ptrs; // holds all current pointers. assigned in ptr_st module.
    wire [nports*nstrms-1:0] 	    s1_rd_v, s1_rd_r;

    // Compare input stream ids.
    // - send which streams are used (one-hot) to ptr_st modules.
    // - calculate address for each respective read port to interface with L1 BRAMs.
    genvar i;
    generate
        for(i=0; i<nports; i=i+1)
        begin : gen1
            rd_port # (
                .nstrms(nstrms),
                .nports(nports),
                .portid(i),
                .ptr_width(ptr_width)
            ) iport (
                .clk                (clk),
                .reset              (reset),
                .i_rd_v             (i_rd_v[i]),
                .i_rd_r             (i_rd_r[i]),
                .i_rd_sid           (i_rd_sid[(i+1)*sid_width-1:i*sid_width]),      // stream id read request
                .i_cmp_sid_v        (i_rd_v),
                .i_cmp_sid_d        (i_rd_sid),                                     // array with all stream id read requests
                .i_ptrs             (s1_ptrs),                                      // array with all current stream pointers
                .o_req_v            (s1_rd_v[(i+1)*nstrms-1:i*nstrms]),
                .o_req_r            (s1_rd_r[(i+1)*nstrms-1:i*nstrms]),             // which stream id is requested for this read port (one-hot). used for transpose.
                .o_addr_v           (o_addr_v[i]),
                .o_addr_r           (o_addr_r[i]),
                .o_addr_ptr         (o_addr_ptr[ptr_width*(i+1)-1:ptr_width*i]),
                .o_addr_sid         (o_addr_sid[sid_width*(i+1)-1:sid_width*i])     // addr to index the BRAM for this particular read port
            );
        end
    endgenerate

    // PARSE INITIALIZATION INTERFACE DATA -------------------------------------------------------------------------------------------------------
    // Fix timing if needed.
    wire [nstrms-1:0]			         s1_rst_v, s1_rst_r;
    wire [sid_width-1:0] 	 s1_rst_sid;

    genvar m;
    generate
    for(m=0; m<nstrms; m=m+1) begin : GEN_REGS
        base_areg # (
            .lbl        (3'b000),
            .width      (1) //(sid_width)
        ) is1_rst_reg (
            .clk        (clk),
            .reset      (reset),
            .i_v        (i_rst_v[m]),
            .i_r        (i_rst_r[m]),
            .i_d        (), //(i_rst_sid),
            .o_v        (s1_rst_v[m]),
            .o_r        (s1_rst_r[m]),
            .o_d        () //(s1_rst_sid)
        );
    end
    endgenerate

    // Demux the initialization stream id from the initialization interface.
//    wire [nstrms-1:0] 		 s1a_rst_v, s1a_rst_r, s1a_rst_sid_dec;
//    base_decode_le#(.enc_width(sid_width),.dec_width(nstrms)) is1_rst_sid_dec(.din(s1_rst_sid),.dout(s1a_rst_sid_dec),.en(1'b1));
//    base_ademux#(.ways(nstrms)) is1_rst_demux (.i_v(s1_rst_v),.i_r(s1_rst_r),.o_v(s1a_rst_v),.o_r(s1a_rst_r),.sel(s1a_rst_sid_dec));

    // UPDATE CURRENT STREAM POINTERS ------------------------------------------------------------------------------------------------------------
    // transpose the ready and valid signals for consumption by the streams
    // first each entry shows which stream is requested as one-hot. by transposing each entry shows how often each stream is requested.
    wire [nports*nstrms-1:0] 	 s1_rd_xpose_v, s1_rd_xpose_r;
    base_transpose#(.w(1),.rs(nports),.cs(nstrms)) is1_xpose_v(.din(s1_rd_v),.dout(s1_rd_xpose_v)); //why are these different? because they go in opposite directions. look more into this.
    base_transpose#(.w(1),.rs(nstrms),.cs(nports)) is1_xpose_r(.din(s1_rd_xpose_r),.dout(s1_rd_r));

    // Generate as many ptr_st modules as there are streams since each stream has to keep track of its own pointer.
    wire [nstrms-1:0] s1_clreq_v; // Requests a cache line from L2. Used in the Round-Robin merge MUX.
    wire [nstrms-1:0] s1_clreq_r;
    wire [nstrms-1:0] s2_clreq_v; // Response from L2, the cache line has been received.
    wire [nstrms-1:0] s2_clreq_r;

    genvar j;
    generate
        for(j=0; j<nstrms; j=j+1)
        begin : gen2
            ptr_st # (
                .nports(nports),.ncl(ncl),.cl_size(cl_size)
            ) iptr_st (
                .clk(clk), .reset(reset),
                .i_rst_v(s1_rst_v[j]),.i_rst_r(s1_rst_r[j]),        // Initialization interface.
                .o_rst_v(o_rst_v[j]),.o_rst_r(o_rst_r[j]),
                .i_rd_v(s1_rd_xpose_v[(j+1)*nports-1:j*nports]),    // Valid signals for this stream.
                .i_rd_r(s1_rd_xpose_r[(j+1)*nports-1:j*nports]),    // Ready signals for this stream.
                .o_d(s1_ptrs[(j+1)*ptr_width-1:j*ptr_width]),       // Outputs current (not updated) pointer.
                .o_clreq_v(s1_clreq_v[j]),                          // Request a new cache line for this stream from L2 URAM.
                .o_clreq_r(s1_clreq_r[j]),
                .i_clrsp_v(s2_clreq_v[j]),                          // The new cache line has been received from L2 URAM.
                .i_clrsp_r(s2_clreq_r[j])
            );
        end
    endgenerate

/*
    // MERGE L2 URAM REQUESTS INTO TILES * QUEUES ------------------------------------------------------------------------------------------------
    // TODO: attach queues at the four ends. base_afifo
    genvar l;
    generate
        for(l=0; l<TILES; l=l+1)
        begin : GEN_REQ_MERGE
            // Generate req_merge modules.
            localparam  RRWAYS = 4;     // 4 inputs per RR MUX.
            req_merge # (
                .NSTRMS (nstrms),
                .NCL    (ncl),
                .RRWAYS (RRWAYS),
                .NMUX   (ncl/RRWAYS)    // Number of RRMUX in first level.
            ) ireq_merge (
                .clk        (clk),
                .reset      (reset),
                .i_clreq_v  (s1_clreq_v[(l+1)*ncl-1:l*ncl]),
                .i_clreq_r  (s1_clreq_r[(l+1)*ncl-1:l*ncl]),
                .o_v        (o_tile_req_v[l]),
                .o_r        (o_tile_req_r[l]),
                .o_clid_req (o_tile_req_clid[(l+1)*clid_width-1:l*clid_width])
            );

            // Generate response demux logic.
            wire [ncl-1:0] s1_rsp_clid_dec;
            base_decode_le#(.enc_width(clid_width),.dec_width(ncl)) is1_rsp_gen_dec (
                .din        (i_tile_rsp_clid[(l+1)*clid_width-1:l*clid_width]),
                .dout       (s1_rsp_clid_dec),
                .en         (1'b1)
            );
            base_ademux # (
                .ways(ncl)
            ) is1_rst_demux (
                .i_v(i_tile_rsp_v[l]),
                .i_r(i_tile_rsp_r[l]),
                .o_v(s2_clreq_v[(l+1)*ncl-1:l*ncl]),
                .o_r(s2_clreq_r[(l+1)*ncl-1:l*ncl]),
                .sel(s1_rsp_clid_dec)
            );
        end
    endgenerate
*/

    // L2 REQUEST INTERFACE
    assign o_req_v = s1_clreq_v;
    assign s1_clreq_r= o_req_r;

    // L2 RESPONSE INTERFACE
    assign s2_clreq_v = i_rsp_v;
    assign i_rsp_r = s2_clreq_r;

endmodule // rd_ctrl_top
