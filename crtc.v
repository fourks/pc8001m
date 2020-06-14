//
// CRTC
// version 1.01a
//
// Orignal Auther	: kwhr0-san
// Modifyed 		: RJB
//

module crtc(
	input wire				clk,
	output wire [3:0] 	y_out,
	output wire [3:0] 	c_out,
	input wire				port30h_we,
	input wire				crtc_we,
	input wire				adr,
	input wire [7:0] 		data,
	output reg 				busreq = 0, 
	input wire				busack,
	output wire 			ram_ce_n,
	output wire 			ram_oe_n,
	output wire 			ram_we_n,
	output wire [16:0] 	ram_adr,
	input wire [7:0] 		ram_data,

	input wire				clk2,
	input wire				mode,
	output [1:0] 			bw_out,
	output wire				vga_hs,
	output wire				vga_vs,
	output wire [3:0]		vga_r,
	output wire [3:0]		vga_g,
	output wire [3:0]		vga_b,
	
	input wire [9:0]		pcg_adr,
	input wire [7:0]		pcg_data,
	input wire				pcg_we,
	input wire				pcg_on
	);
	
	parameter START_H = 192;
	parameter END_H = START_H + 640;
	parameter START_V = 40;
	parameter END_V = START_V + 200;
	parameter CHCNT_RESET_V = START_V - 1;

	parameter START_H2 = 208;
	parameter END_H2 = START_H2 + 640;
	parameter START_V2 = 81;
	parameter END_V2 = START_V2 + 401;

	
	function sel2;
		input [1:0] s;
		input [3:0] a;
		case (s)
			2'b00: sel2 = a[0];
			2'b01: sel2 = a[1];
			2'b10: sel2 = a[2];
			2'b11: sel2 = a[3];
		endcase
	endfunction

	reg q0 = 0;
	reg [9:0] dotcnt = 0;
	reg [8:0] hcnt = 0;
	reg [3:0] chcnt = 0;
	reg [7:0] chrline = 0;
	reg [6:0] text_adr = 0;
	reg [5:0] atr_adr = 0;
	reg [6:0] xcnt = 0;
	reg [4:0] ycnt = 0;
	reg [6:0] atr = 7'b1110000, atr0 = 7'b1110000;
	reg [6:0] vcnt = 0;
	reg [11:0] dma_src_adr = 0;
	reg [6:0] dma_dst_adr = 0;
	reg [7:0] text_data; // added
	reg [1:0] state = 0;
	reg [6:0] xcurs = 0;
	reg [4:0] ycurs = 0;
	reg qinh = 0, qrev = 0, qcurs = 0, width80 = 0, colormode = 0; // busreq = 0,
	reg [2:0] seq = 0;
	reg [3:0] lpc = 9;
	reg [14:0] atr_data = 0;
	wire [7:0] chrline_c, chrline_g;
//	wire [7:0] text_data;
	wire chlast, dotl, dotr, rowbuf_we;
	wire hvalid = dotcnt >= START_H & dotcnt < END_H;
	wire vvalid = hcnt >= START_V & hcnt < END_V;
	wire burst = dotcnt >= 76 & dotcnt < 112;
	wire hsync = dotcnt < 67;
	wire vsync = hcnt < 3;
	assign chlast = chcnt == lpc;

	// VGA
	reg [9:0] dotcnt2 = 0;
	reg [9:0] hcnt2 = 0;
	wire hsync2 = dotcnt2 < 109;
	wire vsync2 = hcnt2 < 2;
	wire hvalid2 = dotcnt2 >= START_H2 & dotcnt2 < END_H2;
	wire vvalid2 = hcnt2 >= START_V2 & hcnt2 < END_V2;
	
	//
	// register access
	//
	always @(posedge clk) begin
		if (port30h_we) begin
			width80 <= data[0];
			colormode <= ~data[1];
		end
		if (crtc_we) begin
			if (adr) begin
				if (data == 8'h00) seq <= 5;
				if (data == 8'h80) ycurs <= 31;
				if (data == 8'h81) seq <= 7;
			end
			else begin
				if (seq == 3) lpc <= data[3:0];
				if (seq == 7) xcurs <= data[6:0];
				if (seq == 6) ycurs <= data[4:0];
				if (seq) seq <= seq == 6 ? 0 : seq - 1;
			end
		end
	end

	//
	always @(posedge clk) begin
		if (dotcnt == 909) begin
			dotcnt <= 0;
			if (hcnt == 261) begin
				hcnt <= 0;
				vcnt <= vcnt + 1;
			end
			else begin
				if (~vvalid | chlast) chcnt <= 4'b0000;
				else chcnt <= chcnt + 1;
				hcnt <= hcnt + 1;
			end
		end
		else dotcnt <= dotcnt + 1;
	end
	
	//
	// DMA state
	//
	always @(posedge clk) begin
		if (state == 0 & dotcnt == END_H) begin
			if (hcnt == 0) dma_src_adr <= 12'h300;
			if ((hcnt == CHCNT_RESET_V | chlast)) begin
				state <= 1;
				dma_dst_adr <= 0;
			end
		end
/*
		if (state == 1 & busack) state <= 2;
		if (state == 2) state <= 3;
		if (state == 3) begin
			state <= dma_dst_adr == 7'h77 ? 0 : 2;
			dma_src_adr <= dma_src_adr + 1;
			dma_dst_adr <= dma_dst_adr + 1;
		end
*/
		if (state == 1 & busack) state <= 2;
		if (state == 2) begin
			dma_src_adr <= dma_src_adr + 1;
			state <= 3;
		end
		if (state == 3) begin
			dma_dst_adr <= dma_dst_adr + 1;
			state <= dma_dst_adr == 7'h77 ? 0 : 2;
		end
		busreq <= state != 0;
	end
	assign ram_ce_n = 1'b0;
	assign ram_oe_n = 1'b0;
	assign ram_we_n = 1'b1;
	assign ram_adr = { 5'h0f, dma_src_adr };

	//
	// text
	//
	always @(posedge clk) begin
		if (hvalid & dotcnt[2:0] == 3'b111) begin
			text_adr <= text_adr + 1;
			xcnt <= xcnt + 1;
		end
		if (dotcnt == 909) begin
			text_adr <= 0;
			xcnt <= 0;
		end
	end

	//
	// attribute
	//
	always @(posedge clk) begin
		if (dotcnt[2:0] == 3'b001) atr_data[14:8] <= text_data[6:0];
		if (dotcnt[2:0] == 3'b011) atr_data[7:0] <= text_data;
		if (hvalid & dotcnt[2:0] == 3'b110 & atr_data[14:8] == xcnt) begin
			atr_adr <= atr_adr + 1;
			if (colormode & atr_data[3]) atr[6:3] <= atr_data[7:4];
			else atr[2:0] <= atr_data[2:0];
			if (~colormode) atr[6:3] <= { 3'b111, atr_data[7] };
		end
		if (dotcnt == 909) begin
			if (hcnt == CHCNT_RESET_V) begin
				atr_adr <= 6'h28;
				ycnt <= 0;
			end
			else if (chlast) begin
				atr_adr <= 6'h28;
				atr0 <= atr;
				ycnt <= ycnt + 1;
			end
			else begin
				atr_adr <= 6'h28;
				atr <= atr0;
			end
		end
	end

	//
	// color
	//
	reg [2:0] color;
	wire [3:0] col;
	wire [2:0] ctmp;
	assign ctmp[2] = ~burst & color[2];
	assign ctmp[1] = ~burst & (color[2] ^ color[1]);
	assign ctmp[0] = ~burst & (color[2] ^ color[0]);

	colordata colordata(
		.clk(clk),
		.adr({ burst, ctmp[1:0], ctmp[2] ^ dotcnt[1] ^ hcnt[0], dotcnt[0] }),
		.data(col)
	);

	//
	assign rowbuf_we = state == 3;
	wire [6:0] rowbuf_adr = dotcnt[2] ? text_adr : { atr_adr, dotcnt[1] };

	//
	// ROW BUFFER
	//
	reg[7:0] rowbuf[0:127];
	
	always @( posedge clk)
	begin
		if( rowbuf_we) rowbuf[dma_dst_adr] <= ram_data;
		text_data <= rowbuf[rowbuf_adr];
	end
	
	//
	// CG ROM / PCG RAM
	//
	wire [7:0]	pcg_ram;
	wire [7:0]	cg_rom;
	wire [10:0]	cg_adr;
	
	assign	cg_adr = { text_data, chcnt[2:0] };
	assign	chrline_c = pcg_on & cg_adr[10] ? pcg_ram : cg_rom;
	
	pcgram pcgram (
		.clock		( clk			),
		.data			( pcg_data	),
		.rdaddress	( cg_adr[9:0]	),
		.wraddress	( pcg_adr	),
		.wren			( pcg_we		),
		.q				( pcg_ram	)
	);
	
	cgrom cgrom (
		.address		( cg_adr 	),
		.clock		( clk			),
		.q				( cg_rom		)
	);
	
	assign dotl = sel2(chcnt[2:1], text_data[3:0]);
	assign dotr = sel2(chcnt[2:1], text_data[7:4]);
	assign chrline_g = { dotl, dotl, dotl, dotl, dotr, dotr, dotr, dotr };

	always @(posedge clk) begin
		if (dotcnt[2:0] == 3'b111 & (width80 | ~dotcnt[3])) begin
			if (hvalid & vvalid & ~chcnt[3]) 
				chrline <= atr[3] ? chrline_g : chrline_c;
			else chrline <= 8'b00000000;
			qinh <= atr[0] | (atr[1] & vcnt[6:5] == 2'b00);
			qrev <= atr[2] & hvalid & vvalid;
			qcurs <= vcnt[5] & hvalid & xcnt == xcurs & ycnt == ycurs;
			color <= atr[6:4];
		end
		else if (width80 | dotcnt[0]) chrline <= chrline << 1;
	end

	wire d0 = hsync ~^ vsync;
	wire y0 = (chrline[7] & ~qinh) ^ qrev ^ qcurs;

	always @(posedge clk) q0 <= d0;

	assign y_out = y0 ? { 1'b1, color[2:0] } : q0 ? 4'h8 : 4'h4;
	assign c_out = burst | y0 ? col : 4'h8;

	assign bw_out[0] = q0;
	assign bw_out[1] = y0;
	
	//
	// LINE BUFFER
	//
	reg[9:0]	lb_src_adr;
	reg[9:0]	lb_dst_adr;
	reg[3:0] linebuf[0:2048];
	reg[3:0]	lb_out;
	
	// VGA SYNC
	always @(posedge clk2) begin
		if (dotcnt2 == 909) begin
			dotcnt2 <= 0;
			if (hcnt2 == 523) begin
				hcnt2 <= 0;
			end
			else begin
				hcnt2 <= hcnt2 + 1;
			end
		end
		else dotcnt2 <= dotcnt2 + 1;
	end
	
	always @ (posedge clk) begin
		if ( dotcnt == 0 ) lb_src_adr <= 0;
		if ( hvalid ) begin
			linebuf[ { hcnt[0], lb_src_adr }] <= { y0, color[2:0]};
			lb_src_adr <= lb_src_adr + 1;
		end
	end
	
	always @ (posedge clk2) begin
		if ( dotcnt2 == 0 ) lb_dst_adr <= 1;
		if ( hvalid2 ) begin
			lb_out <= linebuf[ { ~hcnt[0], lb_dst_adr } ];
			lb_dst_adr <= lb_dst_adr + 1;
		end
	end

	assign vga_hs = ~hsync2;
	assign vga_vs = ~vsync2;

	assign vga_b = mode ? 4'b0000 : 
						hvalid2 & vvalid2 & lb_out[3] & lb_out[0] ? 4'b1111 : 4'b0000;
	assign vga_r = mode ? 4'b0000 :
						hvalid2 & vvalid2 & lb_out[3] & lb_out[1] ? 4'b1111 : 4'b0000;
	assign vga_g = mode ?
						( hvalid2 & vvalid2 & lb_out[3] ? { lb_out[2:0], 1'b1 } : 4'b0001 ) :
						( hvalid2 & vvalid2 & lb_out[3] & lb_out[2] ? 4'b1111 : 4'b0000 );				
					
endmodule

module colordata(clk, adr, data);
	input clk;
	input [4:0] adr;
	output [3:0] data;
	reg [3:0] data;
	always @(posedge clk) begin
		case (adr)
			5'b00100: data = 4'h2;
			5'b00101: data = 4'h7;
			5'b00110: data = 4'he;
			5'b00111: data = 4'h9;
			5'b01000: data = 4'ha;
			5'b01001: data = 4'he;
			5'b01010: data = 4'h6;
			5'b01011: data = 4'h2;
			5'b01100: data = 4'h4;
			5'b01101: data = 4'hd;
			5'b01110: data = 4'hc;
			5'b01111: data = 4'h3;
			5'b10000: data = 4'he;
			5'b10001: data = 4'h8;
			5'b10010: data = 4'h2;
			5'b10011: data = 4'h8;
			default: data = 4'h8;
		endcase
	end
endmodule
