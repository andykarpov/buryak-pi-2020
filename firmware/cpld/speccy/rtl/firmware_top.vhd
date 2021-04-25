-- --------------------------------------------------------------------
-- Buriak-Pi firmware
-- v2.0
-- (c) 2020 Andy Karpov
-- --------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity firmware_top is
	generic (
		-- mark active area of input video
		ram_ext_std        : integer range 0 to 3 := 2; -- 0 - pentagon-512 via 6,7 bits of the #7FFD port (bit 5 is for 48k lock)
																      -- 1 - pentagon-1024 via 5,6,7 bits of the #7FFD port (no 48k lock)
																      -- 2 - profi-1024 via 0,1,2 bits of the #DFFD port
																      -- 3 - pentagon-128
		enable_timex	    : boolean := false;
		enable_port_ff 	 : boolean := true;
		enable_divmmc 	    : boolean := true;
		enable_zcontroller : boolean := false;
		enable_vga 		    : boolean := true
	);
	port(
		-- Clock
		CLK28				: in std_logic;

		-- CPU signals
		CLK_CPU			: out std_logic := '1';
		N_RESET			: inout std_logic := 'Z';
		N_INT				: out std_logic := '1';
		N_RD				: in std_logic;
		N_WR				: in std_logic;
		N_IORQ			: in std_logic;
		N_MREQ			: in std_logic;
		N_M1				: in std_logic;
		A					: in std_logic_vector(15 downto 0);
		D 					: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_NMI 			: out std_logic := 'Z';
		N_WAIT 			: out std_logic := 'Z';
		
		-- RAM 
		MA 				: out std_logic_vector(20 downto 0);
		MD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_MRD				: out std_logic := '1';
		N_MWR				: out std_logic := '1';
		
		-- VRAM 
		VA					: out std_logic_vector(14 downto 0);
		VD 				: inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_VWE 			: out std_logic := '1';

		-- ROM
		N_ROMCS			: out std_logic := '1';
		N_ROMWE			: out std_logic := '1';
		ROM_A 			: out std_logic_vector(15 downto 14) := "00";
		
		-- VGA Video
		VGA_VSYNC    		: out std_logic := '1';
		VGA_HSYNC 			: out std_logic := '1';
		VGA_R       		: out std_logic_vector(1 downto 0) := "ZZ";
		VGA_G       		: out std_logic_vector(1 downto 0) := "ZZ";
		VGA_B       		: out std_logic_vector(1 downto 0) := "ZZ";

		-- Interfaces 
		BEEPER			: out std_logic := '1';

		-- AY
		AY_BC1			: out std_logic;
		AY_BDIR			: out std_logic;

		-- SD card
		SD_CLK 			: out std_logic := '0';
		SD_DI 			: out std_logic;
		SD_DO 			: in std_logic;
		N_SD_CS 			: out std_logic := '1';
		SD_DETECT		: in std_logic;
		
		-- Keyboard Atmega
		KEY_SCK 			: in std_logic;
		KEY_SS 			: in std_logic;
		KEY_MOSI 		: in std_logic;
		KEY_MISO 		: out std_logic;
		
		-- Other in signals
		N_BTN_NMI		: in std_logic := '1';
		N_BTN_RESET 	: in std_logic := '1'
	);
end firmware_top;

architecture rtl of firmware_top is

	signal clk_14 		: std_logic := '0';
	signal clk_7 		: std_logic := '0';
	signal clkcpu 		: std_logic := '1';

	signal attr_r   	: std_logic_vector(7 downto 0);
	signal rgb 	 		: std_logic_vector(2 downto 0);
	signal i 			: std_logic;
	signal vid_a 		: std_logic_vector(13 downto 0);
	signal hcnt0 		: std_logic;
	
	signal timexcfg_reg : std_logic_vector(5 downto 0);
	signal is_port_ff : std_logic := '0';	

	signal border_attr: std_logic_vector(2 downto 0) := "000";

	signal port_7ffd	: std_logic_vector(7 downto 0); -- D0-D2 - RAM page from address #C000
																	  -- D3 - video RAM page: 0 - bank5, 1 - bank7 
																	  -- D4 - ROM page A14: 0 - basic 128, 1 - basic48
																	  -- D5 - 48k RAM lock, 1 - locked, 0 - extended memory enabled
																	  -- D6 - not used
																	  -- D7 - not used

	signal port_dffd : std_logic_vector(2 downto 0); -- D0-D2 ram ext
																	  
	signal ram_ext : std_logic_vector(2 downto 0) := "000";
	signal ram_do : std_logic_vector(7 downto 0);
	signal ram_oe_n : std_logic := '1';
	
	signal fd_port : std_logic;
	signal fd_sel : std_logic;	
																	  
	signal ay_port		: std_logic := '0';
		
	signal vbus_mode  : std_logic := '0';
	signal vid_rd		: std_logic := '0';
	
	signal hsync     	: std_logic := '1';
	signal vsync     	: std_logic := '1';

	signal sound_out 	: std_logic := '0';
	signal port_read	: std_logic := '0';
	signal port_write	: std_logic := '0';
	
	signal divmmc_enable : std_logic := '0';
	signal divmmc_do	: std_logic_vector(7 downto 0);
	
	signal divmmc_ram : std_logic;
	signal divmmc_rom : std_logic;
	
	signal divmmc_disable_zxrom : std_logic;
	signal divmmc_eeprom_cs_n : std_logic;
	signal divmmc_eeprom_we_n : std_logic;
	signal divmmc_sram_cs_n : std_logic;
	signal divmmc_sram_we_n : std_logic;
	signal divmmc_sram_hiaddr : std_logic_vector(5 downto 0);
	signal divmmc_sd_cs_n : std_logic;
	signal divmmc_wr : std_logic;
	signal divmmc_sd_di: std_logic;
	signal divmmc_sd_clk: std_logic;
	
	signal zc_do_bus	: std_logic_vector(7 downto 0);
	signal zc_wr 		: std_logic :='0';
	signal zc_rd		: std_logic :='0';
	signal zc_sd_cs_n: std_logic;
	signal zc_sd_di: std_logic;
	signal zc_sd_clk: std_logic;
	
	signal trdos	: std_logic :='1';
	
	signal kb : std_logic_vector(4 downto 0) := "11111";
	signal joy : std_logic_vector(7 downto 0) := "11111111";
	signal nmi : std_logic;
	signal reset : std_logic;
	signal turbo : std_logic;
	
	signal vga_red: std_logic_vector(1 downto 0);
	signal vga_green: std_logic_vector(1 downto 0);
	signal vga_blue: std_logic_vector(1 downto 0);	
	signal hsync_vga : std_logic;
	signal vsync_vga : std_logic;
	
	signal cs_dffd : std_logic := '0';
	signal cs_7ffd : std_logic := '0';
	signal cs_xxfd : std_logic := '0';

begin

	divmmc_rom <= '1' when (divmmc_disable_zxrom = '1' and divmmc_eeprom_cs_n = '0') else '0';
	divmmc_ram <= '1' when (divmmc_disable_zxrom = '1' and divmmc_sram_cs_n = '0') else '0';
	
	N_ROMWE <= '1';	

	BEEPER <= sound_out;

	ay_port <= '1' when A(7 downto 0) = x"FD" and A(15)='1' and fd_port = '1' else '0';
	AY_BC1 <= '1' when ay_port = '1' and A(14) = '1' and N_IORQ = '0' and (N_WR='0' or N_RD='0') else '0';
	AY_BDIR <= '1' when ay_port = '1' and N_IORQ = '0' and N_WR = '0' else '0';	
	
	N_NMI <= '0' when N_BTN_NMI = '0' or nmi = '0' else '1';
	N_RESET <= '0' when N_BTN_RESET = '0' or reset = '0' else 'Z';

	--N_NMI <= '0' when nmi = '0' else '1';
	--N_RESET <= '0' when reset = '0' else 'Z';
	
	 -- #FD port correction
	 fd_sel <= '0' when D(7 downto 4) = "1101" and D(2 downto 0) = "011" else '1'; -- IN, OUT Z80 Command Latch

	 process(fd_sel, N_M1, N_RESET)
	 begin
			if N_RESET='0' then
				  fd_port <= '1';
			elsif rising_edge(N_M1) then 
				  fd_port <= fd_sel;
			end if;
	 end process;

	-- CPU clock 
	process( N_RESET, clk28, clk_14, clk_7, hcnt0 )
	begin
		if clk_14'event and clk_14 = '1' then
			if (turbo = '1') then
				clkcpu <= clk_7;
			elsif clk_7 = '1' then
				clkcpu <= hcnt0;
			end if;
		end if;
	end process;
	
	CLK_CPU <= clkcpu;
	
	port_write <= '1' when N_IORQ = '0' and N_WR = '0' and N_M1 = '1' else '0';
	port_read <= '1' when N_IORQ = '0' and N_RD = '0' and N_M1 = '1' else '0';
	
	-- read ports by CPU
	D(7 downto 0) <= 
		ram_do when ram_oe_n = '0' else -- #memory
		port_7ffd when port_read = '1' and A = X"7FFD" else  -- #7FFD - system port 
		"00000" & ram_ext when port_read = '1' and A = X"DFFD" else  -- #DFFD - system port 
		"111" & kb(4 downto 0) when port_read = '1' and A(0) = '0' else -- #FE - keyboard 
		joy when port_read = '1' and A(7 downto 0) = X"1F" else -- #1F - kempston joy
		divmmc_do when divmmc_wr = '1' else 									 -- divMMC
		zc_do_bus when port_read = '1' and A(7 downto 6) = "01" and A(4 downto 0) = "10111" and enable_zcontroller else -- Z-controller
		"00" & timexcfg_reg when enable_timex and port_read = '1' and A(7 downto 0) = x"FF" and is_port_ff = '1' else -- #FF (timex config)
		attr_r when enable_port_ff and port_read = '1' and A(7 downto 0) = x"FF" and is_port_ff = '0' else -- #FF - attributes (timex port never set)
		"ZZZZZZZZ";

	divmmc_enable <= '1' when enable_divmmc and SD_DETECT = '0' else '0';
	
	-- z-controller 
	zc_wr <= '1' when (enable_zcontroller and N_IORQ = '0' and N_WR = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
	zc_rd <= '1' when (enable_zcontroller and N_IORQ = '0' and N_RD = '0' and A(7 downto 6) = "01" and A(4 downto 0) = "10111") else '0';
	
	-- clocks
	process (CLK28)
	begin 
		if (CLK28'event and CLK28 = '1') then 
			clk_14 <= not(clk_14);
		end if;
	end process;
	
	process (clk_14)
	begin 
		if (clk_14'event and clk_14 = '1') then 
			clk_7 <= not(clk_7);
		end if;
	end process;
	
	cs_dffd <= '1' when N_IORQ = '0' and N_M1 = '1' and A = X"DFFD" and fd_port = '1' else '0';
	cs_7ffd <= '1' when N_IORQ = '0' and N_M1 = '1' and A = X"7FFD" else '0';
	cs_xxfd <= '1' when N_IORQ = '0' and N_M1 = '1' and A(15) = '0' and A(1) = '0' and fd_port = '0' else '0';
	
	ram_ext <= '0' & port_7ffd(6) & port_7ffd(7) when ram_ext_std = 0 else 
				  port_7ffd(5) & port_7ffd(6) & port_7ffd(7) when ram_ext_std = 1 else
				  port_dffd(2 downto 0) when ram_ext_std = 2 else 
				  "000";				  

	-- ports, write by CPU
	process( clk28, clk_14, clk_7, N_RESET, A, D, port_write, port_7ffd, N_M1, N_MREQ )
	begin
		if N_RESET = '0' then
			port_7ffd <= "00000000";
			sound_out <= '0';
			timexcfg_reg <= (others => '0');
			is_port_ff <= '0';
			if (enable_zcontroller) then 
				trdos <= '1'; -- 1 - boot into service rom, 0 - boot into 128 menu
			else 
				trdos <= '0';
			end if;
		elsif clk28'event and clk28 = '1' then 
			if clk_14 = '1' and (TURBO = '1' or clk_7 = '1') then
				if port_write = '1' then

					 -- port #7FFD  
					if cs_7ffd = '1' and port_7ffd(5) = '0' then 
						port_7ffd <= D;
					elsif cs_xxfd = '1' and port_7ffd(5) = '0' then 
						port_7ffd <= D;
					end if;
					 
					-- port #DFFD (profi ram ext)
					if cs_dffd = '1' and port_7ffd(5) = '0' and fd_port='1' then
							port_dffd <= D(2 downto 0);
					end if;
					
					-- port #FE
					if A(0) = '0' then
						border_attr <= D(2 downto 0); -- border attr
						sound_out <= D(4); -- BEEPER
					end if;
					
					-- port FF / timex CFG
					if (A(7 downto 0) = X"FF" and enable_timex) then 
						timexcfg_reg(5 downto 0) <= D(5 downto 0);
						is_port_ff <= '1';
					end if;
					
				end if;
				
				-- trdos flag
				if enable_zcontroller and N_M1 = '0' and N_MREQ = '0' and A(15 downto 8) = X"3D" and port_7ffd(4) = '1' then 
					trdos <= '1';
				elsif enable_zcontroller and N_M1 = '0' and N_MREQ = '0' and A(15 downto 14) /= "00" then 
					trdos <= '0'; 
				end if;
				
			end if;
		end if;
	end process;	

	-- memory arbiter
	U1: entity work.memory 
	generic map (
		enable_divmmc => enable_divmmc,
		enable_zcontroller => enable_zcontroller
	)
	port map ( 
		CLK28 => CLK28,
		CLK14 => CLK_14,
		CLK7  => CLK_7,
		HCNT0 => hcnt0,
		TURBO => turbo,
		
		-- cpu signals
		A => A,
		D => D,
		N_MREQ => N_MREQ,
		N_IORQ => N_IORQ,
		N_WR => N_WR,
		N_RD => N_RD,
		N_M1 => N_M1,

		-- ram 
		MA => MA,
		MD => MD,
		N_MRD => N_MRD,
		N_MWR => N_MWR,
		
		-- ram out to cpu
		DO => ram_do,
		N_OE => ram_oe_n,
		
		-- ram pages
		RAM_BANK => port_7ffd(2 downto 0),
		RAM_EXT => ram_ext,

		-- divmmc
		DIVMMC_A => divmmc_sram_hiaddr,
		IS_DIVMMC_RAM => divmmc_ram,
		IS_DIVMMC_ROM => divmmc_rom,

		-- video
		VA => vid_a,
		VID_PAGE => port_7ffd(3),

		-- video bus control signals
		VBUS_MODE_O => vbus_mode, -- video bus mode: 0 - ram, 1 - vram
		VID_RD_O => vid_rd, -- read bitmap or attribute from video memory
		
		-- TRDOS 
		TRDOS => trdos,
		
		-- rom
		ROM_BANK => port_7ffd(4),
		ROM_A => ROM_A,
		N_ROMCS => N_ROMCS		
	);
	
	-- divmmc interface
	G_DIVMMC: if enable_divmmc generate
	U2: entity work.divmmc
	port map (
		I_CLK		=> CLK28,
		I_CS		=> divmmc_enable,
		I_RESET		=> not(N_RESET),
		I_ADDR		=> A,
		I_DATA		=> D,
		O_DATA		=> divmmc_do,
		I_WR_N		=> N_WR,
		I_RD_N		=> N_RD,
		I_IORQ_N		=> N_IORQ,
		I_MREQ_N		=> N_MREQ,
		I_M1_N		=> N_M1,
		
		O_WR 				 => divmmc_wr,
		O_DISABLE_ZXROM => divmmc_disable_zxrom,
		O_EEPROM_CS_N 	 => divmmc_eeprom_cs_n,
		O_EEPROM_WE_N 	 => divmmc_eeprom_we_n,
		O_SRAM_CS_N 	 => divmmc_sram_cs_n,
		O_SRAM_WE_N 	 => divmmc_sram_we_n,
		O_SRAM_HIADDR	 => divmmc_sram_hiaddr,
		
		O_CS_N		=> divmmc_sd_cs_n,
		O_SCLK		=> divmmc_sd_clk,
		O_MOSI		=> divmmc_sd_di,
		I_MISO		=> SD_DO
	);
	end generate G_DIVMMC;
		
	-- Z-Controller	
	G_ZCCONTROLLER: if enable_zcontroller generate
	U3: entity work.zcontroller 
	port map(
		RESET => not(N_RESET),
		CLK => clk_7,
		A => A(5),
		DI => D,
		DO => zc_do_bus,
		RD => zc_rd,
		WR => zc_wr,
		SDDET => '0',
		SDPROT => '0',
		CS_n => zc_sd_cs_n,
		SCLK => zc_sd_clk,
		MOSI => zc_sd_di,
		MISO => SD_DO
	);
	end generate G_ZCCONTROLLER;

	-- share SD card between DivMMC / ZC
	N_SD_CS <= divmmc_sd_cs_n when enable_divmmc else zc_sd_cs_n when enable_zcontroller else '1';
	SD_CLK <= divmmc_sd_clk when enable_divmmc else zc_sd_clk when enable_zcontroller else '1';
	SD_DI <= divmmc_sd_di when enable_divmmc else zc_sd_di when enable_zcontroller else '1';
	
	-- keyboard
	U4: entity work.cpld_kbd 
	port map (
		CLK => CLK28,
		A => A(15 downto 8),
		KB => kb,
		AVR_SCK => KEY_SCK,
		AVR_MOSI => KEY_MOSI,
		AVR_MISO => KEY_MISO,
		AVR_SS => KEY_SS,
		
		O_RESET => reset,
		O_TURBO => turbo,
		O_MAGICK => nmi,
		O_JOY => joy,
		O_BANK => open,
		O_WAIT => N_WAIT
	);
	
	-- video module
	U5: entity work.video 
	port map (
		CLK => CLK_14,
		CLK28 => CLK28,
		ENA7 => CLK_7,
		BORDER => border_attr,
		TIMEXCFG => timexcfg_reg,
		DI => MD,
		TURBO => turbo,
		INTA => N_IORQ or N_M1,
		INT => N_INT,
		ATTR_O => attr_r, 
		A => vid_a,
		BLANK => open,
		RGB => rgb,
		I => i,
		HSYNC => hsync,
		VSYNC => vsync,
		VBUS_MODE => vbus_mode,
		VID_RD => vid_rd,
		HCNT0 => hcnt0
	);
	
	-- scandoubler
	U6: entity work.scan_convert 
	port map (
		I_VIDEO => rgb & i,
		
      I_HSYNC => hsync,
		I_VSYNC => vsync,
		
		CLK_x2 => CLK28,
		CLK => not(CLK_14),
		
		O_RED => vga_red,
		O_GREEN => vga_green,
		O_BLUE => vga_blue,

		O_HSYNC => hsync_vga,
		O_VSYNC => vsync_vga,
		
		VA => VA(9 downto 0),
		VWE => N_VWE,
		VDD => VD
	);	
	
	VA(14 downto 10) <= (others => '1');
	
	-- Share VGA connector between RGB / VGA modes
	VGA_R <= vga_red when enable_vga else rgb(2) & i;
	VGA_G <= vga_green when enable_vga else rgb(1) & i;
	VGA_B <= vga_blue when enable_vga else rgb(0) & i;
	VGA_HSYNC <= hsync_vga when enable_vga else hsync;
	VGA_VSYNC <= vsync_vga when enable_vga else vsync;
	
	
end;
