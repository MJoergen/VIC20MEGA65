----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- based on VIC20_MiSTer by the MiSTer development team
-- port done by MJoergen and sy2002 in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.vdrives_pkg.all;

entity main is
   generic (
      G_VDNUM : natural -- amount of virtual drives
   );
   port (
      clk_main_i             : in    std_logic;
      clk_video_i            : in    std_logic;

      -- A pulse of reset_soft_i needs to be 32 clock cycles long at a minimum
      reset_soft_i           : in    std_logic;
      reset_hard_i           : in    std_logic;

      -- Pull high to pause the core
      pause_i                : in    std_logic;

      -- Trigger the sequence RUN<Return> to autostart PRG files
      trigger_run_i          : in    std_logic;

      ---------------------------
      -- Configuration options
      ---------------------------

      -- Select VIC20's ROM: 0=Custom, 1=Standard
      vic20_rom_i            : in    std_logic;
      ram_ext_ro_i           : in    std_logic_vector(4 downto 0);
      ram_ext_i              : in    std_logic_vector(4 downto 0);

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i       : in    natural;
      video_retro15khz_i     : in    std_logic;

      ---------------------------
      -- VIC 20 I/O ports
      ---------------------------

      -- M2M Keyboard interface
      kb_key_num_i           : in    integer range 0 to 79; -- cycles through all MEGA65 keys
      kb_key_pressed_n_i     : in    std_logic;             -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles
      joy_1_up_n_i           : in    std_logic;
      joy_1_down_n_i         : in    std_logic;
      joy_1_left_n_i         : in    std_logic;
      joy_1_right_n_i        : in    std_logic;
      joy_1_fire_n_i         : in    std_logic;
      joy_1_up_n_o           : out   std_logic;
      joy_1_down_n_o         : out   std_logic;
      joy_1_left_n_o         : out   std_logic;
      joy_1_right_n_o        : out   std_logic;
      joy_1_fire_n_o         : out   std_logic;
      joy_2_up_n_i           : in    std_logic;
      joy_2_down_n_i         : in    std_logic;
      joy_2_left_n_i         : in    std_logic;
      joy_2_right_n_i        : in    std_logic;
      joy_2_fire_n_i         : in    std_logic;
      joy_2_up_n_o           : out   std_logic;
      joy_2_down_n_o         : out   std_logic;
      joy_2_left_n_o         : out   std_logic;
      joy_2_right_n_o        : out   std_logic;
      joy_2_fire_n_o         : out   std_logic;
      pot1_x_i               : in    std_logic_vector(7 downto 0);
      pot1_y_i               : in    std_logic_vector(7 downto 0);
      pot2_x_i               : in    std_logic_vector(7 downto 0);
      pot2_y_i               : in    std_logic_vector(7 downto 0);

      -- Video output
      video_ce_o             : out   std_logic;
      video_ce_ovl_o         : out   std_logic;
      video_red_o            : out   std_logic_vector(7 downto 0);
      video_green_o          : out   std_logic_vector(7 downto 0);
      video_blue_o           : out   std_logic_vector(7 downto 0);
      video_vs_o             : out   std_logic;
      video_hs_o             : out   std_logic;
      video_hblank_o         : out   std_logic;
      video_vblank_o         : out   std_logic;

      -- Audio output (Signed PCM)
      audio_left_o           : out   signed(15 downto 0);
      audio_right_o          : out   signed(15 downto 0);

      -- VIC20 drive led (color is RGB)
      drive_led_o            : out   std_logic;
      drive_led_col_o        : out   std_logic_vector(23 downto 0);

      -- Access to main memory
      conf_clk_i             : in    std_logic;
      conf_ai_i              : in    std_logic_vector(15 downto 0);
      conf_di_i              : in    std_logic_vector(7 downto 0);
      conf_wr_i              : in    std_logic;

      -- IEC handled by QNICE
      iec_clk_sd_i           : in    std_logic;             -- QNICE "sd card write clock" for floppy drive internal dual clock RAM buffer
      iec_qnice_addr_i       : in    std_logic_vector(27 downto 0);
      iec_qnice_data_i       : in    std_logic_vector(15 downto 0);
      iec_qnice_data_o       : out   std_logic_vector(15 downto 0);
      iec_qnice_ce_i         : in    std_logic;
      iec_qnice_we_i         : in    std_logic;

      -- CBM-488/IEC serial (hardware) port
      iec_hardware_port_en_i : in    std_logic;
      iec_reset_n_o          : out   std_logic;
      iec_atn_n_o            : out   std_logic;
      iec_clk_en_o           : out   std_logic;
      iec_clk_n_i            : in    std_logic;
      iec_clk_n_o            : out   std_logic;
      iec_data_en_o          : out   std_logic;
      iec_data_n_i           : in    std_logic;
      iec_data_n_o           : out   std_logic;
      iec_srq_en_o           : out   std_logic;
      iec_srq_n_i            : in    std_logic;
      iec_srq_n_o            : out   std_logic
   );
end entity main;

architecture synthesis of main is

   -- Generic MiSTer VIC20 signals
   signal   drive_led : std_logic;

   -- directly connect the VIC20's CIA1 to the emulated keyboard matrix within keyboard.vhd
   signal   cia1_pa_in  : std_logic_vector(7 downto 0);
   signal   cia1_pa_out : std_logic_vector(7 downto 0);
   signal   cia1_pb_in  : std_logic_vector(7 downto 0);
   signal   cia1_pb_out : std_logic_vector(7 downto 0);

   signal   o_audio : std_logic_vector(5 downto 0);

   -- the Restore key is special : it creates a non maskable interrupt (NMI)
   signal   restore_key_n : std_logic;

   -- VIC20's IEC signals
   signal   vic20_iec_clk_out  : std_logic;
   signal   vic20_iec_clk_in   : std_logic;
   signal   vic20_iec_atn_out  : std_logic;
   signal   vic20_iec_data_out : std_logic;
   signal   vic20_iec_data_in  : std_logic;

   -- Hardware IEC port
   signal   hw_iec_clk_n_in  : std_logic;
   signal   hw_iec_data_n_in : std_logic;

   -- Simulated IEC drives
   signal   iec_drive_ce : std_logic;              -- chip enable for iec_drive (clock divider, see generate_drive_ce below)
   signal   iec_dce_sum  : integer     := 0;       -- caution: we expect 32-bit integers here and we expect the initialization to 0

   signal   iec_img_mounted  : std_logic_vector(G_VDNUM - 1 downto 0);
   signal   iec_img_readonly : std_logic;
   signal   iec_img_size     : std_logic_vector(31 downto 0);
   signal   iec_img_type     : std_logic_vector( 1 downto 0);

   signal   iec_drives_reset : std_logic_vector(G_VDNUM - 1 downto 0);
   signal   vdrives_mounted  : std_logic_vector(G_VDNUM - 1 downto 0);
   signal   cache_dirty      : std_logic_vector(G_VDNUM - 1 downto 0);
   signal   prevent_reset    : std_logic;

   signal   iec_sd_lba          : vd_vec_array(G_VDNUM - 1 downto 0)(31 downto 0);
   signal   iec_sd_blk_cnt      : vd_vec_array(G_VDNUM - 1 downto 0)( 5 downto 0);
   signal   iec_sd_rd           : vd_std_array(G_VDNUM - 1 downto 0);
   signal   iec_sd_wr           : vd_std_array(G_VDNUM - 1 downto 0);
   signal   iec_sd_ack          : vd_std_array(G_VDNUM - 1 downto 0);
   signal   iec_sd_buf_addr     : std_logic_vector(13 downto 0);
   signal   iec_sd_buf_data_in  : std_logic_vector( 7 downto 0);
   signal   iec_sd_buf_data_out : vd_vec_array(G_VDNUM - 1 downto 0)(7 downto 0);
   signal   iec_sd_buf_wr       : std_logic;
   signal   iec_par_stb_in      : std_logic;
   signal   iec_par_stb_out     : std_logic;
   signal   iec_par_data_in     : std_logic_vector(7 downto 0);
   signal   iec_par_data_out    : std_logic_vector(7 downto 0);

   -- unprocessed video output of the VIC20 core
   signal   vga_hs    : std_logic;
   signal   vga_vs    : std_logic;
   signal   vga_red   : std_logic_vector(3 downto 0);
   signal   vga_green : std_logic_vector(3 downto 0);
   signal   vga_blue  : std_logic_vector(3 downto 0);
   signal   div       : unsigned(1 downto 0);
   signal   v20_en    : std_logic;
   signal   div_ovl   : unsigned(0 downto 0);

   -- clock enable to derive the VIC20's pixel clock from the core's main clock
   signal   video_ce   : std_logic;
   signal   video_ce_d : std_logic;

   signal   reset_core_n : std_logic   := '1';
   signal   hard_reset_n : std_logic   := '1';

   constant C_HARD_RST_DELAY : natural := 100_000; -- roundabout 1/30 of a second
   signal   hard_rst_counter : natural := 0;

begin

   -- prevent data corruption by not allowing a soft reset to happen while the cache is still dirty
   -- since we can have more than one cache that might be dirty, we convert the std_logic_vector of length G_VDNUM
   -- into an unsigned and check for zero
   prevent_reset   <= '0' when unsigned(cache_dirty) = 0 else
                      '1';

   -- the color of the drive led is green normally, but it turns yellow
   -- when the cache is dirty and/or currently being flushed
   drive_led_col_o <= x"00FF00" when unsigned(cache_dirty) = 0 else
                      x"FFFF00";

   -- the drive led is on if either the C64 is writing to the virtual disk (cached in RAM)
   -- or if the dirty cache is dirty and/orcurrently being flushed to the SD card
   drive_led_o     <= drive_led when unsigned(cache_dirty) = 0 else
                      '1';

   --------------------------------------------------------------------------------------------------
   -- Hard reset
   --------------------------------------------------------------------------------------------------

   hard_reset_proc : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         if reset_soft_i = '1' or reset_hard_i = '1' then
            -- Due to sw_cartridge_wrapper's logic, reset_soft_i stays high longer than reset_hard_i.
            -- We need to make sure that this is not interfering with hard_reset_n
            if reset_hard_i = '1' then
               hard_rst_counter <= C_HARD_RST_DELAY;
               hard_reset_n     <= '0';
            end if;

            -- reset_core_n is low-active, so prevent_reset = 0 means execute reset
            -- but a hard reset can override
            reset_core_n <= prevent_reset and (not reset_hard_i);
         else
            -- The idea of the hard reset is, that while reset_core_n is back at '1' and therefore the core is
            -- running (not being reset any more), hard_reset_n stays low for C_HARD_RST_DELAY clock cycles.
            -- Reason: We need to give the KERNAL time to execute the routine $FD02 where it checks for the
            -- cartridge signature "CBM80" in $8003 onwards. In case reset_n = '0' during these tests (i.e. hard
            -- reset active) we will return zero instead of "CBM80" and therefore perform a hard reset.
            reset_core_n <= '1';
            if hard_rst_counter = 0 then
               hard_reset_n <= '1';
            else
               hard_rst_counter <= hard_rst_counter - 1;
            end if;
         end if;
      end if;
   end process hard_reset_proc;


   video_hs_o      <= not vga_hs;
   video_vs_o      <= not vga_vs;

   v20_en_proc : process (clk_main_i)
   begin
      if falling_edge(clk_main_i) then
         div    <= div + 1;
         v20_en <= and(div);
      end if;
   end process v20_en_proc;

   --------------------------------------------------------------------------------------------------
   -- MiSTer VIC 20 core / main machine
   --------------------------------------------------------------------------------------------------

   vic20_inst : entity work.vic20
      port map (
         i_sysclk      => clk_main_i,
         i_sysclk_en   => v20_en,
         i_reset       => reset_soft_i or reset_hard_i,
         i_restore_n   => restore_key_n,
         o_p2h         => open,
         i_ram_ext_ro  => ram_ext_ro_i,   -- read-only region if set
         i_ram_ext     => ram_ext_i, -- at $A000(8k),$6000(8k),$4000(8k),$2000(8k),$0400(3k)
         i_extmem_en   => '0',
         o_extmem_sel  => open,
         o_extmem_r_wn => open,
         o_extmem_addr => open,
         i_extmem_data => x"00",
         o_extmem_data => open,
         o_io2_sel     => open,
         o_io3_sel     => open,
         o_blk123_sel  => open,
         o_blk5_sel    => open,
         o_ram123_sel  => open,

         -- keyboard interface: directly connect the CIA1
         cia1_pa_i     => cia1_pa_in(0) & cia1_pa_in(6 downto 1) & cia1_pa_in(7),
         cia1_pa_o     => cia1_pa_out,
         cia1_pb_i     => cia1_pb_in(3) & cia1_pb_in(6 downto 4) & cia1_pb_in(7) & cia1_pb_in(2 downto 0),
         cia1_pb_o     => cia1_pb_out,

         -- VGA/SCART interface
         o_ce_pix      => video_ce,
         o_hsync       => vga_hs,
         o_vsync       => vga_vs,
         o_video_r     => vga_red,
         o_video_g     => vga_green,
         o_video_b     => vga_blue,
         o_hblank      => video_hblank_o,
         o_vblank      => video_vblank_o,
         i_center      => "11",
         i_pal         => '1',
         i_wide        => '0',

         -- paddle interface
         i_joy         => joy_1_right_n_i & joy_1_left_n_i & joy_1_down_n_i & joy_1_up_n_i,
         i_fire        => joy_1_fire_n_i,
         i_potx        => pot1_x_i,
         i_poty        => pot1_y_i,

         o_audio       => o_audio,

         -- IEC
         clk_i         => vic20_iec_clk_in and hw_iec_clk_n_in,
         clk_o         => vic20_iec_clk_out,
         atn_o         => vic20_iec_atn_out,
         data_i        => vic20_iec_data_in and hw_iec_data_n_in,
         data_o        => vic20_iec_data_out,

         -- Cassette drive
         cass_write    => open,
         cass_motor    => open,
         cass_sw       => '0',
         cass_read     => '0',

         rom_std       => vic20_rom_i,
         conf_clk      => conf_clk_i,
         conf_wr       => conf_wr_i,
         conf_ai       => conf_ai_i,
         conf_di       => conf_di_i
      ); -- vic20_inst

   --------------------------------------------------------------------------------------------------
   -- Generate video output for the M2M framework
   --------------------------------------------------------------------------------------------------

   video_red_o     <= vga_red & "0000";
   video_green_o   <= vga_green & "0000";
   video_blue_o    <= vga_blue & "0000";
   video_ce_o      <= video_ce and not video_ce_d;
   video_ce_ovl_o  <= -- '1' when video_retro15khz_i = '0' else
                      not div_ovl(0);

   -- Clock divider: The core's pixel clock is 1/2 of the main clock
   video_ce_proc : process (clk_video_i)
   begin
      if rising_edge(clk_video_i) then
         video_ce_d <= video_ce;
         div_ovl    <= div_ovl + 1;
      end if;
   end process video_ce_proc;


   --------------------------------------------------------------------------------------------------
   -- Keyboard- and joystick controller
   --------------------------------------------------------------------------------------------------

   -- Convert MEGA65 keystrokes to the VIC20 keyboard matrix that the CIA1 can scan
   -- and convert the MEGA65 joystick signals to CIA1 signals as well
   keyboard_inst : entity work.keyboard
      port map (
         clk_main_i      => clk_main_i,
         reset_i         => not reset_core_n,

         -- Trigger the sequence RUN<Return> to autostart PRG files
         trigger_run_i   => trigger_run_i,

         -- Interface to the MEGA65 keyboard
         key_num_i       => kb_key_num_i,
         key_pressed_n_i => kb_key_pressed_n_i,

         -- Interface to the MEGA65 joysticks
         joy_1_up_n_i    => joy_1_up_n_i,
         joy_1_down_n_i  => joy_1_down_n_i,
         joy_1_left_n_i  => joy_1_left_n_i,
         joy_1_right_n_i => joy_1_right_n_i,
         joy_1_fire_n_i  => joy_1_fire_n_i,

         joy_1_up_n_o    => joy_1_up_n_o,
         joy_1_down_n_o  => joy_1_down_n_o,
         joy_1_left_n_o  => joy_1_left_n_o,
         joy_1_right_n_o => joy_1_right_n_o,
         joy_1_fire_n_o  => joy_1_fire_n_o,

         joy_2_up_n_i    => joy_2_up_n_i,
         joy_2_down_n_i  => joy_2_down_n_i,
         joy_2_left_n_i  => joy_2_left_n_i,
         joy_2_right_n_i => joy_2_right_n_i,
         joy_2_fire_n_i  => joy_2_fire_n_i,

         joy_2_up_n_o    => joy_2_up_n_o,
         joy_2_down_n_o  => joy_2_down_n_o,
         joy_2_left_n_o  => joy_2_left_n_o,
         joy_2_right_n_o => joy_2_right_n_o,
         joy_2_fire_n_o  => joy_2_fire_n_o,

         -- Interface to the MiSTer VIC20 core that directly connects to the VIC20's CIA1 instead of
         -- going the detour of converting the MEGA65 keystrokes into PS/2 keystrokes first.
         -- This means, that the "fpga64_keyboard" entity of the original core is not used. Instead,
         -- we are modifying the "vic20_inst" entity so that we can route the CIA1's ports
         -- A and B into this keyboard driver which then emulates the behavior of the physical
         -- C64 keyboard including the possibility to "scan" via the row, i.e. pull one or more bits of
         -- port A to zero (one by one) and read via the "column" (i.e. from port B) or vice versa.
         cia1_pai_o      => cia1_pa_in,
         cia1_pao_i      => cia1_pa_out(0) & cia1_pa_out(6 downto 1) & cia1_pa_out(7),
         cia1_pbi_o      => cia1_pb_in,
         cia1_pbo_i      => cia1_pb_out(3) & cia1_pb_out(6 downto 4) & cia1_pb_out(7) & cia1_pb_out(2 downto 0),

         -- Restore key = NMI
         restore_n       => restore_key_n
      ); -- keyboard_inst

   --------------------------------------------------------------------------------------------------
   -- MiSTer audio signal processing: Convert the core's 6-bit signal to a signed 16-bit signal
   --------------------------------------------------------------------------------------------------

   audio_left_o    <= "0" & signed(o_audio) & "000000000";
   audio_right_o   <= "0" & signed(o_audio) & "000000000";


   --------------------------------------------------------------------------------------------------
   -- Hardware IEC port
   --------------------------------------------------------------------------------------------------

   handle_hardware_iec_port_proc : process (all)
   begin
      iec_reset_n_o    <= '1';
      iec_atn_n_o      <= '1';
      iec_clk_en_o     <= '0';
      iec_clk_n_o      <= '1';
      iec_data_en_o    <= '0';
      iec_data_n_o     <= '1';

      -- Since IEC is a bus, we need to connect the input lines coming from the hardware port
      -- to all participants of the bus. At this time these are:
      --    VIC20: vic20_inst using the iec_ signals
      --    Simulated disk drives: iec_drive_inst using the iec_ signals
      -- All signals are LOW active, so we need to AND them.
      -- As soon as we have more participants than just vic20_inst and iec_drive_inst we will
      -- need to have some more signals for the bus instead of directly connecting them as we do today.
      hw_iec_clk_n_in  <= '1';
      hw_iec_data_n_in <= '1';

      -- According to https://www.c64-wiki.com/wiki/Serial_Port, the VIC20 does not use the SRQ line and therefore
      -- we are at this time also not using it. The wiki article states, hat even though it is not used, it is
      -- still connected with the read line of the cassette port (although this can only detect signal edges,
      -- but not signal levels).
      -- @TODO: Investigate, if there are some edge-case use-cases that are using this "feature" and
      -- in this case enhance our simulation
      iec_srq_en_o     <= '0';
      iec_srq_n_o      <= '1';

      if iec_hardware_port_en_i = '1' then
         -- The IEC bus is low active. By default, we let the hardware bus lines float by setting the NC7SZ126P5X
         -- output driver's OE to zero. We hardcode all output lines to zero and as soon as we need to pull a line
         -- to zero, we activate the NC7SZ126P5X OE by setting it to one. This means that the actual signalling is
         -- done by changing the NC7SZ126P5X OE instead of changing the output lines to high/low. This ensures
         -- that the lines keep floating when we have "nothing to say" to the bus.
         iec_clk_n_o      <= '0';
         iec_data_n_o     <= '0';

         -- These lines are not connected to a NC7SZ126P5X since the VIC20 is supposed to be the only
         -- party in the bus who is allowed to pull this line to zero
         iec_reset_n_o    <= reset_core_n;
         iec_atn_n_o      <= vic20_iec_atn_out;

         -- Read from the hardware IEC port (see comment above: We need to connect this to i_fpga64_sid_iec and i_iec_drive)
         hw_iec_clk_n_in  <= iec_clk_n_i;
         hw_iec_data_n_in <= iec_data_n_i;

         -- Write to the IEC port by pulling the signals low and otherwise let them float (using the NC7SZ126P5X chip)
         -- We need to invert the logic, because if the VIC20 wants to pull something to LOW we need to ENABLE the NC7SZ126P5X's OE
         iec_clk_en_o     <= not vic20_iec_clk_out;
         iec_data_en_o    <= not vic20_iec_data_out;
      end if;
   end process handle_hardware_iec_port_proc;

   --------------------------------------------------------------------------------------------------
   -- MiSTer IEC drives
   --------------------------------------------------------------------------------------------------

   -- Parallel C1541 port: not implemented, yet
   iec_par_stb_in  <= '0';
   iec_par_data_in <= (others => '0');

   -- Drive is held to reset if the core is held to reset or if the drive is not mounted, yet
   -- @TODO: MiSTer also allows these options when it comes to drive-enable:
   --        "P2oPQ,Enable Drive #8,If Mounted,Always,Never;"
   --        "P2oNO,Enable Drive #9,If Mounted,Always,Never;"
   --        This code currently only implements the "If Mounted" option

   iec_drv_reset_gen : for i in 0 to G_VDNUM - 1 generate
      iec_drives_reset(i) <= (not reset_core_n) or (not vdrives_mounted(i));
   end generate iec_drv_reset_gen;

   c1541_multi_inst : entity work.c1541_multi
      generic map (
         PARPORT => 0, -- Parallel C1541 port for faster (~20x) loading time using DolphinDOS
         DUALROM => 1, -- Two switchable ROMs: Standard DOS and JiffyDOS
         DRIVES  => G_VDNUM
      )
      port map (
         clk          => clk_main_i,
         ce           => iec_drive_ce,
         reset        => iec_drives_reset,
         pause        => '0',

         -- interface to the VIC20 core
         iec_clk_i    => vic20_iec_clk_out and hw_iec_clk_n_in,
         iec_clk_o    => vic20_iec_clk_in,
         iec_atn_i    => vic20_iec_atn_out,
         iec_data_i   => vic20_iec_data_out and hw_iec_data_n_in,
         iec_data_o   => vic20_iec_data_in,

         -- disk image status
         img_mounted  => iec_img_mounted,
         img_readonly => iec_img_readonly,
         img_size     => iec_img_size,
         gcr_mode     => "00",                -- D64

         -- QNICE SD-Card/FAT32 interface
         clk_sys      => iec_clk_sd_i,

         sd_lba       => iec_sd_lba,
         sd_blk_cnt   => iec_sd_blk_cnt,
         sd_rd        => iec_sd_rd,
         sd_wr        => iec_sd_wr,
         sd_ack       => iec_sd_ack,
         sd_buff_addr => iec_sd_buf_addr,
         sd_buff_dout => iec_sd_buf_data_in,  -- data from SD card to the buffer RAM within the drive ("dout" is a strange name)
         sd_buff_din  => iec_sd_buf_data_out, -- read the buffer RAM within the drive
         sd_buff_wr   => iec_sd_buf_wr,

         -- drive led
         led          => drive_led,

         -- Parallel C1541 port
         par_stb_i    => iec_par_stb_in,
         par_stb_o    => iec_par_stb_out,
         par_data_i   => iec_par_data_in,
         par_data_o   => iec_par_data_out,

         rom_std_i    => '1',                 -- 1=use the factory default ROM
         rom_addr_i   => (others => '0'),
         rom_data_i   => (others => '0'),
         rom_data_o   => open,
         rom_wr_i     => '1'
      ); -- c1541_multi_inst

   -- 16 MHz chip enable for the IEC drives, so that ph2_r and ph2_f can be 1 MHz (C1541's CPU runs with 1 MHz)
   -- Uses a counter to compensate for clock drift, because the input clock is not exactly at 32 MHz
   --
   -- It is important that also in the HDMI-Flicker-Free-mode we are using the vanilla clock speed given by
   -- CORE_CLK_SPEED_PAL (or CORE_CLK_SPEED_NTSC) and not a speed-adjusted version of this speed. Reason:
   -- Otherwise the drift-compensation in generate_drive_ce will compensate for the slower clock speed and
   -- ensure an exact 32 MHz frequency even though the system has been slowed down by the HDMI-Flicker-Free.
   -- This leads to a different frequency ratio C64 vs 1541 and therefore to incompatibilities such as the
   -- one described in this GitHub issue:
   -- https://github.com/MJoergen/C64MEGA65/issues/2
   iec_drive_ce_proc : process (all)
      variable msum_v, nextsum_v : integer;
   begin
      msum_v    := clk_main_speed_i;
      nextsum_v := iec_dce_sum + 16000000;

      if rising_edge(clk_main_i) then
         iec_drive_ce <= '0';
         if reset_core_n = '0' then
            iec_dce_sum <= 0;
         else
            iec_dce_sum <= nextsum_v;
            if nextsum_v >= msum_v then
               iec_dce_sum  <= nextsum_v - msum_v;
               iec_drive_ce <= '1';
            end if;
         end if;
      end if;
   end process iec_drive_ce_proc;

   vdrives_inst : entity work.vdrives
      generic map (
         VDNUM => G_VDNUM, -- amount of virtual drives
         BLKSZ => 1        -- 1 = 256 bytes block size
      )
      port map (
         clk_qnice_i      => iec_clk_sd_i,
         clk_core_i       => clk_main_i,
         reset_core_i     => not reset_core_n,

         -- MiSTer's "SD config" interface, which runs in the core's clock domain
         img_mounted_o    => iec_img_mounted,
         img_readonly_o   => iec_img_readonly,
         img_size_o       => iec_img_size,
         img_type_o       => iec_img_type,   -- 00=1541 emulated GCR(D64), 01=1541 real GCR mode (G64,D64), 10=1581 (D81)

         -- While "img_mounted_o" needs to be strobed, "drive_mounted" latches the strobe in the core's clock domain,
         -- so that it can be used for resetting (and unresetting) the drive.
         drive_mounted_o  => vdrives_mounted,

         -- Cache output signals: The dirty flags is used to enforce data consistency
         -- (for example by ignoring/delaying a reset or delaying a drive unmount/mount, etc.)
         -- and to signal via "the yellow led" to the user that the cache is not yet
         -- written to the SD card, i.e. that writing is in progress
         cache_dirty_o    => cache_dirty,
         cache_flushing_o => open,

         -- MiSTer's "SD block level access" interface, which runs in QNICE's clock domain
         -- using dedicated signal on Mister's side such as "clk_sys"
         sd_lba_i         => iec_sd_lba,
         sd_blk_cnt_i     => iec_sd_blk_cnt, -- number of blocks-1
         sd_rd_i          => iec_sd_rd,
         sd_wr_i          => iec_sd_wr,
         sd_ack_o         => iec_sd_ack,

         -- MiSTer's "SD byte level access": the MiSTer components use a combination of the drive-specific sd_ack and the sd_buff_wr
         -- to determine, which RAM buffer actually needs to be written to (using the clk_qnice_i clock domain)
         sd_buff_addr_o   => iec_sd_buf_addr,
         sd_buff_dout_o   => iec_sd_buf_data_in,
         sd_buff_din_i    => iec_sd_buf_data_out,
         sd_buff_wr_o     => iec_sd_buf_wr,

         -- QNICE interface (MMIO, 4k-segmented)
         -- qnice_addr is 28-bit because we have a 16-bit window selector and a 4k window: 65536*4096 = 268.435.456 = 2^28
         qnice_addr_i     => iec_qnice_addr_i,
         qnice_data_i     => iec_qnice_data_i,
         qnice_data_o     => iec_qnice_data_o,
         qnice_ce_i       => iec_qnice_ce_i,
         qnice_we_i       => iec_qnice_we_i
      ); -- vdrives_inst

end architecture synthesis;

