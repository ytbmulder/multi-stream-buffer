module l1_ctrl_top_tb;

  parameter nports                = 8;                        // number of read ports
  parameter nstrms                = 64;                       // total number of streams
  parameter ncl                   = 16;                       // number of cachelines per stream
  parameter cl_size               = 8;                       // number of reads per cacheline - must be at least as big as the number of read ports
  parameter clid_width            = $clog2(ncl);              // number of bits needed to identify a cache line
  parameter clofs_width           = $clog2(cl_size);          // number of bits needed to represent an offset within a cacheline
  parameter sid_width             = $clog2(nstrms);          // number of bits needed to represent the number of streams
  parameter ptr_width             = clid_width+clofs_width;   // number of bits needed to represent a stream pointer
  parameter channels              = 4;                         // 64 streams / 16 streams / BRAM tile = 4 blocks

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
    #2000;
    $finish;
  end

  initial begin
    reset = 1;
    #102;
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
  reg [nstrms-1:0] i_rst_v;
  wire [nstrms-1:0] i_rst_r;
  reg [nstrms*clid_width-1:0] i_rst_ea_b;
  reg [nstrms-1:0] i_rst_end;

  wire [nstrms-1:0] o_rst_v;
  reg [nstrms-1:0] o_rst_r;

  reg  [nports-1:0] i_rd_v;
  wire [nports-1:0] i_rd_r;
  reg  [nports*sid_width-1:0] i_rd_sid;

  wire [nports-1:0] o_addr_v;
  reg  [nports-1:0] o_addr_r;
  wire [nports*ptr_width-1:0] o_addr_ptr;
  wire [nports*sid_width-1:0] o_addr_sid;

  wire [nstrms-1:0]             o_req_v;
  reg  [nstrms-1:0]             o_req_r;

  reg  [nstrms-1:0]             i_rsp_v;
  wire [nstrms-1:0]             i_rsp_r;

  // Input after reg.
  wire [nstrms-1:0] s0_rst_v;
  wire [nstrms*clid_width-1:0] s0_rst_ea_b;
  wire [nstrms-1:0] s0_rst_end;
  wire [nstrms-1:0] s0_rst_r;
  wire [nports-1:0] s0_rd_v;
  wire [nports*sid_width-1:0] s0_rd_sid;
  wire [nports-1:0] s0_addr_r;
  wire [nstrms-1:0] s0_req_r;
  wire [nstrms-1:0] s0_rsp_v;

  // TODO: add reset interfaces since I removed that from the *_top.sv file.
  // REGISTER INPUTS
  base_delay # (
    .width(nstrms+nstrms*clid_width+nstrms+nstrms+nports+nports*sid_width+nports),
    .n(1)
    ) is0_input_delay (.clk(clk),.reset(reset),
    .i_d ({ i_rst_v,  i_rst_ea_b,  i_rst_end,  o_rst_r,  i_rd_v,  i_rd_sid,  o_addr_r}),
    .o_d ({s0_rst_v, s0_rst_ea_b, s0_rst_end, s0_rst_r, s0_rd_v, s0_rd_sid, s0_addr_r})
  );

    // Loop back req and rsp for L2.
    wire [nstrms-1:0] s1_req_v, s1_req_r, s2_rsp_v, s2_rsp_r;
    genvar i;
    generate
        for(i=0; i<nstrms; i=i+1) begin : gen_loop_back
           base_areg#(.lbl(3'b110),.width(1)) is2_tile_req_reg
        (.clk(clk),.reset(reset),
         .i_v(s1_req_v[i]),.i_r(s1_req_r[i]),.i_d(1'b0),
         .o_v(s2_rsp_v[i]),.o_r(s2_rsp_r[i]),.o_d());
        end
    endgenerate

    // DUT
    l1_ctrl_top IDUT (
        .clk                (clk),
        .reset              (reset),

        .i_rst_v            (s0_rst_v),
        .i_rst_r            (i_rst_r),
        .i_rst_ea_b         (s0_rst_ea_b),
        .i_rst_end          (s0_rst_end),

        .o_rst_v            (o_rst_v),
        .o_rst_r            (s0_rst_r),

        .i_rd_v             (s0_rd_v),
        .i_rd_r             (i_rd_r),
        .i_rd_sid           (s0_rd_sid),

        .o_addr_v           (o_addr_v),
        .o_addr_r           (s0_addr_r),
        .o_addr_ptr         (o_addr_ptr),
        .o_addr_sid         (o_addr_sid),

        .o_req_v            (s1_req_v),
        .o_req_r            (s1_req_r),

        .i_rsp_v            (s2_rsp_v),
        .i_rsp_r            (s2_rsp_r)
    );

  // DRIVE INPUTS - best practise to change them on a negative edge.
  initial begin
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    o_rst_r       <= 0;
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_addr_r      <= 0;
    #102;

    // Set interfaces to be ready.
    o_rst_r       <= {nstrms{1'b1}};
    o_addr_r      <= {nports{1'b1}};
    #8;

    // TODO: test what happens if you start reading before all 16 cache lines have been received from L2.
    // TODO: test if new cache line from L2 is requested immediately when a boundary is crossed. should request when 7th element is requested.
    // TODO: is the correct o_addr_ptr still calculated if not the o_addr_r is not ready, but the rd_port o_req_r signal is not ready.

/*
    // TODO: if you read before functionally resetting, the read will be discarded.
    // In this case, the second read lines up after the reset and is therefore serviced.
    // Test read before functional reset.
    // Read stream 1 from port 0.
    i_rd_v        <= 8'b00000010;
    i_rd_sid      <= 48'h000000000040;
    #8;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #16;
*/

    // Reset stream 1.
    i_rst_v       <= 2;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 2;
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #100;

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
    i_rd_sid      <= 48'h000000000041;
    #8;
    // Reset stream 0
    i_rst_v       <= 1;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 1;
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #8;

    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #16;

    // Read stream 0 from port 2.
    i_rd_v        <= 8'b00000100;
    i_rd_sid      <= 48'h000000000041;
    #16;

    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #16;

    // Read stream 5 from port 1 and 2.
    // This stream has not been reset, thus should do nothing.
    i_rd_v        <= 8'b00000110;
    i_rd_sid      <= 48'h000000005140;
    #4;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #16;
    // Reset stream 5.
    i_rst_v       <= 32;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 32;
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #100;

    // Test requesting two streams (6 and 7) which have not been reset yet.
    // Then reset one and see if that one produces an o_addr_v.
    i_rd_v        <= 8'b00001111; // Test with two requests per stream
    i_rd_sid      <= 48'h000000187187;
    #4;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #16;
    // Reset stream 6.
    i_rst_v       <= 64;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 64;
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #40;
    // Reset stream 7.
    // Test if one read port is not ready but the other one is, while requesting from the same stream.
    i_rst_v       <= 128;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 128;
    o_addr_r      <= 8'b11111110; // Test if o_addr_ptr is correct when one read port is not ready.
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #20;
    o_addr_r      <= 8'b11111111;
    #100;

    // End of stream 1 test.
    i_rst_end     <= 2;
    #4;
    i_rd_v        <= 8'b00000001;
    i_rd_sid      <= 48'h000000000001;
    #24;
    #444;
    #28;
    i_rd_v        <= 8'b00000011;
    i_rd_sid      <= 48'h000000000041; // TODO: implement output rst_v/stream_end signal. then see if i need to allow for reads in order to not get into a deadlock for a read port.
    // TODO: probably best to just accept a read but not produce a valid output.
    // TODO: also check about the valid output to l1_stream_ptr. should not update global ptr. however, in this case it doesnt matter anymore what the global ptr's value is since the stream has ended anyway.
    #16;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #12;

    // Reset stream 1 for the second time.
    i_rst_v       <= 2;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 2;
    #4;
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    #4;

    #16;

    // Terminate testbench.
    i_rst_v       <= 0;
    i_rst_ea_b    <= 0;
    i_rst_end     <= 0;
    o_rst_r       <= 0;
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_addr_r      <= 0;
  end

endmodule // l1_ctrl_top_tb
