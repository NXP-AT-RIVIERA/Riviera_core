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
//  File            : $ rounding_unit_nearest.sv $
//  Date            : $Date: Fri Sep 20 15:56:55 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : Rounding2Nearest Unit
//
//  Description	    : Rounding unit implementing a round-to-nearest scheme.
//		      It should be preferred to bare truncation, since the
//		      accuracy is better and it fixes most of the drift errors.
//
//		      Examples:
//		      12.3 --> 12
//		      12.8 --> 13
//		      12.5 --> 13
//		      13.5 --> 14
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

module rounding_unit_nearest #(
	parameter bit          SIMD            = 0 , // if 1, SIMD is enabled and can be used according to simd_mode_i
	parameter int unsigned N_BIT_IN_MAX    = 32, // maximum number of bits of the input
	parameter int unsigned N_BIT_NOSIMD_IN = 32, // maximum number of bits of the input for non-SIMD operation
	parameter int unsigned N_BIT_SIMD_IN   = 32, // maximum number of bits of the input for SIMD operation
	// WARNING: YOU MUST ENSURE THAT THE OUTPUT NUMBER OF BITS IS SUITABLE, OTHERWISE TRUNCATION
	// AND UNWANTED EFFECTS MAY OCCUR
	parameter int unsigned N_BIT_OUT_MAX   = 32, // maximum number of bits of the input
	parameter int unsigned N_BIT_SIMD_OUT  = 32, // number of bits for the output for SIMD operation: the SIMD packing is made according to this value
	parameter int unsigned BITS_CUT_MAX    = 8   // maximum number of bits to cut (used to define the n_bits_cut_i parallelism)
) (
	// if 0, the input operands are threated as a single value (i.e. no-SIMD); if 1, the input operands are threated as a packed-simd value (i.e. two values packed in the two halves)
	input  logic                              simd_mode_i      ,
	// unrounded input
	input  logic [          N_BIT_IN_MAX-1:0] unrounded_value_i,
	// number of bits to be cut
	input  logic [$clog2(BITS_CUT_MAX+1)-1:0] n_bits_cut_i     ,
	// rounded output
	output logic [         N_BIT_OUT_MAX-1:0] rounded_value_o  ,
	// unrounded output: the difference with unrounded_value_i is that in case of simd_mode_i=1, unrounded_value_o is the packed version on N_BIT_SIMD_OUT bits of unrounded_value_i
	output logic [         N_BIT_OUT_MAX-1:0] unrounded_value_o
);

	// generate the wiring for the unrounded output packing unit according to SIMD parameter
	generate
		if (SIMD) begin : UNROUNDED_OUT_PACKING_SIMD_GEN
			// generate unrounded_value_o simply re-packing unrounded_value_i according to N_BIT_OUT
			// notice that these are constant variables, therefore no logic is genereated, but it is only a simple wiring
			always_comb begin : UNROUNDED_OUTPUT_PACKING
				if (simd_mode_i == 0) begin
					unrounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0]));
				end
				else begin
					unrounded_value_o[N_BIT_SIMD_OUT/2-1:0]             = (N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[N_BIT_SIMD_IN/2-1:0]));
					// if N_BIT_SIMD_IN is odd, the MSB is discarded ((N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2) gives an even number). If N_BIT_OUT_MAX>N_BIT_SIMD_OUT, sign-extension is performed.
					unrounded_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2+1)'((N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[(N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2)-1:N_BIT_SIMD_IN/2])));
				end
			end
		end
		else begin : UNROUNDED_OUT_PACKING_NOSIMD_GEN
			assign unrounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0]));
		end
	endgenerate

	// generate the rounding unit according to SIMD parameter
	generate
		if (SIMD) begin : ROUNDING_SIMD_GEN
			// combinational logic to perform the rounding
			always_comb begin : ROUNDING
				// rounding for non-SIMD operands
				if (simd_mode_i == 0) begin
					// if no bits to be cut, simply assign the unrounded input to rounded output
					if (n_bits_cut_i == 0) begin
						rounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0]));
					end
					else begin
						rounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0] + (N_BIT_NOSIMD_IN)'(1'b1 << (n_bits_cut_i-1))) >>> n_bits_cut_i);
					end
				end
				// rounding for SIMD operands
				else begin
					// if no bits to be cut, simply assign the unrounded input to rounded output, repacking the SIMD according to N_BIT_SIMD_IN and N_BIT_SIMD_OUT
					if (n_bits_cut_i == 0) begin
						rounded_value_o[N_BIT_SIMD_OUT/2-1:0]             = (N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[N_BIT_SIMD_IN/2-1:0]));
						// if N_BIT_SIMD_IN is odd, the MSB is discarded ((N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2) gives an even number). If N_BIT_OUT_MAX>N_BIT_SIMD_OUT, sign-extension is performed.
						rounded_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2+1)'((N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[(N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2)-1:N_BIT_SIMD_IN/2])));
					end
					// otherwise a rounding is needed
					else begin
						// LOWER PACKED NUMBER
						rounded_value_o[N_BIT_SIMD_OUT/2-1:0] = (N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[N_BIT_SIMD_IN/2-1:0] + (N_BIT_SIMD_IN/2)'(1'b1 << (n_bits_cut_i-1))) >>> n_bits_cut_i);

						// HIGHER PACKED NUMBER
						// if N_BIT_SIMD_IN is odd, the MSB is discarded ((N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2) gives an even number)
						rounded_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2+1)'((N_BIT_SIMD_OUT/2)'(signed'(unrounded_value_i[(N_BIT_SIMD_IN/2+N_BIT_SIMD_IN/2)-1:N_BIT_SIMD_IN/2] + (N_BIT_SIMD_IN/2)'(1'b1 << (n_bits_cut_i-1))) >>> n_bits_cut_i));
					end
				end
			end
		end
		else begin : ROUNDING_NOSIMD_GEN
			// combinational logic to perform the rounding
			always_comb begin : ROUNDING
				// if no bits to be cut, simply assign the unrounded input to rounded output
				if (n_bits_cut_i == 0) begin
					rounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0]));
				end
				else begin
					rounded_value_o = (N_BIT_OUT_MAX)'(signed'(unrounded_value_i[N_BIT_NOSIMD_IN-1:0] + (N_BIT_NOSIMD_IN)'(1'b1 << (n_bits_cut_i-1))) >>> n_bits_cut_i);
				end
			end
		end
	endgenerate

endmodule : rounding_unit_nearest

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: rounding_unit_nearest.sv.rca $
//	
//	 Revision: 1.3 Fri Sep 20 15:56:55 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.2 Tue Sep 17 14:54:08 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.1 Mon Dec 18 19:01:43 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.3 Tue Jul 18 15:00:37 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.2 Wed Oct 12 00:54:42 2022 nxf87116
//	 Added header and footer to the RTL files.
