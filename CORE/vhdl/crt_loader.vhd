----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- This module acts as a complete wrapper around the SW cartridge emulation.
--
-- Everything is running in the QNICE clock domain.
--
-- Done by MJoergen in 2024 and licensed under GPL v3.
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use work.qnice_csr_pkg.all;

entity crt_loader is
   generic (
      G_BASE_ADDRESS : std_logic_vector(21 downto 0)
   );
   port (
      clk_i              : in    std_logic;
      rst_i              : in    std_logic;

      -- Connect to the QNICE device
      loader_addr_i      : in    std_logic_vector(27 downto 0);
      loader_data_i      : in    std_logic_vector(15 downto 0);
      loader_ce_i        : in    std_logic;
      loader_we_i        : in    std_logic;
      loader_data_o      : out   std_logic_vector(15 downto 0);
      loader_wait_o      : out   std_logic;

      -- Connect to the core memory
      core_ram_we_o      : out   std_logic;
      core_ram_addr_o    : out   std_logic_vector(15 downto 0);
      core_ram_data_o    : out   std_logic_vector(7 downto 0);
      core_reset_o       : out   std_logic;

      -- Connect to the HyperRAM
      hr_write_o         : out   std_logic;
      hr_read_o          : out   std_logic;
      hr_address_o       : out   std_logic_vector(31 downto 0);
      hr_writedata_o     : out   std_logic_vector(15 downto 0);
      hr_byteenable_o    : out   std_logic_vector( 1 downto 0);
      hr_burstcount_o    : out   std_logic_vector( 7 downto 0);
      hr_readdata_i      : in    std_logic_vector(15 downto 0);
      hr_readdatavalid_i : in    std_logic;
      hr_waitrequest_i   : in    std_logic
   );
end entity crt_loader;

architecture synthesis of crt_loader is

   signal   csr          : std_logic;
   signal   csr_wait     : std_logic;
   signal   csr_data     : std_logic_vector(15 downto 0);
   signal   req_status   : std_logic_vector( 3 downto 0);
   signal   req_length   : std_logic_vector(22 downto 0);
   signal   req_valid    : std_logic;
   signal   resp_status  : std_logic_vector( 3 downto 0);
   signal   resp_error   : std_logic_vector( 3 downto 0);
   signal   resp_address : std_logic_vector(22 downto 0);

   signal   hr_ce         : std_logic;
   signal   hr_addr       : std_logic_vector(31 downto 0);
   signal   hr_wait       : std_logic;
   signal   hr_data       : std_logic_vector(15 downto 0);
   signal   hr_byteenable : std_logic_vector( 1 downto 0);

   signal   avm_write         : std_logic;
   signal   avm_read          : std_logic;
   signal   avm_address       : std_logic_vector(31 downto 0);
   signal   avm_writedata     : std_logic_vector(15 downto 0);
   signal   avm_byteenable    : std_logic_vector( 1 downto 0);
   signal   avm_burstcount    : std_logic_vector( 7 downto 0);
   signal   avm_readdata      : std_logic_vector(15 downto 0);
   signal   avm_readdatavalid : std_logic;
   signal   avm_waitrequest   : std_logic;

   constant C_ERROR_STRINGS : string_vector(0 to 15) :=
   (
      "OK                 \n",
      "Missing CRT header \n",
      "Missing CHIP header\n",
      "Wrong CRT header   \n",
      "Wrong CHIP header  \n",
      "Truncated CHIP     \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n",
      "OK                 \n"
   );

   signal   crt_write         : std_logic;
   signal   crt_read          : std_logic;
   signal   crt_address       : std_logic_vector(31 downto 0);
   signal   crt_writedata     : std_logic_vector(15 downto 0);
   signal   crt_byteenable    : std_logic_vector(1 downto 0);
   signal   crt_burstcount    : std_logic_vector(7 downto 0);
   signal   crt_readdata      : std_logic_vector(15 downto 0);
   signal   crt_readdatavalid : std_logic;
   signal   crt_waitrequest   : std_logic;

   -- Decoded CRT headers
   signal   cart_bank_laddr : std_logic_vector(15 downto 0); -- bank loading address
   signal   cart_bank_raddr : std_logic_vector(24 downto 0); -- Byte address in HyperRAM of each bank
   signal   cart_bank_size  : std_logic_vector(15 downto 0); -- length of each bank
   signal   cart_bank_wr    : std_logic;

   signal   cache_write         : std_logic;
   signal   cache_read          : std_logic;
   signal   cache_address       : std_logic_vector(31 downto 0);
   signal   cache_writedata     : std_logic_vector(15 downto 0);
   signal   cache_byteenable    : std_logic_vector(1 downto 0);
   signal   cache_burstcount    : std_logic_vector(7 downto 0);
   signal   cache_readdata      : std_logic_vector(15 downto 0);
   signal   cache_readdatavalid : std_logic;
   signal   cache_waitrequest   : std_logic;

   signal   parse_reset : std_logic;
   signal   cache_reset : std_logic;

begin

   -- Handle the generic framework CSR registers
   qnice_csr_inst : entity work.qnice_csr
      generic map (
         G_ERROR_STRINGS => C_ERROR_STRINGS
      )
      port map (
         qnice_clk_i          => clk_i,
         qnice_rst_i          => rst_i,
         qnice_addr_i         => loader_addr_i,
         qnice_data_i         => loader_data_i,
         qnice_ce_i           => loader_ce_i,
         qnice_we_i           => loader_we_i,
         qnice_data_o         => csr_data,
         qnice_wait_o         => csr_wait,
         qnice_csr_o          => csr,
         qnice_req_status_o   => req_status,
         qnice_req_length_o   => req_length,
         qnice_resp_status_i  => resp_status,
         qnice_resp_error_i   => resp_error,
         qnice_resp_address_i => resp_address
      ); -- qnice_csr_inst

   read_proc : process (all)
   begin
      loader_data_o <= x"0000"; -- By default read back zeros.
      loader_wait_o <= '0';

      if loader_ce_i = '1' then

         case csr is

            when '0' =>
               loader_wait_o <= hr_wait;
               if loader_addr_i(0) = '1' then
                  loader_data_o <= X"00" & hr_data(15 downto 8);
               else
                  loader_data_o <= X"00" & hr_data(7 downto 0);
               end if;

            when '1' =>
               loader_wait_o <= csr_wait;
               loader_data_o <= csr_data;

            when others =>
               null;

         end case;

      end if;
   end process read_proc;

   req_valid     <= '1' when req_status = C_CSR_REQ_OK else
                    '0';

   hr_ce         <= loader_ce_i and not csr;
   hr_addr       <= std_logic_vector(("00000" & unsigned(loader_addr_i(27 downto 1))) +
                                     ("0000000000" & unsigned(G_BASE_ADDRESS)));
   hr_byteenable <= "10" when loader_addr_i(0) = '1' else
                    "01";

   qnice2hyperram_inst : entity work.qnice2hyperram
      port map (
         clk_i                 => clk_i,
         rst_i                 => rst_i,
         s_qnice_wait_o        => hr_wait,
         s_qnice_address_i     => hr_addr,
         s_qnice_cs_i          => hr_ce,
         s_qnice_write_i       => loader_we_i,
         s_qnice_writedata_i   => loader_data_i(7 downto 0) & loader_data_i(7 downto 0),
         s_qnice_byteenable_i  => hr_byteenable,
         s_qnice_readdata_o    => hr_data,
         m_avm_write_o         => avm_write,
         m_avm_read_o          => avm_read,
         m_avm_address_o       => avm_address,
         m_avm_writedata_o     => avm_writedata,
         m_avm_byteenable_o    => avm_byteenable,
         m_avm_burstcount_o    => avm_burstcount,
         m_avm_readdata_i      => avm_readdata,
         m_avm_readdatavalid_i => avm_readdatavalid,
         m_avm_waitrequest_i   => avm_waitrequest
      ); -- qnice2hyperram_inst


   crt_parser_inst : entity work.crt_parser
      port map (
         clk_i               => clk_i,
         rst_i               => rst_i,
         req_address_i       => G_BASE_ADDRESS,
         req_length_i        => req_length,
         req_start_i         => req_valid,
         resp_status_o       => resp_status,
         resp_error_o        => resp_error,
         resp_address_o      => resp_address,

         -- Connect to HyperRAM
         avm_write_o         => crt_write,
         avm_read_o          => crt_read,
         avm_address_o       => crt_address(21 downto 0),
         avm_writedata_o     => crt_writedata,
         avm_byteenable_o    => crt_byteenable,
         avm_burstcount_o    => crt_burstcount,
         avm_readdata_i      => crt_readdata,
         avm_readdatavalid_i => crt_readdatavalid,
         avm_waitrequest_i   => crt_waitrequest,

         -- Decoded CRT headers (connect to cartridge.v)
         cart_bank_laddr_o   => cart_bank_laddr,
         cart_bank_raddr_o   => cart_bank_raddr,
         cart_bank_size_o    => cart_bank_size,
         cart_bank_wr_o      => cart_bank_wr,
         cart_loading_o      => parse_reset
      ); -- crt_parser_inst

   crt_cacher_inst : entity work.crt_cacher
      port map (
         clk_i               => clk_i,
         rst_i               => rst_i,
         cart_bank_laddr_i   => cart_bank_laddr,
         cart_bank_raddr_i   => cart_bank_raddr,
         cart_bank_size_i    => cart_bank_size,
         cart_bank_wr_i      => cart_bank_wr,
         avm_write_o         => cache_write,
         avm_read_o          => cache_read,
         avm_address_o       => cache_address(21 downto 0),
         avm_writedata_o     => cache_writedata,
         avm_byteenable_o    => cache_byteenable,
         avm_burstcount_o    => cache_burstcount,
         avm_readdata_i      => cache_readdata,
         avm_readdatavalid_i => cache_readdatavalid,
         avm_waitrequest_i   => cache_waitrequest,
         core_reset_o        => cache_reset,
         core_ram_we_o       => core_ram_we_o,
         core_ram_addr_o     => core_ram_addr_o,
         core_ram_data_o     => core_ram_data_o
      ); -- crt_cacher_inst

   core_reset_o  <= parse_reset or cache_reset;

   -- Arbiter for HypeRAM access
   avm_arbit_general_inst : entity work.avm_arbit_general
      generic map (
         G_NUM_SLAVES   => 3,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i                                      => clk_i,
         rst_i                                      => rst_i,
         s_avm_write_i                              => cache_write         & crt_write         & avm_write,
         s_avm_read_i                               => cache_read          & crt_read          & avm_read,
         s_avm_address_i                            => cache_address       & crt_address       & avm_address,
         s_avm_writedata_i                          => cache_writedata     & crt_writedata     & avm_writedata,
         s_avm_byteenable_i                         => cache_byteenable    & crt_byteenable    & avm_byteenable,
         s_avm_burstcount_i                         => cache_burstcount    & crt_burstcount    & avm_burstcount,
         s_avm_readdata_o(3 * 16 - 1 downto 2 * 16) => cache_readdata,
         s_avm_readdata_o(2 * 16 - 1 downto 1 * 16) => crt_readdata,
         s_avm_readdata_o(1 * 16 - 1 downto 0 * 16) => avm_readdata,
         s_avm_readdatavalid_o(2)                   => cache_readdatavalid,
         s_avm_readdatavalid_o(1)                   => crt_readdatavalid,
         s_avm_readdatavalid_o(0)                   => avm_readdatavalid,
         s_avm_waitrequest_o(2)                     => cache_waitrequest,
         s_avm_waitrequest_o(1)                     => crt_waitrequest,
         s_avm_waitrequest_o(0)                     => avm_waitrequest,
         m_avm_write_o                              => hr_write_o,
         m_avm_read_o                               => hr_read_o,
         m_avm_address_o                            => hr_address_o,
         m_avm_writedata_o                          => hr_writedata_o,
         m_avm_byteenable_o                         => hr_byteenable_o,
         m_avm_burstcount_o                         => hr_burstcount_o,
         m_avm_readdata_i                           => hr_readdata_i,
         m_avm_readdatavalid_i                      => hr_readdatavalid_i,
         m_avm_waitrequest_i                        => hr_waitrequest_i
      ); -- avm_arbit_general_inst

end architecture synthesis;

