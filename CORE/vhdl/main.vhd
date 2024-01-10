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
   use work.video_modes_pkg.all;

entity main is
   generic (
      G_VDNUM : natural -- amount of virtual drives
   );
   port (
      clk_main_i         : in    std_logic;
      reset_soft_i       : in    std_logic;
      reset_hard_i       : in    std_logic;
      pause_i            : in    std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i   : in    natural;

      -- Video output
      video_ce_o         : out   std_logic;
      video_ce_ovl_o     : out   std_logic;
      video_red_o        : out   std_logic_vector(7 downto 0);
      video_green_o      : out   std_logic_vector(7 downto 0);
      video_blue_o       : out   std_logic_vector(7 downto 0);
      video_vs_o         : out   std_logic;
      video_hs_o         : out   std_logic;
      video_hblank_o     : out   std_logic;
      video_vblank_o     : out   std_logic;

      -- Audio output (Signed PCM)
      audio_left_o       : out   signed(15 downto 0);
      audio_right_o      : out   signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i       : in    integer range 0 to 79; -- cycles through all MEGA65 keys
      kb_key_pressed_n_i : in    std_logic;             -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- CBM-488/IEC serial port
      iec_reset_n_o      : out   std_logic;
      iec_atn_n_o        : out   std_logic;
      iec_clk_en_o       : out   std_logic;
      iec_clk_n_i        : in    std_logic;
      iec_clk_n_o        : out   std_logic;
      iec_data_en_o      : out   std_logic;
      iec_data_n_i       : in    std_logic;
      iec_data_n_o       : out   std_logic;
      iec_srq_en_o       : out   std_logic;
      iec_srq_n_i        : in    std_logic;
      iec_srq_n_o        : out   std_logic;

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i       : in    std_logic;
      joy_1_down_n_i     : in    std_logic;
      joy_1_left_n_i     : in    std_logic;
      joy_1_right_n_i    : in    std_logic;
      joy_1_fire_n_i     : in    std_logic;

      joy_2_up_n_i       : in    std_logic;
      joy_2_down_n_i     : in    std_logic;
      joy_2_left_n_i     : in    std_logic;
      joy_2_right_n_i    : in    std_logic;
      joy_2_fire_n_i     : in    std_logic;

      pot1_x_i           : in    std_logic_vector(7 downto 0);
      pot1_y_i           : in    std_logic_vector(7 downto 0);
      pot2_x_i           : in    std_logic_vector(7 downto 0);
      pot2_y_i           : in    std_logic_vector(7 downto 0)
   );
end entity main;

architecture synthesis of main is

   -- @TODO: Remove these demo core signals
   signal keyboard_n : std_logic_vector(79 downto 0);

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
   signal i_center      : std_logic_vector(1 downto 0);
   signal i_wide        : std_logic;
   signal ps2_key       : std_logic_vector(10 downto 0);
   signal tape_play     : std_logic;
   signal o_audio       : std_logic_vector(5 downto 0);
   signal cass_write    : std_logic;
   signal cass_read     : std_logic;
   signal cass_motor    : std_logic;
   signal cass_sw       : std_logic;
   signal conf_clk      : std_logic;
   signal conf_wr       : std_logic;
   signal conf_ai       : std_logic_vector(15 downto 0);
   signal conf_di       : std_logic_vector(7 downto 0);
   signal o_hsync       : std_logic;
   signal o_vsync       : std_logic;

   signal div           : unsigned(1 downto 0);
   signal v20_en        : std_logic;

begin

   video_hs_o <= not o_hsync;
   video_vs_o <= not o_vsync;

   v20_en_proc : process (clk_main_i)
   begin
      if falling_edge(clk_main_i) then
         div <= div + 1;
         v20_en <= and(div);
      end if;
   end process v20_en_proc;

   core_inst : entity work.vic20
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
         o_ce_pix      => video_ce_o,
         o_video_r     => video_red_o(7 downto 4),
         o_video_g     => video_green_o(7 downto 4),
         o_video_b     => video_blue_o(7 downto 4),
         o_hsync       => o_hsync,
         o_vsync       => o_vsync,
         o_hblank      => video_hblank_o,
         o_vblank      => video_vblank_o,
         i_center      => i_center,
         i_pal         => '1',
         i_wide        => i_wide,
         ps2_key       => ps2_key,
         tape_play     => tape_play,
         o_audio       => o_audio,
         cass_write    => cass_write,
         cass_read     => cass_read,
         cass_motor    => cass_motor,
         cass_sw       => cass_sw,
         rom_std       => '1',
         conf_clk      => conf_clk,
         conf_wr       => conf_wr,
         conf_ai       => conf_ai,
         conf_di       => conf_di
      );


   -- On video_ce_o and video_ce_ovl_o: You have an important @TODO when porting a core:
   -- video_ce_o: You need to make sure that video_ce_o divides clk_main_i such that it transforms clk_main_i
   --             into the pixelclock of the core (means: the core's native output resolution pre-scandoubler)
   -- video_ce_ovl_o: Clock enable for the OSM overlay and for sampling the core's (retro) output in a way that
   --             it is displayed correctly on a "modern" analog input device: Make sure that video_ce_ovl_o
   --             transforms clk_main_o into the post-scandoubler pixelclock that is valid for the target
   --             resolution specified by VGA_DX/VGA_DY (globals.vhd)
   -- video_retro15kHz_o: '1', if the output from the core (post-scandoubler) in the retro 15 kHz analog RGB mode.
   --             Hint: Scandoubler off does not automatically mean retro 15 kHz on.
   video_ce_ovl_o <= video_ce_o;

   -- @TODO: Keyboard mapping and keyboard behavior
   -- Each core is treating the keyboard in a different way: Some need low-active "matrices", some
   -- might need small high-active keyboard memories, etc. This is why the MiSTer2MEGA65 framework
   -- lets you define literally everything and only provides a minimal abstraction layer to the keyboard.
   -- You need to adjust keyboard.vhd to your needs
   keyboard_inst : entity work.keyboard
      port map (
         clk_main_i      => clk_main_i,

         -- Interface to the MEGA65 keyboard
         key_num_i       => kb_key_num_i,
         key_pressed_n_i => kb_key_pressed_n_i,

         -- @TODO: Create the kind of keyboard output that your core needs
         -- "example_n_o" is a low active register and used by the demo core:
         --    bit 0: Space
         --    bit 1: Return
         --    bit 2: Run/Stop
         example_n_o     => keyboard_n
      ); -- keyboard_inst

end architecture synthesis;

