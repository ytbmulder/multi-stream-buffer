module apl_top_tb;

  // Host parameters
  parameter addr_width                  = 64;                 // Host address width in bits.
  parameter cache_line                  = 128;                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line);

  // Stream cache parameters
  parameter nstrms                      = 64;
  parameter nstrms_width                = $clog2(nstrms);
  parameter nports                      = 8;                  // Number of L1 read ports.
  parameter cl_size                     = 8;                  // number of reads per cacheline - must be at least as big as the number of read ports

  // L1 parameters
  parameter l1_ncl                      = 16;                 // Number of L1 cache lines per stream.
  parameter l1_ncl_width                = $clog2(l1_ncl);
  parameter clofs_width                 = $clog2(cl_size); // number of bits needed to represent an offset within a cacheline
  parameter ptr_width                   = l1_ncl_width+clofs_width; // number of bits needed to represent a stream pointer

  // L2 parameters
  parameter l2_nstrms                   = 16;
  parameter l2_nstrms_width             = $clog2(l2_nstrms);
  parameter l2_ncl                      = 256;                // Number of L2 cache lines per stream.
  parameter l2_ncl_width                = $clog2(l2_ncl);
  parameter channels                    = nstrms/l2_nstrms;    // TODO: move to stream cache parameters

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
        #1300;
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
            $dumpfile("apl_top_tb.vcd");
            $dumpvars(0, apl_top_tb);
        `endif
    end

    // SIGNAL DECLARATIONS
    // FUNCTIONAL STREAM RESET reg INTERFACE
    reg 								i_rst_v;
    wire 								i_rst_r;
    reg  [nstrms_width-1:0]			i_rst_sid;
    reg  [addr_width-1:0]               i_rst_ea;

    // FUNCTIONAL STREAM RESET wire INTERFACE
    wire [nstrms-1:0]					o_rst_v;
    reg  [nstrms-1:0]					o_rst_r;

    // AFU READ INTERFACE
    reg  [nports-1:0] 		        i_rd_v;
    wire [nports-1:0] 	            i_rd_r;
    reg  [nports*nstrms_width-1:0]       i_rd_sid;

    // L1 READ INTERFACE
    wire [nports-1:0] 		        o_l1_addr_v;
    reg  [nports-1:0] 	            o_l1_addr_r;
    wire [nports*nstrms_width-1:0]       o_l1_addr_sid;
    wire [nports*ptr_width-1:0]       o_l1_addr_ptr;

    // L2 READ INTERFACE
    wire [channels-1:0]					o_l2_addr_v;
    reg  [channels-1:0]					o_l2_addr_r;
    wire [channels*l2_nstrms_width-1:0]	o_l2_addr_sid;
    wire [channels*l2_ncl_width-1:0] 	o_l2_addr_ptr;

    // OPENCAPI 3.0 REQUEST INTERFACE
    wire 								o_req_v;
    reg  								o_req_r;
    wire [nstrms_width-1:0]			o_req_sid;
    wire [addr_width-1:0] o_req_ea;

    // OPENCAPI 3.0 RESPONSE INTERFACE
    reg  								i_rsp_v;
    wire 								i_rsp_r;
    reg  [nstrms_width-1:0]			i_rsp_sid;

    // TODO: remove in future iteration
    reg  [nstrms-1:0]                 i_rsp_uram_v;
    wire [nstrms-1:0]                 i_rsp_uram_r;

    // after reg
    wire s0_rst_v;
    wire [nstrms_width-1:0] s0_rst_sid;
    wire [addr_width-1:0] s0_rst_ea;
    wire [nstrms-1:0]	s0_rst_r;
    wire [nports-1:0] s0_rd_v;
    wire [nports*nstrms_width-1:0] s0_rd_sid;
    wire [nports-1:0] s0_l1_addr_r;
    wire [channels-1:0]	s0_l2_addr_r;
    wire s0_req_r;
    wire s0_rsp_v;
    wire [nstrms_width-1:0]	s0_rsp_sid;
//    wire [nstrms-1:0] s0_rsp_uram_v;

    // REGISTERS
    base_delay # (
        .width(1+nstrms_width+addr_width+nstrms+nports+nports*nstrms_width+nports+channels+1+1+nstrms_width),
        .n(1)
    ) is0_reg_delay (
        .clk (clk),
        .reset (reset),
        .i_d ({ i_rst_v,  i_rst_sid,  i_rst_ea,  o_rst_r,  i_rd_v,  i_rd_sid,  o_l1_addr_r,  o_l2_addr_r,  o_req_r,  i_rsp_v, i_rsp_sid}),
        .o_d ({s0_rst_v, s0_rst_sid, s0_rst_ea, s0_rst_r, s0_rd_v, s0_rd_sid, s0_l1_addr_r, s0_l2_addr_r, s0_req_r, s0_rsp_v, s0_rsp_sid})
    );

    // Loop back req and rsp for OpenCAPI 3.0.
    wire                       s1_req_v;
    wire                       s1_req_r;
    wire [nstrms_width-1:0]    s1_req_sid;

    wire                       s2_rsp_v;
    wire                       s2_rsp_r;
    wire [nstrms_width-1:0]    s2_rsp_sid;

    // Loop request to response interface.
    base_areg # ( .lbl(3'b110),.width(nstrms_width)) is0_req_reg (
        .clk(clk),.reset(reset),
        .i_v(s1_req_v),.i_r(s1_req_r),.i_d(s1_req_sid),
        .o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d(s2_rsp_sid)
    );

    wire [nstrms-1:0] s5_rsp_uram_v;
    genvar k;
    generate
        for(k=0; k<channels; k=k+1) begin : GEN_DINGES
            wire [l2_nstrms-1:0] s1_rsp_sid_dec;
            base_decode_le#(.enc_width(l2_nstrms_width),.dec_width(l2_nstrms)) is1_rsp_dec (
                .din        (o_l2_addr_sid[(k+1)*l2_nstrms_width-1:k*l2_nstrms_width]),
                .dout       (s1_rsp_sid_dec),
                .en         (1'b1)
            );
            wire v, r;
            wire [l2_nstrms-1:0] s2_rsp_sid_dec;
            base_areg # ( .lbl(3'b110),.width(16)) is0_req_ding_reg (
                .clk(clk),.reset(reset),
                .i_v(o_l2_addr_v[k]),.i_r(s0_l2_addr_r[k]),.i_d(s1_rsp_sid_dec),
                .o_v(v),.o_r(r),.o_d(s2_rsp_sid_dec)
            );
            base_ademux # (
                .ways(16)
            ) is1_rsp_demux_bla (
                .i_v(v),
                .i_r(r),
                .o_v(s5_rsp_uram_v[(k+1)*16-1:k*16]),
                .o_r(i_rsp_uram_r[(k+1)*16-1:k*16]),
                .sel(s2_rsp_sid_dec)
            );
        end
    endgenerate

    // DUT
    apl_top IDUT (
        .clk        (clk),
        .reset      (reset),

        .i_rst_v    (s0_rst_v),
        .i_rst_r    (i_rst_r),
        .i_rst_sid  (s0_rst_sid),
        .i_rst_ea   (s0_rst_ea),

        .o_rst_v    (o_rst_v),
        .o_rst_r    (s0_rst_r),

        .i_rd_v     (s0_rd_v),
        .i_rd_r     (i_rd_r),
        .i_rd_sid   (s0_rd_sid),

        .o_l1_addr_v   (o_l1_addr_v),
        .o_l1_addr_r   (s0_l1_addr_r),
        .o_l1_addr_sid (o_l1_addr_sid),
        .o_l1_addr_ptr (o_l1_addr_ptr),

        .o_l2_addr_v   (o_l2_addr_v),
        .o_l2_addr_r   (s0_l2_addr_r),
        .o_l2_addr_sid (o_l2_addr_sid),
        .o_l2_addr_ptr (o_l2_addr_ptr),

        .o_req_v    (s1_req_v),
        .o_req_r    (s1_req_r),
        .o_req_sid  (s1_req_sid),
        .o_req_ea   (o_req_ea),

        .i_rsp_v    (s2_rsp_v),
        .i_rsp_r    (s2_rsp_r),
        .i_rsp_sid  (s2_rsp_sid),

        .i_rsp_uram_v (s5_rsp_uram_v), // 64 bits
        .i_rsp_uram_r (i_rsp_uram_r)
    );

  // DRIVE REGS - best practise to change them on a negative edge.
  initial begin
    i_rst_v       <= 0;
    i_rst_sid     <= 0;
    i_rst_ea      <= 0;
    o_rst_r       <= 0;
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_l1_addr_r   <= 0;
    o_l2_addr_r   <= 0;
    //o_req_r       <= 0;
    //i_rsp_v       <= 0;
    //i_rsp_sid     <= 0;
    #102;

    // Set interfaces to be ready.
    o_rst_r       <= {nstrms{1'b1}};
    o_l1_addr_r   <= {nports{1'b1}};
    o_l2_addr_r   <= {channels{1'b1}};
    #8;

    // Reset stream 1 with EA = 16.
    i_rst_v       <= 1;
    i_rst_sid     <= 1;
    i_rst_ea      <= 16;
    #4;
    i_rst_v       <= 0;
    i_rst_sid     <= 0;
    i_rst_ea      <= 0;
    #140;

    // Read after L1 has fully reset.
    // TODO: tests;
    // - multiple concurrent reads
    // - read while L1 is not fully reset
    // - read before a stream has been reset

    // Read stream 1 from port 0.
    i_rd_v        <= 8'b00000001;
    i_rd_sid      <= 48'h000000000001;
    #8;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #12;

    // Read stream 1 from port 0 and 1.
    i_rd_v        <= 8'b00000011;
    i_rd_sid      <= 48'h000000000041;
    #8;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #12;

    // Read stream 1 from port 0 and 2.
    i_rd_v        <= 8'b00000101;
    i_rd_sid      <= 48'h000000000042; // NOTE: should be 41
    #8;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #500;







    // TODO: test what happens if L1 keeps reading from L2. Will the number of outstanding requests (counter) surpaass 256?

    // Terminate testbench.
    i_rst_v       <= 0;
    i_rst_sid     <= 0;
    i_rst_ea      <= 0;
    o_rst_r       <= 0;
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_l1_addr_r   <= 0;
    o_l2_addr_r   <= 0;
    //o_req_r       <= 0;
    //i_rsp_v       <= 0;
    //i_rsp_sid     <= 0;
  end

endmodule // apl_top_tb
