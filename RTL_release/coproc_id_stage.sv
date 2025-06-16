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
//  File            : $ coproc_id_stage.sv $
//  Date            : $Date: Fri Sep 20 15:56:52 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : CoProcessor Instruction Decoder Unit
//
//  Description	    : Coprocessor ID-stage.
//		      It contains the instruction decoder and manages the control signals needed for the issue interface.
//		      Decoder is combinationally connected to the issue interface.
//		      A pipe stage is present between the ID and the EX stage.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

import coproc_pkg::*;

module coproc_id_stage #(parameter bit SIMD_MAC = 0) (
	input  logic               clk_i                ,
	input  logic               rst_an               ,
	// issue interface
	cv32e40x_if_xif.coproc_issue        xif_issue_if         ,
	// issue fifo related signals
	input  logic               issue_fifo_is_empty_i,
	input  logic               issue_fifo_is_full_i ,
	input  logic               fifo_pop_i           ,
	// pipe handshaking
	input  logic               ex_ready_i           ,
	// ID/EX pipeline: these will be the signals going to the EX stage
	output id_ex_coproc_pipe_t id_ex_pipe_o         ,
	// needed to select the right ALU output among the ones coming from the different blocks present in it
	output alu_block_sel_t     alu_block_sel_o
);

	logic rs_available;
	logic[X_ID_WIDTH-1:0] id_regout;
	logic valid_regout;
	logic id_changed  ;

	// decoder instance
	decoder_ctrl_coproc_t decoder_ctrl_o;

	coproc_decoder #(.SIMD_MAC(SIMD_MAC)) i_coproc_decoder (
		.instr_i       (xif_issue_if.issue_req.instr),
		.decoder_ctrl_o(decoder_ctrl_o              )
	);

	// check if the registers required by the instruction are validly passed by the core
	assign rs_available = ((decoder_ctrl_o.rs_required & xif_issue_if.issue_req.rs_valid) == decoder_ctrl_o.rs_required);
	// check is the instruction has to be accepted or rejected
	always_comb begin : INSTR_ACC_REJ_COMB_PROC
		if (xif_issue_if.issue_valid && xif_issue_if.issue_ready && id_changed && !decoder_ctrl_o.illegal_instr && rs_available) begin
			xif_issue_if.issue_resp.accept    = 1;
			xif_issue_if.issue_resp.writeback = decoder_ctrl_o.writeback;
			xif_issue_if.issue_resp.dualwrite = decoder_ctrl_o.dualwrite;
			xif_issue_if.issue_resp.dualread  = decoder_ctrl_o.dualread;
			xif_issue_if.issue_resp.loadstore = decoder_ctrl_o.loadstore;
			xif_issue_if.issue_resp.ecswrite  = decoder_ctrl_o.ecswrite;
			xif_issue_if.issue_resp.exc       = decoder_ctrl_o.exc;
		end else begin
			xif_issue_if.issue_resp.accept    = 0;
			xif_issue_if.issue_resp.writeback = 0;
			xif_issue_if.issue_resp.dualwrite = 0;
			xif_issue_if.issue_resp.dualread  = 0;
			xif_issue_if.issue_resp.loadstore = 0;
			xif_issue_if.issue_resp.ecswrite  = 0;
			xif_issue_if.issue_resp.exc       = 0;
		end
	end

	// if the issue fifo is_full, the coprocessor cannot accept other instructions.
	// TODO: in the current implementation we do not manage more than one instruction at a time in
	// the coprocessor, therefore the fifo will always contain 1 instruction at maximum, but
	// in future implementation improvements could be done.
	assign xif_issue_if.issue_ready = !issue_fifo_is_full_i || (issue_fifo_is_full_i && fifo_pop_i);

	// This statement is useful for the cases in which the CPU is maintaining the same
	// issue request on the interface even if the coprocessor has accepted or rejected it.
	// In addition, as written into the x-interface specifications, the CPU can offload a new instruction maintaining
	// the valid signal high and changing only the id and with this signals we manage that case.
	always_ff @(posedge clk_i or negedge rst_an) begin : ID_REG
		if(~rst_an) begin
			id_regout    <= 0;
			valid_regout <= 0;
		end else begin
			if (xif_issue_if.issue_resp.accept) begin
				id_regout    <= xif_issue_if.issue_req.id;
				valid_regout <= 1;
			end
			else if (!xif_issue_if.issue_valid) begin
				valid_regout <= 0;
			end
		end
	end

	assign id_changed = !((xif_issue_if.issue_req.id == id_regout) && valid_regout);

	// pipe registers: update the pipe ONLY if the ID stage has a valid instruction to deliver
	// AND the EX stage is ready to receive it. Otherwise, do NOT change the value of the pipe
	// regs both to save power if accept=0 and to not influence the EX stage that is working
	// if ex_ready_i=0. The instr_valid signal is an exception since it has to be always
	// updated if the ex stage is ready, in order to signal it that there is no valid instruction.
	always_ff @(posedge clk_i or negedge rst_an) begin : ID_EX_PIPE_REGISTERS
		if(~rst_an) begin
			id_ex_pipe_o.rs                  <= '0;
			id_ex_pipe_o.writeback           <= 0;
			id_ex_pipe_o.rd                  <= '0;
			id_ex_pipe_o.mac_ctrl.mac_enable <= 0;
			id_ex_pipe_o.mac_ctrl.mac_op     <= MAC_OP_CLEAR;
			id_ex_pipe_o.mac_ctrl.mem_reg    <= 0;
			id_ex_pipe_o.mac_ctrl.data_coeff <= 0;
		end else begin
			if (ex_ready_i) begin
				if (xif_issue_if.issue_resp.accept) begin
					id_ex_pipe_o.rs        <= xif_issue_if.issue_req.rs;
					id_ex_pipe_o.writeback <= decoder_ctrl_o.writeback;
					id_ex_pipe_o.rd        <= decoder_ctrl_o.rd;
					id_ex_pipe_o.mac_ctrl  <= decoder_ctrl_o.mac_ctrl;
				end else begin
					// we need to place these signals to 0 to disable the ALU blocks.
					// Leave the other signals as they are to reduce power consumption, since they are not relevant.
					id_ex_pipe_o.mac_ctrl.mac_enable <= 0;
				end
			end
		end
	end

	// drive the alu_block_sel_o signal needed to select the right ALU block output in the EX stage.
	// This signal will be stored into the issue FIFO --> to the ex stage
	// for now only MAC is present, but if you add other instructions, you should use a MUX according to the instr_enable signals
	assign alu_block_sel_o = MAC_ALU_BLOCK_SEL;


	// TODO: exceptions?
	// TODO: ecs?
	// TODO: mode?

endmodule : coproc_id_stage

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_id_stage.sv.rca $
//	
//	 Revision: 1.3 Fri Sep 20 15:56:52 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.2 Tue Sep 17 14:54:06 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.1 Mon Dec 18 19:01:44 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.10 Tue Jul 18 15:00:38 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.9 Wed Oct 12 00:54:46 2022 nxf87116
//	 Added header and footer to the RTL files.
