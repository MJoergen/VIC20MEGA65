----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.vdrives_pkg;

entity main is
   generic (
      G_VDNUM : natural -- amount of virtual drives
   );
   port (
      clk_main_i             : in    std_logic;
      clk_video_i            : in    std_logic;
      reset_soft_i           : in    std_logic;
      reset_hard_i           : in    std_logic;
      pause_i                : in    std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i       : in    natural;

      -- Access to main memory
      conf_clk_i             : in    std_logic;
      conf_wr_i              : in    std_logic;
      conf_ai_i              : in    std_logic_vector(15 downto 0);
      conf_di_i              : in    std_logic_vector(7 downto 0);

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

      -- M2M Keyboard interface
      kb_key_num_i           : in    integer range 0 to 79; -- cycles through all MEGA65 keys
      kb_key_pressed_n_i     : in    std_logic;             -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- VIC20 IEC handled by QNICE
      vic20_clk_sd_i         : in    std_logic;             -- QNICE "sd card write clock" for floppy drive internal dual clock RAM buffer
      vic20_qnice_addr_i     : in    std_logic_vector(27 downto 0);
      vic20_qnice_data_i     : in    std_logic_vector(15 downto 0);
      vic20_qnice_data_o     : out   std_logic_vector(15 downto 0);
      vic20_qnice_ce_i       : in    std_logic;
      vic20_qnice_we_i       : in    std_logic;

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
      iec_srq_n_o            : out   std_logic;

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i           : in    std_logic;
      joy_1_down_n_i         : in    std_logic;
      joy_1_left_n_i         : in    std_logic;
      joy_1_right_n_i        : in    std_logic;
      joy_1_fire_n_i         : in    std_logic;

      joy_2_up_n_i           : in    std_logic;
      joy_2_down_n_i         : in    std_logic;
      joy_2_left_n_i         : in    std_logic;
      joy_2_right_n_i        : in    std_logic;
      joy_2_fire_n_i         : in    std_logic;

      pot1_x_i               : in    std_logic_vector(7 downto 0);
      pot1_y_i               : in    std_logic_vector(7 downto 0);
      pot2_x_i               : in    std_logic_vector(7 downto 0);
      pot2_y_i               : in    std_logic_vector(7 downto 0)
   );
end entity main;

architecture synthesis of main is

   -- @TODO: Remove these demo core signals
   signal keyboard_n : std_logic_vector(79 downto 0);

   signal reset_core_n  : std_logic;

   signal i_ram_ext_ro  : std_logic_vector(4 downto 0); -- read-only region if set
   signal i_ram_ext     : std_logic_vector(4 downto 0); -- at $A000(8k),$6000(8k),$4000(8k),$2000(8k),$0400(3k)
   signal i_extmem_en   : std_logic;
   signal o_extmem_sel  : std_logic;
   signal o_extmem_r_wn : std_logic;
   signal o_extmem_addr : std_logic_vector(15 downto 0);
   signal i_extmem_data : std_logic_vector(7 downto 0);
   signal o_extmem_data : std_logic_vector(7 downto 0);
   signal o_io2_sel     : std_logic;
   signal o_io3_sel     : std_logic;
   signal o_blk123_sel  : std_logic;
   signal o_blk5_sel    : std_logic;
   signal o_ram123_sel  : std_logic;
   signal tape_play     : std_logic;
   signal o_audio       : std_logic_vector(5 downto 0);
   signal cass_write    : std_logic;
   signal cass_read     : std_logic;
   signal cass_motor    : std_logic;
   signal cass_sw       : std_logic;
   signal o_hsync       : std_logic;
   signal o_vsync       : std_logic;

   signal div     : unsigned(1 downto 0);
   signal v20_en  : std_logic;
   signal div_ovl : unsigned(0 downto 0);

   signal video_ce   : std_logic;
   signal video_ce_d : std_logic;

   signal cia1_pa_in  : std_logic_vector(7 downto 0);
   signal cia1_pa_out : std_logic_vector(7 downto 0);
   signal cia1_pb_in  : std_logic_vector(7 downto 0);
   signal cia1_pb_out : std_logic_vector(7 downto 0);

   -- VIC20's IEC signals
   signal vic20_iec_clk_o  : std_logic;
   signal vic20_iec_clk_i  : std_logic;
   signal vic20_iec_atn_o  : std_logic;
   signal vic20_iec_data_o : std_logic;
   signal vic20_iec_data_i : std_logic;

   -- Hardware IEC port
   signal hw_iec_clk_n_i  : std_logic;
   signal hw_iec_data_n_i : std_logic;

   -- Simulated IEC drives
   signal iec_drive_ce : std_logic;                     -- chip enable for iec_drive (clock divider, see generate_drive_ce below)
   signal iec_dce_sum  : integer := 0;                  -- caution: we expect 32-bit integers here and we expect the initialization to 0

   signal iec_img_mounted_i  : std_logic_vector(G_VDNUM - 1 downto 0);
   signal iec_img_readonly_i : std_logic;
   signal iec_img_size_i     : std_logic_vector(31 downto 0);
   signal iec_img_type_i     : std_logic_vector( 1 downto 0);

   signal iec_drives_reset : std_logic_vector(G_VDNUM - 1 downto 0);
   signal vdrives_mounted  : std_logic_vector(G_VDNUM - 1 downto 0);
   signal cache_dirty      : std_logic_vector(G_VDNUM - 1 downto 0);
   signal prevent_reset    : std_logic;

   signal iec_sd_lba_o      : vdrives_pkg.vd_vec_array(G_VDNUM - 1 downto 0)(31 downto 0);
   signal iec_sd_blk_cnt_o  : vdrives_pkg.vd_vec_array(G_VDNUM - 1 downto 0)( 5 downto 0);
   signal iec_sd_rd_o       : vdrives_pkg.vd_std_array(G_VDNUM - 1 downto 0);
   signal iec_sd_wr_o       : vdrives_pkg.vd_std_array(G_VDNUM - 1 downto 0);
   signal iec_sd_ack_i      : vdrives_pkg.vd_std_array(G_VDNUM - 1 downto 0);
   signal iec_sd_buf_addr_i : std_logic_vector(13 downto 0);
   signal iec_sd_buf_data_i : std_logic_vector( 7 downto 0);
   signal iec_sd_buf_data_o : vdrives_pkg.vd_vec_array(G_VDNUM - 1 downto 0)(7 downto 0);
   signal iec_sd_buf_wr_i   : std_logic;
   signal iec_par_stb_i     : std_logic;
   signal iec_par_stb_o     : std_logic;
   signal iec_par_data_i    : std_logic_vector(7 downto 0);
   signal iec_par_data_o    : std_logic_vector(7 downto 0);
   signal iec_rom_std_i     : std_logic;
   signal iec_rom_addr_i    : std_logic_vector(15 downto 0);
   signal iec_rom_data_i    : std_logic_vector( 7 downto 0);
   signal iec_rom_wr_i      : std_logic;

begin

   video_hs_o    <= not o_hsync;
   video_vs_o    <= not o_vsync;

   v20_en_proc : process (clk_main_i)
   begin
      if falling_edge(clk_main_i) then
         div    <= div + 1;
         v20_en <= and(div);
      end if;
   end process v20_en_proc;

   video_ce_proc : process (clk_video_i)
   begin
      if rising_edge(clk_video_i) then
         video_ce_d     <= video_ce;
         video_ce_o     <= video_ce and not video_ce_d;

         div_ovl        <= div_ovl + 1;
         video_ce_ovl_o <= and(div_ovl);
      end if;
   end process video_ce_proc;

   audio_left_o  <= signed("0" & o_audio & "000000000");
   audio_right_o <= signed("0" & o_audio & "000000000");

   vic20_inst : entity work.vic20
      port map (
         i_sysclk      => clk_main_i,
         i_sysclk_en   => v20_en,
         i_reset       => reset_soft_i or reset_hard_i,
         o_p2h         => open,
         atn_o         => iec_atn_n_o,
         clk_o         => iec_clk_n_o,
         clk_i         => iec_clk_n_i,
         data_o        => iec_data_n_o,
         data_i        => iec_data_n_i,
         i_joy         => joy_1_right_n_i & joy_1_left_n_i & joy_1_down_n_i & joy_1_up_n_i,
         i_fire        => joy_1_fire_n_i,
         i_potx        => pot1_x_i,
         i_poty        => pot1_y_i,
         i_ram_ext_ro  => i_ram_ext_ro,
         i_ram_ext     => i_ram_ext,
         i_extmem_en   => i_extmem_en,
         o_extmem_sel  => o_extmem_sel,
         o_extmem_r_wn => o_extmem_r_wn,
         o_extmem_addr => o_extmem_addr,
         i_extmem_data => i_extmem_data,
         o_extmem_data => o_extmem_data,
         o_io2_sel     => o_io2_sel,
         o_io3_sel     => o_io3_sel,
         o_blk123_sel  => o_blk123_sel,
         o_blk5_sel    => o_blk5_sel,
         o_ram123_sel  => o_ram123_sel,
         o_ce_pix      => video_ce,
         o_video_r     => video_red_o(7 downto 4),
         o_video_g     => video_green_o(7 downto 4),
         o_video_b     => video_blue_o(7 downto 4),
         o_hsync       => o_hsync,
         o_vsync       => o_vsync,
         o_hblank      => video_hblank_o,
         o_vblank      => video_vblank_o,
         i_center      => "11",
         i_pal         => '1',
         i_wide        => '0',
         cia1_pa_i     => cia1_pa_in(0) & cia1_pa_in(6 downto 1) & cia1_pa_in(7),
         cia1_pa_o     => cia1_pa_out,
         cia1_pb_i     => cia1_pb_in(3) & cia1_pb_in(6 downto 4) & cia1_pb_in(7) & cia1_pb_in(2 downto 0),
         cia1_pb_o     => cia1_pb_out,
         tape_play     => tape_play,
         o_audio       => o_audio,
         cass_write    => cass_write,
         cass_read     => cass_read,
         cass_motor    => cass_motor,
         cass_sw       => cass_sw,
         rom_std       => '1',
         conf_clk      => conf_clk_i,
         conf_wr       => conf_wr_i,
         conf_ai       => conf_ai_i,
         conf_di       => conf_di_i
      ); -- vic20_inst

   keyboard_inst : entity work.keyboard
      port map (
         clk_main_i      => clk_main_i,
         reset_i         => reset_hard_i,
         trigger_run_i   => '0',

         -- Interface to the MEGA65 keyboard
         key_num_i       => kb_key_num_i,
         key_pressed_n_i => kb_key_pressed_n_i,

         cia1_pao_i      => cia1_pa_out(0) & cia1_pa_out(6 downto 1) & cia1_pa_out(7),
         cia1_pai_o      => cia1_pa_in,
         cia1_pbo_i      => cia1_pb_out(3) & cia1_pb_out(6 downto 4) & cia1_pb_out(7) & cia1_pb_out(2 downto 0),
         cia1_pbi_o      => cia1_pb_in
      ); -- keyboard_inst


   reset_core_n <= not reset_soft_i;

   --------------------------------------------------------------------------------------------------
   -- MiSTer IEC drives
   --------------------------------------------------------------------------------------------------

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
         PARPORT => 0,
         DUALROM => 1,
         DRIVES  => G_VDNUM
      )
      port map (
         clk          => clk_main_i,
         ce           => iec_drive_ce,
         reset        => iec_drives_reset,

         -- interface to the VIC20 core
         iec_clk_i    => vic20_iec_clk_o and hw_iec_clk_n_i,
         iec_clk_o    => vic20_iec_clk_i,
         iec_atn_i    => vic20_iec_atn_o,
         iec_data_i   => vic20_iec_data_o and hw_iec_data_n_i,
         iec_data_o   => vic20_iec_data_i,

         -- disk image status
         img_mounted  => iec_img_mounted_i,
         img_readonly => iec_img_readonly_i,
         img_size     => iec_img_size_i,
         gcr_mode     => "11",

         -- QNICE SD-Card/FAT32 interface
         clk_sys      => vic20_clk_sd_i,

         sd_lba       => iec_sd_lba_o,
         sd_blk_cnt   => iec_sd_blk_cnt_o,
         sd_rd        => iec_sd_rd_o,
         sd_wr        => iec_sd_wr_o,
         sd_ack       => iec_sd_ack_i,
         sd_buff_addr => iec_sd_buf_addr_i,
         sd_buff_dout => iec_sd_buf_data_i,
         sd_buff_din  => iec_sd_buf_data_o,
         sd_buff_wr   => iec_sd_buf_wr_i,

         -- drive led
         led          => vic20_drive_led,

         -- Access custom rom (DOS): All in QNICE clock domain but rom_std_i is in main clock domain
         rom_std_i    => vic20_rom_i(0) or vic20_rom_i(1),
         rom_addr_i   => c1541rom_addr_i,
         rom_data_i   => c1541rom_data_i,
         rom_wr_i     => c1541rom_we_i,
         rom_data_o   => c1541rom_data_o
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
         VDNUM => G_VDNUM,
         BLKSZ => 1
      )
      port map (
         clk_qnice_i      => vic20_clk_sd_i,
         clk_core_i       => clk_main_i,
         reset_core_i     => not reset_core_n,

         -- MiSTer's "SD config" interface, which runs in the core's clock domain
         img_mounted_o    => iec_img_mounted_i,
         img_readonly_o   => iec_img_readonly_i,
         img_size_o       => iec_img_size_i,
         img_type_o       => iec_img_type_i,

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
         sd_lba_i         => iec_sd_lba_o,
         sd_blk_cnt_i     => iec_sd_blk_cnt_o,
         sd_rd_i          => iec_sd_rd_o,
         sd_wr_i          => iec_sd_wr_o,
         sd_ack_o         => iec_sd_ack_i,

         -- MiSTer's "SD byte level access": the MiSTer components use a combination of the drive-specific sd_ack and the sd_buff_wr
         -- to determine, which RAM buffer actually needs to be written to (using the clk_qnice_i clock domain)
         sd_buff_addr_o   => iec_sd_buf_addr_i,
         sd_buff_dout_o   => iec_sd_buf_data_i,
         sd_buff_din_i    => iec_sd_buf_data_o,
         sd_buff_wr_o     => iec_sd_buf_wr_i,

         -- QNICE interface (MMIO, 4k-segmented)
         -- qnice_addr is 28-bit because we have a 16-bit window selector and a 4k window: 65536*4096 = 268.435.456 = 2^28
         qnice_addr_i     => vic20_qnice_addr_i,
         qnice_data_i     => vic20_qnice_data_i,
         qnice_data_o     => vic20_qnice_data_o,
         qnice_ce_i       => vic20_qnice_ce_i,
         qnice_we_i       => vic20_qnice_we_i
      ); -- vdrives_inst

end architecture synthesis;

