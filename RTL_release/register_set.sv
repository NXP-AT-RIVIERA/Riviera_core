//  ----------------------------------------------------------------------------
//                    Copyright Message
//  ----------------------------------------------------------------------------
//  
//  COPYRIGHT (c) NXP B.V. 2021
//
//  Copyright and related rights are licensed under the "LA_OPT_Online Code Hosting NXP_Software_License" - v1.2 October 2023 (the "License"); 
//  you may not use this file except in compliance with the License. You may find a copu of the License in the main release package repository.
//  In consideration for NXP allowing you to access the Licensed Software, you are agreeing to be bound by the terms of this Agreement. 
//  If you do not agree to all of the terms of this Agreement, do not download, install or copy from GitHub or similar platform, the Licensed Software.
//  See the License for the specific language governing permissions and limitations under the License.
//
//  ----------------------------------------------------------------------------
//                    Design Information
//  ----------------------------------------------------------------------------
//
//  Organisation    : SCE - STI / Mobile Transactions
//
//  File            : $ register_set.sv $
//  Date            : $Date: Fri Sep 20 15:56:55 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : Internal Registers Unit
//
//  Description	    : Set of register (i.e. a register file) containing an array of registers.
//		      You can write a value into a register of the array specifying its index.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

module register_set #(
	parameter int unsigned N_ELEMENTS = 4, // number of elements
	parameter int unsigned WIDTH      = 5  // number of bits per element
) (
	input  logic                          clk_i         ,
	input  logic                          rst_an        ,
	input  logic                          write_enable_i, // write enable
	input  logic [$clog2(N_ELEMENTS)-1:0] write_index_i , // index of the location to write in
	input  logic [             WIDTH-1:0] data_i        , // input data
	input  logic [$clog2(N_ELEMENTS)-1:0] read_index_i  , // index of the location to read from; the output will be data_o
	output logic [             WIDTH-1:0] data_o          // output data of the location selected with read_index_i
);

	logic [WIDTH-1:0] regout[N_ELEMENTS];

	always_ff @(posedge clk_i or negedge rst_an) begin : REGS
		if(~rst_an) begin
			regout <= '{N_ELEMENTS{'0}};
		end else begin
			if (write_enable_i && (write_index_i < N_ELEMENTS)) begin
				regout[write_index_i] <= data_i;
			end
		end
	end

	// OUTPUT MUX
	always_comb begin : OUTPUT_MUX
		if (read_index_i < N_ELEMENTS) begin
			data_o = regout[read_index_i];
		end
		else begin
			data_o = regout[N_ELEMENTS-1];
		end
	end

endmodule : register_set

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: register_set.sv.rca $
//	
//	 Revision: 1.3 Fri Sep 20 15:56:55 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.2 Tue Sep 17 14:54:07 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.1 Mon Dec 18 19:01:45 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.3 Tue Jul 18 15:00:38 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.2 Wed Oct 12 00:54:46 2022 nxf87116
//	 Added header and footer to the RTL files.
