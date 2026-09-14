// Include inside a module after fx_q8_16_defs.vh.
// Legacy function names are retained; all actual widths derive from W/F.
// The extra sign bit protects abs(minimum accumulator) before ties-away rounding.
localparam signed [`FX_Q8_16_PRODUCT_WIDTH:0] FX_FUNCTION_PRODUCT_HALF =
    ({{`FX_Q8_16_PRODUCT_WIDTH{1'b0}}, 1'b1} <<< (`FX_Q8_16_FRAC-1));
localparam signed [`FX_Q8_16_MAC_WIDTH:0] FX_FUNCTION_MAC_HALF =
    ({{`FX_Q8_16_MAC_WIDTH{1'b0}}, 1'b1} <<< (`FX_Q8_16_FRAC-1));
localparam signed [`FX_Q8_16_WIDTH+1:0] FX_FUNCTION_AVERAGE_HALF =
    {{(`FX_Q8_16_WIDTH+1){1'b0}}, 1'b1};

function signed [`FX_Q8_16_WIDTH-1:0] round_sat48;
    input signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] value;
    reg signed [`FX_Q8_16_PRODUCT_WIDTH:0] extended_value;
    reg signed [`FX_Q8_16_PRODUCT_WIDTH:0] rounded_value;
    begin
        extended_value = {value[`FX_Q8_16_PRODUCT_WIDTH-1], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + FX_FUNCTION_PRODUCT_HALF) >>> `FX_Q8_16_FRAC);
        else
            rounded_value = (extended_value + FX_FUNCTION_PRODUCT_HALF) >>> `FX_Q8_16_FRAC;
        if (rounded_value > $signed(`FX_Q8_16_MAX))
            round_sat48 = `FX_Q8_16_MAX;
        else if (rounded_value < $signed(`FX_Q8_16_MIN))
            round_sat48 = `FX_Q8_16_MIN;
        else
            round_sat48 = rounded_value[`FX_Q8_16_WIDTH-1:0];
    end
endfunction

function overflow48;
    input signed [`FX_Q8_16_PRODUCT_WIDTH-1:0] value;
    reg signed [`FX_Q8_16_PRODUCT_WIDTH:0] extended_value;
    reg signed [`FX_Q8_16_PRODUCT_WIDTH:0] rounded_value;
    begin
        extended_value = {value[`FX_Q8_16_PRODUCT_WIDTH-1], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + FX_FUNCTION_PRODUCT_HALF) >>> `FX_Q8_16_FRAC);
        else
            rounded_value = (extended_value + FX_FUNCTION_PRODUCT_HALF) >>> `FX_Q8_16_FRAC;
        overflow48 = (rounded_value > $signed(`FX_Q8_16_MAX)) ||
                        (rounded_value < $signed(`FX_Q8_16_MIN));
    end
endfunction

function signed [`FX_Q8_16_WIDTH-1:0] round_sat50;
    input signed [`FX_Q8_16_MAC_WIDTH-1:0] value;
    reg signed [`FX_Q8_16_MAC_WIDTH:0] extended_value;
    reg signed [`FX_Q8_16_MAC_WIDTH:0] rounded_value;
    begin
        extended_value = {value[`FX_Q8_16_MAC_WIDTH-1], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + FX_FUNCTION_MAC_HALF) >>> `FX_Q8_16_FRAC);
        else
            rounded_value = (extended_value + FX_FUNCTION_MAC_HALF) >>> `FX_Q8_16_FRAC;
        if (rounded_value > $signed(`FX_Q8_16_MAX))
            round_sat50 = `FX_Q8_16_MAX;
        else if (rounded_value < $signed(`FX_Q8_16_MIN))
            round_sat50 = `FX_Q8_16_MIN;
        else
            round_sat50 = rounded_value[`FX_Q8_16_WIDTH-1:0];
    end
endfunction

function overflow50;
    input signed [`FX_Q8_16_MAC_WIDTH-1:0] value;
    reg signed [`FX_Q8_16_MAC_WIDTH:0] extended_value;
    reg signed [`FX_Q8_16_MAC_WIDTH:0] rounded_value;
    begin
        extended_value = {value[`FX_Q8_16_MAC_WIDTH-1], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + FX_FUNCTION_MAC_HALF) >>> `FX_Q8_16_FRAC);
        else
            rounded_value = (extended_value + FX_FUNCTION_MAC_HALF) >>> `FX_Q8_16_FRAC;
        overflow50 = (rounded_value > $signed(`FX_Q8_16_MAX)) ||
                        (rounded_value < $signed(`FX_Q8_16_MIN));
    end
endfunction

function signed [`FX_Q8_16_WIDTH-1:0] add_sat24;
    input signed [`FX_Q8_16_WIDTH-1:0] left;
    input signed [`FX_Q8_16_WIDTH-1:0] right;
    reg signed [`FX_Q8_16_WIDTH:0] sum;
    begin
        sum = {left[`FX_Q8_16_WIDTH-1], left} + {right[`FX_Q8_16_WIDTH-1], right};
        if (sum > $signed(`FX_Q8_16_MAX))
            add_sat24 = `FX_Q8_16_MAX;
        else if (sum < $signed(`FX_Q8_16_MIN))
            add_sat24 = `FX_Q8_16_MIN;
        else
            add_sat24 = sum[`FX_Q8_16_WIDTH-1:0];
    end
endfunction

function add_overflow24;
    input signed [`FX_Q8_16_WIDTH-1:0] left;
    input signed [`FX_Q8_16_WIDTH-1:0] right;
    reg signed [`FX_Q8_16_WIDTH:0] sum;
    begin
        sum = {left[`FX_Q8_16_WIDTH-1], left} + {right[`FX_Q8_16_WIDTH-1], right};
        add_overflow24 = (sum > $signed(`FX_Q8_16_MAX)) || (sum < $signed(`FX_Q8_16_MIN));
    end
endfunction

function signed [`FX_Q8_16_WIDTH-1:0] sub_sat24;
    input signed [`FX_Q8_16_WIDTH-1:0] left;
    input signed [`FX_Q8_16_WIDTH-1:0] right;
    reg signed [`FX_Q8_16_WIDTH:0] difference;
    begin
        difference = {left[`FX_Q8_16_WIDTH-1], left} - {right[`FX_Q8_16_WIDTH-1], right};
        if (difference > $signed(`FX_Q8_16_MAX))
            sub_sat24 = `FX_Q8_16_MAX;
        else if (difference < $signed(`FX_Q8_16_MIN))
            sub_sat24 = `FX_Q8_16_MIN;
        else
            sub_sat24 = difference[`FX_Q8_16_WIDTH-1:0];
    end
endfunction

function sub_overflow24;
    input signed [`FX_Q8_16_WIDTH-1:0] left;
    input signed [`FX_Q8_16_WIDTH-1:0] right;
    reg signed [`FX_Q8_16_WIDTH:0] difference;
    begin
        difference = {left[`FX_Q8_16_WIDTH-1], left} - {right[`FX_Q8_16_WIDTH-1], right};
        sub_overflow24 = (difference > $signed(`FX_Q8_16_MAX)) ||
                            (difference < $signed(`FX_Q8_16_MIN));
    end
endfunction

function signed [`FX_Q8_16_WIDTH-1:0] average24;
    input signed [`FX_Q8_16_WIDTH-1:0] left;
    input signed [`FX_Q8_16_WIDTH-1:0] right;
    reg signed [`FX_Q8_16_WIDTH+1:0] sum;
    reg signed [`FX_Q8_16_WIDTH+1:0] rounded_value;
    begin
        sum = {left[`FX_Q8_16_WIDTH-1], left[`FX_Q8_16_WIDTH-1], left} + {right[`FX_Q8_16_WIDTH-1], right[`FX_Q8_16_WIDTH-1], right};
        if (sum < 0)
            rounded_value = -(((-sum) + FX_FUNCTION_AVERAGE_HALF) >>> 1);
        else
            rounded_value = (sum + FX_FUNCTION_AVERAGE_HALF) >>> 1;
        average24 = rounded_value[`FX_Q8_16_WIDTH-1:0];
    end
endfunction
