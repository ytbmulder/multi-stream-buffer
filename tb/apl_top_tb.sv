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
  parameter l2_ncl                      = 128;                // TODO: change in the future. // Number of L2 cache lines per stream.
  parameter l2_ncl_width                = $clog2(l2_ncl);
  parameter channels                    = 2;                  // nstrms/l2_nstrms
  parameter channels_width              = $clog2(channels);
  parameter ra_out_width                = channels_width+l2_nstrms_width; // o_ra width.
  parameter L2_RAM_DEPTH              = 4096;
  parameter L2_RAM_DEPTH_WIDTH        = $clog2(L2_RAM_DEPTH);

  // SETUP
  reg clk1x;
  reg clk2x;
  reg reset;

  always begin
    clk1x <= 1'b1;
    #(2.0);
    clk1x <= 1'b0;
    #(2.0);
  end

  always begin
    clk2x <= 1'b1;
    #(1.0);
    clk2x <= 1'b0;
    #(1.0);
  end

  initial begin
    clk1x = 0;
    clk2x = 0;
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

    $display(); // Print empty line.
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
  wire [nports*ra_out_width-1:0]        o_rd_sid;

  // L2 WRITE INTERFACE
  reg                                         i_we;
  reg [L2_RAM_DEPTH_WIDTH+channels_width-1:0] i_wa;
  reg [WAYS*DATA_WIDTH-1:0]                   i_wd;

  // L2 READ INTERFACE
  wire [channels-1:0]                   o_l2_addr_v;
  wire [channels-1:0]                   o_l2_addr_r;
  wire [channels*l2_nstrms_width-1:0]   o_l2_addr_sid;
  wire [channels*l2_ncl_width-1:0]      o_l2_addr_ptr;

  // OPENCAPI 3.0 REQUEST INTERFACE
  wire                                  o_req_v;
  reg                                   o_req_r;
  wire [nstrms_width-1:0]               o_req_sid;
  wire [addr_width-1:0]                 o_req_ea;

  // OPENCAPI 3.0 RESPONSE INTERFACE
  reg                                   i_rsp_v;
  wire                                  i_rsp_r;
  reg  [nstrms_width-1:0]               i_rsp_sid;



  // L2 write interface register and MUX.
  wire [L2_RAM_DEPTH_WIDTH+channels_width-1:0] s1_wa;
  wire [WAYS*DATA_WIDTH-1:0] s1_wd;
  wire s1_reg_v, s1_reg_r;
  base_areg # ( .lbl(3'b110),.width(L2_RAM_DEPTH_WIDTH+channels_width+WAYS*DATA_WIDTH)) write_reg (
      .clk(clk2x),.reset(reset),
      .i_v(i_we),.i_r(),
      .i_d({i_wa, i_wd}),
      .o_v(s1_reg_v),.o_r(s1_reg_r),
      .o_d({s1_wa, s1_wd})
  );

  // Select decode module for the MUX.
  wire [channels-1:0] s1_ch_dec;
  base_decode_le#(.enc_width(channels_width),.dec_width(channels)) is1_rsp_dec (
    .din        (s1_wa[L2_RAM_DEPTH_WIDTH+channels_width-1]),
    .dout       (s1_ch_dec),
    .en         (1'b1)
  );

  // Send response to L1 stream from L2 URAM.
  wire [channels-1:0] i_we_dec;
  base_ademux # (
    .ways(channels)
  ) is1_rsp_demux_bla (
    .i_v(s1_reg_v),
    .i_r(s1_reg_r),
    .sel(s1_ch_dec),
    .o_v(i_we_dec),
    .o_r(2'b11)
  );



  // HOST INTERFACE
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



  // Generate URAM modules for L2.
  wire [nstrms-1:0] i_rsp_uram_v, i_rsp_uram_r;
  wire [channels-1:0] s1_l1_we;
  wire [channels*ADDR_WIDTH-1:0] s1_l1_wa;
  wire [channels*WAYS*DATA_WIDTH-1:0] s1_l1_wd;
  genvar gg;
  generate
    for(gg=0; gg<channels; gg=gg+1) begin : GEN_URAM
      uram_top IDUT (
        .clk1x          (clk1x),
        .clk2x          (clk2x),
        .reset          (reset),

        .i_l2_addr_v    (o_l2_addr_v[gg]),
        .i_l2_addr_r    (o_l2_addr_r[gg]),
        .i_l2_addr_sid  (o_l2_addr_sid[(gg+1)*l2_nstrms_width-1:gg*l2_nstrms_width]),
        .i_l2_addr_ptr  (o_l2_addr_ptr[(gg+1)*l2_ncl_width-1:gg*l2_ncl_width]),

        .o_rsp_v        (i_rsp_uram_v[(gg+1)*l2_nstrms-1:gg*l2_nstrms]),
        .o_rsp_r        (i_rsp_uram_r[(gg+1)*l2_nstrms-1:gg*l2_nstrms]),

        .o_we           (s1_l1_we[gg]),
        .o_wa           (s1_l1_wa[(gg+1)*ADDR_WIDTH-1:gg*ADDR_WIDTH]),
        .o_wd           (s1_l1_wd[(gg+1)*WAYS*DATA_WIDTH-1:gg*WAYS*DATA_WIDTH]),

        .i_we           (i_we_dec[gg]),
        .i_wa           (s1_wa[L2_RAM_DEPTH_WIDTH-1:0]),
        .i_wd           (s1_wd)
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
    .o_rd_sid       (o_rd_sid),

    .o_l2_addr_v    (o_l2_addr_v),
    .o_l2_addr_r    (o_l2_addr_r),
    .o_l2_addr_sid  (o_l2_addr_sid),
    .o_l2_addr_ptr  (o_l2_addr_ptr),

    .i_we           (s1_l1_we), // Write to L1.
    .i_wa           (s1_l1_wa),
    .i_wd           (s1_l1_wd),

    .o_req_v        (s1_req_v),
    .o_req_r        (s1_req_r),
    .o_req_sid      (s1_req_sid),
    .o_req_ea       (o_req_ea),

    .i_rsp_v        (s2_rsp_v),
    .i_rsp_r        (s2_rsp_r),
    .i_rsp_sid      (s2_rsp_sid),

    .i_rsp_uram_v   (i_rsp_uram_v),
    .i_rsp_uram_r   (i_rsp_uram_r)
  );



  // Reset begin and end addresses determine the write addresses.
  parameter rst_ea_b = 0;
  parameter rst_ea_e = 384; // Means I will read 384 cache lines of 128B.

  // TODO: write in thesis: ocapi probably supplies data as first half and second half. my buffer requires a rearrangement of that data. the reason is the chosen memory organisation. ideally you want to write the first half in one half cycle, and the other half in the second half cycle. However, in order to utilise BRAM primitives fully, a single element in divided over two entries within the same BRAM. Therefore a rearrangement is required.

  // Parameters for data generation.
  localparam number_of_cache_lines   = rst_ea_e - rst_ea_b;
  localparam number_of_elements      = number_of_cache_lines * WAYS;
  localparam number_of_half_elements = number_of_elements * 2;

  // Generate half-element data set.
  integer i, nx, ny;
  reg [DATA_WIDTH-1:0] data [0:nstrms*number_of_half_elements-1];
  initial begin
    for( i=0; i<nstrms*number_of_half_elements; i=i+1 ) begin
      data[i] = i; // TODO: in the future use: data[i] = $urandom;
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
  end

  // Task to write from HOST to URAM.
  task l2_write;
    input [L2_RAM_DEPTH_WIDTH+channels_width-1:0] address;
    input [WAYS*DATA_WIDTH-1:0]                   data;
    begin
      @ (negedge clk2x);
        i_we = 1'b1;
        i_wa = address;
        i_wd = data;
    end
  endtask

  // Write task to write full cache line. Calls l1_write task twice.
  reg [addr_width-1:0] task_counter [0:nstrms-1];
  integer tsk_cntr_int;

  // Initialise task_counter offsets, depending on the stream number.
  initial begin
    for( tsk_cntr_int=0; tsk_cntr_int<nstrms; tsk_cntr_int=tsk_cntr_int+1 ) begin
      task_counter[tsk_cntr_int] = tsk_cntr_int * 2 * number_of_cache_lines;
    end
  end

  task l2_write_cache_line;
    input [nstrms_width-1:0] stream;
    input [l2_ncl_width-1:0] line;
    begin

      // Write even half-element data.
      l2_write( {stream, line, 1'b0}, half_cache_line[task_counter[stream]] );
      // Increment global counter.
      task_counter[stream] = task_counter[stream] + 1;

      // Write odd half-element data.
      l2_write( {stream, line, 1'b1}, half_cache_line[task_counter[stream]] );
      // Increment global counter.
      task_counter[stream] = task_counter[stream] + 1;

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
      #4;
    end
  endtask

  // Task to functionally reset a stream.
  // TODO: have inputs for rst_ea_b and rst_ea_e as well.
  task tsk_func_rst;
    input [nstrms_width-1:0] sid;
    begin
      i_rst_v       <= 1'b1;
      i_rst_sid     <= sid;
      i_rst_ea_b    <= rst_ea_b * 128; // EA increments per 128B.
      i_rst_ea_e    <= rst_ea_e * 128;
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
  reg [addr_width-1:0] verify_counter [0:nstrms];
  integer ww;
  initial begin
    for( ww=0; ww<nstrms; ww=ww+1 ) begin
      verify_counter[ww] = ww*number_of_half_elements;
    end
  end

  reg [2*DATA_WIDTH-1:0] rd_d, test_d;
  reg comparison [0:nstrms-1];
  genvar qq;
  generate
    for( qq=0; qq<nstrms; qq=qq+1 ) begin
      always @ (negedge clk1x) begin
        if( o_rd_v == 1'b1 ) begin
          if( o_rd_sid == qq ) begin
            rd_d = o_rd_d;
            test_d = {data[verify_counter[qq]+1], data[verify_counter[qq]]};
            comparison[qq] = (rd_d == test_d);
            //if( comparison[qq] === 1'b1 ) begin // === Also takes X and Z into account.
            //  $display( "%0d - Stream %0d CORRECT!", $time-2, qq );
            //end
            if( comparison[qq] !== 1'b1 ) begin // === Also takes X and Z into account.
              $display( "%0d - Stream %0d ERROR!", $time-2, qq );
              $display( "Expected = %h", test_d );
              $display( "Output   = %h", rd_d );
            end
            verify_counter[qq] = verify_counter[qq] + 2;
          end
        end
      end
    end
  endgenerate

  // Count the number of AFU read requests and responses made.
  integer rd_req_counter [0:nstrms-1];
  integer rd_v_req_counter [0:nstrms-1];
  integer rd_rsp_counter [0:nstrms-1];
  integer rd_v_rsp_counter [0:nstrms-1];
  integer rd_req_int;
  initial begin
    for(rd_req_int=0; rd_req_int<nstrms; rd_req_int=rd_req_int+1) begin
      rd_req_counter[rd_req_int] = 0; // Number of accepted read requests.
      rd_rsp_counter[rd_req_int] = 0; // Number of accepted read responses.
      rd_v_req_counter[rd_req_int] = 0;
      rd_v_rsp_counter[rd_req_int] = 0;
    end
  end

  genvar yy;
  generate
    // TODO: for loop not needed, just as with BRAM channel write task calling.
    // TODO: finish coding of rsp_v counter for not all response have been accepted.
    for( yy=0; yy<nstrms; yy=yy+1 ) begin
      always @ (negedge clk1x) begin
        // Increment counter if a read request has been accepted.
        if( (i_rd_v & i_rd_r) === 1'b1 ) begin
          if( i_rd_sid == yy ) begin
            rd_req_counter[yy] = rd_req_counter[yy] + 1;
          end
        end

        // Increment counter if a read request has been made.
        if( i_rd_v === 1'b1 ) begin
          if( i_rd_sid == yy ) begin
            rd_v_req_counter[yy] = rd_v_req_counter[yy] + 1;
          end
        end

        // Increment counter if a read response has been received.
        if( (o_rd_v & o_rd_r) === 1'b1 ) begin
          if( o_rd_sid == yy ) begin
            rd_rsp_counter[yy] = rd_rsp_counter[yy] + 1;
          end
        end
      end
    end
  endgenerate

  // Test for concurrent channel writing.
  always @ (negedge clk1x) begin
    if(o_l2_addr_v == 2'b11)
      $display("%0d - CONCURRENT CHANNEL WRITE!", $time );
  end



  // HOST WRITE BEHAVIOUR MODEL
  // Initialise l1_counters depending on the stream number.
  reg [addr_width-1:0] l1_counter [0:nstrms-1];
  integer rr;
  initial begin
    for(rr=0; rr<nstrms; rr=rr+1) begin
      l1_counter[rr] = rst_ea_b;
    end
  end

  integer tmp_int;
  always @ (negedge clk1x) begin
    if( (s1_req_v & s1_req_r) === 1'b1 ) begin
      // Required since s1_req_sid is not captured correctly.
      tmp_int = s1_req_sid; // Cast wire to integer.

      l2_write_cache_line( tmp_int, l1_counter[tmp_int] ); // stream, line
      l1_counter[tmp_int] = l1_counter[tmp_int] + 1;
    end
  end

  // Properly end the data to be written.
  always @ (negedge clk1x) begin
    if( (s1_req_v & s1_req_r) === 1'b0 ) begin
      #1;
      i_we <= 0;
      i_wa <= 0;
      i_wd <= 0;
      #4;
    end
  end



  // DRIVE REGS - best practise to change inputs on a negative edge.
  integer rst_sid;
  initial begin
    // Initialise all input signals as zero.
    init( 102 );

    // Set interfaces to be ready.
    rest( 8 );



    // Functionally reset all streams.
    for( rst_sid=0; rst_sid<nstrms; rst_sid=rst_sid+1 ) begin
      tsk_func_rst( rst_sid );
      rest( 100 );
    end



    // Read random streams from one read port.
    repeat( 1600*8 ) begin
      tsk_afu_rd( 1, $urandom_range( nstrms-1, 0 ) ); // enable, sid
    end

    rest( 100 );



// NOTE: OLDER TESTS, BEFORE VERIFICAITON WAS USED.
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

    // TODO: test what happens if L1 keeps reading from L2. Will the number of outstanding requests (counter) surpass 256?
*/



    // Compare the read request and response counters.
    for(rd_req_int=0; rd_req_int<nstrms; rd_req_int=rd_req_int+1) begin
      //if( rd_req_counter[rd_req_int] === rd_rsp_counter[rd_req_int] )
        //$display( "%0d - rd_cntr %0d PASS", $time, rd_req_int );
      // A read has been accepted, but was discarded. Therefore rd_req_counter is larger than rd_rsp_counter.
      if( rd_req_counter[rd_req_int] !== rd_rsp_counter[rd_req_int] )
        $display( "%0d - WARNING! STREAM %0d DISCARDED READ REQUESTS", $time, rd_req_int );

      if( (rd_v_req_counter[rd_req_int] - rd_req_counter[rd_req_int]) !== 0 )
        $display( "%0d - WARNING! STREAM %0d has %0d unaccepted i_rd_v", $time, rd_req_int, rd_v_req_counter[rd_req_int] - rd_req_counter[rd_req_int] );
    end

    // Terminate testbench.
    init( 4 );
    $display(); // Print empty line.
    $finish;
  end

endmodule // apl_top_tb
