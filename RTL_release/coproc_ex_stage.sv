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
//  File            : $ coproc_ex_Stage.sv $
//  Date            : $Date: Fri Sep 20 15:56:52 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : CoProcessor Execution Unit
//
//  Description	    : Coprocessor EX-stage.
//		      It contains the ALU and manages the control signals needed for the memory and result interfaces.
//		      A pipe stage is present between the ID and the EX stage.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

import coproc_pkg::*;

module coproc_ex_stage #(
	// MAC RELATED PARAMETERS
	parameter int unsigned N_BANKS_MAC                 = 4 , // number of banks
	parameter int unsigned N_ELEMENTS_BANK_MAC[N_BANKS_MAC] = '{N_BANKS_MAC{32'd4}}, // number of elements per bank
	parameter int unsigned N_ELEMENTS_BANK_MAX_MAC     = 4 , // maximum elements among the banks defined above
	parameter int unsigned WIDTH_DATA_MAC[N_BANKS_MAC] = '{N_BANKS_MAC{32'd32}}, // data parallelism per bank
	parameter int unsigned WIDTH_DATA_NOSIMD_MAX_MAC   = 32, // maximum parallelism for non-simd data
	parameter int unsigned WIDTH_DATA_SIMD_MAX_MAC     = 32, // maximum parallelism for simd data
	parameter int unsigned WIDTH_DATA_MAX_MAC          = 32, // maximum data parallelism among the banks defined above
	parameter int unsigned WIDTH_COEFFS_MAC[N_BANKS_MAC] = '{N_BANKS_MAC{32'd32}}, // coeffs parallelism per bank
	parameter int unsigned WIDTH_COEFFS_NOSIMD_MAX_MAC = 32, // maximum parallelism for non-simd coeffs
	parameter int unsigned WIDTH_COEFFS_SIMD_MAX_MAC   = 32, // maximum parallelism for simd coeffs
	parameter int unsigned WIDTH_COEFFS_MAX_MAC        = 32, // maximum coeffs parallelism among the banks defined above
	parameter bit          SIMD_MAC                    = 0 , // if 1, there is the possibility to use SIMD
	parameter int unsigned N_BIT_NFEED_MAC             = 2 , // number of bits of n_feed to setup the DATAREGS selectors
	parameter bit          FEEDBACK_UNROUNDED_MAC      = 0 , // if 1, store into the feedback part of the data regs the unrounded result. The result returned to the core register file will be always the rounded one.
	parameter int unsigned N_OPERANDS_MAC              = 4 , // number of operands that the MAC arithmetic block can process in parallel
	parameter int unsigned BITS_CUT_MAX_MAC            = 8   // maximum number of bits the rounding unit can throw away
) (
	input  logic               clk_i            ,
	input  logic               rst_an           ,
	// xif interface signals
	cv32e40x_if_xif.coproc_commit       xif_commit_if    ,
	cv32e40x_if_xif.coproc_mem          xif_mem_if       ,
	cv32e40x_if_xif.coproc_mem_result   xif_mem_result_if,
	cv32e40x_if_xif.coproc_result       xif_result_if    ,
	// FIFOs related signals
	input  issue_fifo_t        issue_fifo_out_i ,
	input  commit_fifo_t       commit_fifo_out_i,
	output logic               fifo_pop_o       ,
	// ID/EX pipeline
	input  id_ex_coproc_pipe_t id_ex_pipe_i     ,
	// pipe handshaking
	output logic               ex_ready_o
);

	logic                   memory_if_accept          ;
	logic                   result_if_accept          ;
	logic                   commit                    ;
	logic                   kill                      ;
	logic                   mem_exception_debug_valid ;
	exc_dbg_struct_coproc_t mem_exception_debug_struct;
	alu_out_t               alu_out                   ;

	coproc_alu #(
		.N_BANKS_MAC                (N_BANKS_MAC                ),
		.N_ELEMENTS_BANK_MAC        (N_ELEMENTS_BANK_MAC        ),
		.N_ELEMENTS_BANK_MAX_MAC    (N_ELEMENTS_BANK_MAX_MAC    ),
		.WIDTH_DATA_MAC             (WIDTH_DATA_MAC             ),
		.WIDTH_DATA_NOSIMD_MAX_MAC  (WIDTH_DATA_NOSIMD_MAX_MAC  ),
		.WIDTH_DATA_SIMD_MAX_MAC    (WIDTH_DATA_SIMD_MAX_MAC    ),
		.WIDTH_DATA_MAX_MAC         (WIDTH_DATA_MAX_MAC         ),
		.WIDTH_COEFFS_MAC           (WIDTH_COEFFS_MAC           ),
		.WIDTH_COEFFS_NOSIMD_MAX_MAC(WIDTH_COEFFS_NOSIMD_MAX_MAC),
		.WIDTH_COEFFS_SIMD_MAX_MAC  (WIDTH_COEFFS_SIMD_MAX_MAC  ),
		.WIDTH_COEFFS_MAX_MAC       (WIDTH_COEFFS_MAX_MAC       ),
		.SIMD_MAC                   (SIMD_MAC                   ),
		.N_BIT_NFEED_MAC            (N_BIT_NFEED_MAC            ),
		.FEEDBACK_UNROUNDED_MAC     (FEEDBACK_UNROUNDED_MAC     ),
		.N_OPERANDS_MAC             (N_OPERANDS_MAC             ),
		.BITS_CUT_MAX_MAC           (BITS_CUT_MAX_MAC           )
	) i_coproc_alu (
		.clk_i                       (clk_i                         ),
		.rst_an                      (rst_an                        ),
		.xif_mem_result_if           (xif_mem_result_if             ),
		.id_ex_pipe_i                (id_ex_pipe_i                  ),
		.alu_block_sel               (issue_fifo_out_i.alu_block_sel),
		.memory_if_accept_i          (memory_if_accept              ),
		.result_if_accept_i          (result_if_accept              ),
		.commit_i                    (commit                        ),
		.kill_i                      (kill                          ),
		.mem_exception_debug_valid_i (mem_exception_debug_valid     ),
		.mem_exception_debug_struct_i(mem_exception_debug_struct    ),
		.alu_ready_o                 (ex_ready_o                    ),
		.alu_out_o                   (alu_out                       )
	);

	// check the FIFO to understand if there is an accepted instruction
	assign accept = !issue_fifo_out_i.is_empty && issue_fifo_out_i.accept;
	// signals realated to the committing, killing, exception and debug of the current instruction
	assign commit = (!commit_fifo_out_i.is_empty && !commit_fifo_out_i.commit_kill) ||
		(commit_fifo_out_i.is_empty && (xif_commit_if.commit_valid && !xif_commit_if.commit.commit_kill));
	assign kill = (!commit_fifo_out_i.is_empty && commit_fifo_out_i.commit_kill) ||
		(commit_fifo_out_i.is_empty && (xif_commit_if.commit_valid && xif_commit_if.commit.commit_kill));
	assign mem_exception_debug_valid = xif_mem_if.mem_ready && xif_mem_if.mem_valid;

	// MEMORY INTERFACE
	// handshake and control signals (the ALU makes the execution go on after a transaction
	// according to memory_if_accept and commit/kill)
	assign xif_mem_if.mem_valid = alu_out.mem_trans_valid && !kill;
	// memory_if has accepted the memory transaction from the ALU
	assign memory_if_accept = xif_mem_if.mem_ready;
	// data signals
	assign xif_mem_if.mem_req.id    = issue_fifo_out_i.id;
	assign xif_mem_if.mem_req.addr  = alu_out.addr_mem;
	assign xif_mem_if.mem_req.mode  = alu_out.mode_mem;
	assign xif_mem_if.mem_req.we    = alu_out.we_mem;
	assign xif_mem_if.mem_req.size  = alu_out.size_mem;
	assign xif_mem_if.mem_req.be    = alu_out.be_mem;
	assign xif_mem_if.mem_req.attr  = alu_out.attr_mem;
	assign xif_mem_if.mem_req.wdata = alu_out.wdata_mem;
	assign xif_mem_if.mem_req.last  = alu_out.last_mem_trans;
	assign xif_mem_if.mem_req.spec  = !commit;
	// signals from the mem_resp to be passed to the ALU
	assign mem_exception_debug_struct.exc     = xif_mem_if.mem_resp.exc;
	assign mem_exception_debug_struct.exccode = xif_mem_if.mem_resp.exccode;
	assign mem_exception_debug_struct.dbg     = xif_mem_if.mem_resp.dbg;
	assign mem_exception_debug_struct.ecswe   = 0;
	assign mem_exception_debug_struct.ecsdata = '0;

	// RESULT INTERFACE
	// No need for FIFO here since we accept only one instruction at a time and we need only one result transaction per instruction
	// at the end of each instruction, but in the future, if more than one instruction is accepted, a result FIFO would be necessary.

	// handshake and control signals
	// we can assert result_valid if the alu has a valid result, the instruction has been accepted (otherwise, no result transaction to be done
	// accordingo the xif requirements) and the commit has arrived.
	assign xif_result_if.result_valid = alu_out.result_valid && accept && commit;
	// if a result transaction is ongoing, this signal states that the core has accepted the result transaction from the coprocessor
	assign result_if_accept = xif_result_if.result_ready && (commit || kill);
	// the FIFOs can be pop if the instruction has not been accepted (in that case, no result transaction to be done) OR a kill is received (no
	// result transaction to be done) OR a result transaction from the coprocessor is ongoing (xif_result_if.result_valid=1) and the core accepts it
	// (xif_result_if.result_ready=1)
	// the fifo_pop makes the execution go on after a result transaction, since with a pop the issue FIFO is freed
	// and the coprocessor returns available to receive a new instruction from the core
	assign fifo_pop_o = (!accept && !issue_fifo_out_i.is_empty) || kill || (xif_result_if.result_valid && xif_result_if.result_ready);
	// data signals
	assign xif_result_if.result.id      = issue_fifo_out_i.id;
	assign xif_result_if.result.data    = alu_out.result;
	assign xif_result_if.result.rd      = alu_out.rd;
	assign xif_result_if.result.we      = alu_out.writeback;
	assign xif_result_if.result.ecsdata = alu_out.exc_dbg_err.ecsdata;
	assign xif_result_if.result.ecswe   = alu_out.exc_dbg_err.ecswe;
	assign xif_result_if.result.exc     = alu_out.exc_dbg_err.exc;
	assign xif_result_if.result.exccode = alu_out.exc_dbg_err.exccode;
	assign xif_result_if.result.err     = alu_out.exc_dbg_err.err;
	assign xif_result_if.result.dbg     = alu_out.exc_dbg_err.dbg;

endmodule : coproc_ex_stage

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_ex_stage.sv.rca $
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
//	 Revision: 1.12 Tue Jul 18 15:00:39 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.11 Wed Oct 12 00:54:46 2022 nxf87116
//	 Added header and footer to the RTL files.
