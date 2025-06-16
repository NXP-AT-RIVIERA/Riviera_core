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
//  File            : $ fifo_single_reg.sv $
//  Date            : $Date: Fri Sep 20 15:56:53 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : Single Element FIFO
//
//  Description	    : FIFO able to store a single element.
//		      The number of ports (i.e. number of elements that the FIFO can store !!!in parallel!!!) and the bitwidth are configurable.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

module fifo_single_reg #(
	parameter int unsigned N_PORTS   = 2, // number of elements that the FIFO can store !!!in parallel!!!
	parameter int unsigned WIDTH[N_PORTS] = '{N_PORTS{5}}, // bitwidth for each port
	parameter int unsigned WIDTH_MAX = 5 // maximum bitwdith among the ones defined in WIDTH[...]
) (
	input  logic                 clk_i            ,
	input  logic                 rst_an           ,
	input  logic                 push_i           , // push into the FIFO
	input  logic [WIDTH_MAX-1:0] data_in[N_PORTS] , // data to be stored into the FIFO
	input  logic                 pop_i            , // pop from the FIFO
	input  logic                 flush_i          , // flush the FIFO (i.e. clear)
	output logic [WIDTH_MAX-1:0] data_out[N_PORTS], // data out from the FIFO
	output logic                 is_empty_o       , // 1 if the FIFO is empty
	output logic                 is_full_o          // 1 if the FIFO is full
);

	// status bits: 1 if a data is stored, 0 otherwise
	logic status;
	// stored data
	logic [WIDTH_MAX-1:0] regout[N_PORTS];

	// generate the FF for the data stored into the FIFO
	generate
		// loop on the different ports
		for (genvar port_index = 0; port_index < N_PORTS; port_index++) begin
			// loop on the bits of the single port
			// this is useful to avoid the generation of unuseful FF if WIDTH[port_index]<WIDTH_MAX
			for (genvar bit_index = 0; bit_index < WIDTH[port_index]; bit_index++) begin
				always_ff @(posedge clk_i or negedge rst_an) begin : REGS
					if(~rst_an) begin
						regout[port_index][bit_index] <= 0;
					end else begin
						if (flush_i) begin
							regout[port_index][bit_index] <= 0;
						end
						else begin
							// if the FIFO is full, but a pop is received, you can concurrently push a new value overwriting the existing one
							if (pop_i && push_i && is_full_o) begin
								regout[port_index][bit_index] <= data_in[port_index][bit_index];
							end
							// if the FIFO is empty, and a pop and a push are received, nothing should be done since in this FIFO you have only
							// one register and pop+push=nothing happens
							else if (pop_i && push_i && is_empty_o) begin
								// nothing to do, just here for conditions
							end
							else begin
								// if pop is asserted and the FIFO is not empty, perform a pop
								// the data remains stored (in fact here you have nothing to do), but the status bit is set to 0
								if (pop_i && !is_empty_o) begin
									// nothing to do, just here for conditions
								end
								// if push is asserted and the FIFO is not full, perform a push storing the new data
								else if (push_i && !is_full_o) begin
									regout[port_index][bit_index] <= data_in[port_index][bit_index];
								end
							end
						end
					end
				end
			end
			// if the WIDTH of the port that we are currently generating is lower than WIDTH_MAX, set the remaining bits of regout[port_index] to 0.
			// These bits should not be used from outside, since the only useful ones are defined by WIDTH[port_index], but this statement is here just to
			// make the regout variable complete.
			if (WIDTH[port_index] < WIDTH_MAX) begin
				assign regout[port_index][WIDTH_MAX-1:WIDTH[port_index]] = '0;
			end
		end
	endgenerate

	// this generate is for the status bit
	// this bit is common to all the elements of the FIFO and it signals if a valid value is stored into the FIFO or not
	always_ff @(posedge clk_i or negedge rst_an) begin : STATUS
		if(~rst_an) begin
			status <= 1'b0;
		end else begin
			if (flush_i) begin
				status <= 1'b0;
			end
			else begin
				// if the FIFO is full, but a pop is received, you can concurrently push a new value overwriting the existing one
				if (pop_i && push_i && is_full_o) begin
					// nothing to do, just here for conditions
				end
				// if the FIFO is empty, and a pop and a push are received, nothing should be done since in this FIFO you have only
				// one register and pop+push=nothing happens
				else if (pop_i && push_i && is_empty_o) begin
					// nothing to do, just here for conditions
				end
				else begin
					// if pop is asserted and the FIFO is not empty, perform a pop setting the status bit to 0
					if (pop_i && !is_empty_o) begin
						status <= 1'b0;
					end
					// if push is asserted and the FIFO is not full, perform a push setting the status bit to 1
					else if (push_i && !is_full_o) begin
						status <= 1'b1;
					end
				end
			end
		end
	end

	// assign the output
	generate
		for (genvar port_index = 0; port_index < N_PORTS; port_index++) begin
			assign data_out[port_index] = regout[port_index];
		end
	endgenerate

	// define the signals to state if the FIFO is empty/full
	assign is_empty_o = !status;
	assign is_full_o  = status;

endmodule : fifo_single_reg

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: fifo_single_reg.sv.rca $
//	
//	 Revision: 1.3 Fri Sep 20 15:56:53 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.2 Tue Sep 17 14:54:06 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.1 Mon Dec 18 19:01:43 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.4 Tue Jul 18 15:00:37 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.3 Wed Oct 12 00:54:42 2022 nxf87116
//	 Added header and footer to the RTL files.
