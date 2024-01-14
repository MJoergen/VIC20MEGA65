## NAME-OF-YOUR-PROJECT for MEGA65 (NAME-OF-THE-GITHUB-REPO)
##
## Signal mapping for CORE-R3
##
## This machine is based on EXACT GITHUB REPO NAME OF THE MiSTer REPO
## Powered by MiSTer2MEGA65
## MEGA65 port done by YOURNAME in YEAR and licensed under GPL v3


## Name Autogenerated Clocks
## Important: Using them in subsequent statements, e.g. clock dividers requires that they
## have been named/defined here before
## otherwise Vivado does not find the pins)
create_generated_clock -name video_clk     [get_pins CORE/clk_inst/i_clk_main/CLKOUT0]
create_generated_clock -name main_clk      [get_pins CORE/clk_inst/i_clk_main/CLKOUT1]
# Add more clocks here, if needed

