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
//  File            : $ output_modifier.sv $
//  Date            : $Date: Fri Sep 20 15:56:54 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : Output Modifier Unit
//
//  Description	    : Output modifier as final stage of the processing chain mac arith + rounding unit + output modifier
//		      According to the control signal one can produce
//		      00 -> simply wiring
//		      01 -> absolute value
//		      10 -> sum of simd I/Q
//		      11 -> not used so far
//
//  Author 	    : Tommaso Ricci
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

module output_modifier #(
	parameter bit          SIMD            = 0 , // if 1, SIMD is enabled and can be used according to simd_mode_i
	parameter int unsigned N_BIT_IN_MAX    = 32, // maximum number of bits of the input
	parameter int unsigned N_BIT_NOSIMD_IN = 32, // maximum number of bits of the input for non-SIMD operation
	parameter int unsigned N_BIT_SIMD_IN   = 32, // maximum number of bits of the input for SIMD operation
	parameter int unsigned N_BIT_OUT_MAX   = 32, // maximum number of bits of the output
	parameter int unsigned N_BIT_SIMD_OUT  = 32  // number of bits for the output for SIMD operation: the SIMD packing is made according to this value
) (
	// if 0, the input operands are threated as a single value (i.e. no-SIMD); if 1, the input operands are threated as a packed-simd value (i.e. two values packed in the two halves)
	input  logic                              simd_mode_i     ,
	input  logic [          N_BIT_IN_MAX-1:0] rounded_value_i ,  // rounded input
	input  logic [                       1:0] output_mod_sel_i,  //selctor for the output modifier module
	output logic [         N_BIT_OUT_MAX-1:0] modified_value_o  // modified output
);

	generate
		if (SIMD) begin : SIMD_PARAMETER_SET
			always_comb begin  
				if (simd_mode_i == 0) begin //NO EFFECTIVE SIMD CASE
					if(output_mod_sel_i == 2'b00) begin	//wiring
						modified_value_o = rounded_value_i;
					end
					else if(output_mod_sel_i == 2'b01) begin	//absolute
						if(signed'(rounded_value_i) < 0) begin
							modified_value_o = signed'(- rounded_value_i);
						end
						else begin
							modified_value_o = rounded_value_i;
						end
					end
					//for no effective simd case it makes no sense to perform a sum, so the code 10 for the 					output_mod_sel_i is not check, anyway a default condition is set
					else begin //wiring default
						modified_value_o = rounded_value_i;
					end
				end
				else begin //EFFECTIVE SIMD CASE 
					if(output_mod_sel_i == 2'b00) begin	//wiring
						modified_value_o[N_BIT_SIMD_OUT/2-1:0] 	           = (N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN/2-1:0])); //lower half
					// If N_BIT_OUT_MAX>N_BIT_SIMD_OUT, sign-extension is performed.
						modified_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2)'((N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2]))); //upper half
					end
					else if(output_mod_sel_i == 2'b01) begin	//absolute
						if(signed'(rounded_value_i[N_BIT_SIMD_IN/2-1:0]) < 0) begin //absolute lower
							modified_value_o[N_BIT_SIMD_OUT/2-1:0]      = (N_BIT_SIMD_OUT/2)'(signed'(- rounded_value_i[N_BIT_SIMD_IN/2-1:0])); //lower half
						end
						else begin //default wiring
							modified_value_o[N_BIT_SIMD_OUT/2-1:0] 	           = (N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN/2-1:0])); //lower half
						end					
						
						if(signed'(rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2]) < 0) begin //absolute upper
						modified_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2)'((N_BIT_SIMD_OUT/2)'(signed'(- rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2]))); //upper half				
						end
						else begin //default wiring
							modified_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2)'((N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2]))); //upper half
						end
					end
					else if(output_mod_sel_i == 2'b10) begin	//addition
						modified_value_o = (N_BIT_OUT_MAX)'((N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN/2-1:0])) + (N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2])));
					end
					else begin //wiring default
						modified_value_o[N_BIT_SIMD_OUT/2-1:0] 	           = (N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN/2-1:0])); //lower half
						modified_value_o[N_BIT_OUT_MAX-1:N_BIT_SIMD_OUT/2] = (N_BIT_OUT_MAX-N_BIT_SIMD_OUT/2)'((N_BIT_SIMD_OUT/2)'(signed'(rounded_value_i[N_BIT_SIMD_IN-1:N_BIT_SIMD_IN/2]))); //upper half
					end
					
				end
			end
		end
		else begin : NO_SIMD_PARAMETER_SET
			always_comb begin 
				if(output_mod_sel_i == 2'b00) begin	//wiring
					modified_value_o = rounded_value_i;
				end
				else if(output_mod_sel_i == 2'b01) begin	//absolute
					if(signed'(rounded_value_i) < 0) begin
						modified_value_o = signed'(- rounded_value_i);						
					end
					else begin
						modified_value_o = rounded_value_i;
					end
				end
				//for no simd case it makes no sense to perform a sum, so the code 10 for the output_mod_sel_i is not checked out, anyway a default condition is set
				else begin //wiring default
					modified_value_o = rounded_value_i;
				end
			end
		end
	endgenerate
endmodule: output_modifier

