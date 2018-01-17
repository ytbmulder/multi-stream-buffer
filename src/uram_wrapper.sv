// Wrapper around a double-pumped URAM.
// Both a behaviour model and Xilinx primitive instantiation versions are available.

module uram_wrapper #
(
  parameter   DATA_WIDTH              = 8*8,              // 8 bytes per element
  parameter   RAM_DEPTH               = 4096,             // double pump -> 2048 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH)
)
(
  input                               clk2x,
  input                               reset,

  // Write interface
  input                               i_we,
  input  [ADDR_WIDTH-1:0]             i_wa,
  input  [DATA_WIDTH-1:0]             i_wd,

  // Read interface
  input                               i_re,
  input  [ADDR_WIDTH-1:0]             i_ra,
  output [DATA_WIDTH-1:0]             o_rd
);

  // Global wire declarations.
  wire                  clk   = clk2x;
  // Write port.
  wire                  ena   = 1'b1;   // This port is always enabled.
  wire                  wea   = i_we;
  wire [ADDR_WIDTH-1:0] addra = i_wa;
  wire [DATA_WIDTH-1:0] dia   = i_wd;
  // Read port.
  wire                  enb   = i_re;
  wire [ADDR_WIDTH-1:0] addrb = i_ra;
  //wire [DATA_WIDTH-1:0] dob;            // Internal signal.

  // Free-running register for REGCEB signals.
  wire s1_re, s2_re, s3_re;
  base_vlat # (
    .width  (1)
    ) FF1 (
    .clk    (clk),
    .reset  (reset),
    .din    (enb),
    .q      (s1_re)
  );

  // TODO: in the future, check if URAM can operate with 2 cycles read latency. If not, change to 3 or 4 cycles latency by adding more base_vlat and base_vlat_en modules.
/*
  base_vlat # (
    .width  (1)
    ) FF2 (
    .clk    (clk),
    .reset  (reset),
    .din    (s1_re),
    .q      (s2_re)
  );
*/



  // Ability to select either a behaviour model or the Xilinx primitive instantiation.
  `ifdef VCD
    // Behaviour model supplied by Xilinx (simple_dual_one_clock module).
    reg [DATA_WIDTH-1:0] ram [RAM_DEPTH-1:0];
    reg [DATA_WIDTH-1:0] doa, dob;

    always @(posedge clk) begin
      if (ena) begin
        if (wea)
          ram[addra] <= dia;
      end
    end

    always @(posedge clk) begin
      if (enb)
        dob <= ram[addrb];
    end

    // Additional BRAM internal register. Captured by BRAM_LATENCY.
    wire [DATA_WIDTH-1:0] s2_rd, s3_rd;
    base_vlat_en # (
      .width (DATA_WIDTH)
      ) REGCEB1 (
      .clk    (clk),
      .reset  (reset),
      .enable (s1_re),
      .din    (dob),
      .q      (s2_rd)
    );

/*
    base_vlat_en # (
      .width (DATA_WIDTH)
      ) REGCEB2 (
      .clk    (clk),
      .reset  (reset),
      .enable (s2_re),
      .din    (s2_rd),
      .q      (o_rd)
    );
*/

  assign o_rd = s2_rd;




  `else
    // BRAM latency parameter.
    localparam BRAM_LATENCY = 2;

    // Xilinx Parameterized Macro, Version 2017.1
    xpm_memory_sdpram # (
      // Common module parameters
      .MEMORY_SIZE        (DATA_WIDTH*RAM_DEPTH),     //positive integer
      .MEMORY_PRIMITIVE   ("ultra"),                  //string; "auto", "distributed", "block" or "ultra";
      .CLOCKING_MODE      ("common_clock"),           //string; "common_clock", "independent_clock"
      .MEMORY_INIT_FILE   ("none"),                   //string; "none" or "<filename>.mem"
      .MEMORY_INIT_PARAM  (""), 	                  //string;
      .USE_MEM_INIT       (0),                        //integer; 0,1
      .WAKEUP_TIME        ("disable_sleep"),          //string; "disable_sleep" or "use_sleep_pin"
      .MESSAGE_CONTROL    (1),                        //integer; 0,1
      .ECC_MODE           ("no_ecc"),                 //string; "no_ecc", "encode_only", "decode_only" or "both_encode_and_decode"
      .AUTO_SLEEP_TIME    (0),                        //Do not Change

      // Port A module parameters
      .WRITE_DATA_WIDTH_A (DATA_WIDTH),               //positive integer
      .BYTE_WRITE_WIDTH_A (DATA_WIDTH),               //integer; 8, 9, or WRITE_DATA_WIDTH_A value
      .ADDR_WIDTH_A       (ADDR_WIDTH),               //positive integer

      // Port B module parameters
      .READ_DATA_WIDTH_B  (DATA_WIDTH),               //positive integer
      .ADDR_WIDTH_B       (ADDR_WIDTH),               //positive integer
      .READ_RESET_VALUE_B ("0"),                      //string
      .READ_LATENCY_B     (BRAM_LATENCY),             //non-negative integer one or two.
      .WRITE_MODE_B       ("read_first")              //string; "write_first", "read_first", "no_change"
    ) xpm_memory_sdpram_inst (
      // Common module ports
      .sleep          (1'b0),

      // Port A module ports
      .clka           (clk),
      .ena            (ena),
      .wea            (wea),
      .addra          (addra),
      .dina           (dia),
      .injectsbiterra (1'b0),                         //ignore, only for ECC
      .injectdbiterra (1'b0),                         //ignore, only for ECC

      // Port B module ports
      .clkb           (clk),
      .rstb           (reset),
      .enb            (enb),
      .regceb         (s1_re),
      .addrb          (addrb),
      .doutb          (o_rd),
      .sbiterrb       (),
      .dbiterrb       ()
    );

  `endif

endmodule //uram_wrapper
