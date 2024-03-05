## VIC 20 for MEGA65 (VIC20MEGA65)
##
## MEGA65 port done by MJoergen in 2024 and licensed under GPL v3


create_generated_clock -name video_clk [get_pins CORE/clk_inst/i_clk_main/CLKOUT0]
create_generated_clock -name main_clk  [get_pins CORE/clk_inst/i_clk_main/CLKOUT1]

## CDC in IEC drives, handled manually in the source code
set_false_path -from [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_gcr/id1_reg[*]/C]
set_false_path -from [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_gcr/id2_reg[*]/C]
set_false_path -to   [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/busy_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_track/reset_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_track/change_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_track/save_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/main_inst/c1541_multi_inst/drives[*].c1541_drv/c1541_track/track_sync/s1_reg[*]/D]

