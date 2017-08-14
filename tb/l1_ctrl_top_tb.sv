module l1_ctrl_top_tb;

    parameter nports                = 8;                        // number of read ports
    parameter nstrms                = 64;                       // total number of streams
    parameter ncl                   = 16;                       // number of cachelines per stream
    parameter cl_size               = 8;                       // number of reads per cacheline - must be at least as big as the number of read ports
    parameter clid_width            = $clog2(ncl);              // number of bits needed to identify a cache line
    parameter clofs_width           = $clog2(cl_size);          // number of bits needed to represent an offset within a cacheline
    parameter sid_width             = $clog2(nstrms);          // number of bits needed to represent the number of streams
    parameter ptr_width             = clid_width+clofs_width;   // number of bits needed to represent a stream pointer
    parameter TILES                 = 4;                         // 64 streams / 16 streams / BRAM tile = 4 blocks

    // SETUP
    reg clk;
    reg reset;

    always
    begin
        clk <= 1'b1;
        #(2.0);
        clk <= 1'b0;
        #(2.0);
    end

    initial
    begin
        clk = 0;
        #1000;
        $finish;
    end

    initial begin
        reset = 1;
        #100;
        reset = 0;
    end

    initial begin
        // dump waveform files
        // dumpvars = dumps ALL the variables of that module and all the variables in ALL lower level modules instantiated by this top module
        `ifdef VCD
            $dumpfile("l1_ctrl_top_tb.vcd");
            $dumpvars(0, l1_ctrl_top_tb);
        `endif
    end

    // SIGNAL DECLARATIONS
    // Input signals.
    reg                           i_rst_v;
    reg [sid_width-1:0]           i_rst_sid;

    reg  [nports-1:0] 		      i_rd_v;
    reg  [nports*sid_width-1:0]   i_rd_sid;

    reg  [nports-1:0] 	          o_addr_r;

    //reg  [TILES-1:0]              o_tile_req_r;

    //reg  [TILES-1:0]              o_tile_rsp_v;
    //reg  [clid_width*TILES-1:0]   o_tile_rsp_clid;

    // Input after reg.
    wire                           s0_rst_v;
    wire [sid_width-1:0]           s0_rst_sid;

    wire  [nports-1:0] 		       s0_rd_v;
    wire  [nports*sid_width-1:0]   s0_rd_sid;

    wire  [nports-1:0] 	           s0_addr_r;

    //wire  [TILES-1:0]              s0_tile_req_r;

    //wire  [TILES-1:0]              s0_tile_rsp_v;
    //wire  [clid_width*TILES-1:0]   s0_tile_rsp_clid;

    // Output signals.
    wire 			              i_rst_r;
    wire [nports-1:0] 	          i_rd_r;
    wire [nports-1:0] 		      o_addr_v;
    wire [nports*ptr_width-1:0]   o_addr_ptr;
    wire [nports*sid_width-1:0]   o_addr_sid;

    wire [TILES-1:0]              s1_tile_req_v;
    wire [clid_width*TILES-1:0]   s1_tile_req_clid;
    wire [TILES-1:0]              s1_tile_req_r;

    wire [TILES-1:0]              s2_tile_rsp_v;
    wire [clid_width*TILES-1:0]   s2_tile_rsp_clid;
    wire [TILES-1:0]              s2_tile_rsp_r;

    // REGISTER INPUTS
    base_delay # (
        .width(1+sid_width+nports+nports*sid_width+nports),
        .n(1)
    ) is0_input_delay (
        .clk (clk),
        .reset (reset),
        .i_d ({i_rst_v, i_rst_sid, i_rd_v, i_rd_sid, o_addr_r}),
        .o_d ({s0_rst_v, s0_rst_sid, s0_rd_v, s0_rd_sid, s0_addr_r})
    );

    // DUT
    l1_ctrl_top IDUT (
        .clk                (clk),
        .reset              (reset),

        .i_rst_v            (s0_rst_v),
        .i_rst_r            (i_rst_r),
        .i_rst_sid          (s0_rst_sid),

        .i_rd_v             (s0_rd_v),
        .i_rd_r             (i_rd_r),
        .i_rd_sid           (s0_rd_sid),

        .o_addr_v           (o_addr_v),
        .o_addr_r           (s0_addr_r),
        .o_addr_ptr         (o_addr_ptr),
        .o_addr_sid         (o_addr_sid),

        .o_tile_req_v       (s1_tile_req_v),
        .o_tile_req_r       (s1_tile_req_r),
        .o_tile_req_clid    (s1_tile_req_clid),

        .i_tile_rsp_v       (s2_tile_rsp_v),
        .i_tile_rsp_r       (s2_tile_rsp_r),
        .i_tile_rsp_clid    (s2_tile_rsp_clid)
    );

    // Loop back req and rsp for L2.
    genvar i;
    generate
        for(i=0; i<TILES; i=i+1) begin : gen1
           base_areg#(.lbl(3'b110),.width(clid_width)) is2_tile_req_reg
        (.clk(clk),.reset(reset),
         .i_v(s1_tile_req_v[i]),.i_r(s1_tile_req_r[i]),.i_d(s1_tile_req_clid[(i+1)*clid_width-1:i*clid_width]),
         .o_v(s2_tile_rsp_v[i]),.o_r(s2_tile_rsp_r[i]),.o_d(s2_tile_rsp_clid[(i+1)*clid_width-1:i*clid_width]));
        end
    endgenerate

    // DRIVE INPUTS - best practise to change them on a negative edge.
    initial begin
        i_rst_v             <= 0;
        i_rst_sid           <= 0;
        i_rd_v              <= 0;
        i_rd_sid            <= 0;
        o_addr_r            <= 0;
        //o_tile_req_r        <= 0;
        //o_tile_rsp_v        <= 0;
        //o_tile_rsp_clid     <= 0;
        #102;

        // Write base stream addresses.
        i_rst_v             <= 1;
        i_rst_sid           <= 63;
        #4;

        i_rst_v             <= 0;
        #4;
        #100;

        // TODO: test what happens if you start reading before all 16 cache lines have been received from L2.
        // Read
        i_rd_v              <= 8'hFF;
        i_rd_sid            <= 48'hFFFFFFFFFFFF;
        o_addr_r            <= 8'hFF;
        #4;

        i_rd_v              <= 0;
        i_rd_sid            <= 0;

        #8;
        // Read
        i_rd_v              <= 8'hFF;
        i_rd_sid            <= 48'hFFFFFFFFFFFF;
        o_addr_r            <= 8'hFF;
        #4;

        i_rd_v              <= 0;
        i_rd_sid            <= 0;
    end

endmodule // l1_ctrl_top_tb
