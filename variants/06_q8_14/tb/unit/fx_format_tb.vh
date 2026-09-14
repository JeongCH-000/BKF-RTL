// Testbench-only format constants. References use 64-bit math independently of DUT helpers.
localparam integer W = `FX_Q8_16_WIDTH;
localparam integer F = `FX_Q8_16_FRAC;
localparam signed [63:0] TB_ONE = 64'sd1 << F;
localparam signed [63:0] TB_HALF = 64'sd1 << (F-1);
localparam signed [63:0] TB_MAX = (64'sd1 << (W-1))-1;
localparam signed [63:0] TB_MIN = -(64'sd1 << (W-1));
localparam signed [W-1:0] TB_MAX_WORD = `FX_Q8_16_MAX;
localparam signed [W-1:0] TB_MIN_WORD = `FX_Q8_16_MIN;
function signed [W-1:0] fx_q16;
    input signed [63:0] original_raw;
    reg signed [63:0] magnitude;
    begin
        magnitude = original_raw < 0 ? -original_raw : original_raw;
        if (F < 16) magnitude = (magnitude + (64'sd1 << (15-F))) >> (16-F);
        else magnitude = magnitude << (F-16);
        fx_q16 = original_raw < 0 ? -magnitude : magnitude;
    end
endfunction
