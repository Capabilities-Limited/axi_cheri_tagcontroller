// TODO header

module llc_cache_wrapper #(
    parameter type tag_req_t = logic,
    parameter type tag_data_req_t = logic,
    parameter type tag_write_resp_t = logic,
    parameter type tag_read_resp_t = logic,
    parameter int unsigned AxiIdWidth = 64'd6,
    parameter int unsigned AxiAddrWidth = 64'd64,
    parameter int unsigned AxiDataWidth = 64'd64,
    parameter int unsigned AxiUserWidth = 64'd1,
    parameter type mem_req_t = logic,
    parameter type mem_resp_t = logic,
    parameter type axi_addr_t = logic,
    parameter type tagc_desc_t = logic
  ) (
    // Rising-edge clock of all ports.
    input logic clk_i,
    // Asynchronous reset, active low
    input logic rst_ni,

    // tag controller slave interfaces //
    /////////////////////////////////////
    // incoming tag read request descriptor
    input logic read_req_valid_i,
    output logic read_req_ready_o,
    input tag_req_t read_req_i,
    // incoming tag write request descriptor
    input logic write_req_valid_i,
    output logic write_req_ready_o,
    input tag_req_t write_req_i,
    // incoming write data
    input logic write_data_req_valid_i,
    output logic write_data_req_ready_o,
    input tag_data_req_t write_data_req_i,
    // outgoing write response
    output logic write_resp_valid_o,
    input logic write_resp_ready_i,
    output tag_write_resp_t write_resp_o,
    // outgoing read response
    output logic read_resp_valid_o,
    input logic read_resp_ready_i,
    output tag_read_resp_t read_resp_o,

    // ctrl interfaces //
    /////////////////////
    output logic isolate_o,
    input logic isolated_i,
    input axi_addr_t cached_start_addr_i,
    input axi_addr_t cached_end_addr_i,

    // tag store master interfaces //
    /////////////////////////////////
    output mem_req_t mem_req_o,
    input mem_resp_t mem_resp_i
  );

  localparam int unsigned CapSize = 128;
  localparam int unsigned DRAMMemBase = {64'h80000000};
  localparam int unsigned DRAMMemLength = {64'h40000000};
  localparam int unsigned TagCacheMemBase = {64'hA0000000};
  localparam int unsigned SetAssociativity = 32'd8;
  localparam int unsigned NumLines = 32'd128;
  localparam int unsigned NumBlocks = 32'd4;
  localparam int unsigned RegWidth = 64;
  `include "axi/typedef.svh"
  // Axi parameters are accumulated in a struct for further use.
  localparam axi_llc_pkg::llc_axi_cfg_t AxiCfg = axi_llc_pkg::llc_axi_cfg_t
  '{SlvPortIdWidth: AxiIdWidth, AddrWidthFull: AxiAddrWidth, DataWidthFull: AxiDataWidth};

  `include "axi_llc/typedef.svh"
  // configuration struct that has all the cache parameters included for the submodules
  localparam axi_llc_pkg::llc_cfg_t LLC_Cfg = axi_llc_pkg::llc_cfg_t
  '{

      SetAssociativity  : SetAssociativity,
      NumLines          : NumLines,
      NumBlocks         : NumBlocks,
      BlockSize         : AxiCfg.DataWidthFull,
      TagLength         :
      AxiCfg.AddrWidthFull
      - unsigned'(
      $clog2(NumLines)
      ) - unsigned'(
      $clog2(NumBlocks)
      ) - unsigned'(
      $clog2(AxiCfg.DataWidthFull / 32'd8)
      ),
      IndexLength       : unsigned'($clog2(NumLines)),
      BlockOffsetLength : unsigned'($clog2(NumBlocks)),
      ByteOffsetLength  : unsigned'($clog2(AxiCfg.DataWidthFull / 32'd8)),
      SPMLength         : SetAssociativity * NumLines * NumBlocks * (AxiCfg.DataWidthFull / 32'd8)
  };
  localparam axi_tagctrl_pkg::tagctrl_cfg_t Cfg = axi_tagctrl_pkg::tagctrl_cfg_t
  '{
      AxiIdWidth: AxiIdWidth,
      AxiAddrWidth: AxiAddrWidth,
      AxiDataWidth: AxiDataWidth,
      CapSize: CapSize,
      DRAMMemBase: DRAMMemBase,
      DRAMMemLength : DRAMMemLength,
      TagCacheMemBase: TagCacheMemBase,
      TagWFifoDepth: 4,
      TagAXFifoDepth: 4,
      TagRFifoDepth: 8,
      tagc_cfg: LLC_Cfg
  };
  localparam bit          PrintSramCfg     = 0;

  localparam type way_ind_t = logic [SetAssociativity-1:0];

  // definition of the lock signals
  typedef struct packed {
    logic [Cfg.tagc_cfg.IndexLength-1:0]      index;    // index of lock (cache-line)
    logic [Cfg.tagc_cfg.SetAssociativity-1:0] way_ind;  // way which is locked
  } lock_t;

  typedef logic [AxiCfg.SlvPortIdWidth-1:0] axi_slv_id_t;
  typedef logic [AxiCfg.SlvPortIdWidth:0] axi_mst_id_t;
  typedef logic [AxiCfg.DataWidthFull-1:0] axi_data_t;
  typedef logic [(AxiCfg.DataWidthFull/8)-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;

  // definitions of the miss counting struct
  typedef struct packed {
    axi_slv_id_t id;     // AXI id of the count operation
    logic        rw;     // 0:read, 1:write
    logic        valid;  // valid, equals enable
  } cnt_t;

  // definition of the structs that are between the units and the ways
  typedef struct packed {
    axi_llc_pkg::cache_unit_e                  cache_unit;  // which unit does the access
    logic [Cfg.tagc_cfg.SetAssociativity -1:0] way_ind;     // to which way the access goes
    logic [Cfg.tagc_cfg.IndexLength      -1:0] line_addr;   // cache line address
    logic [Cfg.tagc_cfg.BlockOffsetLength-1:0] blk_offset;  // block offset
    logic                                      we;          // write enable
    axi_data_t                                 data;        // input data
    axi_strb_t                                 strb;        // write enable (equals AXI strb)
    axi_data_t                                 bit_en;      // write enable (equals AXI strb)
  } way_inp_t;

  typedef struct packed {
    axi_llc_pkg::cache_unit_e cache_unit;  // which unit had the access
    axi_data_t                data;        // read data from the way
  } way_oup_t;

  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_chan_t, axi_addr_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_chan_t, axi_addr_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(slv_r_chan_t, axi_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(mst_r_chan_t, axi_data_t, axi_mst_id_t, axi_user_t)

  logic test_i;
  assign test_i = '0;
  // descriptor from the hit_miss_unit
  tag_req_t desc;
  logic hit_valid, hit_ready;
  logic miss_valid, miss_ready;

  // descriptor from the evict_unit to the refill_unit
  tag_req_t evict_desc;
  logic evict_desc_valid, evict_desc_ready;

  // descriptor from the refill_unit to the merge_unit
  tag_req_t refill_desc;
  logic refill_desc_valid, refill_desc_ready;

  // descriptor from the merge_unit to the write_unit
  tag_req_t write_desc;
  logic write_desc_valid, write_desc_ready;

  // descriptor from the merge_unit to the read_unit
  tag_req_t read_desc;
  logic read_desc_valid, read_desc_ready;

  // signals from the unit to the data_ways
  way_inp_t [3:0] to_way;
  logic     [3:0] to_way_valid;
  logic     [3:0] to_way_ready;

  // read signals from the data SRAMs
  way_oup_t evict_way_out, read_way_out;
  logic evict_way_out_valid, read_way_out_valid;
  logic evict_way_out_ready, read_way_out_ready;

  // count down signal from the merge_unit to the hit miss unit
  cnt_t cnt_down;

  // unlock signals from the read / write unit towards the hit miss unit
  // req signal depends on gnt signal!
  lock_t r_unlock, w_unlock;
  logic r_unlock_req, w_unlock_req;  // Not AXI valid / ready dependency
  logic r_unlock_gnt, w_unlock_gnt;  // Not AXI valid / ready dependency

  // global SPM lock signal
  logic [Cfg.tagc_cfg.SetAssociativity-1:0] flushed;

  // BIST from tag_store
  logic [Cfg.tagc_cfg.SetAssociativity-1:0] bist_res;
  logic                                     bist_valid;

  // global flush signals
  logic flush_recv;

  // descriptor from spill register to hit miss detect
  tagc_desc_t spill_desc;
  logic spill_valid, spill_ready;
  // signals between channel splitters and rw_arb_tree
  tagc_desc_t rw_desc;
  logic rw_desc_valid, rw_desc_ready;
  tagc_desc_t [2:0] ax_desc;
  logic       [2:0] ax_desc_valid;
  logic       [2:0] ax_desc_ready;
  assign ax_desc[0] = read_req_i;
  assign ax_desc_valid[0] = read_req_valid_i;
  assign read_req_ready_o = ax_desc_ready[0];
  assign ax_desc[1] = write_req_i;
  assign ax_desc_valid[1] = write_req_valid_i;
  assign write_req_ready_o = ax_desc_ready[1];

  // arbitration tree which funnels the flush, read and write descriptors together
  rr_arb_tree #(
      .NumIn    (32'd3),
      .DataType (tagc_desc_t),
      .AxiVldRdy(1'b1),
      .LockIn   (1'b1)
  ) i_rw_arb_tree (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .flush_i('0),
      .rr_i   ('0),
      .req_i  (ax_desc_valid),
      .gnt_o  (ax_desc_ready),
      .data_i (ax_desc),
      .gnt_i  (rw_desc_ready),
      .req_o  (rw_desc_valid),
      .data_o (rw_desc),
      .idx_o  ()
  );

  spill_register #(
      .T(tagc_desc_t)
  ) i_rw_spill (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .valid_i(rw_desc_valid),
      .ready_o(rw_desc_ready),
      .data_i (rw_desc),
      .valid_o(spill_valid),
      .ready_i(spill_ready),
      .data_o (spill_desc)
  );

  `include "register_interface/typedef.svh"
  // Define 64-bit register types for the AXI_LLC toplevel
  `AXI_LLC_TYPEDEF_ALL(axi_llc, logic [63:0], way_ind_t)
  `REG_BUS_TYPEDEF_ALL(conf, logic [31:0], logic [31:0], logic [3:0])

  // Generated register file interface variables
  axi_llc_reg_pkg::axi_llc_reg2hw_t config_reg2hw;
  axi_llc_reg_pkg::axi_llc_hw2reg_t config_hw2reg;

  // Variables for the AXI_LLC registers
  axi_llc_cfg_regs_d_t config_regs_d;
  axi_llc_cfg_regs_q_t config_regs_q;

  // Connecting the generated register file structs and the AXI_LLC register structs
  `AXI_LLC_ASSIGN_REGS_Q_FROM_REGBUS(config_regs_q, config_reg2hw)
  `AXI_LLC_ASSIGN_REGBUS_FROM_REGS_D(config_hw2reg, config_regs_d)

  // Generated 32-bit RegBus register file
  axi_llc_reg_top #(
      .reg_req_t(conf_req_t),
      .reg_rsp_t(conf_rsp_t)
  ) i_llc_config_regfile (
      .clk_i,
      .rst_ni,
      //.reg_req_i(conf_req_i),
      //.reg_rsp_o(conf_resp_o),

      // To HW
      .reg2hw(config_reg2hw),  // Write
      .hw2reg(config_hw2reg),  // Read

      // Config
      .devmode_i(1'b1)  // If 1, explicit error return for unmapped register access
  );
  typedef struct packed {
    // AXI4+ATOP specific descriptor signals
    axi_slv_id_t a_x_id;  // AXI ID from slave port
    axi_addr_t a_x_addr;  // memory address
    axi_pkg::len_t a_x_len;  // AXI burst length
    axi_pkg::size_t a_x_size;  // AXI burst size
    axi_pkg::burst_t a_x_burst;  // AXI burst type
    axi_pkg::resp_t x_resp;  // AXI response signal, for error propagation
    axi_pkg::len_t a_x_tag_len;  // Tag len request to the Tag Cache
    logic x_last;  // Last descriptor of a burst
    // Cache specific descriptor signals
    logic spm;  // this descriptor targets a SPM region in the cache
    logic rw;  // this descriptor is a read:0 or write:1 access
    logic [Cfg.tagc_cfg.SetAssociativity-1:0] way_ind;  // way we have to perform an operation on
    logic evict;  // evict what is standing in the line
    logic [Cfg.tagc_cfg.TagLength -1:0] evict_tag;  // tag for evicting a line
    logic refill;  // refill the cache line
    logic flush;  // flush this line, comes from config
  } tagctrl_desc_t;
  // define address rules from the address ports, propagate it throughout the design
  axi_pkg::xbar_rule_64_t cached_addr_rule;
  always_comb begin
    cached_addr_rule            = '0;
    cached_addr_rule.start_addr = cached_start_addr_i;
    cached_addr_rule.end_addr   = cached_end_addr_i;
  end
  // configuration, also has control over bypass logic and flush
  axi_tagctrl_config #(
      .Cfg          (Cfg),
      .AxiCfg       (AxiCfg),
      .RegWidth     (RegWidth),
      .conf_regs_d_t(axi_llc_cfg_regs_d_t),
      .conf_regs_q_t(axi_llc_cfg_regs_q_t),
      .desc_t       (tagctrl_desc_t),
      .rule_full_t  (axi_pkg::xbar_rule_64_t),
      .set_asso_t   (way_ind_t),
      .addr_full_t  (axi_addr_t),
      .PrintLlcCfg  (0)
  ) i_tagctrl_config (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),
      // Configuration registers
      .conf_regs_i(config_regs_q),
      .conf_regs_o(config_regs_d),
      .flushed_o         (flushed),
      .desc_o            (ax_desc[2]),
      .desc_valid_o      (ax_desc_valid[2]),
      .desc_ready_i      (ax_desc_ready[2]),
      // flush control signals to prevent new data in ax_cutter loading
      .tagctrl_isolate_o (isolate_o),
      .tagctrl_isolated_i(isolated_i),
      .aw_unit_busy_i    (aw_unit_busy),
      .ar_unit_busy_i    (ar_unit_busy),
      .flush_desc_recv_i (flush_recv),
      // BIST input
      .bist_res_i        (bist_res),
      .bist_valid_i      (bist_valid),
      // address rules for bypass selection
      .axi_cached_rule_i (cached_addr_rule),
      .axi_spm_rule_i    ('0)
  );

  axi_llc_hit_miss #(
      .Cfg         (Cfg.tagc_cfg),
      .AxiCfg      (AxiCfg),
      .desc_t      (tag_req_t),
      .lock_t      (lock_t),
      .cnt_t       (cnt_t),
      .way_ind_t   (way_ind_t),
      .PrintSramCfg(PrintSramCfg)
  ) i_hit_miss_unit (
      .clk_i,
      .rst_ni,
      .test_i,
      .desc_i        (spill_desc),
      .valid_i       (spill_valid),
      .ready_o       (spill_ready),
      .desc_o        (desc),
      .miss_valid_o  (miss_valid),
      .miss_ready_i  (miss_ready),
      .hit_valid_o   (hit_valid),
      .hit_ready_i   (hit_ready),
      .spm_lock_i    (1'b0),
      .flushed_i     (flushed),
      .w_unlock_i    (w_unlock),
      .w_unlock_req_i(w_unlock_req),
      .w_unlock_gnt_o(w_unlock_gnt),
      .r_unlock_i    (r_unlock),
      .r_unlock_req_i(r_unlock_req),
      .r_unlock_gnt_o(r_unlock_gnt),
      .cnt_down_i    (cnt_down),
      .bist_res_o    (bist_res),
      .bist_valid_o  (bist_valid)
  );

  axi_llc_evict_unit #(
      .Cfg      (Cfg.tagc_cfg),
      .AxiCfg   (AxiCfg),
      .desc_t   (tag_req_t),
      .way_inp_t(way_inp_t),
      .way_oup_t(way_oup_t),
      .aw_chan_t(slv_aw_chan_t),
      .w_chan_t (w_chan_t),
      .b_chan_t (slv_b_chan_t)
  ) i_evict_unit (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .test_i           (test_i),
      .desc_i           (desc),
      .desc_valid_i     (miss_valid),
      .desc_ready_o     (miss_ready),
      .desc_o           (evict_desc),
      .desc_valid_o     (evict_desc_valid),
      .desc_ready_i     (evict_desc_ready),
      .way_inp_o        (to_way[axi_llc_pkg::EvictUnit]),
      .way_inp_valid_o  (to_way_valid[axi_llc_pkg::EvictUnit]),
      .way_inp_ready_i  (to_way_ready[axi_llc_pkg::EvictUnit]),
      .way_out_i        (evict_way_out),
      .way_out_valid_i  (evict_way_out_valid),
      .way_out_ready_o  (evict_way_out_ready),
      .aw_chan_mst_o    (mem_req_o.aw),
      .aw_chan_valid_o  (mem_req_o.aw_valid),
      .aw_chan_ready_i  (mem_resp_i.aw_ready),
      .w_chan_mst_o     (mem_req_o.w),
      .w_chan_valid_o   (mem_req_o.w_valid),
      .w_chan_ready_i   (mem_resp_i.w_ready),
      .b_chan_mst_i     (mem_resp_i.b),
      .b_chan_valid_i   (mem_resp_i.b_valid),
      .b_chan_ready_o   (mem_req_o.b_ready),
      .flush_desc_recv_o(flush_recv)
  );

  // plug in refill unit for test
  axi_llc_refill_unit #(
      .Cfg      (Cfg.tagc_cfg),
      .AxiCfg   (AxiCfg),
      .desc_t   (tag_req_t),
      .way_inp_t(way_inp_t),
      .ar_chan_t(slv_ar_chan_t),
      .r_chan_t (slv_r_chan_t)
  ) i_refill_unit (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .test_i         (test_i),
      .desc_i         (evict_desc),
      .desc_valid_i   (evict_desc_valid),
      .desc_ready_o   (evict_desc_ready),
      .desc_o         (refill_desc),
      .desc_valid_o   (refill_desc_valid),
      .desc_ready_i   (refill_desc_ready),
      .way_inp_o      (to_way[axi_llc_pkg::RefilUnit]),
      .way_inp_valid_o(to_way_valid[axi_llc_pkg::RefilUnit]),
      .way_inp_ready_i(to_way_ready[axi_llc_pkg::RefilUnit]),
      .ar_chan_mst_o  (mem_req_o.ar),
      .ar_chan_valid_o(mem_req_o.ar_valid),
      .ar_chan_ready_i(mem_resp_i.ar_ready),
      .r_chan_mst_i   (mem_resp_i.r),
      .r_chan_valid_i (mem_resp_i.r_valid),
      .r_chan_ready_o (mem_req_o.r_ready)
  );

  // merge unit
  axi_llc_merge_unit #(
      .Cfg   (Cfg.tagc_cfg),
      .desc_t(tag_req_t),
      .cnt_t (cnt_t)
  ) i_merge_unit (
      .clk_i,
      .rst_ni,
      .bypass_desc_i (desc),
      .bypass_valid_i(hit_valid),
      .bypass_ready_o(hit_ready),
      .refill_desc_i (refill_desc),
      .refill_valid_i(refill_desc_valid),
      .refill_ready_o(refill_desc_ready),
      .read_desc_o   (read_desc),
      .read_valid_o  (read_desc_valid),
      .read_ready_i  (read_desc_ready),
      .write_desc_o  (write_desc),
      .write_valid_o (write_desc_valid),
      .write_ready_i (write_desc_ready),
      .cnt_down_o    (cnt_down)
  );

  // write unit
  axi_tagc_write_unit #(
      .Cfg      (Cfg.tagc_cfg),
      .AxiCfg   (AxiCfg),
      .desc_t   (tag_req_t),
      .way_inp_t(way_inp_t),
      .lock_t   (lock_t),
      .w_chan_t (tag_data_req_t),
      .b_chan_t (slv_b_chan_t)
  ) i_write_unit (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .test_i         (test_i),
      .desc_i         (write_desc),
      .desc_valid_i   (write_desc_valid),
      .desc_ready_o   (write_desc_ready),
      .w_chan_slv_i   (write_data_req_i),
      .w_chan_valid_i (write_data_req_valid_i),
      .w_chan_ready_o (write_data_req_ready_o),
      .b_chan_slv_o   (write_resp_o),
      .b_chan_valid_o (write_resp_valid_o),
      .b_chan_ready_i (write_resp_ready_i),
      .way_inp_o      (to_way[axi_llc_pkg::WChanUnit]),
      .way_inp_valid_o(to_way_valid[axi_llc_pkg::WChanUnit]),
      .way_inp_ready_i(to_way_ready[axi_llc_pkg::WChanUnit]),
      .w_unlock_o     (w_unlock),
      .w_unlock_req_o (w_unlock_req),
      .w_unlock_gnt_i (w_unlock_gnt)
  );

  // read unit
  axi_tagc_read_unit #(
      .Cfg       (Cfg.tagc_cfg),
      .AxiCfg    (AxiCfg),
      .desc_t    (tag_req_t),
      .way_inp_t (way_inp_t),
      .way_oup_t (way_oup_t),
      .lock_t    (lock_t),
      .tagc_inp_t(tag_read_resp_t)
  ) i_read_unit (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .test_i         (test_i),
      .desc_i         (read_desc),
      .desc_valid_i   (read_desc_valid),
      .desc_ready_o   (read_desc_ready),
      .r_inp_slv_o    (read_resp_o),
      .r_inp_valid_o  (read_resp_valid_o),
      .r_inp_ready_i  (read_resp_ready_i),
      .way_inp_o      (to_way[axi_llc_pkg::RChanUnit]),
      .way_inp_valid_o(to_way_valid[axi_llc_pkg::RChanUnit]),
      .way_inp_ready_i(to_way_ready[axi_llc_pkg::RChanUnit]),
      .way_out_i      (read_way_out),
      .way_out_valid_i(read_way_out_valid),
      .way_out_ready_o(read_way_out_ready),
      .r_unlock_o     (r_unlock),
      .r_unlock_req_o (r_unlock_req),
      .r_unlock_gnt_i (r_unlock_gnt)
  );

  // data storage
  axi_tagctrl_ways #(
      .Cfg         (Cfg.tagc_cfg),
      .AxiCfg      (AxiCfg),
      .way_inp_t   (way_inp_t),
      .way_oup_t   (way_oup_t),
      .PrintSramCfg(PrintSramCfg)
  ) i_llc_ways (
      .clk_i                (clk_i),
      .rst_ni               (rst_ni),
      .test_i               (test_i),
      .way_inp_i            (to_way),
      .way_inp_valid_i      (to_way_valid),
      .way_inp_ready_o      (to_way_ready),
      .evict_way_out_o      (evict_way_out),
      .evict_way_out_valid_o(evict_way_out_valid),
      .evict_way_out_ready_i(evict_way_out_ready),
      .read_way_out_o       (read_way_out),
      .read_way_out_valid_o (read_way_out_valid),
      .read_way_out_ready_i (read_way_out_ready)
  );

endmodule
