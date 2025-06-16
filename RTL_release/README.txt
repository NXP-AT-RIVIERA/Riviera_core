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
//  File            : $ README.txt $
//  Date            : $Date: Fri Sep 20 16:01:48 2024 $
//  Revision        : $Revision: 1.4 $
//
//  Description     : RIVIERA - CV32E40X RISC-V CPU DSP Co-Processor ReadMe file
//
//  Author          : Luca Lingardo / Slaven Vidakovic
//  IP Name         : RIVIERA (RISC-V ISA Extensions for RF Applications) DSP Co-Processor  
//  Project         : TRISTAN
//
//  ----------------------------------------------------------------------------

This folder contains the RTL SystemVerilog code of the developed coprocessor.
For more information on how to use the verification environment and the coprocessor,
refer to the wiki on Collabnet and to the provided documentation.

The top level module of the coprocessor only is "coproc.sv" and here its hierarchy is shown:
----------------------------------------------------------------------------
coproc
  + i_coproc_id_stage    (coproc_id_stage)
    + i_coproc_decoder    (coproc_decoder)
  + i_coproc_ex_stage    (coproc_ex_stage)
    + i_coproc_alu    (coproc_alu)
      + i_coproc_mac    (coproc_mac)
        + i_data_regs    (bidir_set)
          + i_bidir_bank    (bidir_bank)
        + i_selectors_regs    (selectors_set)
          + i_selectors_bank    (selectors_bank)
        + i_coeff_regs    (unidir_set)
          + i_unidir_bank    (unidir_bank)
        + i_rounding_regs    (register_set)
        + i_simd_regs    (register_set)
        + i_mac_arith    (mac_arith)
        + i_rounding_unit_nearest_even    (rounding_unit_nearest_even)
  + i_issue_fifo    (fifo_single_reg)
  + i_commit_fifo    (fifo_single_reg)
----------------------------------------------------------------------------
This is the module instantiated into the testbench-related files for the simulation.


As for as the synthesis, an additional top-level module (core_coproc_top.sv) has been defined and it contains
the core (cv32e40x_core) and the coprocessor (coproc), coupled through the eXtension Interface.
