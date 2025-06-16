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
//  File            : $ coproc_mac.sv $
//  Date            : $Date: Fri Sep 20 15:56:53 2024 $
//  Revision        : $Revision: 1.4 $
//
//  Design Unit     : CoProcessor MAC (Multiple-Accumulate) Unit 
//
//  Description	    : Coprocessor MAC module.
//		      It contains the registers (data and configuration), the mac arithmetic part and all the logic needed to manage the mac-related instructions. 
//		      It is one (the only one for now) of the blocks to be instantiated into the ALU module.
//
//  Author 	    : Francesco Babbaro
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------
  
import coproc_pkg::*;

module coproc_mac #(
	parameter  int unsigned N_BANKS                  = 4                                                      , // number of banks
	parameter  int unsigned N_ELEMENTS_BANK[N_BANKS] = '{N_BANKS{32'd4}}, // number of elements per bank
	parameter  int unsigned N_ELEMENTS_BANK_MAX      = 4                                                      , // maximum elements among the banks defined above
	parameter  int unsigned WIDTH_DATA[N_BANKS] = '{N_BANKS{32'd32}}, // data parallelism per bank
	parameter  int unsigned WIDTH_DATA_NOSIMD_MAX    = 32                                                     , // maximum parallelism for non-simd data
	parameter  int unsigned WIDTH_DATA_SIMD_MAX      = 32                                                     , // maximum parallelism for simd data
	parameter  int unsigned WIDTH_DATA_MAX           = 32                                                     , // maximum data parallelism among the banks defined above
	parameter  int unsigned WIDTH_COEFFS[N_BANKS] = '{N_BANKS{32'd32}}, // coeffs parallelism per bank
	parameter  int unsigned WIDTH_COEFFS_NOSIMD_MAX  = 32                                                     , // maximum parallelism for non-simd coeffs
	parameter  int unsigned WIDTH_COEFFS_SIMD_MAX    = 32                                                     , // maximum parallelism for simd coeffs
	parameter  int unsigned WIDTH_COEFFS_MAX         = 32                                                     , // maximum coeffs parallelism among the banks defined above
	parameter  bit          SIMD                     = 0                                                      , // if 1, there is the possibility to use SIMD
	parameter  int unsigned N_BIT_NFEED              = 2                                                      , // number of bits of selectors_nfeed to setup the DATAREGS selectors
	parameter  bit          FEEDBACK_UNROUNDED       = 0                                                      , // if 1, store into the feedback part of the data regs the unrounded result. The result returned to the core register file will be always the rounded one.
	parameter  int unsigned N_OPERANDS_MAC           = 4                                                      , // number of operands that the MAC arithmetic block can process in parallel
	parameter  int unsigned BITS_CUT_MAX             = 8                                                        // maximum number of bits the rounding unit can throw away
) (
	input  logic                   clk_i                       ,
	input  logic                   rst_an                      ,
	// xif memory result interface
	cv32e40x_if_xif.coproc_mem_result       xif_mem_result_if           ,
	// ID/EX pipeline
	input  id_ex_coproc_pipe_t     id_ex_pipe_i                ,
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
	// mac handshaking
	output logic                   mac_ready_o                 ,
	// mac output
	output alu_out_t               mac_out_o
);
	// maximum number of iterations needed by the MAC arithmetic unit if N_OPERANDS_MAC<N_ELEMENTS_BANK_MAX
	localparam int unsigned MAC_ITERATIONS_COUNT_MAX = (N_ELEMENTS_BANK_MAX+(N_OPERANDS_MAC-1))/N_OPERANDS_MAC;

	// define the parallelism in case of SIMD or non-SIMD
	// parallelism with SIMD ON is: (2*(WIDTH_DATA_MAX/2 + WIDTH_COEFFS/2 + log2(N_OP))) = (WIDTH_DATA_MAX + WIDTH_COEFFS + 2*log2(N_OP))
	// parallelism with SIMD OFF is: (WIDTH_DATA_MAX + WIDTH_COEFFS + log2(N_OP))

	// parallelism for the MAC output: in this case N_OP=N_OPERANDS_MAC
	localparam int unsigned MAC_OUT_BITS = WIDTH_DATA_MAX+WIDTH_COEFFS_MAX+(1+SIMD)*$clog2(N_OPERANDS_MAC);
	// parallelism for the final result: in this case N_OP=N_ELEMENTS_BANK_MAX
	localparam int unsigned RESULT_BITS = WIDTH_DATA_MAX+WIDTH_COEFFS_MAX+(1+SIMD)*$clog2(N_ELEMENTS_BANK_MAX);

	/*
	REGISTERS RELATED SIGNALS
	*/
	// DATAREGS SIGNALS
	logic                       dataregs_clear_bank_enable                                                      ;
	logic [$clog2(N_BANKS)-1:0] dataregs_clear_bank_index                                                       ;
	logic                       dataregs_shift_bank_feedforward_enable                                          ;
	logic                       dataregs_shift_bank_feedback_enable                                             ;
	logic [$clog2(N_BANKS)-1:0] dataregs_shift_bank_index                                                       ;
	logic [ WIDTH_DATA_MAX-1:0] dataregs_feedforward_in                                                         ;
	logic [ WIDTH_DATA_MAX-1:0] dataregs_feedback_in                                                            ;
	logic [ WIDTH_DATA_MAX-1:0] dataregs_bottom_trunc_sign_ext_out                                              ;
	logic                       dataregs_selectors                    [            N_BANKS][N_ELEMENTS_BANK_MAX];
	logic [ WIDTH_DATA_MAX-1:0] dataregs_read_bank_out                [N_ELEMENTS_BANK_MAX]                     ;
	// SELECTORS DATA REG SIGNALS
	logic [    N_BIT_NFEED-1:0] selectors_nfeed            ;
	logic                       selectors_write_bank_enable;
	logic [$clog2(N_BANKS)-1:0] selectors_write_bank_index ;
	// COEFFREGS SIGNALS
	logic                        coeffregs_clear_bank_enable                     ;
	logic [ $clog2(N_BANKS)-1:0] coeffregs_clear_bank_index                      ;
	logic                        coeffregs_shift_bank_enable                     ;
	logic [ $clog2(N_BANKS)-1:0] coeffregs_shift_bank_index                      ;
	logic [WIDTH_COEFFS_MAX-1:0] coeffregs_in                                    ;
	logic [WIDTH_COEFFS_MAX-1:0] coeffregs_read_bank_out    [N_ELEMENTS_BANK_MAX];
	// ROUNDING UNIT CONFIGURATION REGS
	logic                              roundingregs_write_bank_enable;
	logic [       $clog2(N_BANKS)-1:0] roundingregs_write_bank_index ;
	logic [$clog2(BITS_CUT_MAX+1)-1:0] roundingregs_in               ;
	logic [$clog2(BITS_CUT_MAX+1)-1:0] roundingregs_read_bank_out    ;
	// SIMD CONFIGURATION REGS (used only if parameter SIMD=1)
	logic                       simdregs_write_bank_enable;
	logic [$clog2(N_BANKS)-1:0] simdregs_write_bank_index ;
	logic                       simdregs_in               ;
	logic                       simdregs_read_bank_out    ;
	// OUTPUT MODIFIER REGS
	logic                       omregs_write_bank_enable  ;
	logic [$clog2(N_BANKS)-1:0] omregs_write_bank_index   ;
	logic [1:0]                 omregs_in                 ;
	logic [1:0]                 omregs_read_bank_out      ;
	// SIGNALS COMMON TO ALL THE REGS
	logic [$clog2(N_BANKS)-1:0] read_bank_index;

	/*
	MEMORY STAGE RELATED SIGNALS
	*/
	// "MEMORY REQUEST" FSM SIGNALS
	typedef enum {MEM_REQUEST, MEM_RESULT_WAIT, COMMIT_KILL_WAIT} state_mem_req_t;
	state_mem_req_t curr_state_mem_req_e;
	state_mem_req_t next_state_mem_req_e;
	// "LOAD TO BANK REGISTERS" FSM SIGNALS
	typedef enum {LOAD, WAIT} state_load_t;
	state_load_t curr_state_loadtoregs_e;
	state_load_t next_state_loadtoregs_e;
	// type of instruction detection
	logic load_from_mem_instr;
	logic load_instr         ;
	logic exec_instr         ;
	logic chain_instr        ;
	
	logic value_from_mem_ready;			// if 1, a value from the memory result interface is ready
	logic mem_exception_debug;			// if 1, a memory exception/debug has occurred
	// signals related to a temporary register used to store the result coming from the memory if
	// the coprocessor is waiting for the commit/kill signal
	logic [X_MEM_WIDTH-1:0] mem_result_tempreg_out         ;
	logic                   mem_result_tempreg_write_enable;
	logic                   mem_result_tempreg_select      ;
	// memory stage handshaking signals
	logic mem_stage_ready;
	logic mem_stage_valid;


	/*
	CHAINING RELATED SIGNALS
	*/
	typedef enum {IDLE, SHIFT_FOUR_TOP, SHIFT_THREE_TOP, SHIFT_TWO_TOP, SHIFT_ONE_TOP, SHIFT_BOTTOM, EXEC_BANK} state_chain_t;
	state_chain_t state_chain_p, state_chain_n;

	logic                       mac_enable;
	logic                       fir_filter;
	logic [1:0]                 num_inputs;
	logic [$clog2(N_BANKS)-1:0] chained_bank_indices [8];		//banks chained according to config chained instruction
	logic [7:0]                 use_bank;			 			//use bits to enable banks to be chained

	logic [$clog2(N_BANKS)-1:0] selected_bank;
	logic [3:0]                 index_n, index_p;
	logic                       chain_result_valid;
	logic                       reset_counter;
	logic [31:0]                bank_input_n, bank_input_p;
	logic                       chain_enable;
	logic                       exec_enable;
	logic                       exec_disable;
	logic                       shift_bottom_enable;
	logic                       shift_top_enable;
	logic [31:0]                input_1, input_2, input_3, input_4;
	logic                       chain_active;

	logic                       dataregs_shift_bank_top_enable;


	/*
	RESULT STAGE RELATED SIGNALS
	*/
	// MAC ARITHMETIC SIGNALS
	// input operands for the MAC arithmetic
	logic [  WIDTH_DATA_MAX-1:0] mac_arith_data_operands [N_OPERANDS_MAC];
	logic [WIDTH_COEFFS_MAX-1:0] mac_arith_coeff_operands[N_OPERANDS_MAC];
	// MAC ARITHMETIC output
	logic [MAC_OUT_BITS-1:0] mac_arith_out;
	// in case of MAC_ITERATIONS_COUNT_MAX=1, this signal is the same as mac_arith_out;
	// in case of MAC_ITERATIONS_COUNT_MAX>1, this signal is the output of the accumulation adder, representing the
	// final result.
	logic [RESULT_BITS-1:0] mac_arith_result;
	// signals for the operand multiplexing
	logic [  WIDTH_DATA_MAX-1:0] mac_arith_data_operands_muxin [MAC_ITERATIONS_COUNT_MAX*N_OPERANDS_MAC];
	logic [WIDTH_COEFFS_MAX-1:0] mac_arith_coeff_operands_muxin[MAC_ITERATIONS_COUNT_MAX*N_OPERANDS_MAC];
	// unrounded_result is different from mac_arith_result, since in case of SIMD mac_arith_result is packed on RESULT_BITS bits, while
	// this one on WIDTH_DATA_MAX bits, that is compliant with the size of the dataregs
	logic [WIDTH_DATA_MAX-1:0] unrounded_result;
	// rounded result
	logic [WIDTH_DATA_MAX-1:0] rounded_result;
	// modified result
	logic [WIDTH_DATA_MAX-1:0] modified_result;
	// RESULT STAGE SIGNALS
	logic                       mem_exc_dbg_pipe1           ;
	logic                       mem_result_dbg_err_pipe1    ;
	exc_dbg_err_struct_coproc_t mem_exc_dbg_err_struct_pipe1;
	logic                       mac_result_valid            ;
	logic                       exec_enable_pipe1           ;
	logic [$clog2(N_BANKS)-1:0] read_bank_index_pipe1       ;
	logic                       res_accepted                ;
	logic                       res_stage_ready             ;
	logic                       res_stage_valid             ;

	assign mac_enable = id_ex_pipe_i.mac_ctrl.mac_enable;
	assign dataregs_shift_bank_top_enable = chain_instr ? 
		shift_top_enable : dataregs_shift_bank_feedforward_enable;

	/*
	DATAREGS
	*/
	bidir_set #(
		.N_BANKS       (N_BANKS            ),
		.N_ELEMENTS    (N_ELEMENTS_BANK    ),
		.N_ELEMENTS_MAX(N_ELEMENTS_BANK_MAX),
		.WIDTH         (WIDTH_DATA         ),
		.WIDTH_MAX     (WIDTH_DATA_MAX     )
	) i_data_regs (
		.clk_i                     (clk_i                                 ),
		.rst_an                    (rst_an                                ),
		.clear_bank_enable_i       (dataregs_clear_bank_enable            ),
		.clear_bank_index_i        (dataregs_clear_bank_index             ),
		.read_bank_index_i         (read_bank_index_pipe1                 ),
		.shift_bank_index_i        (dataregs_shift_bank_index             ),
		.shift_bank_top_enable_i   (dataregs_shift_bank_top_enable        ),
		.shift_bank_bottom_enable_i(dataregs_shift_bank_feedback_enable   ),
		.data_top_i                (dataregs_feedforward_in               ),
		.data_bottom_i             (dataregs_feedback_in                  ),
		.selectors_i               (dataregs_selectors                    ),
		.read_bank_o               (dataregs_read_bank_out                ),
		.bottom_trunc_sign_ext_o   (dataregs_bottom_trunc_sign_ext_out    )
	);

	// selectors for the dataregs
	// this block defines which regs are for the feedforward elements and which ones for the feedback
	selectors_set #(
		.N_BANKS       (N_BANKS            ),
		.N_ELEMENTS    (N_ELEMENTS_BANK    ),
		.N_ELEMENTS_MAX(N_ELEMENTS_BANK_MAX),
		.N_BIT_NFEED   (N_BIT_NFEED        )
	) i_selectors_regs (
		.clk_i              (clk_i                      ),
		.rst_an             (rst_an                     ),
		.n_feed_i           (selectors_nfeed            ),
		.write_bank_enable_i(selectors_write_bank_enable),
		.write_bank_index_i (selectors_write_bank_index ),
		.selectors_o        (dataregs_selectors         )
	);

	/*
	COEFFS REGS
	*/
	unidir_set #(
		.N_BANKS       (N_BANKS            ),
		.N_ELEMENTS    (N_ELEMENTS_BANK    ),
		.N_ELEMENTS_MAX(N_ELEMENTS_BANK_MAX),
		.WIDTH         (WIDTH_COEFFS       ),
		.WIDTH_MAX     (WIDTH_COEFFS_MAX   )
	) i_coeff_regs (
		.clk_i              (clk_i                      ),
		.rst_an             (rst_an                     ),
		.clear_bank_enable_i(coeffregs_clear_bank_enable),
		.clear_bank_index_i (coeffregs_clear_bank_index ),
		.read_bank_index_i  (read_bank_index_pipe1      ),
		.shift_bank_index_i (coeffregs_shift_bank_index ),
		.shift_bank_enable_i(coeffregs_shift_bank_enable),
		.data_i             (coeffregs_in               ),
		.read_bank_o        (coeffregs_read_bank_out    )
	);

	/*
	ROUNDING CONFIGURATION REGS
	*/
	register_set #(
		.N_ELEMENTS(N_BANKS               ),
		.WIDTH     ($clog2(BITS_CUT_MAX+1))
	) i_rounding_regs (
		.clk_i         (clk_i                         ),
		.rst_an        (rst_an                        ),
		.write_enable_i(roundingregs_write_bank_enable),
		.write_index_i (roundingregs_write_bank_index ),
		.data_i        (roundingregs_in               ),
		.read_index_i  (read_bank_index_pipe1         ),
		.data_o        (roundingregs_read_bank_out    )
	);

	/*
	SIMD CONFIGURATION REGS
	*/
	generate
		if (SIMD) begin : SIMD_confregs_gen
			register_set #(
				.N_ELEMENTS(N_BANKS),
				.WIDTH     (1      )
			) i_simd_regs (
				.clk_i         (clk_i                     ),
				.rst_an        (rst_an                    ),
				.write_enable_i(simdregs_write_bank_enable),
				.write_index_i (simdregs_write_bank_index ),
				.data_i        (simdregs_in               ),
				.read_index_i  (read_bank_index_pipe1     ),
				.data_o        (simdregs_read_bank_out    )
			);
		end
	endgenerate

	/*
	OM CONFIGURATION REGS
	*/
	register_set #(
		.N_ELEMENTS(N_BANKS),
		.WIDTH     (2      )
	) i_om_regs (
		.clk_i         (clk_i                   ),
		.rst_an        (rst_an                  ),
		.write_enable_i(omregs_write_bank_enable),
		.write_index_i (omregs_write_bank_index ),
		.data_i        (omregs_in               ),
		.read_index_i  (read_bank_index_pipe1   ),
		.data_o        (omregs_read_bank_out    )
	);

	// assign the source registers from the core register-file
	assign dataregs_clear_bank_index     = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign coeffregs_clear_bank_index    = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];

	// MUX to decouple some signals when in chaining instruction
	assign dataregs_shift_bank_index     = chain_instr ? 
		selected_bank : id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];

	assign coeffregs_shift_bank_index    = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign selectors_nfeed               = id_ex_pipe_i.rs[1][N_BIT_NFEED-1:0];
	assign selectors_write_bank_index    = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign roundingregs_write_bank_index = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign roundingregs_in               = id_ex_pipe_i.rs[1][$clog2(BITS_CUT_MAX+1)-1:0];
	assign simdregs_write_bank_index     = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign omregs_write_bank_index       = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign simdregs_in                   = id_ex_pipe_i.rs[1][0];
	assign omregs_in                     = id_ex_pipe_i.rs[1][2:1];  // ASSIGN BITS IN POSITION 2,1 OF RS2(simd) -> rs[1]: 2(output modifier)||1(output modifier)||0(simd)
	assign read_bank_index               = id_ex_pipe_i.rs[0][$clog2(N_BANKS)-1:0];
	assign dataregs_feedback_in          = (FEEDBACK_UNROUNDED == 0) ? rounded_result : unrounded_result;
	
	// here we need a register since the DATA and COEFF REGS act as a sort of pipe stage between the
	// first stage (memory, load...) and the second one (MAC execution, result...), otherwise this signal
	// would be out-of-synch.
	// Probably it is not strictly needed for now since we do not exploit the pipeline, yet. In the future,
	// if the pipelining will be possible, this register will be strictly needed.
	// However, in this way (using exec_instr as enable for this signal) we avoid to have a
	// continous switching of the MAC arithmetic inputs, saving power.
	always_ff @(posedge clk_i or negedge rst_an) begin : REG_bank_read_index
		if(~rst_an) begin
			read_bank_index_pipe1 <= 0;
		end else begin
			if (mem_stage_valid && exec_instr) begin
				read_bank_index_pipe1 <= read_bank_index;
			end else if (chain_instr) begin
				read_bank_index_pipe1 <= selected_bank;
			end
		end
	end

	// MUX selecting the data from the core RF or from the memory.
	// Notice also that the data coming from the memory can be taken from the memory_result_if or from the
	// temporary register (in case the memory_result comes before the commit and we need to wait for the commit)
	always_comb begin : MEM_REG_MUX
		// data from memory
		if (id_ex_pipe_i.mac_ctrl.mem_reg == 0) begin
			if (mem_result_tempreg_select) begin
				dataregs_feedforward_in = (WIDTH_DATA_MAX)'(signed'(mem_result_tempreg_out));
				coeffregs_in            = (WIDTH_COEFFS_MAX)'(signed'(mem_result_tempreg_out));
			end
			else begin
				dataregs_feedforward_in = (WIDTH_DATA_MAX)'(signed'(xif_mem_result_if.mem_result.rdata));
				coeffregs_in            = (WIDTH_COEFFS_MAX)'(signed'(xif_mem_result_if.mem_result.rdata));
			end
		end
		// data from core RF
		else begin
			if (chain_instr) begin
				dataregs_feedforward_in = bank_input_p;
			end else begin
				dataregs_feedforward_in = (WIDTH_DATA_MAX)'(signed'(id_ex_pipe_i.rs[1]));
			end
			coeffregs_in            = (WIDTH_COEFFS_MAX)'(signed'(id_ex_pipe_i.rs[1]));
		end
	end

	// detect the different types of instructions (notice that the three signals are NOT mutual exclusive)
	assign load_instr          = ((id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_SET_NFEED) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_SET_ROUNDING) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_SET_FEATURES) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD_EXEC_DATA)); //CHANGED MAC_OP_SET_SIMD WITH *_FEATURES
	assign load_from_mem_instr = ((id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD_EXEC_DATA)) && (id_ex_pipe_i.mac_ctrl.mem_reg == 0);
	assign exec_instr          = (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD_EXEC_DATA) || (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_EXEC);
	assign chain_instr         = (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_LOAD_CHAINED_EXEC_DATA_REG);
	assign set_chain_instr     = (id_ex_pipe_i.mac_ctrl.mac_op == MAC_OP_CONFIG_CHAINED_EXEC);

	always_comb begin : BANK_CTRL_SIGNALS
		
		dataregs_shift_bank_feedforward_enable = 0;
		coeffregs_shift_bank_enable            = 0;
		selectors_write_bank_enable            = 0;
		dataregs_clear_bank_enable             = 0;
		coeffregs_clear_bank_enable            = 0;
		roundingregs_write_bank_enable         = 0;
		simdregs_write_bank_enable             = 0;
		omregs_write_bank_enable               = 0;
		mem_stage_valid                        = 0;
		chain_enable                           = 0;
		
		// only if a commit is received we can go on with instructions acting on the dataregs or coeffregs, otherwise the state of the
		// internal registers would be modified with no possibilities to recover the previous one, if a kill is stated later on.
		if (mac_enable && commit_i) begin
			unique case (id_ex_pipe_i.mac_ctrl.mac_op)
				MAC_OP_CLEAR : begin
					// clear the dataregs
					if (id_ex_pipe_i.mac_ctrl.data_coeff == 0) begin
						dataregs_clear_bank_enable  = 1;
					end
					// clear the coeffregs
					else begin
						coeffregs_clear_bank_enable = 1;
					end
					mem_stage_valid = 1;
				end
				MAC_OP_SET_NFEED : begin
					// assert the write enable if we are in the LOAD state (see FSMs section)
					// if we are not in the LOAD state, the write enable has to be set to 0 (see FSMs section)
					if (curr_state_loadtoregs_e == LOAD) begin
						selectors_write_bank_enable = 1;
					end
					mem_stage_valid = 1;
				end
				MAC_OP_SET_ROUNDING : begin
					// assert the write enable if we are in the LOAD state (see FSMs section)
					// if we are not in the LOAD state, the write enable has to be set to 0 (see FSMs section)
					if (curr_state_loadtoregs_e == LOAD) begin
						roundingregs_write_bank_enable = 1;
					end
					mem_stage_valid = 1;
				end
				MAC_OP_SET_FEATURES : begin	//BEFORE IT WAS SET_SIMD
					// assert the write enable if we are in the LOAD state (see FSMs section)
					// if we are not in the LOAD state, the write enable has to be set to 0 (see FSMs section)
					if (curr_state_loadtoregs_e == LOAD) begin
						simdregs_write_bank_enable = 1;
						omregs_write_bank_enable   = 1;
					end
					mem_stage_valid = 1;
				end
				MAC_OP_LOAD, MAC_OP_LOAD_EXEC_DATA : begin
					// load into the bank from the memory
					if (id_ex_pipe_i.mac_ctrl.mem_reg == 0) begin
						// we got the result from the memory
						if (value_from_mem_ready) begin
							mem_stage_valid = 1;
							// assert the shift enable if we are in the LOAD state (see FSMs section)
							// if we are not in the LOAD state, the shift enable has to be set to 0 (see FSMs section)
							if (curr_state_loadtoregs_e == LOAD) begin
								// to data regs
								if (id_ex_pipe_i.mac_ctrl.data_coeff == 0) begin
									dataregs_shift_bank_feedforward_enable = 1;
								end
								// to coeff regs
								else begin
									coeffregs_shift_bank_enable = 1;
								end
							end
						end
					end
					// load into the bank from the register
					else begin
						mem_stage_valid = 1;
						// assert the shift enable if we are in the LOAD state (see FSMs section)
						// if we are not in the LOAD state, the shift enable has to be set to 0 (see FSMs section)
						if (curr_state_loadtoregs_e == LOAD) begin
							// to data regs
							if (id_ex_pipe_i.mac_ctrl.data_coeff == 0) begin
								dataregs_shift_bank_feedforward_enable = 1;
							end
							// to coeff regs
							else begin
								coeffregs_shift_bank_enable = 1;
							end
						end
					end
				end
				MAC_OP_CONFIG_CHAINED_EXEC : begin
					mem_stage_valid = 1;
				end
				MAC_OP_LOAD_CHAINED_EXEC_DATA_REG : begin
					chain_enable     = 1;
					mem_stage_valid  = 1;
				end
				MAC_OP_EXEC : begin
					mem_stage_valid  = 1;
				end
				default : begin
				end
			endcase
		end
		// mac is not enable or the commit has not arrived, yet
	end

	// exception or debug from the memory interface
	assign mem_exception_debug = mem_exception_debug_valid_i && (mem_exception_debug_struct_i.exc || mem_exception_debug_struct_i.dbg);
	// debug or error from the memory result interface
	assign mem_result_debug_error = xif_mem_result_if.mem_result_valid && (xif_mem_result_if.mem_result.dbg || xif_mem_result_if.mem_result.err);

	/*
	MEALY FINITE STATE MACHINES
	*/
	// sequential logic to store the states of the two FSMs
	always_ff @(posedge clk_i or negedge rst_an) begin : MEALY_FSM_SEQ_LOGIC
		if(~rst_an) begin
			curr_state_mem_req_e    <= MEM_REQUEST;
			curr_state_loadtoregs_e <= LOAD;
		end else begin
			curr_state_mem_req_e    <= next_state_mem_req_e;
			curr_state_loadtoregs_e <= next_state_loadtoregs_e;
		end
	end

	// this FSM is needed to ensure that the write_enable/shift_enable signals of the shift registers are asserted only for
	// one clock cycle.
	// The write_enable/shift_enable signals can be asserted if we are in the LOAD state, while in the WAIT the they
	// are SET to '0'. The passage in the WAIT state means that after a load instruction (in which
	// write_enable/shift_enable are set to '1'), the coprocessor is not ready to accept a new instruction, therefore it has to deassert
	// the write_enable/shift_enable after 1 clock cycle to avoid that the same data is loaded more than one time into the shift registers.
	always_comb begin : LOAD_REG_FSM_COMB_LOGIC
		unique case (curr_state_loadtoregs_e)
			LOAD : begin
				if (id_ex_pipe_i.mac_ctrl.mac_enable && commit_i && load_instr) begin
					// load from memory
					if (id_ex_pipe_i.mac_ctrl.mem_reg == 0) begin
						// we got the value from the memory, but we are not ready for the next instruction -->
						// --> we need to pass in the WAIT state in which the write_enable/shift_enable signal will be deasserted.
						if (value_from_mem_ready && !mac_ready_o) begin
							next_state_loadtoregs_e = WAIT;
						end
						// we are ready for the next instruction -> remains into the LOAD state
						else begin
							next_state_loadtoregs_e = LOAD;
						end
					end
					// load from register
					else begin
						// we are not ready for the next instruction -->
						// --> we need to pass in the WAIT state in which the write_enable/shift_enable signal will be deasserted.
						if (!mac_ready_o) begin
							next_state_loadtoregs_e = WAIT;
						end
						// we are ready for the next instruction -> remains into the LOAD state
						else begin
							next_state_loadtoregs_e = LOAD;
						end
					end
				end
				else begin
					next_state_loadtoregs_e = LOAD;
				end
			end
			WAIT : begin
				// we are ready for the next instruction --> return to the LOAD
				if (mac_ready_o) begin
					next_state_loadtoregs_e = LOAD;
				end
				// we are not ready for the next instruction --> remains into the WAIT state
				else begin
					next_state_loadtoregs_e = WAIT;
				end
			end
			default : begin
				next_state_loadtoregs_e = LOAD;
			end
		endcase
	end

	// this FSM is in charge of managing the memory requests to the core in case of instructions that require them
	// TODO: the specs say that the coprocessor is not allowed to retract the valid signals, even after a kill. I am not so sure
	// about it, therefore for now let's assume that it can. The kill forces all the states to return to the initial one (MEM_REQUEST).
	// TODO: I cannot use a pipelined approach, since the kill would be not synchronized: the one
	// we receive as kill_i is referred to the instruction we are currently serving, if we assume
	// that the mem_stage and the res_stage can serve two different instructions, it is a mess.
	always_comb begin : MEMORY_REQUEST_FSM_COMB_LOGIC
		unique case (curr_state_mem_req_e)
			// this is the state in which a memory request (if needed) is done
			MEM_REQUEST : begin
				// the mac is enabled, no kill and the instruction requires a load from the memory
				if (id_ex_pipe_i.mac_ctrl.mac_enable && !kill_i && load_from_mem_instr) begin
					// set to 1 the signal to request a memory transaction
					mac_out_o.mem_trans_valid = 1;
					// if the memory interface has accepted the request
					if (memory_if_accept_i) begin
						// no exception/debug got
						if (!mem_exception_debug) begin
							// pass in MEM_RESULT_WAIT to wait for the memory result
							next_state_mem_req_e            = MEM_RESULT_WAIT;
							mem_stage_ready                 = 0;
							mem_result_tempreg_write_enable = 0;
							mem_result_tempreg_select       = 0;
							value_from_mem_ready            = 0;
						end
						// I got exception/debug from the memory if
						else begin
							// remain in MEM_REQUEST since no result will be provided by the memory result interface
							next_state_mem_req_e            = MEM_REQUEST;
							mem_stage_ready                 = 1;
							mem_result_tempreg_write_enable = 0;
							mem_result_tempreg_select       = 0;
							value_from_mem_ready            = 0;
						end
					end
					// wait for the memory interface accepting
					else begin
						next_state_mem_req_e            = MEM_REQUEST;
						mem_stage_ready                 = 0;
						mem_result_tempreg_write_enable = 0;
						mem_result_tempreg_select       = 0;
						value_from_mem_ready            = 0;
					end
				end
				// we do not need a memory transaction
				else begin
					next_state_mem_req_e            = MEM_REQUEST;
					mem_stage_ready                 = 1;
					mem_result_tempreg_write_enable = 0;
					mem_result_tempreg_select       = 0;
					mac_out_o.mem_trans_valid       = 0;
					value_from_mem_ready            = 0;
				end
			end
			// in this state we wait for the memory result after a memory request
			MEM_RESULT_WAIT : begin
				if (id_ex_pipe_i.mac_ctrl.mac_enable && !kill_i && load_from_mem_instr) begin
					// memory request transaction already performed in the previous state
					mac_out_o.mem_trans_valid = 0;
					// we receive the response from the memory_result interface
					if (xif_mem_result_if.mem_result_valid) begin
						// check that no error and debug signals have occurred from memory result interface
						if (!mem_result_debug_error) begin
							value_from_mem_ready = 1;
							// we already have the commit --> the transaction is over and we can return to the MEM_REQUEST asserting mem_stage_ready=1
							if (commit_i) begin
								next_state_mem_req_e            = MEM_REQUEST;
								mem_stage_ready                 = 1;
								mem_result_tempreg_write_enable = 0;
								mem_result_tempreg_select       = 0;
							end
							// we do not have a commit --> go to COMMIT_KILL_WAIT to wait for the commit: meanwhile the value obtained from the memory result
							// will be stored into a temporary register
							else begin
								next_state_mem_req_e            = COMMIT_KILL_WAIT;
								mem_stage_ready                 = 0;
								mem_result_tempreg_write_enable = 1;
								mem_result_tempreg_select       = 1;
							end
						end
						// if I get an error or an exception, I go directly to the result if
						else begin
							next_state_mem_req_e            = MEM_REQUEST;
							mem_stage_ready                 = 1;
							mem_result_tempreg_write_enable = 0;
							mem_result_tempreg_select       = 0;
							value_from_mem_ready            = 0;
						end
					end
					// otherwise I will wait for the memory result
					else begin
						next_state_mem_req_e            = MEM_RESULT_WAIT;
						mem_stage_ready                 = 0;
						mem_result_tempreg_write_enable = 0;
						mem_result_tempreg_select       = 0;
						value_from_mem_ready            = 0;
					end
				end
				else begin
					next_state_mem_req_e            = MEM_REQUEST;
					mem_stage_ready                 = 1;
					mem_result_tempreg_write_enable = 0;
					mem_result_tempreg_select       = 0;
					mac_out_o.mem_trans_valid       = 0;
					value_from_mem_ready            = 0;
				end
			end
			// we go in this state if we did the memory request, we got the memory result, but the commit/kill has not arrived, yet
			COMMIT_KILL_WAIT : begin
				// memory request already done in MEM_REQUEST
				mac_out_o.mem_trans_valid = 0;
				if (id_ex_pipe_i.mac_ctrl.mac_enable && !kill_i && load_from_mem_instr) begin
					value_from_mem_ready            = 1;
					mem_result_tempreg_write_enable = 0;
					mem_result_tempreg_select       = 1;
					// we receive the commit
					if (commit_i) begin
						next_state_mem_req_e = MEM_REQUEST;
						mem_stage_ready      = 1;
					end
					// we continue to wait for the commit/kill
					else begin
						next_state_mem_req_e = COMMIT_KILL_WAIT;
						mem_stage_ready      = 0;
					end
				end
				else begin
					next_state_mem_req_e            = MEM_REQUEST;
					mem_stage_ready                 = 1;
					mem_result_tempreg_write_enable = 0;
					mem_result_tempreg_select       = 0;
					value_from_mem_ready            = 0;
				end
			end
			default : begin
				next_state_mem_req_e            = MEM_REQUEST;
				mem_stage_ready                 = 1;
				mem_result_tempreg_write_enable = 0;
				mem_result_tempreg_select       = 0;
				mac_out_o.mem_trans_valid       = 0;
				value_from_mem_ready            = 0;
			end
		endcase
	end

	// this temporary register is needed in case the result from the memory_result_if comes before the commit/kill signal: in that case
	// we can not store the received value into the registers having not a commit, but we need to save the memory result somewhere waiting for the (eventual) commit.
	// In case of kill, this data will be not stored into the register.
	always_ff @(posedge clk_i or negedge rst_an) begin : MEM_RESULT_TEMPREG
		if(~rst_an) begin
			mem_result_tempreg_out <= 0;
		end else begin
			if (mem_result_tempreg_write_enable) begin
				mem_result_tempreg_out <= xif_mem_result_if.mem_result.rdata;
			end
		end
	end

	// memory_if signals that can be statically assigned. For future improvements their values
	// could change (e.g. if you need to write into the memory, we_mem=1).
	assign mac_out_o.addr_mem       = id_ex_pipe_i.rs[1];
	assign mac_out_o.mode_mem       = 2'b11;
	assign mac_out_o.we_mem         = 0;
	assign mac_out_o.size_mem       = 2;
	assign mac_out_o.be_mem         = '1;
	assign mac_out_o.attr_mem       = '0;
	assign mac_out_o.wdata_mem      = '0;
	assign mac_out_o.last_mem_trans = 1;

	/*
	CHAINING
	*/

	// SET CHAINING
	always_ff @(posedge clk_i or negedge rst_an) begin : CONFIG_CHAINING
		if(~rst_an) begin
			num_inputs                   <= '0;
			use_bank                     <= '0;
			chained_bank_indices[0]      <= '0;
			chained_bank_indices[1]      <= '0;
			chained_bank_indices[2]      <= '0;
			chained_bank_indices[3]      <= '0;
			chained_bank_indices[4]      <= '0;
			chained_bank_indices[5]      <= '0;
			chained_bank_indices[6]      <= '0;
			chained_bank_indices[7]      <= '0;
		end else begin
			if (mac_enable && set_chain_instr) begin
				num_inputs 					<= id_ex_pipe_i.rs[0][1:0];
				use_bank					<= {
					id_ex_pipe_i.rs[1][31],
					id_ex_pipe_i.rs[1][23],
					id_ex_pipe_i.rs[1][15],
					id_ex_pipe_i.rs[1][7],
					id_ex_pipe_i.rs[0][31],
					id_ex_pipe_i.rs[0][23],
					id_ex_pipe_i.rs[0][15],
					1'b1
				};
				//chained_bank_indices[0][$clog2(N_BANKS)-1:0]        <= {1'b0, id_ex_pipe_i.rs[0][7:2]};
				//chained_bank_indices[1][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][14:8];
				//chained_bank_indices[2][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][22:16];
				//chained_bank_indices[3][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][30:24];
				//chained_bank_indices[4][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][6:0];
				//chained_bank_indices[5][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][14:8];
				//chained_bank_indices[6][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][22:16];
				//chained_bank_indices[7][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][30:24];
				//2024 MOD - to fix error in LINT
				chained_bank_indices[0][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][$clog2(N_BANKS)+1:2];
				chained_bank_indices[1][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][$clog2(N_BANKS)+7:8];
				chained_bank_indices[2][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][$clog2(N_BANKS)+15:16];
				chained_bank_indices[3][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[0][$clog2(N_BANKS)+23:24];
				chained_bank_indices[4][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][$clog2(N_BANKS)-1:0];
				chained_bank_indices[5][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][$clog2(N_BANKS)+7:8];
				chained_bank_indices[6][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][$clog2(N_BANKS)+15:16];
				chained_bank_indices[7][$clog2(N_BANKS)-1:0]        <= id_ex_pipe_i.rs[1][$clog2(N_BANKS)+23:24];
			end
		end
	end

	// CHAINED EXECUTION

	always_comb begin
		if (index_p + 1 <= 'd7) begin
			chain_result_valid = (use_bank[index_p + 1] == 0) && mac_result_valid;
		end else begin
			chain_result_valid = mac_result_valid;
		end
	end
	assign input_1            = id_ex_pipe_i.rs[0];
	assign input_2            = id_ex_pipe_i.rs[1];
	assign input_3            = id_ex_pipe_i.rs[1];
	assign input_4            = id_ex_pipe_i.rs[1];

	always_ff @(posedge clk_i or negedge rst_an) begin : MEALY_FSM_CHAIN_SEQ_LOGIC
		if(~rst_an) begin
			state_chain_p	<= IDLE;
			bank_input_p 	<= 'b0;
			index_p 		<= 'b0;
			chain_active 	<= 0;
		end else begin
			state_chain_p	<= state_chain_n;
			bank_input_p 	<= bank_input_n;
			index_p 		<= index_n;
			if (chain_enable) begin
				chain_active	<= 1;
			end else if (res_accepted) begin
				chain_active 	<= 0;
			end
		end
	end

	

	always_comb begin : CHAIN_COMB_LOGIC

		bank_input_n = bank_input_p;
		index_n = index_p;
		state_chain_n = state_chain_p;
		shift_bottom_enable = 0;
		shift_top_enable = 0;
		reset_counter = 0;
		selected_bank = chained_bank_indices[index_p];
		fir_filter = 'b1;
		for( int i=0 ; i < N_ELEMENTS_BANK_MAX ; i++ ) begin
			fir_filter = fir_filter && (dataregs_selectors[selected_bank][i] == 1'b0);
		end
		exec_enable = 0;
		exec_disable = 0;

		unique case (state_chain_p)
			IDLE: begin
				if (chain_enable) begin
					if (num_inputs == 'd0) begin
						state_chain_n = SHIFT_ONE_TOP;
					end else if (num_inputs == 'd1) begin
						state_chain_n = SHIFT_TWO_TOP;
					end else if (num_inputs == 'd2) begin
						state_chain_n = SHIFT_THREE_TOP;
					end else if (num_inputs == 'd3) begin
						state_chain_n = SHIFT_FOUR_TOP;
					end
					bank_input_n = input_1;
					index_n = 'd0;
				end
			end
			SHIFT_FOUR_TOP: begin
				state_chain_n = SHIFT_THREE_TOP;
				shift_top_enable = 1;
				bank_input_n = input_2;
			end
			SHIFT_THREE_TOP: begin
				state_chain_n = SHIFT_TWO_TOP;
				shift_top_enable = 1;
				bank_input_n = input_2;
			end
			SHIFT_TWO_TOP: begin
				state_chain_n = SHIFT_ONE_TOP;
				bank_input_n = input_2;
				shift_top_enable = 1;
			end
			SHIFT_ONE_TOP: begin
				state_chain_n = EXEC_BANK;
				shift_top_enable = 1;
				reset_counter = 1;
				exec_enable = 1;
			end
			EXEC_BANK: begin
				// intermediate result is ready
				if (mac_result_valid) begin
					exec_disable = 1;
					// current bank is fir filter => no shift bottom needed
					if (fir_filter) begin
						if (chain_result_valid) begin
							state_chain_n = IDLE;
						end else begin
							state_chain_n = SHIFT_ONE_TOP;
							bank_input_n = modified_result;
							index_n = index_p + 1;
						end
					end 
					// current bank is iir filter => shift bottom needed
					else begin
						state_chain_n = SHIFT_BOTTOM;
						bank_input_n = modified_result;
					end
				end
			end
			SHIFT_BOTTOM: begin
				shift_bottom_enable = 1;
				if (chain_result_valid) begin
					state_chain_n = IDLE;
				end else begin
					state_chain_n = SHIFT_ONE_TOP;
					index_n = index_p + 1;
				end
			end
			default: begin
				state_chain_n = IDLE;
			end
		endcase
	end

	/*
	RESULT STAGE
	*/
	// signals from the memory stage to the result stage: these signals must be saved in a register since
	// they are not stable during the execution of the result stage.
	always_ff @(posedge clk_i or negedge rst_an) begin : RES_STAGE_REGS
		if(~rst_an) begin
			mem_exc_dbg_pipe1                    <= 0;
			mem_result_dbg_err_pipe1             <= 0;
			mem_exc_dbg_err_struct_pipe1.exc     <= 0;
			mem_exc_dbg_err_struct_pipe1.dbg     <= 0;
			mem_exc_dbg_err_struct_pipe1.exccode <= '0;
			mem_exc_dbg_err_struct_pipe1.err     <= '0;
		end else begin
			// store the exception/debug information from the memory interface if you receive mem_exception_debug_valid_i
			if (mem_exception_debug_valid_i) begin
				mem_exc_dbg_pipe1                    <= mem_exception_debug;
				mem_exc_dbg_err_struct_pipe1.exc     <= mem_exception_debug_struct_i.exc;
				mem_exc_dbg_err_struct_pipe1.dbg     <= mem_exception_debug_struct_i.dbg;
				mem_exc_dbg_err_struct_pipe1.exccode <= mem_exception_debug_struct_i.exccode;
			end
			// store the debug/error information from the memory result interface if you receive mem_result_debug_error
			else if (mem_result_debug_error) begin
				mem_result_dbg_err_pipe1         <= mem_result_debug_error;
				mem_exc_dbg_err_struct_pipe1.dbg <= xif_mem_result_if.mem_result.dbg;
				mem_exc_dbg_err_struct_pipe1.err <= xif_mem_result_if.mem_result.err;
			end
			// if res_accepted=1 --> the result transaction and, consequently, the current instruction execution iare over --> reset the registers for the next instruction
			else if (res_accepted) begin
				mem_exc_dbg_pipe1        <= 0;
				mem_result_dbg_err_pipe1 <= 0;
			end
		end
	end
	// this alu block does not need to write into the CSRs
	assign mem_exc_dbg_err_struct_pipe1.ecswe   = '0;
	assign mem_exc_dbg_err_struct_pipe1.ecsdata = '0;


	// ASSIGN SIGNALS TO THE RESULT INTERFACE
	assign mac_out_o.exc_dbg_err = mem_exc_dbg_err_struct_pipe1;
	// These signals are not given by a register, but they are maintained stable by the id_ex pipe stage, since pipelining is not present for now.
	if (FEEDBACK_UNROUNDED == 0) begin
		// if FEEDBACK_UNROUNDED=0, we give as result for the core the same result that will be written into the feedback data regs (that is rounded, being FEEDBACK_UNROUNDED=0),
		// Notice that dataregs_bottom_trunc_sign_ext_out is already sign-extended within the bidir_set module
		// according to the WIDTH of the selected bank, but here we sign-extend it further to 32 bits, that is the bitwidth of the core RF.
		// assign mac_out_o.result       = 32'(signed'(dataregs_bottom_trunc_sign_ext_out));
		assign mac_out_o.result       = 32'(signed'(modified_result));
	end
	else begin
		// if FEEDBACK_UNROUNDED=1, the value returned to the core RF is rounded according to roundingregs_read_bank_out, while the value stored into the feedback part of the data
		// registers is NOT rounded.
		always_comb begin : FEEDBACK_UNROUNDED_MUX
			// roundingregs_read_bank_out=0: no rounding is made -> the value returned to the core RF is compliant with the one stored into the feedback register.
			// we perform a sign-extension on 32 bits, that is the bitwidth of the core RF.
			/*if (roundingregs_read_bank_out == 0) begin
				mac_out_o.result       = 32'(signed'(dataregs_bottom_trunc_sign_ext_out));
			end*/
			// roundingregs_read_bank_out>0: a rounding is made for the value returned to the core RF, but NOT for the value stored into the feedback register (being FEEDBACK_UNROUNDED=1) ->
			// -> the value returned to the core RF is NOT compliant with the one stored into the feedback register.
			// For the value returned to the core RF, perform a simpler sign-extension of rounding_result without taking into account WIDTH_DATA[read_bank_index].
			mac_out_o.result       = 32'(signed'(modified_result));
		end
	end
	assign mac_out_o.result_valid = res_stage_valid;
	assign mac_out_o.writeback    = id_ex_pipe_i.writeback;
	assign mac_out_o.rd           = id_ex_pipe_i.rd;


	// exec_enable_pipe1 is a control signal for the execution: if 1, the MAC arithmetic part has to compute a new value
	always_ff @(posedge clk_i or negedge rst_an) begin : exec_enable_reg
		if(~rst_an) begin
			exec_enable_pipe1 <= 0;
		end else begin
			if (kill_i || (exec_disable && chain_instr)) begin
				exec_enable_pipe1 <= 0;
			end
			// if exec_instr directly enable execution
			// if in chaining execution controlled manually
			else if ((mem_stage_valid && exec_instr) || (exec_enable && chain_instr)) begin
				exec_enable_pipe1 <= 1;
			end
			else if (res_accepted) begin
				exec_enable_pipe1 <= 0;
			end
		end
	end

	// ARITHMETIC PART OF THE MAC
	// these assignments are needed in case of (N_ELEMENTS_BANK_MAX < MAC_ITERATIONS_COUNT_MAX*N_OPERANDS_MAC). In that case some inputs of the MUX
	// have to be placed to 0 since N_ELEMENTS_BANK_MAX and N_OPERANDS_MAC are not multiple (i.e. (N_ELEMENTS_BANK_MAX % N_OPERANDS_MAC)!=0).
	// This statements work both for MAC_ITERATIONS_COUNT_MAX>1 and =1.
	generate
		for (genvar elem_index = 0; elem_index < (MAC_ITERATIONS_COUNT_MAX*N_OPERANDS_MAC); elem_index++) begin
			if (elem_index < N_ELEMENTS_BANK_MAX) begin
				assign mac_arith_data_operands_muxin[elem_index] = dataregs_read_bank_out[elem_index];
				assign mac_arith_coeff_operands_muxin[elem_index] = coeffregs_read_bank_out[elem_index];
			end
			else begin
				assign mac_arith_data_operands_muxin[elem_index] = '0;
				assign mac_arith_coeff_operands_muxin[elem_index] = '0;
			end
		end
	endgenerate

	// counter and mux generation (in case of more than 1 iteration needed)
	generate
		if (MAC_ITERATIONS_COUNT_MAX>1) begin : counter_and_mux_gen
			// COUNTER
			logic [$clog2(MAC_ITERATIONS_COUNT_MAX+1)-1:0] counter;
			// iterative adder signals
			logic [RESULT_BITS-1:0] adder_accumul_out    ;
			logic [RESULT_BITS-1:0] adder_accumul_tempreg;

			// define the MAC_ITERATION COUNT vector storing the number of iterations needed for each bank according to N_ELEMENTS_BANK[bank_index]
			int unsigned MAC_ITERATIONS_COUNT[N_BANKS];
			always_comb begin : MAC_ITERATIONS_COUNT_gen
				for (int bank_index = 0; bank_index < N_BANKS; bank_index++) begin
					MAC_ITERATIONS_COUNT[bank_index] = (N_ELEMENTS_BANK[bank_index]+(N_OPERANDS_MAC-1))/N_OPERANDS_MAC;
				end
			end
			// counter and adder accumulation registers
			always_ff @(posedge clk_i or negedge rst_an) begin : MAC_counter
				if(~rst_an) begin
					counter               <= 0;
					adder_accumul_tempreg <= 0;
				end else begin
					if (res_accepted || kill_i || reset_counter) begin
						counter               <= 0;
						adder_accumul_tempreg <= 0;
					end
					else if (exec_enable_pipe1 && !mac_result_valid) begin
						counter               <= counter+1;
						adder_accumul_tempreg <= adder_accumul_out;
					end
				end
			end

			// MULTIPLEXING OF THE OPERANDS ACCORDING TO counter
			assign mac_arith_data_operands = mac_arith_data_operands_muxin[counter*N_OPERANDS_MAC +: N_OPERANDS_MAC];
			assign mac_arith_coeff_operands = mac_arith_coeff_operands_muxin[counter*N_OPERANDS_MAC +: N_OPERANDS_MAC];

			// here the adder needed for the iterations is instantiated
			if (SIMD) begin
				always_comb begin : ADDER_ACCUMUL_SIMD_MUX
					if (simdregs_read_bank_out == 0) begin
						adder_accumul_out = (RESULT_BITS)'((signed'(adder_accumul_tempreg)) + (signed'(mac_arith_out)));
					end
					else begin
						adder_accumul_out[RESULT_BITS/2-1:0] = (RESULT_BITS/2)'((signed'(adder_accumul_tempreg[RESULT_BITS/2-1:0])) + (signed'(mac_arith_out[MAC_OUT_BITS/2-1:0])));
						adder_accumul_out[RESULT_BITS-1:RESULT_BITS/2] = (RESULT_BITS-RESULT_BITS/2+1)'((signed'(adder_accumul_tempreg[(RESULT_BITS/2+RESULT_BITS/2)-1:RESULT_BITS/2])) + (signed'(mac_arith_out[(MAC_OUT_BITS/2+MAC_OUT_BITS/2)-1:MAC_OUT_BITS/2])));
					end
				end
			end
			else begin
				assign adder_accumul_out = (RESULT_BITS)'((signed'(adder_accumul_tempreg)) + (signed'(mac_arith_out)));
			end

			// assign the output of the accumulation adder as result of the operation
			assign mac_arith_result = adder_accumul_out;
			// are the iterations finished?
			always_comb begin : COUNTER_STOP
				if (read_bank_index_pipe1 < N_BANKS) begin
					mac_result_valid  = (counter == (MAC_ITERATIONS_COUNT[read_bank_index_pipe1]-1));
				end
				else begin
					mac_result_valid  = (counter == (MAC_ITERATIONS_COUNT[N_BANKS-1]-1));
				end
			end
		end
		else begin : no_counter_and_mux_gen
			// no multiplexing needed since all the operands are computed by the MAC in parallel
			assign mac_arith_data_operands = mac_arith_data_operands_muxin[0:N_OPERANDS_MAC-1];
			assign mac_arith_coeff_operands = mac_arith_coeff_operands_muxin[0:N_OPERANDS_MAC-1];

			// no adder to accumulate needed here
			assign mac_arith_result = mac_arith_out;
			// are the iterations finished? No counter in this case, therefore always yes.
			assign mac_result_valid          = 1;
		end
	endgenerate

	// instantiate MAC and rounding unit according to the SIMD parameter
	generate
		if (SIMD) begin : MAC_ARITH_SIMD_GEN
			mac_arith #(
				.N_OPERANDS       (N_OPERANDS_MAC         ),
				.SIMD             (SIMD                   ),
				.N_BIT_OP_A_MAX   (WIDTH_DATA_MAX         ),
				.N_BIT_OP_B_MAX   (WIDTH_COEFFS_MAX       ),
				.N_BIT_OP_A_NOSIMD(WIDTH_DATA_NOSIMD_MAX  ),
				.N_BIT_OP_B_NOSIMD(WIDTH_COEFFS_NOSIMD_MAX),
				.N_BIT_OP_A_SIMD  (WIDTH_DATA_SIMD_MAX    ),
				.N_BIT_OP_B_SIMD  (WIDTH_COEFFS_SIMD_MAX  ),
				.N_BIT_OUT_MAX    (MAC_OUT_BITS           ),
				.N_BIT_SIMD_OUT   (MAC_OUT_BITS           )
			) i_mac_arith (
				.simd_mode_i (simdregs_read_bank_out  ),
				.operands_a_i(mac_arith_data_operands ),
				.operands_b_i(mac_arith_coeff_operands),
				.result_o    (mac_arith_out           )
			);
			rounding_unit_nearest_even #(
				.SIMD           (SIMD               ),
				.N_BIT_IN_MAX   (RESULT_BITS        ),
				.N_BIT_NOSIMD_IN(RESULT_BITS        ),
				.N_BIT_SIMD_IN  (RESULT_BITS        ),
				.N_BIT_OUT_MAX  (WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_OUT (WIDTH_DATA_SIMD_MAX),
				.BITS_CUT_MAX   (BITS_CUT_MAX       )
			) i_rounding_unit_nearest_even (
				.simd_mode_i      (simdregs_read_bank_out    ),
				.unrounded_value_i(mac_arith_result          ),
				.n_bits_cut_i     (roundingregs_read_bank_out),
				.rounded_value_o  (rounded_result            ),
				.unrounded_value_o(unrounded_result          )
			);
			output_modifier #(
				.SIMD           (SIMD               ),
				.N_BIT_IN_MAX   (WIDTH_DATA_MAX     ),
				.N_BIT_NOSIMD_IN(WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_IN  (WIDTH_DATA_MAX     ),
				.N_BIT_OUT_MAX  (WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_OUT (WIDTH_DATA_SIMD_MAX)
			) i_output_modifier (
				.simd_mode_i      (simdregs_read_bank_out    ),
				.rounded_value_i  (rounded_result            ),
				.output_mod_sel_i (omregs_read_bank_out      ),
				.modified_value_o (modified_result           )
			);
		end
		else begin : MAC_ARITH_NOSIMD_GEN
			//logic [MAC_OUT_BITS-1:0] mac_arith_out_dummy;	//dummy signal for comparison while simulating		
			mac_arith #(
				.N_OPERANDS       (N_OPERANDS_MAC         ),
				.SIMD             (SIMD                   ),
				.N_BIT_OP_A_MAX   (WIDTH_DATA_MAX         ),
				.N_BIT_OP_B_MAX   (WIDTH_COEFFS_MAX       ),
				.N_BIT_OP_A_NOSIMD(WIDTH_DATA_NOSIMD_MAX  ),
				.N_BIT_OP_B_NOSIMD(WIDTH_COEFFS_NOSIMD_MAX),
				.N_BIT_OP_A_SIMD  (WIDTH_DATA_SIMD_MAX    ),
				.N_BIT_OP_B_SIMD  (WIDTH_COEFFS_SIMD_MAX  ),
				.N_BIT_OUT_MAX    (MAC_OUT_BITS           ),
				.N_BIT_SIMD_OUT   (MAC_OUT_BITS           )
			) i_mac_arith (
				.simd_mode_i (1'b0                    ),
				.operands_a_i(mac_arith_data_operands ),
				.operands_b_i(mac_arith_coeff_operands),
				.result_o    (mac_arith_out	      ) //eventually mac_arith_out_dummy for simulation
			);
			rounding_unit_nearest_even #(
				.SIMD           (SIMD               ),
				.N_BIT_IN_MAX   (RESULT_BITS        ),
				.N_BIT_NOSIMD_IN(RESULT_BITS        ),
				.N_BIT_SIMD_IN  (RESULT_BITS        ),
				.N_BIT_OUT_MAX  (WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_OUT (WIDTH_DATA_SIMD_MAX),
				.BITS_CUT_MAX   (BITS_CUT_MAX       )
			) i_rounding_unit_nearest_even (
				.simd_mode_i      (1'b0                      ),
				.unrounded_value_i(mac_arith_result          ),
				.n_bits_cut_i     (roundingregs_read_bank_out),
				.rounded_value_o  (rounded_result            ),
				.unrounded_value_o(unrounded_result          )
			);
			output_modifier #(
				.SIMD           (SIMD               ),
				.N_BIT_IN_MAX   (WIDTH_DATA_MAX     ),
				.N_BIT_NOSIMD_IN(WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_IN  (WIDTH_DATA_MAX     ),
				.N_BIT_OUT_MAX  (WIDTH_DATA_MAX     ),
				.N_BIT_SIMD_OUT (WIDTH_DATA_SIMD_MAX)
			) i_output_modifier (
				.simd_mode_i      (1'b0                      ),
				.rounded_value_i  (rounded_result            ),
				.output_mod_sel_i (omregs_read_bank_out      ),
				.modified_value_o (modified_result           )
			);
		end
	endgenerate

	// ready and valid signal for the result stage
	// 0 if busy and not accepted
	assign res_stage_ready = 
		kill_i || !(
			(exec_enable_pipe1 && !mac_result_valid && exec_instr) ||	// busy during execution
			(chain_active && (state_chain_p != IDLE) && chain_instr) || 	// busy in chained execution
			(res_stage_valid && !result_if_accept_i)					// after result is valid wait for accept
		);

	// operation finished
	assign res_stage_valid = 
		(mac_result_valid && exec_enable_pipe1 && exec_instr) || 		// exec_instr
		(mem_stage_valid && !exec_instr && !chain_instr) || 			// load, set_chaining (1 clock cycle)
		(chain_active && (state_chain_p == IDLE) && chain_result_valid && chain_instr) ||		// chained execution 
		(mem_exc_dbg_pipe1 || mem_result_dbg_err_pipe1);				// debugging

	// the result has been accepted by the core OR the instruction has been killed
	assign res_accepted = res_stage_valid && result_if_accept_i;
	// signal to load the result into the feedback part of the DATA REGS
	assign dataregs_shift_bank_feedback_enable = 
		(
			(exec_instr && res_accepted) ||					// in exec: shift mac result when result accepted
			(chain_instr && shift_bottom_enable)			// in chain: shift mac result when manually enabled
		) && !kill_i;

	// both the stages must be ready, since otherwise it would mean that two different instructions for
	// the mem and the res stage are admitted (usual pipelining), but we would need additional logic
	// to manage the kill and so on, since the kill_i signal we have now is referred to the current
	// served instruction.
	assign mac_ready_o = mem_stage_ready && res_stage_ready && !(id_ex_pipe_i.mac_ctrl.mac_enable && !commit_i);

endmodule : coproc_mac

//	----------------------------------------------------------------------------
//                    			Revision History
//	----------------------------------------------------------------------------
//
//	$Log: coproc_mac.sv.rca $
//	
//	 Revision: 1.4 Fri Sep 20 15:56:53 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow - correction for OpenSource code
//	
//	 Revision: 1.3 Tue Sep 17 14:54:06 2024 nxf64830
//	 artf1182083 :: added header file compliant to NXP SW release flow
//	
//	 Revision: 1.2 Mon Sep 16 12:48:19 2024 nxg06494
//	 artf1178505 : Modified file to fix lint error
//	
//	 Revision: 1.1 Mon Dec 18 19:01:44 2023 nxf99842
//	 Release 2 - 18.12.2023
//	
//	 Revision: 1.12 Tue Jul 18 15:00:38 2023 nxf99772
//	 Output modifier in the processing chain
//	
//	 Revision: 1.11 Wed Oct 12 00:54:44 2022 nxf87116
//	 Added header and footer to the RTL files.
