----------------------------------------------------------------------------------
-- VIC 20 for MEGA65
--
-- This module reads and parses the CRT file that is loaded into the HyperRAM device.
-- It stores decoded header information in various tables.
--
-- It acts as a master towards the HyperRAM.
-- The maximum amount of addressable HyperRAM is 22 address bits @ 16 data bits, i.e. 8 MB of memory.
-- Not all this memory will be available to the CRT file, though.
-- The CRT file is stored in little-endian format, i.e. even address bytes are in bits 7-0 and
-- odd address bytes are in bits 15-8.
--
-- req_start_i   : Asserted when the entire CRT file has been loaded verbatim into HyperRAM.
-- req_address_i : The start address in HyperRAM (in units of 16-bit words).
-- req_length_i  : The length of the CRT file (in units of bytes).
--
-- done by MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use ieee.numeric_std_unsigned.all;
   use work.qnice_csr_pkg.all;

entity crt_parser is
   port (
      clk_i               : in    std_logic;
      rst_i               : in    std_logic;

      -- Control interface (QNICE)
      req_start_i         : in    std_logic;
      req_address_i       : in    std_logic_vector(21 downto 0); -- Address in HyperRAM of start of CRT file
      req_length_i        : in    std_logic_vector(22 downto 0); -- Length of CRT file in HyperRAM
      resp_status_o       : out   std_logic_vector( 3 downto 0);
      resp_error_o        : out   std_logic_vector( 3 downto 0);
      resp_address_o      : out   std_logic_vector(22 downto 0);

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

      -- Decoded CRT headers (connect to cartridge.v)
      cart_bank_laddr_o   : out   std_logic_vector(15 downto 0); -- bank loading address
      cart_bank_size_o    : out   std_logic_vector(15 downto 0); -- length of each bank
      cart_bank_num_o     : out   std_logic_vector(15 downto 0);
      cart_bank_raddr_o   : out   std_logic_vector(24 downto 0); -- Byte address in HyperRAM of each bank
      cart_bank_wr_o      : out   std_logic;
      cart_loading_o      : out   std_logic;
      cart_id_o           : out   std_logic_vector(15 downto 0); -- cart ID or cart type
      cart_exrom_o        : out   std_logic_vector( 7 downto 0); -- CRT file EXROM status
      cart_game_o         : out   std_logic_vector( 7 downto 0); -- CRT file GAME status
      cart_size_o         : out   std_logic_vector(22 downto 0)  -- CRT file size (in bytes)
   );
end entity crt_parser;

architecture synthesis of crt_parser is

   constant C_ERROR_NONE           : std_logic_vector(3 downto 0) := "0000";
   constant C_ERROR_NO_CRT_HDR     : std_logic_vector(3 downto 0) := "0001"; -- Missing CRT header
   constant C_ERROR_NO_CHIP_HDR    : std_logic_vector(3 downto 0) := "0010"; -- Missing CHIP header
   constant C_ERROR_WRONG_CRT_HDR  : std_logic_vector(3 downto 0) := "0011"; -- Wrong CRT header
   constant C_ERROR_WRONG_CHIP_HDR : std_logic_vector(3 downto 0) := "0100"; -- Wrong CHIP header
   constant C_ERROR_TRUNCATED_CHIP : std_logic_vector(3 downto 0) := "0101"; -- Truncated CHIP

   subtype  r_crt_file_header_length is natural range  4 * 8 - 1 downto  0 * 8;
   subtype  r_crt_cartridge_version  is natural range  6 * 8 - 1 downto  4 * 8;
   subtype  r_crt_cartridge_type     is natural range  8 * 8 - 1 downto  6 * 8;
   subtype  r_crt_exrom              is natural range  9 * 8 - 1 downto  8 * 8;
   subtype  r_crt_game               is natural range 10 * 8 - 1 downto  9 * 8;

   subtype  r_chip_signature         is natural range  4 * 8 - 1 downto  0 * 8;
   subtype  r_chip_length            is natural range  8 * 8 - 1 downto  4 * 8;
   subtype  r_chip_type              is natural range 10 * 8 - 1 downto  8 * 8;
   subtype  r_chip_bank_number       is natural range 12 * 8 - 1 downto 10 * 8;
   subtype  r_chip_load_address      is natural range 14 * 8 - 1 downto 12 * 8;
   subtype  r_chip_image_size        is natural range 16 * 8 - 1 downto 14 * 8;

   type     state_type is (
      IDLE_ST,
      WAIT_FOR_CRT_HEADER_00_ST,
      WAIT_FOR_CRT_HEADER_10_ST,
      WAIT_FOR_CHIP_HEADER_ST,
      READY_ST,
      ERROR_ST
   );
   signal   state : state_type                                    := IDLE_ST;

   -- 16-byte of data in little-endian format
   signal   wide_readdata       : std_logic_vector(127 downto 0);
   signal   wide_readdata_valid : std_logic;
   signal   read_pos            : integer range 0 to 7;

   signal   req_address : std_logic_vector(21 downto 0);                     -- Start address in HyperRAM
   signal   end_address : std_logic_vector(21 downto 0);                     -- End address in HyperRAM

   -- Convert an ASCII string to std_logic_vector (little-endian format)

   pure function str2slv (
      s : string
   ) return std_logic_vector is
      variable res_v : std_logic_vector(s'length * 8 - 1 downto 0);
   begin
      --
      for i in 0 to s'length-1 loop
         res_v(8 * i + 7 downto 8 * i) := to_stdlogicvector(character'pos(s(i + 1)), 8);
      end loop;

      return res_v;
   end function str2slv;

   -- purpose: byteswap a vector

   pure function bswap (
      din : std_logic_vector
   ) return std_logic_vector is
      variable swapped_v : std_logic_vector(din'length-1 downto 0);
      variable input_v   : std_logic_vector(din'length-1 downto 0);
   begin
      -- normalize din to start at zero and to have downto as direction
      for i in 0 to din'length-1 loop
         input_v(i) := din(i + din'low);
      end loop;

      for i in 0 to din'length / 8 - 1 loop
         swapped_v(swapped_v'high - i * 8 downto swapped_v'high - i * 8 - 7) := input_v(i * 8 + 7 downto i * 8);
      end loop;

      return swapped_v;
   end function bswap;

begin

   -- Gather together 16 bytes of data.
   -- This is just to make the state machine simpler,
   -- i.e. we can process more data at a time.
   wide_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         wide_readdata_valid <= '0';

         if avm_readdatavalid_i = '1' then
            wide_readdata(16 * read_pos + 15 downto 16 * read_pos) <= avm_readdata_i;

            if read_pos = 7 then
               wide_readdata_valid <= '1'; -- 16 bytes are now ready
               read_pos            <= 0;
            else
               read_pos <= read_pos + 1;
            end if;
         end if;

         if rst_i = '1' then
            read_pos            <= 0;
            wide_readdata_valid <= '0';
         end if;
      end if;
   end process wide_proc;

   fsm_proc : process (clk_i)
      variable file_header_length_v : std_logic_vector(31 downto 0);
      variable image_size_v         : std_logic_vector(15 downto 0);
      variable read_addr_v          : std_logic_vector(21 downto 0);
   begin
      if rising_edge(clk_i) then
         cart_bank_wr_o <= '0';

         if avm_waitrequest_i = '0' then
            avm_write_o <= '0';
            avm_read_o  <= '0';
         end if;

         case state is

            when IDLE_ST =>
               if req_start_i = '1' then
                  cart_loading_o <= '1';
                  req_address    <= req_address_i;
                  cart_size_o    <= req_length_i;
                  -- As a minimum, the file must contain a complete CRT header.
                  if req_length_i >= X"00040" then
                     -- Read first 0x20 bytes of CRT header.
                     avm_address_o    <= req_address_i;
                     avm_read_o       <= '1';
                     avm_burstcount_o <= X"10";
                     resp_status_o    <= C_CSR_RESP_PARSING;
                     end_address      <= req_address_i + req_length_i(22 downto 1);
                     state            <= WAIT_FOR_CRT_HEADER_00_ST;
                  else
                     resp_status_o  <= C_CSR_RESP_ERROR;
                     resp_error_o   <= C_ERROR_NO_CRT_HDR;
                     resp_address_o <= (others => '0');
                     state          <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CRT_HEADER_00_ST =>
               if wide_readdata_valid = '1' then
                  if wide_readdata = str2slv("VIC20 CARTRIDGE ") then
                     state <= WAIT_FOR_CRT_HEADER_10_ST;
                  else
                     resp_status_o               <= C_CSR_RESP_ERROR;
                     resp_error_o                <= C_ERROR_WRONG_CRT_HDR;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state                       <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CRT_HEADER_10_ST =>
               if wide_readdata_valid = '1' then
                  cart_id_o            <= bswap(wide_readdata(r_crt_cartridge_type));
                  cart_exrom_o         <= wide_readdata(r_crt_exrom);
                  cart_game_o          <= wide_readdata(r_crt_game);
                  file_header_length_v := bswap(wide_readdata(r_crt_file_header_length));
                  report "Detected cartridge ID: " &
                         to_string(to_integer(bswap(wide_readdata(r_crt_cartridge_type))));
                  if file_header_length_v < X"00000040" then
                     file_header_length_v := X"00000040";
                  end if;

                  if end_address >= avm_address_o + file_header_length_v(22 downto 1) + X"08" then
                     -- Read 0x10 bytes from CHIP header
                     avm_address_o    <= avm_address_o + file_header_length_v(22 downto 1);
                     avm_read_o       <= '1';
                     avm_burstcount_o <= X"08";
                     state            <= WAIT_FOR_CHIP_HEADER_ST;
                  else
                     resp_status_o               <= C_CSR_RESP_ERROR;
                     resp_error_o                <= C_ERROR_NO_CHIP_HDR;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state                       <= ERROR_ST;
                  end if;
               end if;

            when WAIT_FOR_CHIP_HEADER_ST =>
               if wide_readdata_valid = '1' then
                  if wide_readdata(r_chip_signature) = str2slv("CHIP") then
                     cart_bank_laddr_o              <= bswap(wide_readdata(r_chip_load_address));
                     cart_bank_size_o               <= bswap(wide_readdata(r_chip_image_size));
                     cart_bank_num_o                <= bswap(wide_readdata(r_chip_bank_number));
                     read_addr_v                    := avm_address_o + X"08";
                     cart_bank_raddr_o              <= (others => '0');
                     cart_bank_raddr_o(22 downto 1) <= read_addr_v;
                     cart_bank_wr_o                 <= '1';

                     report "Detected CHIP " &
                            to_string(to_integer(bswap(wide_readdata(r_chip_bank_number)))) &
                            ", addr=" & to_hstring(bswap(wide_readdata(r_chip_load_address))) &
                            ", size=" & to_hstring(bswap(wide_readdata(r_chip_image_size)));

                     image_size_v                   := bswap(wide_readdata(r_chip_image_size));
                     if end_address = avm_address_o + X"08" + image_size_v(15 downto 1) then
                        resp_status_o <= C_CSR_RESP_READY;
                        state         <= READY_ST;
                     elsif end_address >= avm_address_o + X"08" + image_size_v(15 downto 1) + X"08" then
                        -- Oh, there's more ...
                        avm_address_o    <= avm_address_o + X"08" + image_size_v(15 downto 1);
                        avm_read_o       <= '1';
                        avm_burstcount_o <= X"08";
                        resp_status_o    <= C_CSR_RESP_PARSING;
                        state            <= WAIT_FOR_CHIP_HEADER_ST;
                     else
                        resp_status_o               <= C_CSR_RESP_ERROR;
                        resp_error_o                <= C_ERROR_TRUNCATED_CHIP;
                        resp_address_o(22 downto 1) <= avm_address_o - req_address;
                        state                       <= ERROR_ST;
                     end if;
                  else
                     resp_status_o               <= C_CSR_RESP_ERROR;
                     resp_error_o                <= C_ERROR_WRONG_CHIP_HDR;
                     resp_address_o(22 downto 1) <= avm_address_o - req_address;
                     state                       <= ERROR_ST;
                  end if;
               end if;

            when ERROR_ST | READY_ST =>
               cart_loading_o <= '0';
               if req_start_i = '0' then
                  resp_status_o  <= C_CSR_RESP_IDLE;
                  resp_error_o   <= C_ERROR_NONE;
                  resp_address_o <= (others => '0');
                  state          <= IDLE_ST;
               end if;

            when others =>
               null;

         end case;

         if rst_i = '1' then
            avm_write_o       <= '0';
            avm_read_o        <= '0';
            avm_address_o     <= (others => '0');
            avm_writedata_o   <= (others => '0');
            avm_byteenable_o  <= (others => '0');
            avm_burstcount_o  <= (others => '0');
            cart_bank_raddr_o <= (others => '0');
            cart_bank_wr_o    <= '0';
            cart_id_o         <= (others => '0');
            cart_exrom_o      <= (others => '1');
            cart_game_o       <= (others => '1');
            cart_loading_o    <= '0';
            resp_status_o     <= C_CSR_RESP_IDLE;
            resp_error_o      <= C_ERROR_NONE;
            resp_address_o    <= (others => '0');
            state             <= IDLE_ST;
            req_address       <= (others => '0');
         end if;
      end if;
   end process fsm_proc;

end architecture synthesis;

