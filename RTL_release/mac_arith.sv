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
//  File            : $ mac_arith.sv $
//  Date            : $Date: Fri Sep 20 15:56:54 2024 $
//  Revision        : $Revision: 1.4 $
//
//  Design Unit     : MAC Arithmetic Unit
//
//  Description	    : Arithmetic block (fully combinational) implementing multiply-accumulate operation.
//		      It supports SIMD and some parameters are configurable.
//  
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

module mac_arith #(
	parameter N_OPERANDS        = 34                                                , // number of operands
	parameter SIMD              = 0                                                 , // if 1, SIMD is enabled and can be used according to simd_mode_i
	parameter N_BIT_OP_A_MAX    = 32                                                , // maximum number of bits of the first operand (to be correctly defined according to N_BIT_OP_A_NOSIMD and N_BIT_OP_A_SIMD)
	parameter N_BIT_OP_B_MAX    = 32                                                , // maximum number of bits of the second operand (to be correctly defined according to N_BIT_OP_B_NOSIMD and N_BIT_OP_B_SIMD)
	parameter N_BIT_OP_A_NOSIMD = 32                                                , // number of bits of the first operand for non-SIMD operation
	parameter N_BIT_OP_B_NOSIMD = 32                                                , // number of bits of the second operand for non-SIMD operation
	parameter N_BIT_OP_A_SIMD   = 32                                                , // number of bits of the first operand for SIMD operation
	parameter N_BIT_OP_B_SIMD   = 32                                                , // number of bits of the second operand for SIMD operation
	// number of bits of the output result.
	// WARNING! If N_BIT_OUT is too low, truncation is done and the output number could be wrong!
	parameter N_BIT_OUT_MAX     = N_BIT_OP_A_MAX+N_BIT_OP_B_MAX+2*$clog2(N_OPERANDS), // maximum number of bits of the first operand (it must be >= N_BIT_SIMD_OUT)
	parameter N_BIT_SIMD_OUT    = N_BIT_OP_A_MAX+N_BIT_OP_B_MAX+2*$clog2(N_OPERANDS)  // number of bits of the SIMD output that states how it is packed in output
) (
	// if 0, the input operands are threated as a single value (i.e. no-SIMD); if 1, the input operands are threated as a packed-simd value (i.e. two values packed in the two halves)
	input  logic                      simd_mode_i              ,
	// first operand: it can be SIMD or non-SIMD, according to simd_mode_i
	input  logic [N_BIT_OP_A_MAX-1:0] operands_a_i [N_OPERANDS],
	// first operand: it can be SIMD or non-SIMD, according to simd_mode_i
	input  logic [N_BIT_OP_B_MAX-1:0] operands_b_i [N_OPERANDS],
	// output result: it can be SIMD or non-SIMD, according to simd_mode_i
	output logic [ N_BIT_OUT_MAX-1:0] result_o
);

	// temporary result variable
	logic [N_BIT_OUT_MAX-1:0] result_temp;

	generate
		if (SIMD) begin : MAC_SIMD_GEN
			// define the MAC with a for loop
			always_comb begin : MAC_ARITHMETIC_COMB_LOGIC
				result_temp = 0;
				// MAC for non-SIMD operation
				if (simd_mode_i == 0) begin
					for (int i = 0; i < N_OPERANDS; i++) begin
						result_temp = (N_BIT_OUT_MAX)'($signed(result_temp) + $signed(operands_a_i[i][N_BIT_OP_A_NOSIMD-1:0])*$signed(operands_b_i[i][N_BIT_OP_B_NOSIMD-1:0]));
					end
				end
				// MAC for SIMD operation
				else begin
					for (int i = 0; i < N_OPERANDS; i++) begin
						// compute the result for the lower word stored into the packed-simd (i.e. the first half)
						result_temp[N_BIT_SIMD_OUT/2-1:0]                         = (N_BIT_SIMD_OUT/2)'($signed(result_temp[N_BIT_SIMD_OUT/2-1:0]) + $signed(operands_a_i[i][N_BIT_OP_A_SIMD/2-1:0])*$signed(operands_b_i[i][N_BIT_OP_B_SIMD/2-1:0]));
						// compute the result for the upper word stored into the packed-simd (i.e. the second half)
						// if N_BIT_* is odd, the MSB is discarded ((N_BIT_*/2+N_BIT_*/2) gives an even number)
						//result_temp[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2+1)'((N_BIT_SIMD_OUT/2)'($signed(result_temp[(N_BIT_SIMD_OUT/2+N_BIT_SIMD_OUT/2)-1:N_BIT_SIMD_OUT/2]) + $signed(operands_a_i[i][(N_BIT_OP_A_SIMD/2+N_BIT_OP_A_SIMD/2)-1:N_BIT_OP_A_SIMD/2])*$signed(operands_b_i[i][(N_BIT_OP_B_SIMD/2+N_BIT_OP_B_SIMD/2)-1:N_BIT_OP_B_SIMD/2])));
						//2024 MOD - to fix error in LINT
						result_temp[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2)'((N_BIT_SIMD_OUT/2)'($signed(result_temp[(N_BIT_SIMD_OUT/2+N_BIT_SIMD_OUT/2)-1:N_BIT_SIMD_OUT/2]) + $signed(operands_a_i[i][(N_BIT_OP_A_SIMD/2+N_BIT_OP_A_SIMD/2)-1:N_BIT_OP_A_SIMD/2])*$signed(operands_b_i[i][(N_BIT_OP_B_SIMD/2+N_BIT_OP_B_SIMD/2)-1:N_BIT_OP_B_SIMD/2])));
					end
				end
				result_o = result_temp;
			end
		end
		else begin : MAC_NO_SIMD_GEN
			// define the MAC with a for loop
			always_comb begin : MAC_ARITHMETIC_COMB_LOGIC
				result_temp = 0;
				for (int i = 0; i < N_OPERANDS; i++) begin
					result_temp = (N_BIT_OUT_MAX)'($signed(result_temp) + $signed(operands_a_i[i][N_BIT_OP_A_NOSIMD-1:0])*$signed(operands_b_i[i][N_BIT_OP_B_NOSIMD-1:0]));
				end
				result_o = result_temp;
			end
		end
	endgenerate

endmodule : mac_arith

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: mac_arith.sv.rca $
//	
//	 Revision: 1.4 Fri Sep 20 15:56:54 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.3 Tue Sep 17 14:54:07 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.2 Mon Sep 16 12:47:15 2024 nxg06494
//	 artf1178505 : Modified file to fix lint error
//	
//	 Revision: 1.1 Mon Dec 18 19:01:44 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.3 Tue Jul 18 15:00:38 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.2 Wed Oct 12 00:54:46 2022 nxf87116
//	 Added header and footer to the RTL files.
