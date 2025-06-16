//  ----------------------------------------------------------------------------
//                              Design Information
//  ----------------------------------------------------------------------------
//
//
//  File            :   $RCSfile: core_coproc_top.sv.rca $
//  Date            :   $Date: Mon Sep 16 12:43:55 2024 $
//  Revision        :   $Revision: 1.2 $
//
//  Description     :   Top-level module containing the core and the coprocessor
//                      coupled through the eXtension Interface.
//                      It is not used by the testbench, but it is only needed
//                      for the synthesis.
//
//  Author          :   Francesco Babbaro
//  ----------------------------------------------------------------------------

import cv32e40x_pkg::*;
import coproc_pkg::*;

module core_coproc_top #(
    // core parameters
    parameter                         LIB                         = 0          ,
    parameter rv32_e                  RV32                        = RV32I      , // todo: Add support for RV32E
    parameter bit                     A_EXT                       = 0          ,
    parameter b_ext_e                 B_EXT                       = B_NONE     ,
    parameter m_ext_e                 M_EXT                       = M_NONE     ,
    parameter int                     DBG_NUM_TRIGGERS            = 1          ,
    parameter int                     PMA_NUM_REGIONS             = 0          ,
    parameter pma_cfg_t      PMA_CFG[PMA_NUM_REGIONS-1:0] = '{default:PMA_R_DEFAULT},
    parameter bit                     CLIC                      = 0          ,
    parameter int                     CLIC_ID_WIDTH             = 5          ,
    parameter bit                     X_EXT                       = 1          ,
    parameter int                     X_NUM_RS                    = X_NUM_RS   ,
    parameter int                     X_ID_WIDTH                  = X_ID_WIDTH ,
    parameter int                     X_MEM_WIDTH                 = X_MEM_WIDTH,
    parameter int                     X_RFR_WIDTH                 = X_RFR_WIDTH,
    parameter int                     X_RFW_WIDTH                 = X_RFW_WIDTH,
    parameter logic            [31:0] X_MISA                      = X_MISA     ,
    parameter logic            [ 1:0] X_ECS_XS                    = X_ECS_XS   ,
    parameter int                     NUM_MHPMCOUNTERS            = 1          ,
    // coprocessor parameters
    parameter int     unsigned        N_BANKS_MAC                 = 5          , // number of banks
    parameter  int unsigned N_ELEMENTS_BANK_MAC[N_BANKS_MAC] = '{32'd2, 32'd33, 32'd4, 32'd34, 32'd2}, // number of elements per bank
    parameter int     unsigned        N_ELEMENTS_BANK_MAX_MAC     = 34         , // maximum elements among the banks defined above
    parameter  int unsigned WIDTH_DATA_MAC[N_BANKS_MAC] = '{32'd32, 32'd32, 32'd32, 32'd21, 32'd23}, // data parallelism per bank
    parameter int     unsigned        WIDTH_DATA_NOSIMD_MAX_MAC   = 23         , // maximum parallelism for non-simd data
    parameter int     unsigned        WIDTH_DATA_SIMD_MAX_MAC     = 32         , // maximum parallelism for simd data
    parameter int     unsigned        WIDTH_DATA_MAX_MAC          = 32         , // maximum data parallelism among the banks defined above
    parameter  int unsigned WIDTH_COEFFS_MAC[N_BANKS_MAC] = '{N_BANKS_MAC{32'd8}}                              , // coeffs parallelism per bank
    parameter int     unsigned        WIDTH_COEFFS_NOSIMD_MAX_MAC = 8          , // maximum parallelism for non-simd coeffs
    parameter int     unsigned        WIDTH_COEFFS_SIMD_MAX_MAC   = 8          , // maximum parallelism for simd coeffs
    parameter int     unsigned        WIDTH_COEFFS_MAX_MAC        = 8          , // maximum coeffs parallelism among the banks defined above
    parameter bit                     SIMD_MAC                    = 1          , // if 1, there is the possibility to use SIMD
    parameter int     unsigned        N_BIT_NFEED_MAC             = 2          , // number of bits of n_feed to setup the DATAREGS selectors
    parameter bit                     FEEDBACK_UNROUNDED_MAC      = 1          , // if 1, store into the feedback part of the data regs the unrounded result. The result returned to the core register file will be always the rounded one.
    parameter int     unsigned        N_OPERANDS_MAC              = 34         , // number of operands that the MAC arithmetic block can process in parallel
    parameter int     unsigned        BITS_CUT_MAX_MAC            = 8          , // maximum number of bits the rounding unit can throw away
    parameter int     unsigned	      DATA_WIDTH		  = 32	       , // for interfaces
    parameter int     unsigned	      ADDR_WIDTH		  = 32	         // for interfaces
) (
    // Clock and reset
    input  logic                       clk_i                ,
    input  logic                       rst_ni               ,
    input  logic                       scan_cg_en_i         , // Enable all clock gates for testing
    // Static configuration
    input  logic [               31:0] boot_addr_i          ,
    input  logic [               31:0] dm_exception_addr_i  ,
    input  logic [               31:0] dm_halt_addr_i       ,
    input  logic [               31:0] mhartid_i            ,
    input  logic [                3:0] mimpid_patch_i       ,
    input  logic [               31:0] mtvec_addr_i         ,
    //AHB IF MODIFICATION
    // Instruction memory interface
    /*output logic                       instr_req_o        ,
    input  logic                       instr_gnt_i        ,
    input  logic                       instr_rvalid_i     ,
    output logic [               31:0] instr_addr_o       ,
    output logic [                1:0] instr_memtype_o    ,
    output logic [                2:0] instr_prot_o       ,
    output logic                       instr_dbg_o        ,
    input  logic [               31:0] instr_rdata_i      ,
    input  logic                       instr_err_i        ,
    // Data memory interface
    output logic                       data_req_o         ,
    input  logic                       data_gnt_i         ,
    input  logic                       data_rvalid_i      ,
    output logic [               31:0] data_addr_o        ,
    output logic [                3:0] data_be_o          ,
    output logic                       data_we_o          ,
    output logic [               31:0] data_wdata_o       ,
    output logic [                1:0] data_memtype_o     ,
    output logic [                2:0] data_prot_o        ,
    output logic                       data_dbg_o         ,
    output logic [                5:0] data_atop_o        ,
    input  logic [               31:0] data_rdata_i       ,
    input  logic                       data_err_i         ,
    input  logic                       data_exokay_i      ,*/
    // Cycle count
    output logic [               63:0] mcycle_o             ,
    // Basic interrupt architecture
    input  logic [               31:0] irq_i                ,
    // Smclic interrupt architecture
    input  logic                       clic_irq_i           ,
    input  logic [  CLIC_ID_WIDTH-1:0] clic_irq_id_i        ,
    input  logic [                7:0] clic_irq_level_i     ,
    input  logic [                1:0] clic_irq_priv_i      ,
    input  logic                       clic_irq_shv_i       ,
    // Fence.i flush handshake
    output logic                       fencei_flush_req_o   ,
    input  logic                       fencei_flush_ack_i   ,
    // Debug interface
    input  logic                       debug_req_i          ,
    output logic                       debug_havereset_o    ,
    output logic                       debug_running_o      ,
    output logic                       debug_halted_o       ,
    // CPU control signals
    input  logic                       fetch_enable_i       ,
    output logic                       core_sleep_o	    ,
    //AHB INSTRUCTION
    output logic [     ADDR_WIDTH-1:0] ahb_inst_req_haddr   ,
    output logic [            	  3:0] ahb_inst_req_hprot   ,
    output logic [     		  2:0] ahb_inst_req_hsize   ,
    output logic [     		  1:0] ahb_inst_req_htrans  ,
    output logic 		       ahb_inst_req_hwrite  ,
    input logic  [     DATA_WIDTH-1:0] ahb_inst_resp_hrdata ,
    input logic  		       ahb_inst_resp_hresp  ,
    input logic  		       ahb_inst_resp_hready ,
    output logic		       ahb_inst_dbg	    ,
    //AHB DATA
    output logic [     ADDR_WIDTH-1:0] ahb_data_req_haddr   ,
    output logic [            	  3:0] ahb_data_req_hprot   ,
    output logic [     		  2:0] ahb_data_req_hsize   ,
    output logic [     		  1:0] ahb_data_req_htrans  ,
    output logic 		       ahb_data_req_hwrite  ,
    output logic [ (DATA_WIDTH/8)-1:0] ahb_data_req_hwstrobe,
    output logic [     DATA_WIDTH-1:0] ahb_data_req_hwdata  ,
    output logic 		       ahb_data_req_hexcl   ,
    output logic 		       ahb_data_req_hmaster ,
    input logic  [     DATA_WIDTH-1:0] ahb_data_resp_hrdata ,
    input logic  		       ahb_data_resp_hresp  ,
    input logic  		       ahb_data_resp_hready ,
    input logic  		       ahb_data_resp_hexokay,
    output logic 		       ahb_data_dbg
);

    ahb_inst_req_t  ahb_inst_req ;
    ahb_inst_resp_t ahb_inst_resp;
    ahb_data_req_t  ahb_data_req ;
    ahb_data_resp_t ahb_data_resp;
    
    assign ahb_inst_req_haddr    = ahb_inst_req.haddr   ;
    assign ahb_inst_req_hprot    = ahb_inst_req.hprot   ;
    assign ahb_inst_req_hsize    = ahb_inst_req.hsize   ;
    assign ahb_inst_req_htrans   = ahb_inst_req.htrans  ;
    assign ahb_inst_req_hwrite   = ahb_inst_req.hwrite  ;
    assign ahb_inst_resp.hrdata  = ahb_inst_resp_hrdata ;
    assign ahb_inst_resp.hresp   = ahb_inst_resp_hresp  ;
    assign ahb_inst_resp.hready  = ahb_inst_resp_hready ;
    assign ahb_data_req_haddr    = ahb_data_req.haddr   ;
    assign ahb_data_req_hprot    = ahb_data_req.hprot   ;
    assign ahb_data_req_hsize    = ahb_data_req.hsize   ;
    assign ahb_data_req_htrans   = ahb_data_req.htrans  ;
    assign ahb_data_req_hwrite   = ahb_data_req.hwrite  ;
    assign ahb_data_req_hwstrobe = ahb_data_req.hwstrobe;
    assign ahb_data_req_hwdata   = ahb_data_req.hwdata  ;
    assign ahb_data_req_hexcl    = ahb_data_req.hexcl   ;
    assign ahb_data_req_hmaster  = ahb_data_req.hmaster ;
    assign ahb_data_resp.hrdata  = ahb_data_resp_hrdata ;
    assign ahb_data_resp.hresp   = ahb_data_resp_hresp  ;
    assign ahb_data_resp.hready  = ahb_data_resp_hready ;
    assign ahb_data_resp.hexokay = ahb_data_resp_hexokay;
    
    cv32e40x_core #(
        .LIB             (LIB             ),
        .RV32            (RV32            ),
        .A_EXT           (A_EXT           ),
        .B_EXT           (B_EXT           ),
        .M_EXT           (M_EXT           ),
        .DBG_NUM_TRIGGERS(DBG_NUM_TRIGGERS),
        .PMA_NUM_REGIONS (PMA_NUM_REGIONS ),
        .CLIC            (CLIC          ),
        .CLIC_ID_WIDTH   (CLIC_ID_WIDTH ),
        .X_EXT           (X_EXT           ),
        .X_NUM_RS        (X_NUM_RS        ),
        .X_ID_WIDTH      (X_ID_WIDTH      ),
        .X_MEM_WIDTH     (X_MEM_WIDTH     ),
        .X_RFR_WIDTH     (X_RFR_WIDTH     ),
        .X_RFW_WIDTH     (X_RFW_WIDTH     ),
        .X_MISA          (X_MISA          ),
        .X_ECS_XS        (X_ECS_XS        ),
        .NUM_MHPMCOUNTERS(NUM_MHPMCOUNTERS)
    ) i_cv32e40x_core (
        .clk_i              (clk_i                         ),
        .rst_ni             (rst_ni                        ),
        .scan_cg_en_i       (scan_cg_en_i                  ),
        .boot_addr_i        (boot_addr_i                   ),
        .dm_exception_addr_i(dm_exception_addr_i           ),
        .dm_halt_addr_i     (dm_halt_addr_i                ),
        .mhartid_i          (mhartid_i                     ),
        .mimpid_patch_i     (mimpid_patch_i                ),
        .mtvec_addr_i       (mtvec_addr_i                  ),
        //AHB IF MODIFICATION
        /*.instr_req_o        (instr_req_o                   ),
        .instr_gnt_i        (instr_gnt_i                   ),
        .instr_rvalid_i     (instr_rvalid_i                ),
        .instr_addr_o       (instr_addr_o                  ),
        .instr_memtype_o    (instr_memtype_o               ),
        .instr_prot_o       (instr_prot_o                  ),
        .instr_dbg_o        (instr_dbg_o                   ),
        .instr_rdata_i      (instr_rdata_i                 ),
        .instr_err_i        (instr_err_i                   ),
        .data_req_o         (data_req_o                    ),
        .data_gnt_i         (data_gnt_i                    ),
        .data_rvalid_i      (data_rvalid_i                 ),
        .data_addr_o        (data_addr_o                   ),
        .data_be_o          (data_be_o                     ),
        .data_we_o          (data_we_o                     ),
        .data_wdata_o       (data_wdata_o                  ),
        .data_memtype_o     (data_memtype_o                ),
        .data_prot_o        (data_prot_o                   ),
        .data_dbg_o         (data_dbg_o                    ),
        .data_atop_o        (data_atop_o                   ),
        .data_rdata_i       (data_rdata_i                  ),
        .data_err_i         (data_err_i                    ),
        .data_exokay_i      (data_exokay_i                 ),*/
        .ahb_inst_req	    (ahb_inst_req		   ),
	.ahb_inst_resp	    (ahb_inst_resp		   ),
	.dbg_inst	    (ahb_inst_dbg		   ),
	.ahb_data_req	    (ahb_data_req		   ),
	.ahb_data_resp	    (ahb_data_resp		   ),
	.dbg_data	    (ahb_data_dbg		   ),
        .mcycle_o           (mcycle_o                      ),
        .xif_compressed_if  (i_xif_interface.cpu_compressed),
        .xif_issue_if       (i_xif_interface.cpu_issue     ),
        .xif_commit_if      (i_xif_interface.cpu_commit    ),
        .xif_mem_if         (i_xif_interface.cpu_mem       ),
        .xif_mem_result_if  (i_xif_interface.cpu_mem_result),
        .xif_result_if      (i_xif_interface.cpu_result    ),
        .irq_i              (irq_i                         ),
        .clic_irq_i         (clic_irq_i                    ),
        .clic_irq_id_i      (clic_irq_id_i                 ),
        .clic_irq_level_i   (clic_irq_level_i              ),
        .clic_irq_priv_i    (clic_irq_priv_i               ),
        .clic_irq_shv_i     (clic_irq_shv_i                ),
        .fencei_flush_req_o (fencei_flush_req_o            ),
        .fencei_flush_ack_i (fencei_flush_ack_i            ),
        .debug_req_i        (debug_req_i                   ),
        .debug_havereset_o  (debug_havereset_o             ),
        .debug_running_o    (debug_running_o               ),
        .debug_halted_o     (debug_halted_o                ),
        .fetch_enable_i     (fetch_enable_i                ),
        .core_sleep_o       (core_sleep_o                  )
    );

    cv32e40x_if_xif #(
        .X_NUM_RS   (X_NUM_RS   ), // Number of register file read ports that can be used by the eXtension interface
        .X_ID_WIDTH (X_ID_WIDTH ), // Width of ID field.
        .X_MEM_WIDTH(X_MEM_WIDTH), // Memory access width for loads/stores via the eXtension interface
        .X_RFR_WIDTH(X_RFR_WIDTH), // Register file read access width for the eXtension interface
        .X_RFW_WIDTH(X_RFW_WIDTH), // Register file write access width for the eXtension interface
        .X_MISA     (X_MISA     ), // MISA extensions implemented on the eXtension interface
        .X_ECS_XS   (X_ECS_XS   )  // Default value for mstatus.XS
    ) i_xif_interface ();

    coproc #(
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
    ) i_coproc (
        .clk_i            (clk_i                            ),
        .rst_an           (rst_ni                           ),
        .xif_compressed_if(i_xif_interface.coproc_compressed),
        .xif_issue_if     (i_xif_interface.coproc_issue     ),
        .xif_commit_if    (i_xif_interface.coproc_commit    ),
        .xif_mem_if       (i_xif_interface.coproc_mem       ),
        .xif_mem_result_if(i_xif_interface.coproc_mem_result),
        .xif_result_if    (i_xif_interface.coproc_result    )
    );

endmodule : core_coproc_top

//  ----------------------------------------------------------------------------
//                              Revision History
//  ----------------------------------------------------------------------------
//
//  $Log: core_coproc_top.sv.rca $
//  
//   Revision: 1.2 Mon Sep 16 12:43:55 2024 nxg06494
//   artf1167376 : Existing top module modified to pass along AHB signals
//  
//   Revision: 1.1 Mon Dec 18 19:01:42 2023 nxf99842
//   Release 2 - 18.12.2023
//  
//   Revision: 1.6 Tue Jul 18 15:00:37 2023 nxf99772
//   Output modifier in the processing chain
//  
//   Revision: 1.5 Wed Oct 12 00:54:42 2022 nxf87116
//   Added header and footer to the RTL files.