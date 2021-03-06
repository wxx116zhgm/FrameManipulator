# SDC file for POWERLINK Slave reference design with
# - SRAM (10 ns - IS61LV25616AL)
# - Nios II (PCP) with 100 MHz

# ----------------------------------------------------------------------------------
# clock definitions
## define the clocks in your design (depends on your PLL settings!)
##  (under "Compilation Report" - "TimeQuest Timing Analyzer" - "Clocks")
set ext_clk       EXT_CLK
set clk50         pllInst|altpll_component|auto_generated|pll1|clk[0]
set clk100        pllInst|altpll_component|auto_generated|pll1|clk[1]
set clk25         pllInst|altpll_component|auto_generated|pll1|clk[2]

## define which clock drives SRAM controller
set clkSRAM        $clk100
# ----------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------
# note: changes below this line have to be done carefully

# ----------------------------------------------------------------------------------
# constrain JTAG
create_clock -period 10MHz {altera_reserved_tck}
set_clock_groups -asynchronous -group {altera_reserved_tck}
set_input_delay -clock {altera_reserved_tck} 20 [get_ports altera_reserved_tdi]
set_input_delay -clock {altera_reserved_tck} 20 [get_ports altera_reserved_tms]
set_output_delay -clock {altera_reserved_tck} 20 [get_ports altera_reserved_tdo]
# ----------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------
# derive pll clocks (generated + input)
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty
# ----------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------
# create virtual clocks
## used by SRAM
create_generated_clock -source $clkSRAM -name CLKSRAM_virt

# define clock groups
## clock group B includes Nios II + SRAM
set clkGroupB    [format "%s %s" $clk100 CLKSRAM_virt]

set_clock_groups -asynchronous     -group $clkGroupB \
                                            -group $clk25 \
                                            -group $ext_clk

# ----------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------
# sram (IS61WV51216BLL-10TLI)
## SRAM is driven by 100 MHz fsm.
## Note: The SOPC inserts 2 write and 2 read cycles, thus, the SRAM "sees" 50 MHz!
set sram_clkRd      50.0
set sram_clkWr      100.0
set sram_tperRd     [expr 1000.0 / $sram_clkRd]
set sram_tperWr     [expr 1000.0 / $sram_clkWr]
## delay Address Access Time (tAA) = 10.0 ns
set sram_ddel        10.0
## pcb delay
set sram_tpcb        0.1
## fpga settings... Tco range BeMicro 5..9 ns
set sram_tco        7.0
set sram_tsu        [expr $sram_tperRd - $sram_ddel - $sram_tco - 2*$sram_tpcb]
set sram_th         0.0
set sram_tcom       0.0

set sram_in_max     [expr $sram_tperRd - $sram_tsu]
set sram_in_min     $sram_th
set sram_out_max    [expr $sram_tperWr - $sram_tco]
set sram_out_min    $sram_tcom

## TSU / TH
set_input_delay -clock CLKSRAM_virt -max $sram_in_max [get_ports SRAM_DQ[*]]
set_input_delay -clock CLKSRAM_virt -min $sram_in_min [get_ports SRAM_DQ[*]]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_DQ[*]]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_DQ[*]]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_ADDR[*]]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_ADDR[*]]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_BE_n[*]]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_BE_n[*]]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_OE_n]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_OE_n]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_WE_n]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_WE_n]
## TCO
set_output_delay -clock CLKSRAM_virt -max $sram_out_max [get_ports SRAM_CE_n]
set_output_delay -clock CLKSRAM_virt -min $sram_out_min [get_ports SRAM_CE_n]

## relax timing...
## Note: Nios II is running with 90 MHz, but Tri-State-bridge reads with 45 MHz.
### from FPGA to SRAM
set_multicycle_path -from [get_clocks $clkSRAM] -to [get_clocks CLKSRAM_virt] -setup -start 2
set_multicycle_path -from [get_clocks $clkSRAM] -to [get_clocks CLKSRAM_virt] -hold -start 1
### from SRAM to FPGA
set_multicycle_path -from [get_clocks CLKSRAM_virt] -to [get_clocks $clkSRAM] -setup -end 2
set_multicycle_path -from [get_clocks CLKSRAM_virt] -to [get_clocks $clkSRAM] -hold -end 1
# ----------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------
# IOs
## cut paths
###EPCS
set_false_path -from [get_registers *] -to [get_ports EPCS_DCLK]
set_false_path -from [get_registers *] -to [get_ports EPCS_SCE]
set_false_path -from [get_registers *] -to [get_ports EPCS_SDO]
set_false_path -from [get_ports EPCS_DATA0] -to [get_registers *]
###IOs
set_false_path -from [get_registers *] -to [get_ports LED[*]]
set_false_path -from [get_ports NODE_SWITCH[*]] -to [get_registers *]
#### example for output: set_false_path -from [get_registers *] -to [get_ports LED[*]]
#### example for input:  set_false_path -from [get_ports BUTTON[*]] -to [get_registers *]
#############################################################
# add here your slow IOs...
#############################################################
# ----------------------------------------------------------------------------------

###RMII-PHYs
###############################################################################
# PCB delay (FPGA <--> PHY(s)) [ns]
set tpcb            0.1

# RMII Timing [ns]
set rmii_tsu        4.0
set rmii_th         2.0
set rmii_tco        14.0
set rmii_tcomin     2.0

# I/O MIN/MAX DELAY [ns]
set rmii_in_max     [expr $rmii_tco    + $tpcb ]
set rmii_in_min     [expr $rmii_tcomin - $tpcb ]
set rmii_out_max    [expr $rmii_tsu    + $tpcb ]
set rmii_out_min    [expr $rmii_th     - $tpcb ]

###############################################################################
# RMII CLOCK RATE
create_generated_clock -source $clk50 -name CLK50_virt

## input
set_input_delay -clock CLK50_virt -max $rmii_in_max [get_ports {PHY_RXDV[*] PHY_RXER[*] PHY_RXD[*]}]
set_input_delay -clock CLK50_virt -min $rmii_in_min [get_ports {PHY_RXDV[*] PHY_RXER[*] PHY_RXD[*]}]
## output
set_output_delay -clock CLK50_virt -max $rmii_out_max [get_ports {PHY_TXEN[*] PHY_TXD[*]}]
set_output_delay -clock CLK50_virt -min $rmii_out_min [get_ports {PHY_TXEN[*] PHY_TXD[*]}]
## cut path
set_false_path -from [get_registers *] -to [get_ports PHY_RESET_n[*]]
set_false_path -from [get_registers *] -to [get_ports PHY_MDC[*]]
set_false_path -from [get_registers *] -to [get_ports PHY_MDIO[*]]
set_false_path -from [get_ports PHY_MDIO[*]] -to [get_registers *]
## multicycle
## Note: TX signals are latched at falling edge of 100 MHz signal
### from FPGA to PHY
set_multicycle_path -from [get_clocks $clk100] -to [get_ports {PHY_TXEN[*] PHY_TXD[*]}] -setup -start 2
set_multicycle_path -from [get_clocks $clk100] -to [get_ports {PHY_TXEN[*] PHY_TXD[*]}] -hold -start 1
# ----------------------------------------------------------------------------------

