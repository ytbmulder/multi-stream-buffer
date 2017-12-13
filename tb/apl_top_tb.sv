module apl_top_tb;

  // Host parameters
  parameter addr_width                  = 64;                 // Host address width in bits.
  parameter cache_line                  = 128;                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line);

  // Stream cache parameters
  parameter nstrms                      = 32;
  parameter nstrms_width                = $clog2(nstrms);
  parameter nports                      = 1;                  // Number of L1 read ports.
  parameter cl_size                     = 8;                  // number of reads per cacheline - must be at least as big as the number of read ports
  parameter DATA_WIDTH                  = 8*8;                // 8 bytes per element
  parameter RAM_DEPTH                   = 512;                // double pump -> 256 16B
  parameter ADDR_WIDTH                  = $clog2(RAM_DEPTH);
  parameter WAYS                        = 8;                  // Number of BRAMs per cache line.

  // L1 parameters
  parameter l1_ncl                      = 16;                 // Number of L1 cache lines per stream.
  parameter l1_ncl_width                = $clog2(l1_ncl);
  parameter clofs_width                 = $clog2(cl_size);    // number of bits needed to represent an offset within a cacheline
  parameter ptr_width                   = l1_ncl_width+clofs_width; // number of bits needed to represent a stream pointer

  // L2 parameters
  parameter l2_nstrms                   = 16;
  parameter l2_nstrms_width             = $clog2(l2_nstrms);
  parameter l2_ncl                      = 256;                // Number of L2 cache lines per stream.
  parameter l2_ncl_width                = $clog2(l2_ncl);
  parameter channels                    = 2;                  // nstrms/l2_nstrms
  parameter channels_width              = $clog2(channels);

  // SETUP
  reg clk1x;
  reg clk2x;
  reg reset;

  always
  begin
    clk1x <= 1'b1;
    #(2.0);
    clk1x <= 1'b0;
    #(2.0);
  end

  always
  begin
    clk2x <= 1'b1;
    #(1.0);
    clk2x <= 1'b0;
    #(1.0);
  end

  initial
  begin
    clk1x = 0;
    clk2x = 0;
    #16000;
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
      $dumpfile("apl_top_tb.vcd");
      $dumpvars(0, apl_top_tb);
    `endif
  end

  // SIGNAL DECLARATIONS
  // FUNCTIONAL STREAM RESET reg INTERFACE
  reg                                   i_rst_v;
  wire                                  i_rst_r;
  reg  [nstrms_width-1:0]               i_rst_sid;
  reg  [addr_width-1:0]                 i_rst_ea_b;
  reg  [addr_width-1:0]                 i_rst_ea_e;

  // FUNCTIONAL STREAM RESET wire INTERFACE
  wire [nstrms-1:0]                     o_rst_v;
  reg  [nstrms-1:0]                     o_rst_r;
  wire [nstrms-1:0]                     o_rst_end;

  // AFU READ INTERFACE
  reg  [nports-1:0]                     i_rd_v;
  wire [nports-1:0]                     i_rd_r;
  reg  [nports*nstrms_width-1:0]        i_rd_sid;

  // AFU READ DATA INTERFACE
  wire [nports-1:0]                     o_rd_v;
  reg  [nports-1:0]                     o_rd_r;
  wire [nports*2*DATA_WIDTH-1:0]        o_rd_d;

/*
  // L1 READ INTERFACE
  wire [nports-1:0]                     o_l1_addr_v;
  reg  [nports-1:0]                     o_l1_addr_r;
  wire [nports*nstrms_width-1:0]        o_l1_addr_sid;
  wire [nports*ptr_width-1:0]           o_l1_addr_ptr;
*/

  // L2 READ INTERFACE
  wire [channels-1:0]                   o_l2_addr_v;
  reg  [channels-1:0]                   o_l2_addr_r;
  wire [channels*l2_nstrms_width-1:0]   o_l2_addr_sid;
  wire [channels*l2_ncl_width-1:0]      o_l2_addr_ptr;

  // L2 WRITE INTERFACE
  reg  [channels-1:0]                   i_we;
  reg  [channels*ADDR_WIDTH-1:0]        i_wa;
  reg  [channels*WAYS*DATA_WIDTH-1:0]   i_wd;

  // OPENCAPI 3.0 REQUEST INTERFACE
  wire                                  o_req_v;
  reg                                   o_req_r;
  wire [nstrms_width-1:0]               o_req_sid;
  wire [addr_width-1:0]                 o_req_ea;

  // OPENCAPI 3.0 RESPONSE INTERFACE
  reg                                   i_rsp_v;
  wire                                  i_rsp_r;
  reg  [nstrms_width-1:0]               i_rsp_sid;

  // TODO: remove in future iteration
  reg  [nstrms-1:0]                     i_rsp_uram_v;
  wire [nstrms-1:0]                     i_rsp_uram_r;

/*
  // after reg
  wire s0_rst_v;
  wire [nstrms_width-1:0] s0_rst_sid;
  wire [addr_width-1:0] s0_rst_ea_b;
  wire [addr_width-1:0] s0_rst_ea_e;
  wire [nstrms-1:0]  s0_rst_r;
  wire [nports-1:0] s0_rd_v;
  wire [nports*nstrms_width-1:0] s0_rd_sid;
  wire [nports-1:0] s0_l1_addr_r;
  wire [channels-1:0]  s0_l2_addr_r;
  wire s0_req_r;
  wire s0_rsp_v;
  wire [nstrms_width-1:0]  s0_rsp_sid;
//    wire [nstrms-1:0] s0_rsp_uram_v;

  // REGISTERS
  base_delay # (
    .width(1+nstrms_width+2*addr_width+nstrms+nports+nports*nstrms_width+nports+channels+1+1+nstrms_width),
    .n(1)
  ) is0_reg_delay (
    .clk (clk),
    .reset (reset),
    .i_d ({ i_rst_v,  i_rst_sid,  i_rst_ea_b,  i_rst_ea_e,  o_rst_r,  i_rd_v,  i_rd_sid,  o_l1_addr_r,  o_l2_addr_r,  o_req_r,  i_rsp_v, i_rsp_sid}),
    .o_d ({s0_rst_v, s0_rst_sid, s0_rst_ea_b, s0_rst_ea_e, s0_rst_r, s0_rd_v, s0_rd_sid, s0_l1_addr_r, s0_l2_addr_r, s0_req_r, s0_rsp_v, s0_rsp_sid})
  );
*/

  // For o_l2_addr_r.
  wire [channels-1:0] s0_l2_addr_r;
  base_delay # (
    .width  (channels),
    .n      (1)
  ) is0_reg_delay (
    .clk    (clk1x),
    .reset  (reset),
    .i_d    (o_l2_addr_r),
    .o_d    (s0_l2_addr_r)
  );

  // Loop back req and rsp for OpenCAPI 3.0.
  wire                       s1_req_v;
  wire                       s1_req_r;
  wire [nstrms_width-1:0]    s1_req_sid;

  wire                       s2_rsp_v;
  wire                       s2_rsp_r;
  wire [nstrms_width-1:0]    s2_rsp_sid;

  // This register acts as the host sending a response back to the APL.
  base_areg # ( .lbl(3'b110),.width(nstrms_width)) is0_req_reg (
      .clk(clk1x),.reset(reset),
      .i_v(s1_req_v),.i_r(s1_req_r),.i_d(s1_req_sid),
      .o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d(s2_rsp_sid)
  );

/*
  integer l1_counter [0:nstrms-1];
  initial begin
    l1_counter[1] = rst_ea_b; // stream 1
    l1_counter[7] = rst_ea_b; // stream 7
  end
*/
  integer l1_counter = rst_ea_b;

  // Send response to L1 stream from L2 URAM.
  wire [nstrms-1:0] s5_rsp_uram_v;
  genvar k;
  generate
    for(k=0; k<channels; k=k+1) begin : GEN_DINGES
      wire [l2_nstrms_width-1:0] s1_rsp_sid_enc = o_l2_addr_sid[(k+1)*l2_nstrms_width-1:k*l2_nstrms_width];
      wire [l2_nstrms-1:0] s1_rsp_sid_dec;
      base_decode_le#(.enc_width(l2_nstrms_width),.dec_width(l2_nstrms)) is1_rsp_dec (
        .din        (s1_rsp_sid_enc),
        .dout       (s1_rsp_sid_dec),
        .en         (1'b1)
      );
      wire v, r;
      wire [l2_nstrms-1:0] s2_rsp_sid_dec;
      base_areg # ( .lbl(3'b110),.width(16)) is0_req_ding_reg (
        .clk(clk1x),.reset(reset),
        .i_v(o_l2_addr_v[k]),.i_r(s0_l2_addr_r[k]),.i_d(s1_rsp_sid_dec),
        .o_v(v),.o_r(r),.o_d(s2_rsp_sid_dec)
      );

      // Write new data from L2 to L1.
      // TODO: use o_l2_addr_act instead of _v. However, _r == 1'b1 by default.
      // TODO: fix properly for multiple read ports.
      always @ (posedge clk1x) begin
        if( o_l2_addr_v[k] == 1'b1 ) begin
          //$display( "%0d - TEST %d", $time, k );
        //  $display( "l1_counter[%0d] = %0d", s1_rsp_sid_enc, l1_counter[s1_rsp_sid_enc] );
        //  l1_write_cache_line( k, s1_rsp_sid_enc, l1_counter[s1_rsp_sid_enc] % l1_ncl ); // channel, stream, line
        //  l1_counter[s1_rsp_sid_enc] = l1_counter[s1_rsp_sid_enc] + 1;

        l1_write_cache_line( k, 1, l1_counter % l1_ncl ); // channel, stream, line
        l1_counter = l1_counter + 1;
        end
      end

      // Properly end the data to be written.
      // TODO: use o_l2_addr_act instead of _v. However, _r == 1'b1 by default.
      // TODO: fix properly for multiple read ports.
      always @ (negedge clk1x) begin
        if( o_l2_addr_v[k] == 1'b0 ) begin
          //$display( "%0d - L1 rsp LOW", $time );
          #3;
          i_we <= 0;
          i_wa <= 0;
          i_wd <= 0;
          #4;
        end
      end

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
  apl_top # (
    .addr_width     (addr_width),
    .cache_line     (cache_line),
    .nstrms         (nstrms),
    .nports         (nports),
    .cl_size        (cl_size),
    .DATA_WIDTH     (DATA_WIDTH),
    .RAM_DEPTH      (RAM_DEPTH),
    .WAYS           (WAYS),
    .l1_ncl         (l1_ncl),
    .l2_nstrms      (l2_nstrms),
    .l2_ncl         (l2_ncl),
    .channels       (channels)
    ) IDUT (
    .clk1x          (clk1x),
    .clk2x          (clk2x),
    .reset          (reset),

    .i_rst_v        (i_rst_v),
    .i_rst_r        (i_rst_r),
    .i_rst_sid      (i_rst_sid),
    .i_rst_ea_b     (i_rst_ea_b),
    .i_rst_ea_e     (i_rst_ea_e),

    .o_rst_v        (o_rst_v),
    .o_rst_r        (o_rst_r),
    .o_rst_end      (o_rst_end),

    .i_rd_v         (i_rd_v),
    .i_rd_r         (i_rd_r),
    .i_rd_sid       (i_rd_sid),

    .o_rd_v         (o_rd_v),
    .o_rd_r         (o_rd_r),
    .o_rd_d         (o_rd_d),

/*
    .o_l1_addr_v    (o_l1_addr_v),
    .o_l1_addr_r    (s0_l1_addr_r),
    .o_l1_addr_sid  (o_l1_addr_sid),
    .o_l1_addr_ptr  (o_l1_addr_ptr),
*/

    .o_l2_addr_v    (o_l2_addr_v),
    .o_l2_addr_r    (o_l2_addr_r),
    .o_l2_addr_sid  (o_l2_addr_sid),
    .o_l2_addr_ptr  (o_l2_addr_ptr),

    .i_we           (i_we),
    .i_wa           (i_wa),
    .i_wd           (i_wd),

    .o_req_v        (s1_req_v),
    .o_req_r        (s1_req_r),
    .o_req_sid      (s1_req_sid),
    .o_req_ea       (o_req_ea),

    .i_rsp_v        (s2_rsp_v),
    .i_rsp_r        (s2_rsp_r),
    .i_rsp_sid      (s2_rsp_sid),

    .i_rsp_uram_v   (s5_rsp_uram_v),
    .i_rsp_uram_r   (i_rsp_uram_r)
  );

/*
  wire [DATA_WIDTH-1:0] tmp;
  wd_driver driver (
    .clk    (clk2x),
    .reset  (reset),

    .i_v    (i_we[0]),

    .o_v    (),
    .o_d    (tmp)
  );
*/

  // Reset begin and end addresses determine the write addresses.
  parameter rst_ea_b = 0;
  parameter rst_ea_e = 384; // Means I will read 384 cache lines of 128B.

  // TODO: write in thesis: ocapi probably supplies data as first half and second half. my buffer requires a rearrangement of that data. the reason is the chosen memory organisation. ideally you want to write the first half in one half cycle, and the other half in the second half cycle. However, in order to utilise BRAM primitives fully, a single element in divided over two entries within the same BRAM. Therefore a rearrangement is required.

  // Parameters for data generation.
  localparam number_of_cache_lines = rst_ea_e - rst_ea_b;
  localparam number_of_half_elements = number_of_cache_lines * 2 * WAYS;

  // Generate half-element data set.
  integer i, nx, ny;
  reg [DATA_WIDTH-1:0] data [0:nstrms*number_of_half_elements-1];
  initial begin
    for( i=0; i<nstrms*number_of_half_elements; i=i+1 ) begin
      data[i] = i;
      //$display("data[%0d] = %d", i, data[i] );
    end
  end

  // Generate even and odd half-element cache line data set.
  // Note that half cache line consists of either even or odd indices.
  // cache line odd  = {data[15], ..., data[7], data[5], data[3], data[1]}
  // cache line even = {data[14], ..., data[6], data[4], data[2], data[0]}
  reg [WAYS*DATA_WIDTH-1:0] half_cache_line [0:nstrms*2*number_of_cache_lines-1];
  initial begin
    for( nx=0; nx<nstrms*2*number_of_cache_lines; nx=nx+2 ) begin : nxx
      // EVEN
      half_cache_line[nx] = {data[14+WAYS*nx], data[12+WAYS*nx], data[10+WAYS*nx], data[8+WAYS*nx], data[6+WAYS*nx], data[4+WAYS*nx], data[2+WAYS*nx], data[0+WAYS*nx]};
      //$display( "even[%0d] = %h", nx, half_cache_line[nx]);
    end
    for( ny=0; ny<nstrms*2*number_of_cache_lines; ny=ny+2 ) begin : nyx
      // ODD
      half_cache_line[ny+1] = {data[15+WAYS*ny], data[13+WAYS*ny], data[11+WAYS*ny], data[9+WAYS*ny], data[7+WAYS*ny], data[5+WAYS*ny], data[3+WAYS*ny], data[1+WAYS*ny]};
      //$display( "odd[%0d] = %h", ny+1, half_cache_line[ny+1]);
    end

    //for( i=0; i<2*number_of_cache_lines; i=i+1 )
    //  $display( "half_cache_line[%0d] = %b", i, half_cache_line[i] );
  end

  // L1 Write Task (generic write task).
  task l1_write;
    input [channels_width-1:0]  channel;
    input [ADDR_WIDTH-1:0]      address;
    input [WAYS*DATA_WIDTH-1:0] data;
    begin
      //$display("%g CPU Write task with address : %h Data : %h", $time, address, data);
      //$display("%g  -> Driving CE, WR, WR data and ADDRESS on to bus", $time);
      @ (negedge clk2x);
        i_we[channel] = 1'b1;
        i_wa = address << (channel*ADDR_WIDTH);
        //$display("addr = %b, addr shift = %b", address, tmp);
        i_wd = data << (channel*WAYS*DATA_WIDTH);
        //$display("======================");
    end
  endtask

  // Write task to write full cache line. Calls l1_write task twice.
  integer counter [0:nstrms-1];
  initial begin
    counter[1] = 1*2*number_of_cache_lines;
    //$display("%0d - counter 1", $time, counter[1]);
    counter[7] = 7*2*number_of_cache_lines;
    //$display("%0d - counter 7", $time, counter[7]);
  end

  task l1_write_cache_line;
    input [channels_width-1:0]  channel;
    input [nstrms_width-1:0]    stream;
    input [l1_ncl_width-1:0]    line;
    begin

      //$display( "%0d - l1_wr_cl() - counter[stream] = %0d - half_cl = %0h", $time, counter[stream], half_cache_line[counter[stream]] );

      // Write even half-element data.
      l1_write( channel, {stream, line, 1'b0}, half_cache_line[counter[stream]] );
      // Increment global counter.
      counter[stream] = counter[stream] + 1;

      // Write odd half-element data.
      l1_write( channel, {stream, line, 1'b1}, half_cache_line[counter[stream]] );
      // Increment global counter.
      counter[stream] = counter[stream] + 1;
    end
  endtask

  // Task for the "Rest" case.
  // - delay determines the number of time steps of this task.
  task rest;
    input integer delay;
    begin
      i_rst_v       <= 0;
      i_rst_sid     <= 0;
      i_rst_ea_b    <= 0;
      i_rst_ea_e    <= 0;
      o_rst_r       <= {nstrms{1'b1}};
      i_rd_v        <= 0;
      i_rd_sid      <= 0;
      o_rd_r        <= {nports{1'b1}};
      //o_l1_addr_r   <= {nports{1'b1}};
      o_l2_addr_r   <= {channels{1'b1}};
      #delay;
    end
  endtask

  // Task to initialise and terminate the testbench.
  // - delay determines the number of time steps of this task.
  task init;
    input integer delay;
    begin
      i_rst_v       <= 0;
      i_rst_sid     <= 0;
      i_rst_ea_b    <= 0;
      i_rst_ea_e    <= 0;
      o_rst_r       <= 0;
      i_rd_v        <= 0;
      i_rd_sid      <= 0;
      o_rd_r        <= 0;
      //o_l1_addr_r   <= 0;
      o_l2_addr_r   <= 0;
      i_we          <= 0;
      i_wa          <= 0;
      i_wd          <= 0;
      #delay;
    end
  endtask

  // Task to issue an AFU read request.
  task tsk_afu_rd;
    input                     rd_en;
    input [nstrms_width-1:0]  sid;
    begin
      i_rst_v       <= 0;
      i_rst_sid     <= 0;
      i_rst_ea_b    <= 0;
      i_rst_ea_e    <= 0;
      o_rst_r       <= {nstrms{1'b1}};
      i_rd_v        <= 1;
      i_rd_sid      <= sid;
      o_rd_r        <= {nports{1'b1}};
      o_l2_addr_r   <= {channels{1'b1}};
      #4;
    end
  endtask

  // Display when stream starts (is reset) and finishes.
  genvar vv;
  generate
    for( vv=0; vv<nstrms; vv=vv+1 ) begin
      // Display when a stream starts.
      always @ (negedge o_rst_end[vv]) begin
        if( $time != 0 )
          $display( "%0d - Stream %0d (o_rst_end[%0d]) started", $time, vv, vv );
      end

      // Display when stream has finished.
      // TODO: check again when o_rst_end is L1 end. Now it is L2 end.
      always @ (posedge o_rst_end[vv]) begin
        if( $time != 0 )
          $display( "%0d - Stream %0d (o_rst_end[%0d]) finished", $time, vv, vv );
      end
    end
  endgenerate

  // Verify o_rd_d by comparing it to the generated data array: data.
  // data array is index using: stream * cl * 2 (double pump) * ways
  integer verify_counter = 1*number_of_half_elements; // stream 1
  reg [2*DATA_WIDTH-1:0] rd_d, test_d;
  integer comparison;
  always @ (negedge clk1x) begin
    if( o_rd_v == 1'b1 ) begin
      //$display( "%0d - o_rd_v is high - o_rd_d = %h", $time, o_rd_d );
      //$display( "data = %h", {data[verify_counter+1], data[verify_counter]} );
      rd_d = o_rd_d;
      test_d = {data[verify_counter+1], data[verify_counter]};
      comparison = (rd_d == test_d);
      //if( comparison == 1'b1 ) begin
      //  $display( "%0d - CORRECT!", $time );
      //end
      if( comparison != 1'b1 ) begin
        $display( "%0d - ERROR!", $time );
        $display( "Expected = %h", test_d );
        $display( "Output   = %h", rd_d );
        //$finish;
      end
      verify_counter = verify_counter + 2;
    end
  end
//------------------------------------------------



  // DRIVE REGS - best practise to change inputs on a negative edge.
  initial begin
    // Initialise all input signals as zero.
    init( 102 );

    // Set interfaces to be ready.
    rest( 8 );



    // Reset stream 1.
    i_rst_v       <= 1;
    i_rst_sid     <= 1;
    i_rst_ea_b    <= rst_ea_b * 128;
    i_rst_ea_e    <= rst_ea_e * 128; // EA increments per 128B.
    o_rst_r       <= {nstrms{1'b1}};
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_rd_r        <= {nports{1'b1}};
    o_l2_addr_r   <= {channels{1'b1}};
    #4;

    // Rest
    rest( 100 );

    // Reset stream 7.
    //i_rst_v       <= 1;
    i_rst_sid     <= 7;
    i_rst_ea_b    <= rst_ea_b * 128;
    i_rst_ea_e    <= rst_ea_e * 128; // EA increments per 128B.
    o_rst_r       <= {nstrms{1'b1}};
    i_rd_v        <= 0;
    i_rd_sid      <= 0;
    o_rd_r        <= {nports{1'b1}};
    o_l2_addr_r   <= {channels{1'b1}};
    #4;

    // Rest
    rest( 100 );



    // Read from stream 1.
    // 3 cache lines
    repeat( 3*8 ) begin
      tsk_afu_rd( 1, 1 ); // enable, sid
    end

    // Rest
    rest( 100 );

    // Read until end of stream.
    // 383 cache lines. this is more than rst_ea_e - _b, therefore final reads are invalidated, as expected.
    repeat( 383*8 ) begin
      tsk_afu_rd( 1, 1 ); // enable, sid
    end



/*
    // Reset stream 1 with EA = 16.
    i_rst_v       <= 1;
    i_rst_sid     <= 1;
    i_rst_ea_b    <= 128*17;    // o_rst_ea_b should be 17 mod 16 = 1
    i_rst_ea_e    <= 128*17*4;
    #4;
    i_rst_v       <= 0;
    i_rst_sid     <= 0;
    i_rst_ea_b    <= 0;
    i_rst_ea_e    <= 0;
    #140;

    // Read after L1 has fully reset.
    // TODO: tests;
    // - multiple concurrent reads
    // - read while L1 is not fully reset
    // - read before a stream has been reset

    // TODO: fix undefined o_l2_addr_r signal before reset.
    // TODO: remove one areg from i_rst path.

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
    i_rd_sid      <= 48'h000000000042;
    #32;
    i_rd_v        <= 8'b00000000;
    i_rd_sid      <= 48'h000000000000;
    #500;

    // TODO: test what happens if L1 keeps reading from L2. Will the number of outstanding requests (counter) surpaass 256?
*/



    // Terminate testbench.
    init( 4 );
  end

endmodule // apl_top_tb
