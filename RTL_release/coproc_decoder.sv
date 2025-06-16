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
//  File            : $ coproc_decoder.sv $
//  Date            : $Date: Fri Sep 20 15:56:52 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : CoProcessor Decoder
//
//  Description	    : Coprocessor Decoder.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

import coproc_pkg::*;

module coproc_decoder #(parameter bit SIMD_MAC = 0) (
	input  logic [31:0]          instr_i       ,
	output decoder_ctrl_coproc_t decoder_ctrl_o
);

	logic [6:0] opcode;
	logic [2:0] funct3;
	logic [6:0] funct7;
	logic [4:0] rd    ;
	logic [9:0] funct3_funct7;

	assign opcode = instr_i[6:0];
	assign funct3 = instr_i[14:12];
	assign funct7 = instr_i[31:25];
	assign rd     = instr_i[11:7];

	assign funct3_funct7 = {funct3, funct7};

	always_comb begin
		unique case (opcode)
			// the opcode related to the MAC has been selected
			OPCODE_MAC : begin
				// check func3 and drive the signals accordingly
				unique case (funct3_funct7)
					// Configuration Instructions
					OP_CLEAR_DATA : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_CLEAR;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b001;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_CLEAR_COEFF : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_CLEAR;
						decoder_ctrl_o.mac_ctrl.data_coeff = 1;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b001;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_SET_NFEED : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_SET_NFEED;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_SET_ROUNDING : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_SET_ROUNDING;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_SET_FEATURES : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_SET_FEATURES;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_SET_CHAINING : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_CONFIG_CHAINED_EXEC;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					// Load Instructions
					OP_LOAD_DATA_MEM : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 1;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_LOAD_COEFF_MEM : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD;
						decoder_ctrl_o.mac_ctrl.data_coeff = 1;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 1;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_LOAD_DATA_REG : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_LOAD_COEFF_REG : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD;
						decoder_ctrl_o.mac_ctrl.data_coeff = 1;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					// Execute Instruction
					OP_EXEC : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_EXEC;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b001;
						decoder_ctrl_o.rd                  = rd;
						decoder_ctrl_o.writeback           = 1;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					// Load and Execute Instructions
					OP_LOAD_EXEC_DATA_MEM : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD_EXEC_DATA;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = rd;
						decoder_ctrl_o.writeback           = 1;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 1;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_LOAD_EXEC_DATA_REG : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD_EXEC_DATA;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = rd;
						decoder_ctrl_o.writeback           = 1;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					OP_CHAINED_LOAD_EXEC_DATA_REG : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 1;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_LOAD_CHAINED_EXEC_DATA_REG ;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 1;
						decoder_ctrl_o.illegal_instr       = 0;
						decoder_ctrl_o.rs_required         = 3'b011;
						decoder_ctrl_o.rd                  = rd;
						decoder_ctrl_o.writeback           = 1;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
					// Illegal Instruction
					default : begin
						decoder_ctrl_o.mac_ctrl.mac_enable = 0;
						decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_CLEAR;
						decoder_ctrl_o.mac_ctrl.data_coeff = 0;
						decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
						decoder_ctrl_o.illegal_instr       = 1;
						decoder_ctrl_o.rs_required         = '0;
						decoder_ctrl_o.rd                  = '0;
						decoder_ctrl_o.writeback           = 0;
						decoder_ctrl_o.dualwrite           = 0;
						decoder_ctrl_o.dualread            = '0;
						decoder_ctrl_o.loadstore           = 0;
						decoder_ctrl_o.ecswrite            = 0;
						decoder_ctrl_o.exc                 = 0;
					end
				endcase
			end
			// Illegal Instruction
			default : begin
				decoder_ctrl_o.mac_ctrl.mac_enable = 0;
				decoder_ctrl_o.mac_ctrl.mac_op     = MAC_OP_CLEAR;
				decoder_ctrl_o.mac_ctrl.data_coeff = 0;
				decoder_ctrl_o.mac_ctrl.mem_reg    = 0;
				decoder_ctrl_o.illegal_instr       = 1;
				decoder_ctrl_o.rs_required         = '0;
				decoder_ctrl_o.rd                  = '0;
				decoder_ctrl_o.writeback           = 0;
				decoder_ctrl_o.dualwrite           = 0;
				decoder_ctrl_o.dualread            = '0;
				decoder_ctrl_o.loadstore           = 0;
				decoder_ctrl_o.ecswrite            = 0;
				decoder_ctrl_o.exc                 = 0;
			end
		endcase
	end

endmodule : coproc_decoder

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_decoder.sv.rca $
//	
//	 Revision: 1.3 Fri Sep 20 15:56:52 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.2 Tue Sep 17 14:54:04 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.1 Mon Dec 18 19:01:46 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.9 Wed Oct 12 00:54:46 2022 nxf87116
//	 Added header and footer to the RTL files.
