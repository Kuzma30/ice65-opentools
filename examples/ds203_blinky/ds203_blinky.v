// First-light design for the DS203 (iCE65L04F-TVQ100C), built with the open flow.
//  - nPD (pin 2, ADC power-down line) toggles at about 1.07 Hz  (72 MHz / 2^26)
//  - CKA (pin 81) = 72 MHz / 64 = 1.125 MHz, CKB (pin 100) = 72 MHz / 128 = 562.5 kHz
//  - the data bus is only driven while NE1 is high and nRD is low, like the stock design:
//      H_L = 1 -> 16'hA55A,  H_L = 0 -> number of read strobes seen so far
// All other pins stay inputs.
module ds203_blinky (
  input MCI, NE1, nRD, H_L,
  output nPD, CKA, CKB,
  inout [15:0] DB
);
  wire clk;
  SB_GB_IO #(.PIN_TYPE(6'b000001), .PULLUP(1'b0)) mci_pad (.PACKAGE_PIN(MCI), .GLOBAL_BUFFER_OUTPUT(clk));

  reg [25:0] cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;
  assign nPD = cnt[25];
  assign CKA = cnt[5];
  assign CKB = cnt[6];

  reg [15:0] reads = 0;
  always @(negedge nRD) if (NE1) reads <= reads + 1;
  assign DB = (NE1 & ~nRD) ? (H_L ? 16'hA55A : reads) : 16'bz;
endmodule
