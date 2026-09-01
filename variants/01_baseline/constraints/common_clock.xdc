create_clock -name estimator_clk -period 10.000 [get_ports clk]

# Out-of-context core synthesis only. A system wrapper must add I/O delays.
