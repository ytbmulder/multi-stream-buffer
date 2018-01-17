module apl_top_tb;

  // Host parameters
  parameter addr_width                  = 64;                 // Host address width in bits.
  parameter cache_line                  = 128;                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line);

  // Stream cache parameters
  parameter nstrms                      = 32;
  parameter nstrms_width                = $clog2(nstrms);
  parameter nports                      = 2;                  // Number of L1 read ports.
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
  parameter L2_RAM_DEPTH                = 4096;
  parameter L2_RAM_DEPTH_WIDTH          = $clog2(L2_RAM_DEPTH);

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
  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  reg                                   i_rst_v;
  wire                                  i_rst_r;
  reg  [nstrms_width-1:0]               i_rst_sid;
  reg  [addr_width-1:0]                 i_rst_ea_b;
  reg  [addr_width-1:0]                 i_rst_ea_e;

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  wire [nstrms-1:0]                     o_rst_v;
  reg  [nstrms-1:0]                     o_rst_r;
  wire [nstrms-1:0]                     o_rst_end;

  // AFU READ INTERFACE
  reg  [nports-1:0]                     i_rd_v;
  wire [nports-1:0]                     i_rd_r;
  reg  [nstrms_width-1:0] i_rd_sid_2d [0:nports-1];
  wire [nports*nstrms_width-1:0]        i_rd_sid;
  genvar aaa;
  generate
    for(aaa=0; aaa<nports; aaa=aaa+1) begin
      assign i_rd_sid[(aaa+1)*nstrms_width-1:aaa*nstrms_width] = i_rd_sid_2d[aaa];
    end
  endgenerate

  // AFU READ DATA INTERFACE
  wire [nports-1:0]                     o_rd_v;
  reg  [nports-1:0]                     o_rd_r;
  wire [nports*ra_out_width-1:0]        o_rd_sid;
  wire [nports*2*DATA_WIDTH-1:0]        o_rd_d;

  wire [ra_out_width-1:0] o_rd_sid_2d [0:nports-1];
  wire [2*DATA_WIDTH-1:0] o_rd_d_2d [0:nports-1];
  genvar bbb;
  generate
    for(bbb=0; bbb<nports; bbb=bbb+1) begin
      assign o_rd_sid_2d[bbb] = o_rd_sid[(bbb+1)*ra_out_width-1:bbb*ra_out_width];
      assign o_rd_d_2d[bbb]   = o_rd_d[(bbb+1)*2*DATA_WIDTH-1:bbb*2*DATA_WIDTH];
    end
  endgenerate

  // Dump 2D array data to VCD file.
  // TODO: fix warning: array word apl_top_tb.i_rd_sid_2d[0] will conflict with an escaped identifier.
  integer ccc;
  initial begin
    for(ccc=0; ccc<nports;ccc=ccc+1) begin
      $dumpvars( 0, i_rd_sid_2d[ccc] );
      $dumpvars( 0, o_rd_sid_2d[ccc] );
      $dumpvars( 0, o_rd_d_2d[ccc] );
    end
  end

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

    .i_we           (i_we), // Write to L1.
    .i_wa           (i_wa),
    .i_wd           (i_wd),

    .o_req_v        (s1_req_v),
    .o_req_r        (s1_req_r),
    .o_req_sid      (s1_req_sid),
    .o_req_ea       (o_req_ea),

    .i_rsp_v        (s2_rsp_v),
    .i_rsp_r        (s2_rsp_r),
    .i_rsp_sid      (s2_rsp_sid)
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
        i_we <= 1'b1;
        i_wa <= address;
        i_wd <= data;
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
  integer rest_int;
  task rest;
    input integer delay;
    begin
      i_rst_v       <= 0;
      i_rst_sid     <= 0;
      i_rst_ea_b    <= 0;
      i_rst_ea_e    <= 0;
      o_rst_r       <= {nstrms{1'b1}};
      i_rd_v        <= 0;
      for(rest_int=0; rest_int<nports; rest_int=rest_int+1) begin
        i_rd_sid_2d[rest_int]      <= 0;
      end
      o_rd_r        <= {nports{1'b1}};
      #delay;
    end
  endtask

  // Task to initialise and terminate the testbench.
  // - delay determines the number of time steps of this task.
  integer init_int;
  task init;
    input integer delay;
    begin
      i_rst_v       <= 0;
      i_rst_sid     <= 0;
      i_rst_ea_b    <= 0;
      i_rst_ea_e    <= 0;
      o_rst_r       <= 0;
      i_rd_v        <= 0;
      for(init_int=0; init_int<nports; init_int=init_int+1) begin
        i_rd_sid_2d[init_int]      <= 0;
      end
      o_rd_r        <= 0;
      i_we          <= 0;
      i_wa          <= 0;
      i_wd          <= 0;
      #delay;
    end
  endtask

  // Task to issue an AFU read request.
  task tsk_afu_rd;
    input [nports-1:0]        port_id;
    input [nstrms_width-1:0]  sid;
    begin
      i_rd_v[port_id] <= 1'b1;
      i_rd_sid_2d[port_id] = sid;
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
  // Data array is indexed using: stream * cl * 2 (double pump) * ways.
  reg [addr_width-1:0] verify_counter [0:nstrms];
  integer ww;
  initial begin
    for( ww=0; ww<nstrms; ww=ww+1 ) begin
      verify_counter[ww] = ww*number_of_half_elements;
    end
  end

  reg [2*DATA_WIDTH-1:0] rd_d [0:nports-1];
  reg [2*DATA_WIDTH-1:0] test_d [0:nports-1];
  reg [nstrms_width-1:0] rd_sid [0:nports-1];
  reg comparison [0:nstrms-1];

  // Generate sid comparisons.
  wire [31:0] comp_counter [0:nports-1];
  genvar qqq, iii;
  generate
    for(qqq=0; qqq<nports; qqq=qqq+1) begin
      if(qqq>0) begin
        localparam inc_width = $clog2(qqq+1);
        wire [qqq-1:0] s1_hit;

        for(iii=0; iii<qqq; iii=iii+1) begin : GEN_HIT
          // compare stream id for this read port to stream id from the previous read ports.
          assign s1_hit[iii] = (o_rd_v[iii] & o_rd_r[iii]) && ( o_rd_sid_2d[qqq] === o_rd_sid_2d[iii] );
        end

        wire [inc_width-1:0] s1_ptr_inc;
        base_cenc#(.enc_width(inc_width),.dec_width(qqq)) is1_cenc(.din(s1_hit),.dout(s1_ptr_inc)); // count number of '1's in s1_hit array.
        assign comp_counter[qqq] = verify_counter[o_rd_sid_2d[qqq]] + s1_ptr_inc*2;
      end

      else if(qqq===0) begin
        assign comp_counter[0] = verify_counter[o_rd_sid_2d[0]];
      end

    end
  endgenerate

  // Verification logic for nports.
  genvar ppp;
  generate
    for(ppp=0; ppp<nports; ppp=ppp+1) begin
      always @ (negedge clk1x) begin

          if( o_rd_v[ppp] === 1'b1 ) begin // TODO: change to o_rd_act.

            rd_sid[ppp] = o_rd_sid_2d[ppp];
            test_d[ppp] = {data[comp_counter[ppp]+1], data[comp_counter[ppp]]};
            comparison[rd_sid[ppp]] = (o_rd_d_2d[ppp] === test_d[ppp]);

            //if( comparison[rd_sid[ppp]] === 1'b1 ) begin // === Also takes X and Z into account.
            //  $display( "%0d - RD Port %0d, Stream %0d CORRECT!", $time-2, ppp, rd_sid[ppp] );
            //  $display( "rd_sid = %0d, rd_d = %0h, test_d = %0h", rd_sid[ppp], o_rd_d_2d[ppp], test_d[ppp] );
            //end
            if( comparison[rd_sid[ppp]] !== 1'b1 ) begin // === Also takes X and Z into account.
              $display( "%0d - Port %0d, Stream %0d ERROR!", $time-2, ppp, rd_sid[ppp] );
              $display( "Expected = %h", test_d[ppp] );
              $display( "Output   = %h", o_rd_d_2d[ppp] );
            end
            verify_counter[rd_sid[ppp]] = verify_counter[rd_sid[ppp]] + 2;
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
      rd_v_rsp_counter[rd_req_int] = 0; // TODO: write code for this counter.
    end
  end

  // Update counters for verification.
  integer rd_sid_int [0:nports-1];
  genvar uu;
  generate
    for(uu=0; uu<nports; uu=uu+1) begin
      always @ (negedge clk1x) begin

        // Increment counter if a read request has been accepted.
        if( (i_rd_v[uu] & i_rd_r[uu]) === 1'b1 ) begin
          rd_req_counter[i_rd_sid_2d[uu]] = rd_req_counter[i_rd_sid_2d[uu]] + 1;
        end

        // Increment counter if a read request has been made.
        if( i_rd_v[uu] === 1'b1 ) begin
          rd_v_req_counter[i_rd_sid_2d[uu]] = rd_v_req_counter[i_rd_sid_2d[uu]] + 1;
        end

        // Increment counter if a read response has been accepted.
        if( (o_rd_v[uu] & o_rd_r[uu]) === 1'b1 ) begin
          rd_rsp_counter[o_rd_sid_2d[uu]] = rd_rsp_counter[o_rd_sid_2d[uu]] + 1;
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
  // TODO: use o_req_ea instead of this counter to improve the verification infrastructure.
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
    //for( rst_sid=0; rst_sid<nstrms; rst_sid=rst_sid+1 ) begin
    //  tsk_func_rst( rst_sid );
    //  rest( 100 );
    //end

    tsk_func_rst(3);
    rest(1000);
    //tsk_func_rst(21);
    //rest(100);

    // Read random streams from two read ports.
    repeat( 191*8 +4 ) begin
      //tsk_afu_rd( 0, $urandom_range( nstrms-1, 0 ) ); // port id, sid
      //tsk_afu_rd( 1, $urandom_range( nstrms-1, 0 ) );
      tsk_afu_rd( 0, 3 );
      tsk_afu_rd( 1, 3 );

      //tsk_afu_rd( 2, 21 );
      //tsk_afu_rd( 3, 21 );
      #4;
    end

    rest( 100 );

    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(1, 3);
    #4;
    tsk_afu_rd(0, 3);
    tsk_afu_rd(1, 3);
    #4;

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



    // Print stream statistics.
    $display(); // Print empty line.
    $display( "SIMULATION SUMMARY" );

    // Compare the read request and response counters.
    for(rd_req_int=0; rd_req_int<nstrms; rd_req_int=rd_req_int+1) begin
      // Print total number of reads. Only if reads for that stream have been made.
      if( rd_v_req_counter[rd_req_int] !== 0 ) begin
        $display( "STREAM %0d:", rd_req_int );
        $display( "Elements:     %0d", (rst_ea_e-rst_ea_b)*8 );
        $display( "Requested:    %0d", rd_v_req_counter[rd_req_int] );
        $display( "Responded:    %0d = %0d\%", rd_rsp_counter[rd_req_int], rd_rsp_counter[rd_req_int]/((rst_ea_e-rst_ea_b)*8)*100 );
      end

      // Compare accepted reads versus accepted responses.
      //if( rd_req_counter[rd_req_int] === rd_rsp_counter[rd_req_int] )
      //  $display( "%0d - rd_cntr %0d PASS", $time, rd_req_int );
      // A read has been accepted, but was discarded. Therefore rd_req_counter is larger than rd_rsp_counter.
      if( rd_req_counter[rd_req_int] !== rd_rsp_counter[rd_req_int] )
        $display( "WARNING! Discarded reads: %0d", (rd_req_counter[rd_req_int] - rd_rsp_counter[rd_req_int]) );
      // Compare requested reads versus accepted reads.
      if( (rd_v_req_counter[rd_req_int] - rd_req_counter[rd_req_int]) !== 0 )
        $display( "WARNING! STREAM %0d has %0d unaccepted i_rd_v", rd_req_int, rd_v_req_counter[rd_req_int] - rd_req_counter[rd_req_int] );
    end

    // TODO: at end of simulation, print list of streams that have been reset and how many cache lines and what percentage has been read from them.

    // Terminate testbench.
    init( 4 );
    $display(); // Print empty line.
    $finish;
  end

endmodule // apl_top_tb
