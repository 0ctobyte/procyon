create_clock -period 20 CLOCK_50
create_clock -period 40 -name ext_clk
derive_clock_uncertainty

set_input_delay -clock ext_clk -max 0 [get_ports {SW[*]}]
set_input_delay -clock ext_clk -min 0 [get_ports {SW[*]}]
set_input_delay -clock ext_clk -max 0 [get_ports {KEY[*]}]
set_input_delay -clock ext_clk -min 0 [get_ports {KEY[*]}]

set_output_delay -clock ext_clk -max 0.5 [get_ports {LEDR[*]}]
set_output_delay -clock ext_clk -min -0.5 [get_ports {LEDR[*]}]
set_output_delay -clock ext_clk -max 0.5 [get_ports {LEDG[*]}]
set_output_delay -clock ext_clk -min -0.5 [get_ports {LEDG[*]}]

set_output_delay -clock ext_clk -max 0 [get_ports {HEX0[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX0[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX1[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX1[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX2[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX2[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX3[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX3[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX4[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX4[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX5[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX5[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX6[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX6[*]}]
set_output_delay -clock ext_clk -max 0 [get_ports {HEX7[*]}]
set_output_delay -clock ext_clk -min 0 [get_ports {HEX7[*]}]

set_false_path -from [get_ports {SW[*]}]
set_false_path -from [get_ports {KEY[*]}]

set_false_path -from * -to [get_ports {HEX0[*]}]
set_false_path -from * -to [get_ports {HEX1[*]}]
set_false_path -from * -to [get_ports {HEX2[*]}]
set_false_path -from * -to [get_ports {HEX3[*]}]
set_false_path -from * -to [get_ports {HEX4[*]}]
set_false_path -from * -to [get_ports {HEX5[*]}]
set_false_path -from * -to [get_ports {HEX6[*]}]
set_false_path -from * -to [get_ports {HEX7[*]}]
