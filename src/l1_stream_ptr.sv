module l1_stream_ptr #
(
    parameter nports                    = 8,
    parameter ncl                       = 16, // number of cachelines per stream
    parameter cl_size                   = 8, //number of reads per cacheline - must be at least as big as the number of read ports
    parameter ncl_width                 = $clog2(ncl+1),   // number of bits needed to count the number of valid cachelines
    parameter clid_width                = $clog2(ncl),    // number of bits needed to identify a cache line
    parameter clofs_width               = $clog2(cl_size), // number of bits needed to represent an offset within a cacheline
    parameter [ncl_width-1:0] min_cl    = 2, // don't accept requests if we have less than this number of valid cache lines
    parameter width                     = clid_width + clofs_width
)
(
    // Global signals.
    input                   clk,
    input 		            reset,

    // Start a new stream - used for stream initialization. If high, stored pointer is updated.
    input 		            i_rst_v,
    output 		            i_rst_r,
    // TODO: Needed because of direct mapping of actual 64b addresses. Might not start at index 0 in BRAM.
//    input [clid_width-1:0]  i_rst_clid,

    output                  o_rst_v,
    input                   o_rst_r,

    // read input - high if read stream_id is equal to the stream constant.
    input   [nports-1:0] 	i_rd_v,
    output  [nports-1:0]    i_rd_r,

    // output current pointer for individual read port offset calcuation.
    output  [width-1:0]     o_d,        // 7 bits = line + offset

    // output - used for requesting a new cache line from L2.
    output 		            o_clreq_v,  // request a new cacheline for this stream
    input 		            o_clreq_r,

    // input - used to decrement the fetch queue counter when new cache line has been delivered by L2.
    input 		            i_clrsp_v,  // a new cacheline has been received for this stream
    output 		            i_clrsp_r
);

    wire [ncl_width-1:0]    s0_ncl_req; // how many valid cachelines do we need to request
    wire [ncl_width-1:0]    s0_ncl;     // how many valid cachelines do we have
    wire [clid_width-1:0]   s0_clid;    // what cacheline are we currently reading from
    wire [clofs_width-1:0]  s0_clofs;   // what offset are we currently reading from

    // only accept input requests when we have enough cachelines in the cache, and we are not resetting
    wire s0_en = (s0_ncl >= min_cl) & ~i_rst_v; // TODO: change to o_rst_v

    wire [nports-1:0]   s0_v;
    wire [nports-1:0]   s0_r;
    assign              s0_r = {nports{1'b1}};

    // This generates the i_rd_r and s0_v signals.
    // Enable input works as a pass gate. It connects the valids and readies only if enable is high.
    // So we will only proceed if there are 2 or more valid cache lines present.
    base_agate # (
        .width  (nports)
    ) is0_igt(
        .i_v    (i_rd_v),
        .i_r    (i_rd_r), //output: i_r = en & o_r;
        .o_v    (s0_v),   //output: o_v = en & i_v;
        .o_r    (s0_r),
        .en     ({nports{s0_en}})
    );

    // Only allow reset if there are no outstanding requests.
    //wire s0_rst_v, s0_rst_r;
    wire s0_en_rst = s0_ncl_req_zero & (s0_ncl == xncl); // if there are no outstanding requests, it is safe to functionally reset the stream. after & is from historic assign statement, not sure if needed but does allow only a reset if there are no outstanding requests and if all lines are valid. assume that after stream end pointer, you put in 'valid' lines which are garbage.
    base_agate # (
        .width  (1)
    ) is0_reset_agate(
        .i_v    (i_rst_v),
        .i_r    (i_rst_r),
        .o_v    (o_rst_v),
        .o_r    (o_rst_r),
        .en     (s0_en_rst)
    );

    // Work out by how much to increment the current pointer.
    wire [nports-1:0]   s0_act = s0_v & s0_r;
    localparam inc_width = $clog2(nports+1); // how many bits are needed to represent the increment
    wire [inc_width-1:0] s0_inc;

    // cenc = count encode
    base_cenc # ( // count the number of 1's in .din.
        .enc_width  (inc_width),
        .dec_width  (nports)
    ) is0_inc_cenc (
        .din        (s0_act), // 8 bits
        .dout       (s0_inc)  // 4 bits
    ); // luckily, there is a base cell that "counts"!

    // Cache line id and offset incrementing.
    wire [clofs_width:0]  s0_clofs_nxt = s0_clofs + s0_inc; // 4 bits because offset = 3 and 1b for carry
    wire                  s0_clofs_carry = s0_clofs_nxt[clofs_width]; // pick off the carry bit
    wire [clid_width-1:0] s0_clid_nxt = s0_clid + s0_clofs_carry;
    base_vlat # (
        .width  (clofs_width)
    ) is0_clofs_lat (
        .clk(clk),
        .reset(reset),
        .din(s0_clofs_nxt[clofs_width-1:0]), // don't include the carry bit in the update
        .q(s0_clofs)
    );
    base_vlat # (
        .width      (clid_width)
    ) is0_clid_lat (
        .clk        (clk),
        .reset      (reset),
        .din        (s0_clid_nxt),
        .q          (s0_clid)
    );


    // TODO: should change this at some point. sim breaks if I remove the i_clrsp_r statement.
    assign i_clrsp_r = 1'b1; // for now, no back pressure is needed on responses
    wire 		  s0_clreq_act = o_clreq_v & o_clreq_r;   // we are generating a request, and it is accepted
    wire 		  s0_clrsp_act = i_clrsp_v & i_clrsp_r;   // we have a valid response and we are accepting it
    wire 		  s0_ncl_inc = s0_clrsp_act;              // increment the number of valid cachelines when we accept a valid response
    wire 		  s0_ncl_dec = s0_clofs_carry;            // decrement the number of valid cachelines when we carry
    wire 		  s0_ncl_req_inc = s0_clofs_carry;        // increment the number of requests needed when we carry
    wire 		  s0_ncl_req_dec = s0_clreq_act;          // decrement the number of requests needed when a valid request is accepted
    wire 		  s0_ncl_req_zero;

    localparam [ncl_width-1:0] xncl=ncl; // avoid width warning
    localparam [ncl_width-1:0] ncl0 = 0;
    wire 		  s0_rst_act = o_rst_v & o_rst_r;
    // increment decrement the number of valid cache lines in this stream.
    base_incdec # (
        .width(ncl_width),
        .rstv(ncl) // TODO: changed this to 0 in l2_stream_ptr. Check if i_rd_r is also high here before a reset occurs.
    ) is0_ncl_incdec (
        .clk(clk),
        .reset(reset),
        .i_set_v    (s0_rst_act), // overwrite the output value at any time. this is the enable signal
        .i_set_d    (ncl0),       // overwrite the output value at any time. this is the data signal
        .i_inc      (s0_ncl_inc),
        .i_dec      (s0_ncl_dec),
        .o_cnt      (s0_ncl),
        .o_zero     ()
    );
    // increment decrement outstanding number of cache line requests to L2.
    base_incdec # (
        .width      (ncl_width),
        .rstv       (0)
    ) is0_ncl_req_incdec (
        .clk        (clk),
        .reset      (reset),
        .i_set_v    (s0_rst_act),
        .i_set_d    (xncl),
        .i_inc      (s0_ncl_req_inc),
        .i_dec      (s0_ncl_req_dec),
        .o_cnt      (s0_ncl_req),
        .o_zero     (s0_ncl_req_zero) //assign o_zero = (cnt_d == {width{1'b0}}); cnt_d=o_cnt;
    );

    assign o_clreq_v = ~s0_ncl_req_zero;
    assign o_d = {s0_clid, s0_clofs};
    //assign i_rst_r = (s0_ncl == xncl);  // only accept a reset when we are in a clean state // TODO might want to keep track of end pointer for each stream as well. Or have a special condition. Option could be that L2 always responds, even when it is gibberish and read past the end of the valid address range. Have to think more about this case. First test what happens when you reset the stream, read some stuff and reset again for the next job.

endmodule // l1_stream_ptr
