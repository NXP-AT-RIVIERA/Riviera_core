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
//  File            : $ coproc_alu.sv $
//  Date            : $Date: Fri Sep 20 15:56:52 2024 $
//  Revision        : $Revision: 1.3 $
//
//  Design Unit     : CoProcessor ALU (Arithmetic Logic Unit)
//
//  Description	    : Coprocessor ALU.
//		      It shall contain all the arithmetic blocks needed
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

import coproc_pkg::*;

module coproc_alu #(
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
	input  logic                   clk_i                       ,
	input  logic                   rst_an                      ,
	// xif memory interface
	cv32e40x_if_xif.coproc_mem_result       xif_mem_result_if           ,
	// ID/EX pipeline
	input  id_ex_coproc_pipe_t     id_ex_pipe_i                ,
	// signal needed to select the correct output of the mux according to the current instruction in the FIFO
	input  alu_block_sel_t         alu_block_sel               ,
	// if a memory transaction is ongoing, this signal states that the core has accepted it and that the ALU can go on
	input  logic                   memory_if_accept_i          ,
	// if a result transaction is ongoing, this signal states that the core has accepted it and that the ALU can go on
	input  logic                   result_if_accept_i          ,
	// if asserted, the current instruction has been committed from the core
	input  logic                   commit_i                    ,
	// if asserted, the current instruction has been killed from the core
	input  logic                   kill_i                      ,
	// signals related to exceptions/debug occurred during a memory transaction
	input  logic                   mem_exception_debug_valid_i ,
	input  exc_dbg_struct_coproc_t mem_exception_debug_struct_i,
	// alu handshaking
	output logic                   alu_ready_o                 ,
	// alu output
	output alu_out_t               alu_out_o
);

	logic mac_ready  ;
	alu_out_t mac_out  ;

	// MAC
	coproc_mac #(
		.N_BANKS                (N_BANKS_MAC                ),
		.N_ELEMENTS_BANK        (N_ELEMENTS_BANK_MAC        ),
		.N_ELEMENTS_BANK_MAX    (N_ELEMENTS_BANK_MAX_MAC    ),
		.WIDTH_DATA             (WIDTH_DATA_MAC             ),
		.WIDTH_DATA_NOSIMD_MAX  (WIDTH_DATA_NOSIMD_MAX_MAC  ),
		.WIDTH_DATA_SIMD_MAX    (WIDTH_DATA_SIMD_MAX_MAC    ),
		.WIDTH_DATA_MAX         (WIDTH_DATA_MAX_MAC         ),
		.WIDTH_COEFFS           (WIDTH_COEFFS_MAC           ),
		.WIDTH_COEFFS_NOSIMD_MAX(WIDTH_COEFFS_NOSIMD_MAX_MAC),
		.WIDTH_COEFFS_SIMD_MAX  (WIDTH_COEFFS_SIMD_MAX_MAC  ),
		.WIDTH_COEFFS_MAX       (WIDTH_COEFFS_MAX_MAC       ),
		.SIMD                   (SIMD_MAC                   ),
		.N_BIT_NFEED            (N_BIT_NFEED_MAC            ),
		.FEEDBACK_UNROUNDED     (FEEDBACK_UNROUNDED_MAC     ),
		.N_OPERANDS_MAC         (N_OPERANDS_MAC             ),
		.BITS_CUT_MAX           (BITS_CUT_MAX_MAC           )
	) i_coproc_mac (
		.clk_i                       (clk_i                       ),
		.rst_an                      (rst_an                      ),
		.xif_mem_result_if           (xif_mem_result_if           ),
		.id_ex_pipe_i                (id_ex_pipe_i                ),
		.memory_if_accept_i          (memory_if_accept_i          ),
		.result_if_accept_i          (result_if_accept_i          ),
		.commit_i                    (commit_i                    ),
		.kill_i                      (kill_i                      ),
		.mem_exception_debug_valid_i (mem_exception_debug_valid_i ),
		.mem_exception_debug_struct_i(mem_exception_debug_struct_i),
		.mac_ready_o                 (mac_ready                   ),
		.mac_out_o                   (mac_out                     )
	);


	// only MAC is present, therefore alu_ready and alu_out are the one of the MAC.
	// in case of more than one ALU block present, the ready should be the AND of the ready signals
	// the output should be multiplexed thanks to the alu_block_sel signal.
	assign alu_ready_o = mac_ready;

	assign alu_out_o = mac_out;

endmodule : coproc_alu

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_alu.sv.rca $
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
//	 Revision: 1.11 Tue Jul 18 15:00:39 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.10 Wed Oct 12 00:54:47 2022 nxf87116
//	 Added header and footer to the RTL files.
