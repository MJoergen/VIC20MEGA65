----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- MEGA65 main file that contains the whole machine
--
-- based on VIC20_MiSTer by the MiSTer development team
-- powered by MiSTer2MEGA65 done by sy2002 and MJoergen in 2023
-- port done by MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

library work;
   use work.globals.all;
   use work.types_pkg.all;
   use work.video_modes_pkg.all;

library xpm;
   use xpm.vcomponents.all;

entity mega65_core is
   generic (
      G_BOARD : string -- Which platform are we running on.
   );
   port (
      --------------------------------------------------------------------------------------------------------
      -- QNICE Clock Domain
      --------------------------------------------------------------------------------------------------------

      -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
      qnice_clk_i             : in    std_logic;
      qnice_rst_i             : in    std_logic;

      -- Video and audio mode control
      qnice_dvi_o             : out   std_logic;             -- 0=HDMI (with sound), 1=DVI (no sound)
      qnice_video_mode_o      : out   video_mode_type;       -- Defined in video_modes_pkg.vhd
      qnice_osm_cfg_scaling_o : out   std_logic_vector(8 downto 0);
      qnice_scandoubler_o     : out   std_logic;             -- 0 = no scandoubler, 1 = scandoubler
      qnice_audio_mute_o      : out   std_logic;
      qnice_audio_filter_o    : out   std_logic;
      qnice_zoom_crop_o       : out   std_logic;
      qnice_ascal_mode_o      : out   std_logic_vector(1 downto 0);
      qnice_ascal_polyphase_o : out   std_logic;
      qnice_ascal_triplebuf_o : out   std_logic;
      qnice_retro15khz_o      : out   std_logic;             -- 0 = normal frequency, 1 = retro 15 kHz frequency
      qnice_csync_o           : out   std_logic;             -- 0 = normal HS/VS, 1 = Composite Sync

      -- Flip joystick ports
      qnice_flip_joyports_o   : out   std_logic;

      -- On-Screen-Menu selections
      qnice_osm_control_i     : in    std_logic_vector(255 downto 0);

      -- QNICE general purpose register
      qnice_gp_reg_i          : in    std_logic_vector(255 downto 0);

      -- Core-specific devices
      qnice_dev_id_i          : in    std_logic_vector(15 downto 0);
      qnice_dev_addr_i        : in    std_logic_vector(27 downto 0);
      qnice_dev_data_i        : in    std_logic_vector(15 downto 0);
      qnice_dev_data_o        : out   std_logic_vector(15 downto 0);
      qnice_dev_ce_i          : in    std_logic;
      qnice_dev_we_i          : in    std_logic;
      qnice_dev_wait_o        : out   std_logic;

      --------------------------------------------------------------------------------------------------------
      -- HyperRAM Clock Domain
      --------------------------------------------------------------------------------------------------------

      hr_clk_i                : in    std_logic;
      hr_rst_i                : in    std_logic;
      hr_core_write_o         : out   std_logic;
      hr_core_read_o          : out   std_logic;
      hr_core_address_o       : out   std_logic_vector(31 downto 0);
      hr_core_writedata_o     : out   std_logic_vector(15 downto 0);
      hr_core_byteenable_o    : out   std_logic_vector( 1 downto 0);
      hr_core_burstcount_o    : out   std_logic_vector( 7 downto 0);
      hr_core_readdata_i      : in    std_logic_vector(15 downto 0);
      hr_core_readdatavalid_i : in    std_logic;
      hr_core_waitrequest_i   : in    std_logic;
      hr_high_i               : in    std_logic;             -- Core is too fast
      hr_low_i                : in    std_logic;             -- Core is too slow

      --------------------------------------------------------------------------------------------------------
      -- Video Clock Domain
      --------------------------------------------------------------------------------------------------------

      video_clk_o             : out   std_logic;
      video_rst_o             : out   std_logic;
      video_ce_o              : out   std_logic;
      video_ce_ovl_o          : out   std_logic;
      video_red_o             : out   std_logic_vector(7 downto 0);
      video_green_o           : out   std_logic_vector(7 downto 0);
      video_blue_o            : out   std_logic_vector(7 downto 0);
      video_vs_o              : out   std_logic;
      video_hs_o              : out   std_logic;
      video_hblank_o          : out   std_logic;
      video_vblank_o          : out   std_logic;

      --------------------------------------------------------------------------------------------------------
      -- Core Clock Domain
      --------------------------------------------------------------------------------------------------------

      clk_i                   : in    std_logic;             -- 100 MHz clock

      -- Share clock and reset with the framework
      main_clk_o              : out   std_logic;             -- CORE's clock
      main_rst_o              : out   std_logic;             -- CORE's reset, synchronized

      -- M2M's reset manager provides 2 signals:
      --    m2m:   Reset the whole machine: Core and Framework
      --    core:  Only reset the core
      main_reset_m2m_i        : in    std_logic;
      main_reset_core_i       : in    std_logic;

      main_pause_core_i       : in    std_logic;

      -- On-Screen-Menu selections
      main_osm_control_i      : in    std_logic_vector(255 downto 0);

      -- QNICE general purpose register converted to main clock domain
      main_qnice_gp_reg_i     : in    std_logic_vector(255 downto 0);

      -- Audio output (Signed PCM)
      main_audio_left_o       : out   signed(15 downto 0);
      main_audio_right_o      : out   signed(15 downto 0);

      -- M2M Keyboard interface (incl. power led and drive led)
      main_kb_key_num_i       : in    integer range 0 to 79; -- cycles through all MEGA65 keys
      main_kb_key_pressed_n_i : in    std_logic;             -- low active: debounced feedback: is kb_key_num_i pressed right now?
      main_power_led_o        : out   std_logic;
      main_power_led_col_o    : out   std_logic_vector(23 downto 0);
      main_drive_led_o        : out   std_logic;
      main_drive_led_col_o    : out   std_logic_vector(23 downto 0);

      -- Joysticks and paddles input
      main_joy_1_up_n_i       : in    std_logic;
      main_joy_1_down_n_i     : in    std_logic;
      main_joy_1_left_n_i     : in    std_logic;
      main_joy_1_right_n_i    : in    std_logic;
      main_joy_1_fire_n_i     : in    std_logic;
      main_joy_1_up_n_o       : out   std_logic;
      main_joy_1_down_n_o     : out   std_logic;
      main_joy_1_left_n_o     : out   std_logic;
      main_joy_1_right_n_o    : out   std_logic;
      main_joy_1_fire_n_o     : out   std_logic;
      main_joy_2_up_n_i       : in    std_logic;
      main_joy_2_down_n_i     : in    std_logic;
      main_joy_2_left_n_i     : in    std_logic;
      main_joy_2_right_n_i    : in    std_logic;
      main_joy_2_fire_n_i     : in    std_logic;
      main_joy_2_up_n_o       : out   std_logic;
      main_joy_2_down_n_o     : out   std_logic;
      main_joy_2_left_n_o     : out   std_logic;
      main_joy_2_right_n_o    : out   std_logic;
      main_joy_2_fire_n_o     : out   std_logic;

      main_pot1_x_i           : in    std_logic_vector(7 downto 0);
      main_pot1_y_i           : in    std_logic_vector(7 downto 0);
      main_pot2_x_i           : in    std_logic_vector(7 downto 0);
      main_pot2_y_i           : in    std_logic_vector(7 downto 0);
      main_rtc_i              : in    std_logic_vector(64 downto 0);

      -- CBM-488/IEC serial port
      iec_reset_n_o           : out   std_logic;
      iec_atn_n_o             : out   std_logic;
      iec_clk_en_o            : out   std_logic;
      iec_clk_n_i             : in    std_logic;
      iec_clk_n_o             : out   std_logic;
      iec_data_en_o           : out   std_logic;
      iec_data_n_i            : in    std_logic;
      iec_data_n_o            : out   std_logic;
      iec_srq_en_o            : out   std_logic;
      iec_srq_n_i             : in    std_logic;
      iec_srq_n_o             : out   std_logic;

      -- C64 Expansion Port (aka Cartridge Port)
      cart_en_o               : out   std_logic;             -- Enable port, active high
      cart_phi2_o             : out   std_logic;
      cart_dotclock_o         : out   std_logic;
      cart_dma_i              : in    std_logic;
      cart_reset_oe_o         : out   std_logic;
      cart_reset_i            : in    std_logic;
      cart_reset_o            : out   std_logic;
      cart_game_oe_o          : out   std_logic;
      cart_game_i             : in    std_logic;
      cart_game_o             : out   std_logic;
      cart_exrom_oe_o         : out   std_logic;
      cart_exrom_i            : in    std_logic;
      cart_exrom_o            : out   std_logic;
      cart_nmi_oe_o           : out   std_logic;
      cart_nmi_i              : in    std_logic;
      cart_nmi_o              : out   std_logic;
      cart_irq_oe_o           : out   std_logic;
      cart_irq_i              : in    std_logic;
      cart_irq_o              : out   std_logic;
      cart_roml_oe_o          : out   std_logic;
      cart_roml_i             : in    std_logic;
      cart_roml_o             : out   std_logic;
      cart_romh_oe_o          : out   std_logic;
      cart_romh_i             : in    std_logic;
      cart_romh_o             : out   std_logic;
      cart_ctrl_oe_o          : out   std_logic;             -- 0 : tristate (i.e. input), 1 : output
      cart_ba_i               : in    std_logic;
      cart_rw_i               : in    std_logic;
      cart_io1_i              : in    std_logic;
      cart_io2_i              : in    std_logic;
      cart_ba_o               : out   std_logic;
      cart_rw_o               : out   std_logic;
      cart_io1_o              : out   std_logic;
      cart_io2_o              : out   std_logic;
      cart_addr_oe_o          : out   std_logic;             -- 0 : tristate (i.e. input), 1 : output
      cart_a_i                : in    unsigned(15 downto 0);
      cart_a_o                : out   unsigned(15 downto 0);
      cart_data_oe_o          : out   std_logic;             -- 0 : tristate (i.e. input), 1 : output
      cart_d_i                : in    unsigned( 7 downto 0);
      cart_d_o                : out   unsigned( 7 downto 0)
   );
end entity mega65_core;

architecture synthesis of mega65_core is

   ---------------------------------------------------------------------------------------------
   -- Clocks and active high reset signals for each clock domain
   ---------------------------------------------------------------------------------------------

   signal   main_clk  : std_logic;                                       -- Core main clock
   signal   main_rst  : std_logic;
   signal   video_clk : std_logic;                                       -- Core video clock
   signal   video_rst : std_logic;

   ---------------------------------------------------------------------------------------------
   -- main_clk (MiSTer core's clock)
   ---------------------------------------------------------------------------------------------

   ---------------------------------------------------------------------------------------------
   -- qnice_clk
   ---------------------------------------------------------------------------------------------

   -- OSM selections within qnice_osm_control_i
   constant C_MENU_HDMI_16_9_50  : natural := 7;
   constant C_MENU_HDMI_16_9_60  : natural := 8;
   constant C_MENU_HDMI_4_3_50   : natural := 9;
   constant C_MENU_HDMI_5_4_50   : natural := 10;
   constant C_MENU_HDMI_640_60   : natural := 11;
   constant C_MENU_HDMI_720_5994 : natural := 12;
   constant C_MENU_SVGA_800_60   : natural := 13;
   constant C_MENU_IEC           : natural := 17;
   constant C_MENU_CRT_EMULATION : natural := 18;
   constant C_MENU_HDMI_ZOOM     : natural := 19;
   constant C_MENU_IMPROVE_AUDIO : natural := 20;

   signal   qnice_conf_wr : std_logic;
   signal   qnice_conf_ai : std_logic_vector(15 downto 0);
   signal   qnice_conf_di : std_logic_vector(7 downto 0);

   -- QNICE signals passed down to main.vhd to handle IEC drives using vdrives.vhd
   signal   qnice_iec_qnice_ce   : std_logic;
   signal   qnice_iec_qnice_we   : std_logic;
   signal   qnice_iec_qnice_data : std_logic_vector(15 downto 0);

   signal   qnice_iec_mount_buf_ram_we   : std_logic;
   signal   qnice_iec_mount_buf_ram_data : std_logic_vector(7 downto 0); -- Disk mount buffer

begin

   -- MMCME2_ADV clock generators:
   clk_inst : entity work.clk
      port map (
         sys_clk_i   => clk_i,
         video_clk_o => video_clk,
         video_rst_o => video_rst,
         main_clk_o  => main_clk,
         main_rst_o  => main_rst
      ); -- clk_inst

   main_clk_o           <= main_clk;
   main_rst_o           <= main_rst;
   video_clk_o          <= video_clk;
   video_rst_o          <= video_rst;

   ---------------------------------------------------------------------------------------------
   -- hr_clk (HyperRAM clock)
   ---------------------------------------------------------------------------------------------

   hr_core_write_o      <= '0';
   hr_core_read_o       <= '0';
   hr_core_address_o    <= (others => '0');
   hr_core_writedata_o  <= (others => '0');
   hr_core_byteenable_o <= (others => '0');
   hr_core_burstcount_o <= (others => '0');

   ---------------------------------------------------------------------------------------------
   -- main_clk (VIC20 MiSTer Core clock)
   ---------------------------------------------------------------------------------------------

   -- Tristate all expansion port drivers that we can directly control
   -- @TODO: As soon as we support modules that can act as busmaster, we need to become more flexible here
   cart_ctrl_oe_o       <= '0';
   cart_addr_oe_o       <= '0';
   cart_data_oe_o       <= '0';
   cart_en_o            <= '0'; -- Disable port

   cart_reset_oe_o      <= '0';
   cart_game_oe_o       <= '0';
   cart_exrom_oe_o      <= '0';
   cart_nmi_oe_o        <= '0';
   cart_irq_oe_o        <= '0';
   cart_roml_oe_o       <= '0';
   cart_romh_oe_o       <= '0';

   -- Default values for all signals
   cart_phi2_o          <= '0';
   cart_reset_o         <= '1';
   cart_dotclock_o      <= '0';
   cart_game_o          <= '1';
   cart_exrom_o         <= '1';
   cart_nmi_o           <= '1';
   cart_irq_o           <= '1';
   cart_roml_o          <= '0';
   cart_romh_o          <= '0';
   cart_ba_o            <= '0';
   cart_rw_o            <= '0';
   cart_io1_o           <= '0';
   cart_io2_o           <= '0';
   cart_a_o             <= (others => '0');
   cart_d_o             <= (others => '0');

   main_joy_1_up_n_o    <= '1';
   main_joy_1_down_n_o  <= '1';
   main_joy_1_left_n_o  <= '1';
   main_joy_1_right_n_o <= '1';
   main_joy_1_fire_n_o  <= '1';
   main_joy_2_up_n_o    <= '1';
   main_joy_2_down_n_o  <= '1';
   main_joy_2_left_n_o  <= '1';
   main_joy_2_right_n_o <= '1';
   main_joy_2_fire_n_o  <= '1';


   -- MEGA65's power led: By default, it is on and glows green when the MEGA65 is powered on.
   -- We switch it to blue when a long reset is detected and as long as the user keeps pressing the preset button
   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i else
                           x"00FF00";

   -- main.vhd contains the actual MiSTer core
   main_inst : entity work.main
      generic map (
         G_VDNUM => C_VDNUM
      )
      port map (
         clk_main_i             => main_clk,
         clk_video_i            => video_clk,
         reset_soft_i           => main_reset_core_i,
         reset_hard_i           => main_reset_m2m_i,
         pause_i                => main_pause_core_i,

         ---------------------------
         -- Configuration options
         ---------------------------

         vic20_rom_i            => '0',

         clk_main_speed_i       => CORE_CLK_SPEED,

         ---------------------------
         -- VIC 20 I/O ports
         ---------------------------

         -- M2M Keyboard interface
         kb_key_num_i           => main_kb_key_num_i,
         kb_key_pressed_n_i     => main_kb_key_pressed_n_i,

         -- MEGA65 joysticks and paddles
         joy_1_up_n_i           => main_joy_1_up_n_i,
         joy_1_down_n_i         => main_joy_1_down_n_i,
         joy_1_left_n_i         => main_joy_1_left_n_i,
         joy_1_right_n_i        => main_joy_1_right_n_i,
         joy_1_fire_n_i         => main_joy_1_fire_n_i,
         pot1_x_i               => main_pot1_x_i,
         pot1_y_i               => main_pot1_y_i,

         -- Video output
         -- This is PAL 720x576 @ 50 Hz (pixel clock 27 MHz), but synchronized to main_clk (54 MHz).
         video_ce_o             => video_ce_o,
         video_ce_ovl_o         => video_ce_ovl_o,
         video_red_o            => video_red_o(7 downto 4),
         video_green_o          => video_green_o(7 downto 4),
         video_blue_o           => video_blue_o(7 downto 4),
         video_vs_o             => video_vs_o,
         video_hs_o             => video_hs_o,
         video_hblank_o         => video_hblank_o,
         video_vblank_o         => video_vblank_o,

         -- Audio output (PCM format, signed values)
         audio_left_o           => main_audio_left_o,
         audio_right_o          => main_audio_right_o,

         -- VIC20 drive led
         drive_led_o            => main_drive_led_o,
         drive_led_col_o        => main_drive_led_col_o,

         -- VIC 20 RAM
         conf_clk_i             => qnice_clk_i,
         conf_wr_i              => qnice_conf_wr,
         conf_ai_i              => qnice_conf_ai,
         conf_di_i              => qnice_conf_di,

         -- IEC handled by QNICE
         iec_clk_sd_i           => qnice_clk_i,   -- "sd card write clock" for floppy drive internal dual clock RAM buffer
         iec_qnice_addr_i       => qnice_dev_addr_i,
         iec_qnice_data_i       => qnice_dev_data_i,
         iec_qnice_data_o       => qnice_iec_qnice_data,
         iec_qnice_ce_i         => qnice_iec_qnice_ce,
         iec_qnice_we_i         => qnice_iec_qnice_we,

         -- CBM-488/IEC serial (hardware) port
         iec_hardware_port_en_i => main_osm_control_i(C_MENU_IEC),
         iec_reset_n_o          => iec_reset_n_o,
         iec_atn_n_o            => iec_atn_n_o,
         iec_clk_en_o           => iec_clk_en_o,
         iec_clk_n_i            => iec_clk_n_i,
         iec_clk_n_o            => iec_clk_n_o,
         iec_data_en_o          => iec_data_en_o,
         iec_data_n_i           => iec_data_n_i,
         iec_data_n_o           => iec_data_n_o,
         iec_srq_en_o           => iec_srq_en_o,
         iec_srq_n_i            => iec_srq_n_i,
         iec_srq_n_o            => iec_srq_n_o
      ); -- main_inst

   video_red_o(3 downto 0)   <= "0000";
   video_green_o(3 downto 0) <= "0000";
   video_blue_o(3 downto 0)  <= "0000";


   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- Due to a discussion on the MEGA65 discord (https://discord.com/channels/719326990221574164/794775503818588200/1039457688020586507)
   -- we decided to choose a naming convention for the PAL modes that might be more intuitive for the end users than it is
   -- for the programmers: "4:3" means "meant to be run on a 4:3 monitor", "5:4 on a 5:4 monitor".
   -- The technical reality is though, that in our "5:4" mode we are actually doing a 4/3 aspect ratio adjustment
   -- while in the 4:3 mode we are outputting a 5:4 image. This is kind of odd, but it seemed that our 4/3 aspect ratio
   -- adjusted image looks best on a 5:4 monitor and the other way round.
   -- Not sure if this will stay forever or if we will come up with a better naming convention.
   qnice_video_mode_o        <= C_VIDEO_SVGA_800_60 when qnice_osm_control_i(C_MENU_SVGA_800_60)    = '1' else
                                C_VIDEO_HDMI_720_5994 when qnice_osm_control_i(C_MENU_HDMI_720_5994)  = '1' else
                                C_VIDEO_HDMI_640_60 when qnice_osm_control_i(C_MENU_HDMI_640_60)    = '1' else
                                C_VIDEO_HDMI_5_4_50 when qnice_osm_control_i(C_MENU_HDMI_5_4_50)    = '1' else
                                C_VIDEO_HDMI_4_3_50 when qnice_osm_control_i(C_MENU_HDMI_4_3_50)    = '1' else
                                C_VIDEO_HDMI_16_9_60 when qnice_osm_control_i(C_MENU_HDMI_16_9_60)   = '1' else
                                C_VIDEO_HDMI_16_9_50;

   -- Use On-Screen-Menu selections to configure several audio and video settings
   -- Video and audio mode control
   qnice_dvi_o               <= '0';                                       -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_scandoubler_o       <= '1';                                       -- no scandoubler
   qnice_audio_mute_o        <= '0';                                       -- audio is not muted
   qnice_audio_filter_o      <= qnice_osm_control_i(C_MENU_IMPROVE_AUDIO); -- 0 = raw audio, 1 = use filters from globals.vhd
   qnice_zoom_crop_o         <= qnice_osm_control_i(C_MENU_HDMI_ZOOM);     -- 0 = no zoom/crop

   -- These two signals are often used as a pair (i.e. both '1'), particularly when
   -- you want to run old analog cathode ray tube monitors or TVs (via SCART)
   -- If you want to provide your users a choice, then a good choice is:
   --    "Standard VGA":                     qnice_retro15kHz_o=0 and qnice_csync_o=0
   --    "Retro 15 kHz with HSync and VSync" qnice_retro15kHz_o=1 and qnice_csync_o=0
   --    "Retro 15 kHz with CSync"           qnice_retro15kHz_o=1 and qnice_csync_o=1
   qnice_retro15khz_o        <= '0';
   qnice_csync_o             <= '0';
   qnice_osm_cfg_scaling_o   <= (others => '1');

   -- ascal filters that are applied while processing the input
   -- 00 : Nearest Neighbour
   -- 01 : Bilinear
   -- 10 : Sharp Bilinear
   -- 11 : Bicubic
   qnice_ascal_mode_o        <= "00";

   -- If polyphase is '1' then the ascal filter mode is ignored and polyphase filters are used instead
   -- @TODO: Right now, the filters are hardcoded in the M2M framework, we need to make them changeable inside m2m-rom.asm
   qnice_ascal_polyphase_o   <= qnice_osm_control_i(C_MENU_CRT_EMULATION);

   -- ascal triple-buffering
   -- @TODO: Right now, the M2M framework only supports OFF, so do not touch until the framework is upgraded
   qnice_ascal_triplebuf_o   <= '0';

   -- Flip joystick ports (i.e. the joystick in port 2 is used as joystick 1 and vice versa)
   qnice_flip_joyports_o     <= '0';

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain, device IDs in globals.vhd)
   ---------------------------------------------------------------------------------------------

   core_specific_devices_proc : process (all)
   begin
      -- Avoid latches
      qnice_dev_data_o           <= x"EEEE";
      qnice_dev_wait_o           <= '0';
      qnice_conf_ai              <= (others => '0');
      qnice_conf_wr              <= '0';
      qnice_conf_di              <= (others => '0');
      qnice_iec_qnice_ce         <= '0';
      qnice_iec_qnice_we         <= '0';
      qnice_iec_mount_buf_ram_we <= '0';

      case qnice_dev_id_i is

         -- VIC20 RAM
         when C_DEV_VIC20_RAM =>
            qnice_conf_ai <= qnice_dev_addr_i(15 downto 0);
            qnice_conf_wr <= qnice_dev_we_i;
            qnice_conf_di <= qnice_dev_data_i(7 downto 0);

         -- IEC drives
         when C_DEV_IEC_VDRIVES =>
            qnice_iec_qnice_ce <= qnice_dev_ce_i;
            qnice_iec_qnice_we <= qnice_dev_we_i;
            qnice_dev_data_o   <= qnice_iec_qnice_data;

         -- Disk mount buffer RAM
         when C_DEV_IEC_MOUNT =>
            qnice_iec_mount_buf_ram_we <= qnice_dev_we_i;
            qnice_dev_data_o           <= x"00" & qnice_iec_mount_buf_ram_data;

         when others =>
            null;

      end case;

      null;
   end process core_specific_devices_proc;

   -- For now: Let's use a simple BRAM (using only 1 port will make a BRAM) for buffering
   -- the disks that we are mounting. This will work for D64 only.
   -- @TODO: Switch to HyperRAM at a later stage
   mount_buf_ram_inst : entity work.dualport_2clk_ram
      generic map (
         ADDR_WIDTH   => 18,
         DATA_WIDTH   => 8,
         MAXIMUM_SIZE => 197376,        -- maximum size of any D64 image: non-standard 40-track incl. 768 error bytes
         FALLING_A    => true
      )
      port map (
         -- QNICE only
         clock_a   => qnice_clk_i,
         address_a => qnice_dev_addr_i(17 downto 0),
         data_a    => qnice_dev_data_i(7 downto 0),
         wren_a    => qnice_iec_mount_buf_ram_we,
         q_a       => qnice_iec_mount_buf_ram_data
      ); -- mount_buf_ram_inst

end architecture synthesis;

