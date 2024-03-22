----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- This is part of the testbench for the crt_loader module.
--
-- It simulates the core, by instantiating the CPU and 64k of RAM.
--
-- done by MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity core_sim is
   generic (
      -- Contains the kernal
      G_ROM_FILE_NAME : string
   );
   port (
      main_clk_i        : in    std_logic;
      main_rst_i        : in    std_logic;
      main_reset_core_i : in    std_logic;

      -- VIC 20 RAM
      conf_clk_i        : in    std_logic;
      conf_wr_i         : in    std_logic;
      conf_ai_i         : in    std_logic_vector(15 downto 0);
      conf_di_i         : in    std_logic_vector(7 downto 0)
   );
end entity core_sim;

architecture simulation of core_sim is

   signal main_ce                : std_logic := '0';
   signal main_ram_addr          : std_logic_vector(15 downto 0);
   signal main_ram_we            : std_logic;
   signal main_ram_data_from_cpu : std_logic_vector(7 downto 0);
   signal main_ram_data_to_cpu   : std_logic_vector(7 downto 0);

begin

   main_ce <= not main_ce when rising_edge(main_clk_i);

   cpu_65c02_inst : entity work.cpu_65c02
      port map (
         clk_i     => main_clk_i,
         rst_i     => main_rst_i or main_reset_core_i,
         ce_i      => main_ce,
         nmi_i     => '0',
         irq_i     => '0',
         addr_o    => main_ram_addr,
         wr_en_o   => main_ram_we,
         wr_data_o => main_ram_data_from_cpu,
         rd_en_o   => open,
         rd_data_i => main_ram_data_to_cpu,
         debug_o   => open
      ); -- cpu_65c02_inst

   -- VIC 20's RAM modelled as dual clock & dual port RAM so that the VIC 20 core
   -- as well as QNICE can access it
   tdp_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH   => 16,
         DATA_WIDTH   => 8,
         ROM_PRELOAD  => true,
         ROM_FILE     => G_ROM_FILE_NAME, -- Assumed to be 8k in size
         ROM_FILE_HEX => true,
         ROM_OFFSET   => 14 * 4096        -- Kernal load address
      )
      port map (
         -- VIC 20 MiSTer core
         clock_a   => main_clk_i,
         address_a => main_ram_addr,
         data_a    => main_ram_data_from_cpu,
         wren_a    => main_ram_we,
         q_a       => main_ram_data_to_cpu,

         -- Connect to crt_loader
         clock_b   => conf_clk_i,
         address_b => conf_ai_i,
         data_b    => conf_di_i,
         wren_b    => conf_wr_i,
         q_b       => open
      ); -- tdp_ram_inst

end architecture simulation;

