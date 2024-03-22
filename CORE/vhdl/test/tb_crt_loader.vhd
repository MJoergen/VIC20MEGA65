----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- This is a testbench for the crt_loader module.
--
-- done by MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity tb_crt_loader is
   generic (
      G_ROM_FILE_NAME : string; -- Kernal
      G_CRT_FILE_NAME : string
   );
end entity tb_crt_loader;

architecture simulation of tb_crt_loader is

   -- Clock and reset
   signal qnice_clk     : std_logic := '0';
   signal qnice_rst     : std_logic := '1';
   signal qnice_running : std_logic := '1';
   signal main_clk      : std_logic := '0';
   signal main_rst      : std_logic := '1';
   signal main_running  : std_logic := '1';
   signal hr_clk        : std_logic := '0';
   signal hr_rst        : std_logic := '1';
   signal hr_running    : std_logic := '1';

   signal main_reset_core : std_logic;

   signal loader_addr      : std_logic_vector(27 downto 0);
   signal loader_writedata : std_logic_vector(15 downto 0);
   signal loader_ce        : std_logic;
   signal loader_we        : std_logic;
   signal loader_readdata  : std_logic_vector(15 downto 0);
   signal loader_wait      : std_logic;

   signal core_ram_we       : std_logic;
   signal core_ram_addr     : std_logic_vector(15 downto 0);
   signal core_ram_data_out : std_logic_vector(7 downto 0);
   signal core_reset        : std_logic;

   signal hr_write         : std_logic;
   signal hr_read          : std_logic;
   signal hr_address       : std_logic_vector(31 downto 0);
   signal hr_writedata     : std_logic_vector(15 downto 0);
   signal hr_byteenable    : std_logic_vector( 1 downto 0);
   signal hr_burstcount    : std_logic_vector( 7 downto 0);
   signal hr_readdata      : std_logic_vector(15 downto 0);
   signal hr_readdatavalid : std_logic;
   signal hr_waitrequest   : std_logic;
   signal hr_length        : natural;

begin

   -------------------
   -- Clock and reset
   -------------------

   qnice_clk <= (qnice_running or core_reset) and not qnice_clk after 10 ns;
   main_clk  <= main_running  and not main_clk  after 15 ns;
   hr_clk    <= hr_running    and not hr_clk    after 5 ns;

   qnice_rst <= '1', '0' after 100 ns;
   main_rst  <= '1', '0' after 100 ns;
   hr_rst    <= '1', '0' after 100 ns;


   -------------------
   -- Instantiate DUT
   -------------------

   crt_loader_inst : entity work.crt_loader
      generic map (
         G_BASE_ADDRESS => (others => '0')
      )
      port map (
         clk_i              => qnice_clk,
         rst_i              => qnice_rst,
         loader_addr_i      => loader_addr,
         loader_data_i      => loader_writedata,
         loader_ce_i        => loader_ce,
         loader_we_i        => loader_we,
         loader_data_o      => loader_readdata,
         loader_wait_o      => loader_wait,
         core_ram_we_o      => core_ram_we,
         core_ram_addr_o    => core_ram_addr,
         core_ram_data_o    => core_ram_data_out,
         core_reset_o       => core_reset,
         hr_write_o         => hr_write,
         hr_read_o          => hr_read,
         hr_address_o       => hr_address,
         hr_writedata_o     => hr_writedata,
         hr_byteenable_o    => hr_byteenable,
         hr_burstcount_o    => hr_burstcount,
         hr_readdata_i      => hr_readdata,
         hr_readdatavalid_i => hr_readdatavalid,
         hr_waitrequest_i   => hr_waitrequest
      ); -- crt_loader_inst

   -----------------------------------
   -- Instantiate simulation models
   -----------------------------------

   qnice_sim_inst : entity work.qnice_sim
      port map (
         qnice_clk_i       => qnice_clk,
         qnice_rst_i       => qnice_rst,
         qnice_addr_o      => loader_addr,
         qnice_writedata_o => loader_writedata,
         qnice_ce_o        => loader_ce,
         qnice_we_o        => loader_we,
         qnice_readdata_i  => loader_readdata,
         qnice_wait_i      => loader_wait,
         qnice_length_i    => std_logic_vector(to_unsigned(hr_length * 2, 32)),
         qnice_running_o   => qnice_running
      ); -- qnice_sim_inst

   core_sim_inst : entity work.core_sim
      generic map (
         G_ROM_FILE_NAME => G_ROM_FILE_NAME
      )
      port map (
         main_clk_i        => main_clk,
         main_rst_i        => main_rst,
         main_reset_core_i => core_reset,

         -- VIC 20 RAM
         conf_clk_i        => qnice_clk,
         conf_wr_i         => core_ram_we,
         conf_ai_i         => core_ram_addr,
         conf_di_i         => core_ram_data_out
      ); -- core_sim_inst

   avm_rom_inst : entity work.avm_rom
      generic map (
         G_INIT_FILE    => G_CRT_FILE_NAME,
         G_ADDRESS_SIZE => 16,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i               => qnice_clk,
         rst_i               => qnice_rst,
         avm_write_i         => hr_write,
         avm_read_i          => hr_read,
         avm_address_i       => hr_address(15 downto 0),
         avm_writedata_i     => hr_writedata,
         avm_byteenable_i    => hr_byteenable,
         avm_burstcount_i    => hr_burstcount,
         avm_readdata_o      => hr_readdata,
         avm_readdatavalid_o => hr_readdatavalid,
         avm_waitrequest_o   => hr_waitrequest,
         length_o            => hr_length
      ); -- avm_rom_inst

end architecture simulation;

