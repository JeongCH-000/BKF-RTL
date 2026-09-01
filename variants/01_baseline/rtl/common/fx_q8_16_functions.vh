// Include inside a module after fx_q8_16_defs.vh.
function signed [23:0] round_sat48;
    input signed [47:0] value;
    reg signed [48:0] extended_value;
    reg signed [48:0] rounded_value;
    begin
        extended_value = {value[47], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + 49'sd32768) >>> 16);
        else
            rounded_value = (extended_value + 49'sd32768) >>> 16;
        if (rounded_value > 49'sd8388607)
            round_sat48 = `FX_Q8_16_MAX;
        else if (rounded_value < -49'sd8388608)
            round_sat48 = `FX_Q8_16_MIN;
        else
            round_sat48 = rounded_value[23:0];
    end
endfunction

function overflow48;
    input signed [47:0] value;
    reg signed [48:0] extended_value;
    reg signed [48:0] rounded_value;
    begin
        extended_value = {value[47], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + 49'sd32768) >>> 16);
        else
            rounded_value = (extended_value + 49'sd32768) >>> 16;
        overflow48 = (rounded_value > 49'sd8388607) ||
                        (rounded_value < -49'sd8388608);
    end
endfunction

function signed [23:0] round_sat50;
    input signed [49:0] value;
    reg signed [50:0] extended_value;
    reg signed [50:0] rounded_value;
    begin
        extended_value = {value[49], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + 51'sd32768) >>> 16);
        else
            rounded_value = (extended_value + 51'sd32768) >>> 16;
        if (rounded_value > 51'sd8388607)
            round_sat50 = `FX_Q8_16_MAX;
        else if (rounded_value < -51'sd8388608)
            round_sat50 = `FX_Q8_16_MIN;
        else
            round_sat50 = rounded_value[23:0];
    end
endfunction

function overflow50;
    input signed [49:0] value;
    reg signed [50:0] extended_value;
    reg signed [50:0] rounded_value;
    begin
        extended_value = {value[49], value};
        if (extended_value < 0)
            rounded_value = -(((-extended_value) + 51'sd32768) >>> 16);
        else
            rounded_value = (extended_value + 51'sd32768) >>> 16;
        overflow50 = (rounded_value > 51'sd8388607) ||
                        (rounded_value < -51'sd8388608);
    end
endfunction

function signed [23:0] add_sat24;
    input signed [23:0] left;
    input signed [23:0] right;
    reg signed [24:0] sum;
    begin
        sum = {left[23], left} + {right[23], right};
        if (sum > 25'sd8388607)
            add_sat24 = `FX_Q8_16_MAX;
        else if (sum < -25'sd8388608)
            add_sat24 = `FX_Q8_16_MIN;
        else
            add_sat24 = sum[23:0];
    end
endfunction

function add_overflow24;
    input signed [23:0] left;
    input signed [23:0] right;
    reg signed [24:0] sum;
    begin
        sum = {left[23], left} + {right[23], right};
        add_overflow24 = (sum > 25'sd8388607) || (sum < -25'sd8388608);
    end
endfunction

function signed [23:0] sub_sat24;
    input signed [23:0] left;
    input signed [23:0] right;
    reg signed [24:0] difference;
    begin
        difference = {left[23], left} - {right[23], right};
        if (difference > 25'sd8388607)
            sub_sat24 = `FX_Q8_16_MAX;
        else if (difference < -25'sd8388608)
            sub_sat24 = `FX_Q8_16_MIN;
        else
            sub_sat24 = difference[23:0];
    end
endfunction

function sub_overflow24;
    input signed [23:0] left;
    input signed [23:0] right;
    reg signed [24:0] difference;
    begin
        difference = {left[23], left} - {right[23], right};
        sub_overflow24 = (difference > 25'sd8388607) ||
                            (difference < -25'sd8388608);
    end
endfunction

function signed [23:0] average24;
    input signed [23:0] left;
    input signed [23:0] right;
    reg signed [25:0] sum;
    reg signed [25:0] rounded_value;
    begin
        sum = {left[23], left[23], left} + {right[23], right[23], right};
        if (sum < 0)
            rounded_value = -(((-sum) + 26'sd1) >>> 1);
        else
            rounded_value = (sum + 26'sd1) >>> 1;
        average24 = rounded_value[23:0];
    end
endfunction
