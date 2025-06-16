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
//  File            : $ coproc_no_ds.sv $
//  Date            : $Date: Fri Sep 20 15:56:53 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : CoProcessor Top File
//
//  Description	    : Coprocessor top-level module.
//		      It needs to be coupled to the CV32E40X through the eXtension Interface. SIMD simulation.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------
  
import coproc_pkg::*;

module coproc #(
	// MAC RELATED PARAMETERS
	parameter int unsigned N_BANKS_MAC                 = 6 , // number of banks
	parameter int unsigned N_ELEMENTS_BANK_MAC[N_BANKS_MAC] = '{32'd2, 32'd34, 32'd4, 32'd4, 32'd34, 32'd2}, // number of elements per bank
	parameter int unsigned N_ELEMENTS_BANK_MAX_MAC     = 34, // maximum elements among the banks defined above
	parameter int unsigned WIDTH_DATA_MAC[N_BANKS_MAC] = '{32'd32, 32'd32, 32'd32, 32'd32, 32'd32, 32'd23}, // data parallelism per bank
	parameter int unsigned WIDTH_DATA_NOSIMD_MAX_MAC   = 23, // maximum parallelism for non-simd data
	parameter int unsigned WIDTH_DATA_SIMD_MAX_MAC     = 32, // maximum parallelism for simd data
	parameter int unsigned WIDTH_DATA_MAX_MAC          = 32, // maximum data parallelism among the banks defined above
	parameter int unsigned WIDTH_COEFFS_MAC[N_BANKS_MAC] = '{32'd16, 32'd16, 32'd16, 32'd16, 32'd8, 32'd8}, // coeffs parallelism per bank
	parameter int unsigned WIDTH_COEFFS_NOSIMD_MAX_MAC = 8 , // maximum parallelism for non-simd coeffs
	parameter int unsigned WIDTH_COEFFS_SIMD_MAX_MAC   = 16, // maximum parallelism for simd coeffs
	parameter int unsigned WIDTH_COEFFS_MAX_MAC        = 16, // maximum coeffs parallelism among the banks defined above
	parameter bit          SIMD_MAC                    = 1 , // if 1, there is the possibility to use SIMD
	parameter int unsigned N_BIT_NFEED_MAC             = 2 , // number of bits of n_feed to setup the DATAREGS selectors
	parameter bit          FEEDBACK_UNROUNDED_MAC      = 1 , // if 1, store into the feedback part of the data regs the unrounded result. The result returned to the core register file will be always the rounded one.
	parameter int unsigned N_OPERANDS_MAC              = 5 , // number of operands that the MAC arithmetic block can process in parallel
	parameter int unsigned BITS_CUT_MAX_MAC            = 8   // maximum number of bits the rounding unit can throw away
) (
	// TODO: clock gating
	input logic              clk_i            ,
	input logic              rst_an           ,
	// eXtension interface
	cv32e40x_if_xif.coproc_compressed xif_compressed_if, // NOT IMPEMENTED: it is not implemented in the core at the moment, therefore we will not consider it
	cv32e40x_if_xif.coproc_issue      xif_issue_if     ,
	cv32e40x_if_xif.coproc_commit     xif_commit_if    ,
	cv32e40x_if_xif.coproc_mem        xif_mem_if       ,
	cv32e40x_if_xif.coproc_mem_result xif_mem_result_if,
	cv32e40x_if_xif.coproc_result     xif_result_if
);

	logic               ex_ready  ;
	id_ex_coproc_pipe_t id_ex_pipe;

	issue_fifo_t  issue_fifo_out ;
	commit_fifo_t commit_fifo_out;

	// needed to select the right ALU output among the ones coming from the different blocks present in it
	alu_block_sel_t alu_block_sel;

	logic fifo_pop       ;
	logic issue_fifo_push;

	logic commit_fifo_read_ports ;
	logic commit_fifo_push       ;
	logic commit_fifo_write_ports;
	logic commit_fifo_is_empty   ;

	// The interface for the compressed instructions offload is not implemented in the core, therefore we will not consider it
	assign xif_compressed_if.compressed_ready       = 0;
	assign xif_compressed_if.compressed_resp.accept = 0;
	assign xif_compressed_if.compressed_resp.instr  = '0;

	// ID STAGE
	coproc_id_stage #(.SIMD_MAC(SIMD_MAC)) i_coproc_id_stage (
		.clk_i                (clk_i                  ),
		.rst_an               (rst_an                 ),
		.xif_issue_if         (xif_issue_if           ),
		.issue_fifo_is_empty_i(issue_fifo_out.is_empty),
		.issue_fifo_is_full_i (issue_fifo_out.is_full ),
		.fifo_pop_i           (fifo_pop               ),
		.ex_ready_i           (ex_ready               ),
		.id_ex_pipe_o         (id_ex_pipe             ),
		.alu_block_sel_o      (alu_block_sel          )
	);

	// EX STAGE
	coproc_ex_stage #(
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
	) i_coproc_ex_stage (
		.clk_i            (clk_i            ),
		.rst_an           (rst_an           ),
		.xif_commit_if    (xif_commit_if    ),
		.xif_mem_if       (xif_mem_if       ),
		.xif_mem_result_if(xif_mem_result_if),
		.xif_result_if    (xif_result_if    ),
		.issue_fifo_out_i (issue_fifo_out   ),
		.commit_fifo_out_i(commit_fifo_out  ),
		.fifo_pop_o       (fifo_pop         ),
		.id_ex_pipe_i     (id_ex_pipe       ),
		.ex_ready_o       (ex_ready         )
	);

	// FIFO for the instructions issue:
	// The idea is to have a FIFO in order to manage the instructions coming from the core.
	// With a FIFO, the core could offload to the coprocessor instruction without waiting the ending of the previous ones, exploiting the
	// coprocessor pipelining.
	// Unfortunately, this would complicate a lot the design since hazards would occur. The hazards could be really complex to manage since here we manage
	// read/write from/to memory and RF, commit/kill signals, possibly different blocks into the ALU (for now we have only the MAC,
	// but in the future could be worse).
	// For this reason, the design choice was to accept only one instruction at a time, setting xif_issue_if.issue_ready=0 (i.e. coprocessor not available for
	// the next instruction) right after the first instruction has been accepted.
	// xif_issue_if.issue_ready=0->1 only when the instruction execution is completely over.

	// The issue fifo will store the accept signal from the coprocessor, the id of the offloaded instruction and the signal to choose which alu block should be
	// selected by the EX stage.

	// push a new instruction into the FIFO is the core asserts issue_valid and the coprocessor is ready to accept
	assign issue_fifo_push = xif_issue_if.issue_valid && xif_issue_if.issue_ready;
	// This generate block is needed to choose the WIDTH_MAX for the FIFO ports.
	// This "complex" structure for the FIFO consisting in more than one port, strange bitwidth and so on has been chosen in order to
	// optimize it. For example, in this way, the issue FIFO will have three ports (i.e. able to store three elements in parallel) with
	// different bitwidth and so on, but having only one status bit, only one is_empty/is_full signals and so on. Otherwise, if you define
	// a different FIFO for each of the three elements, you will get three status bits and in general some overhead (look into the FIFO
	// structure to better understand).
	generate
		if (X_ID_WIDTH < ALU_BLOCK_SEL_COPROC_WIDTH) begin : issue_fifo_generate_1
			logic [ALU_BLOCK_SEL_COPROC_WIDTH-1:0] issue_fifo_output_gen[3];

			fifo_single_reg #(
				.N_PORTS  (3                                           ),
				.WIDTH    ('{1, X_ID_WIDTH, ALU_BLOCK_SEL_COPROC_WIDTH}),
				.WIDTH_MAX(ALU_BLOCK_SEL_COPROC_WIDTH                  )
			) i_issue_fifo (
				.clk_i     (clk_i                                                                      ),
				.rst_an    (rst_an                                                                     ),
				.push_i    (issue_fifo_push                                                            ),
				.data_in   ('{xif_issue_if.issue_resp.accept, xif_issue_if.issue_req.id, alu_block_sel}),
				.pop_i     (fifo_pop                                                                   ),
				.flush_i   (1'b0                                                                       ),
				.data_out  (issue_fifo_output_gen                                                      ),
				.is_empty_o(issue_fifo_out.is_empty                                                    ),
				.is_full_o (issue_fifo_out.is_full                                                     )
			);

			assign issue_fifo_out.accept        = issue_fifo_output_gen[0][0];
			assign issue_fifo_out.id            = issue_fifo_output_gen[1][X_ID_WIDTH-1:0];
			assign issue_fifo_out.alu_block_sel = issue_fifo_output_gen[2][ALU_BLOCK_SEL_COPROC_WIDTH-1:0];
		end
		else begin : issue_fifo_generate_2
			logic [X_ID_WIDTH-1:0] issue_fifo_output_gen[3];

			fifo_single_reg #(
				.N_PORTS  (3                                           ),
				.WIDTH    ('{1, X_ID_WIDTH, ALU_BLOCK_SEL_COPROC_WIDTH}),
				.WIDTH_MAX(X_ID_WIDTH                                  )
			) i_issue_fifo (
				.clk_i     (clk_i                                                                      ),
				.rst_an    (rst_an                                                                     ),
				.push_i    (issue_fifo_push                                                            ),
				.data_in   ('{xif_issue_if.issue_resp.accept, xif_issue_if.issue_req.id, alu_block_sel}),
				.pop_i     (fifo_pop                                                                   ),
				.flush_i   (1'b0                                                                       ),
				.data_out  (issue_fifo_output_gen                                                      ),
				.is_empty_o(issue_fifo_out.is_empty                                                    ),
				.is_full_o (issue_fifo_out.is_full                                                     )
			);

			assign issue_fifo_out.accept        = issue_fifo_output_gen[0][0];
			assign issue_fifo_out.id            = issue_fifo_output_gen[1][X_ID_WIDTH-1:0];
			assign issue_fifo_out.alu_block_sel = issue_fifo_output_gen[2][ALU_BLOCK_SEL_COPROC_WIDTH-1:0];
		end
	endgenerate

	// FIFO for the instruction commit
	// same approach as above here: the only signal stored is the commit_kill from the core
	logic [0:0] commit_fifo_output_gen[1];

	fifo_single_reg #(
		.N_PORTS  (1   ),
		.WIDTH    ('{1}),
		.WIDTH_MAX(1   )
	) i_commit_fifo (
		.clk_i     (clk_i                              ),
		.rst_an    (rst_an                             ),
		.push_i    (xif_commit_if.commit_valid         ),
		.data_in   ('{xif_commit_if.commit.commit_kill}),
		.pop_i     (fifo_pop                           ),
		.flush_i   (1'b0                               ),
		.data_out  (commit_fifo_output_gen             ),
		.is_empty_o(commit_fifo_out.is_empty           ),
		.is_full_o (commit_fifo_out.is_full            )
	);

	assign commit_fifo_out.commit_kill = commit_fifo_output_gen[0][0];

endmodule : coproc

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_no_ds.sv.rca $
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
//	 Revision: 1.14 Tue Jul 18 15:00:37 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.8 Mon Oct 24 10:29:44 2022 nxf87116
//	 Added some comments.
//	
//	 Revision: 1.7 Wed Oct 12 00:54:42 2022 nxf87116
//	 Added header and footer to the RTL files.
