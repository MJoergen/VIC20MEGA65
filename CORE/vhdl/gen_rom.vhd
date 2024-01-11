library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity gen_rom is
   generic (

      INIT_FILE  : string                       := "";
      ADDR_WIDTH : natural                      := 14;
      START_AI   : std_logic_vector(2 downto 0) := "000"
   );
   port (
      wrclock   : in    std_logic;
      wraddress : in    std_logic_vector(15 downto 0) := (others => '0');
      data      : in    std_logic_vector(7 downto 0)  := (others => '0');
      wren      : in    std_logic                     := '0';

      rdclock   : in    std_logic;
      rdaddress : in    std_logic_vector((ADDR_WIDTH - 1) downto 0);
      q         : out   std_logic_vector(7 downto 0);
      cs        : in    std_logic                     := '1'
   );
end entity gen_rom;

architecture rtl of gen_rom is

   signal q0        : std_logic_vector(7 downto 0);
   signal conf_en_s : std_logic;

begin

   conf_en_s <= '1' when (wraddress(15 downto 15 - START_AI'left)=START_AI) else
                '0';
   q         <= q0 when cs = '1' else
                (others => '1');

   tdp_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH   => ADDR_WIDTH,
         DATA_WIDTH   => 8,
         ROM_PRELOAD  => true,
         ROM_FILE     => "../../CORE/VIC20_MiSTer/" & INIT_FILE & ".hex",
         ROM_FILE_HEX => true
      )
      port map (
         clock_a   => wrclock,
         clen_a    => conf_en_s,
         address_a => wraddress(ADDR_WIDTH-1 downto 0),
         data_a    => data,
         wren_a    => wren,
         q_a       => open,

         clock_b   => rdclock,
         clen_b    => '1',
         address_b => rdaddress,
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => q0
      );

end architecture rtl;

