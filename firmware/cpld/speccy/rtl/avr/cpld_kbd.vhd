library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity cpld_kbd is
port (
	CLK	     : in std_logic;

	A           : in std_logic_vector(15 downto 8); -- address bus for kbd
	KB          : out std_logic_vector(4 downto 0) := "11111"; -- data bus for kbd

	AVR_MOSI    : in std_logic;
	AVR_MISO    : out std_logic;
	AVR_SCK     : in std_logic;
	AVR_SS      : in std_logic;
			
	O_RESET		: out std_logic;
	O_TURBO		: out std_logic;
	O_MAGICK		: out std_logic;
	O_WAIT 		: out std_logic;
	
	O_JOY 		: out std_logic_vector(7 downto 0);
	O_BANK 		: out std_logic_vector(2 downto 0)
);
end cpld_kbd;

architecture RTL of cpld_kbd is

	 -- keyboard state
	 signal kb_data : std_logic_vector(39 downto 0) := (others => '0'); -- 40 keys

	 -- additional signals
	 signal reset   : std_logic := '0';
	 signal turbo   : std_logic := '0';
	 signal magick  : std_logic := '0';
	 signal waiting : std_logic := '0';
	 
	 -- spi
	 signal spi_do_valid : std_logic := '0';
	 signal spi_do : std_logic_vector(15 downto 0);
	 
	 signal joy : std_logic_vector(7 downto 0);
	 signal bank : std_logic_vector(2 downto 0) := "000";

begin

U_SPI: entity work.spi_slave
    generic map(
        N              => 16 -- 2 bytes (cmd + data)       
    )
    port map(
        clk_i          => CLK,
        spi_sck_i      => AVR_SCK,
        spi_ssel_i     => AVR_SS,
        spi_mosi_i     => AVR_MOSI,
        spi_miso_o     => AVR_MISO,

        di_req_o       => open,
        di_i           => open,
        wren_i         => '0',
        do_valid_o     => spi_do_valid,
        do_o           => spi_do,

        do_transfer_o  => open,
        wren_o         => open,
        wren_ack_o     => open,
        rx_bit_reg_o   => open,
        state_dbg_o    => open
        );


		  
process (CLK, spi_do_valid, spi_do)
begin
	if (rising_edge(CLK)) then
		if spi_do_valid = '1' then
			case spi_do(15 downto 8) is 
				-- keyboard matrix
				when X"01" => kb_data(7 downto 0) <= spi_do (7 downto 0);
				when X"02" => kb_data(15 downto 8) <= spi_do (7 downto 0);
				when X"03" => kb_data(23 downto 16) <= spi_do (7 downto 0);
				when X"04" => kb_data(31 downto 24) <= spi_do (7 downto 0);
				when X"05" => kb_data(39 downto 32) <= spi_do (7 downto 0);	
				when X"06" => reset <= spi_do(0); 
								  turbo <= spi_do(1); 
								  magick <= spi_do(2); 
								  joy(0) <= spi_do(7);
								  joy(1) <= spi_do(6);
								  joy(2) <= spi_do(5);
								  joy(3) <= spi_do(4);
								  joy(4) <= spi_do(3); 
				when X"07" => bank <= spi_do(2 downto 0);
								  joy(5) <= spi_do(3); -- fire2
								  joy(6) <= spi_do(4); -- fire3
								  waiting <= spi_do(5);
								  joy(7) <= spi_do(6); -- fire4
				when others => null;
			end case;
		end if;
	end if;
end process;

process (CLK)
begin
	if (rising_edge(CLK)) then 
		O_RESET <= not(reset);
		O_MAGICK <= not(magick);
		O_WAIT <= not(waiting);
		O_TURBO <= turbo;
		O_JOY <= not(joy);
		O_BANK <= bank;
	end if;
end process;

--    
process( CLK, kb_data, A)
begin
	if (rising_edge(CLK)) then
				KB(0) <=	not(( kb_data(0)  and not(A(8)  ) ) 
							or    ( kb_data(1)  and not(A(9)  ) ) 
							or    ( kb_data(2) and not(A(10) ) ) 
							or    ( kb_data(3) and not(A(11) ) ) 
							or    ( kb_data(4) and not(A(12) ) ) 
							or    ( kb_data(5) and not(A(13) ) ) 
							or    ( kb_data(6) and not(A(14) ) ) 
							or    ( kb_data(7) and not(A(15) ) )  );

				KB(1) <=	not( ( kb_data(8)  and not(A(8) ) ) 
							or   ( kb_data(9)  and not(A(9) ) ) 
							or   ( kb_data(10) and not(A(10)) ) 
							or   ( kb_data(11) and not(A(11)) ) 
							or   ( kb_data(12) and not(A(12)) ) 
							or   ( kb_data(13) and not(A(13)) ) 
							or   ( kb_data(14) and not(A(14)) ) 
							or   ( kb_data(15) and not(A(15)) ) );

				KB(2) <=		not( ( kb_data(16) and not( A(8)) ) 
							or   ( kb_data(17) and not( A(9)) ) 
							or   ( kb_data(18) and not(A(10)) ) 
							or   ( kb_data(19) and not(A(11)) ) 
							or   ( kb_data(20) and not(A(12)) ) 
							or   ( kb_data(21) and not(A(13)) ) 
							or   ( kb_data(22) and not(A(14)) ) 
							or   ( kb_data(23) and not(A(15)) ) );

				KB(3) <=		not( ( kb_data(24) and not( A(8)) ) 
							or   ( kb_data(25) and not( A(9)) ) 
							or   ( kb_data(26) and not(A(10)) ) 
							or   ( kb_data(27) and not(A(11)) ) 
							or   ( kb_data(28) and not(A(12)) ) 
							or   ( kb_data(29) and not(A(13)) ) 
							or   ( kb_data(30) and not(A(14)) ) 
							or   ( kb_data(31) and not(A(15)) ) );

				KB(4) <=		not( ( kb_data(32) and not( A(8)) ) 
							or   ( kb_data(33) and not( A(9)) ) 
							or   ( kb_data(34) and not(A(10)) ) 
							or   ( kb_data(35) and not(A(11)) ) 
							or   ( kb_data(36) and not(A(12)) ) 
							or   ( kb_data(37) and not(A(13)) ) 
							or   ( kb_data(38) and not(A(14)) ) 
							or   ( kb_data(39) and not(A(15)) ) );
	end if;
end process;

end RTL;

