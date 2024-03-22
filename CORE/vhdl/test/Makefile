SRC += ../crt_parser.vhd
SRC += ../crt_cacher.vhd
SRC += ../crt_loader.vhd
SRC += ../../../M2M/vhdl/qnice_csr.vhd
SRC += ../../../M2M/vhdl/memory/axi_fifo.vhd
SRC += ../../../M2M/vhdl/axi_fifo_small.vhd
SRC += ../../../M2M/vhdl/memory/avm_fifo.vhd
SRC += ../../../M2M/vhdl/memory/avm_arbit.vhd
SRC += ../../../M2M/vhdl/memory/avm_arbit_general.vhd
SRC += ../../../M2M/vhdl/memory/avm_rom.vhd
SRC += ../../../M2M/vhdl/memory/avm_memory.vhd
SRC += ../../../M2M/vhdl/memory/avm_increase.vhd
SRC += ../../../M2M/vhdl/cdc_slow.vhd
SRC += ../../../M2M/vhdl/cdc_stable.vhd
SRC += ../../../M2M/vhdl/qnice_csr.vhd
SRC += ../../../M2M/vhdl/qnice2hyperram.vhd
SRC += ../../../M2M/vhdl/tdp_ram.vhd

SRC += ../../../../65c02/src/datapath/alu.vhd
SRC += ../../../../65c02/src/datapath/ar.vhd
SRC += ../../../../65c02/src/datapath/datapath.vhd
SRC += ../../../../65c02/src/datapath/hi.vhd
SRC += ../../../../65c02/src/datapath/lo.vhd
SRC += ../../../../65c02/src/datapath/mr.vhd
SRC += ../../../../65c02/src/datapath/pc.vhd
SRC += ../../../../65c02/src/datapath/sp.vhd
SRC += ../../../../65c02/src/datapath/sr.vhd
SRC += ../../../../65c02/src/datapath/xr.vhd
SRC += ../../../../65c02/src/datapath/yr.vhd
SRC += ../../../../65c02/src/datapath/zp.vhd
SRC += ../../../../65c02/src/control/control.vhd
SRC += ../../../../65c02/src/control/microcode.vhd
SRC += ../../../../65c02/src/cpu_65c02.vhd

SRC += qnice_sim.vhd
SRC += core_sim.vhd

CRT_FILE = quikman-rom.crt
CRT_DIR  = $(HOME)/Documents/MEGA65/MEGA65-SD/vic20/crt

ROM_FILE = ../../../CORE/VIC20_MiSTer/rtl/roms/kernal.901486-07.mif


DUT ?= crt_loader
GENERIC ?= -gG_CRT_FILE_NAME=$(CRT_DIR)/$(CRT_FILE) -gG_ROM_FILE_NAME=$(ROM_FILE).hex


TB = tb_$(DUT)
SRC += $(TB).vhd
WAVE = $(TB).ghw
SAVE = $(TB).gtkw

XPM_TOP_DIR = ../../../../../fransschreuder/xpm_vhdl

.PHONY: sim
sim: $(WAVE)

$(WAVE): $(TB)
	xxd -r -p $(ROM_FILE).hex $(ROM_FILE).bin
	ghdl -r --std=08 $(TB) $(GENERIC) --assert-level=error --wave=$(WAVE) --max-stack-alloc=2097151 --stop-time=150us | tee output.txt

$(TB): $(SRC) xpm-obj08.cf
	ghdl -i --std=08 --work=work $(SRC)
	ghdl -m --std=08 -fexplicit $(TB)

xpm-obj08.cf:
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_VCOMP.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_single.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_array_single.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_async_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_gray.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_handshake.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_low_latency_handshake.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_pulse.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_sync_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_base.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_dpdistram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_dprom.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_sdpram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_spram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_sprom.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_tdpram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_bit.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_counter_updn.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_vec.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_reg_pipe_bit.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_base.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_async.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axi_reg_slice.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axif.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axil.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axis.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_sync.vhd

show: $(WAVE)
	gtkwave $(WAVE) $(SAVE)

clean:
	rm -rf *.o
	rm -rf work-obj08.cf
	rm -rf xpm-obj08.cf
	rm -rf $(TB)
	rm -rf $(WAVE)
	rm -rf output.txt

