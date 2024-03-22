----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- This module reads the contents of the CRT file and writes to the VIC 20 memory.
--
-- done by MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity crt_cacher is
   port (
      clk_i               : in    std_logic;
      rst_i               : in    std_logic;

      -- Decoded CRT headers (connect to crt_parser)
      cart_bank_laddr_i   : in    std_logic_vector(15 downto 0); -- bank loading address
      cart_bank_raddr_i   : in    std_logic_vector(24 downto 0); -- Byte address in HyperRAM of each bank
      cart_bank_size_i    : in    std_logic_vector(15 downto 0); -- length of each bank
      cart_bank_wr_i      : in    std_logic;

      -- Connect to HyperRAM
      avm_write_o         : out   std_logic;
      avm_read_o          : out   std_logic;
      avm_address_o       : out   std_logic_vector(21 downto 0);
      avm_writedata_o     : out   std_logic_vector(15 downto 0);
      avm_byteenable_o    : out   std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out   std_logic_vector( 7 downto 0);
      avm_readdata_i      : in    std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in    std_logic;
      avm_waitrequest_i   : in    std_logic;

      -- Connect to core
      core_reset_o        : out   std_logic;
      core_ram_we_o       : out   std_logic;
      core_ram_addr_o     : out   std_logic_vector(15 downto 0);
      core_ram_data_o     : out   std_logic_vector(7 downto 0)
   );
end entity crt_cacher;

architecture synthesis of crt_cacher is

   type   state_type is (IDLE_ST, READ_ST, DMA_ST);
   signal state : state_type := IDLE_ST;

   signal hr_address   : std_logic_vector(24 downto 0);
   signal load_address : std_logic_vector(15 downto 0);
   signal size         : std_logic_vector(15 downto 0);

   signal avm_slim_write         : std_logic;
   signal avm_slim_read          : std_logic;
   signal avm_slim_address       : std_logic_vector(22 downto 0);
   signal avm_slim_writedata     : std_logic_vector(7 downto 0);
   signal avm_slim_byteenable    : std_logic_vector(0 downto 0);
   signal avm_slim_burstcount    : std_logic_vector(7 downto 0);
   signal avm_slim_readdata      : std_logic_vector(7 downto 0);
   signal avm_slim_readdatavalid : std_logic;
   signal avm_slim_waitrequest   : std_logic;

begin

   avm_slim_writedata  <= X"00";
   avm_slim_byteenable <= "0";

   core_reset_o        <= '1' when state /= IDLE_ST else
                          '0';

   avm_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         core_ram_we_o <= '0';

         if avm_slim_waitrequest = '0' then
            avm_slim_read  <= '0';
            avm_slim_write <= '0';
         end if;

         case state is

            when IDLE_ST =>
               if cart_bank_wr_i = '1' then
                  hr_address   <= cart_bank_raddr_i;
                  load_address <= cart_bank_laddr_i;
                  size         <= cart_bank_size_i;
                  state        <= READ_ST;
               end if;

            when READ_ST =>
               if avm_slim_waitrequest = '0' then
                  avm_slim_address    <= std_logic_vector(hr_address(22 downto 0));
                  avm_slim_read       <= '1';
                  avm_slim_burstcount <= X"80";
                  state               <= DMA_ST;
                  size                <= size - X"80";
                  hr_address          <= hr_address +  X"80";
               end if;

            when DMA_ST =>
               if avm_slim_readdatavalid = '1' then
                  core_ram_we_o       <= '1';
                  core_ram_addr_o     <= std_logic_vector(load_address);
                  core_ram_data_o     <= avm_slim_readdata;
                  load_address        <= load_address + 1;
                  avm_slim_burstcount <= avm_slim_burstcount - 1;

                  if avm_slim_burstcount = 1 then
                     if size > 0 then
                        state <= READ_ST;
                     else
                        state <= IDLE_ST;
                     end if;
                  end if;
               end if;

         end case;

         if rst_i = '1' then
            state          <= IDLE_ST;
            avm_slim_read  <= '0';
            avm_slim_write <= '0';
         end if;
      end if;
   end process avm_proc;

   avm_increase_inst : entity work.avm_increase
      generic map (
         G_SLAVE_ADDRESS_SIZE  => 23,
         G_SLAVE_DATA_SIZE     => 8,
         G_MASTER_ADDRESS_SIZE => 22,
         G_MASTER_DATA_SIZE    => 16
      )
      port map (
         clk_i                 => clk_i,
         rst_i                 => rst_i,
         s_avm_write_i         => avm_slim_write,
         s_avm_read_i          => avm_slim_read,
         s_avm_address_i       => avm_slim_address,
         s_avm_writedata_i     => avm_slim_writedata,
         s_avm_byteenable_i    => avm_slim_byteenable,
         s_avm_burstcount_i    => avm_slim_burstcount,
         s_avm_readdata_o      => avm_slim_readdata,
         s_avm_readdatavalid_o => avm_slim_readdatavalid,
         s_avm_waitrequest_o   => avm_slim_waitrequest,
         m_avm_write_o         => avm_write_o,
         m_avm_read_o          => avm_read_o,
         m_avm_address_o       => avm_address_o,
         m_avm_writedata_o     => avm_writedata_o,
         m_avm_byteenable_o    => avm_byteenable_o,
         m_avm_burstcount_o    => avm_burstcount_o,
         m_avm_readdata_i      => avm_readdata_i,
         m_avm_readdatavalid_i => avm_readdatavalid_i,
         m_avm_waitrequest_i   => avm_waitrequest_i
      ); -- avm_decrease_inst

end architecture synthesis;

