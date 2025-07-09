// TODO header

module hpdcache_tag_wrapper #(
    parameter type tag_req_t = logic,
    parameter type tag_w_data_req_t = logic,
    parameter type tag_w_resp_t = logic,
    parameter type tag_r_resp_t = logic,
    parameter type mem_req_t = logic,
    parameter type mem_resp_t = logic
  ) (
    // Rising-edge clock of all ports.
    input logic clk_i,
    // Asynchronous reset, active low
    input logic rst_ni,

    // tag controller interfaces //
    ///////////////////////////////
    // incoming tag request descriptor
    input logic tag_req_valid_i,
    output logic tag_req_ready_o,
    input tag_req_t tag_req_i,
    // incoming write data
    input logic tag_w_data_req_valid_i,
    output logic tag_w_data_req_ready_o,
    input tag_w_data_req_t tag_w_data_req_i,
    // outgoing write response
    output logic tag_w_resp_valid_o,
    input logic tag_w_resp_ready_i,
    output tag_w_resp_t tag_w_resp_o,
    // outgoing read response
    output logic tag_r_resp_valid_o,
    input logic tag_r_resp_ready_i,
    output tag_r_resp_t tag_r_resp_o,

    // tag store memory interfaces //
    /////////////////////////////////
    output mem_req_t mem_req_o,
    input mem_resp_t mem_resp_i
  );

  function automatic hpdcache_pkg::hpdcache_user_cfg_t hpdcacheSetConfig();
    hpdcache_pkg::hpdcache_user_cfg_t userCfg;
    userCfg.nRequesters = 1;
    userCfg.paWidth = 49;
    userCfg.wordWidth = 1;
    userCfg.sets = 64;
    userCfg.ways = 8;
    userCfg.clWords = 512;
    userCfg.reqWords = 4;
    userCfg.reqTransIdWidth = 6;
    userCfg.reqSrcIdWidth = 3;  // Up to 8 requesters
    userCfg.victimSel = hpdcache_pkg::HPDCACHE_VICTIM_PLRU;
    userCfg.dataWaysPerRamWord = 2;
    userCfg.dataSetsPerRam = 64;
    userCfg.dataRamByteEnable = 1'b1;
    userCfg.accessWords = 64;
    userCfg.mshrSets = 32;
    userCfg.mshrWays = 2;
    userCfg.mshrWaysPerRamWord = 2;
    userCfg.mshrSetsPerRam = 32;
    userCfg.mshrRamByteEnable = 1'b1;
    userCfg.mshrUseRegbank = 1;
    userCfg.cbufEntries = 8;
    userCfg.refillCoreRspFeedthrough = 1'b1;
    userCfg.refillFifoDepth = 2;
    userCfg.wbufDirEntries = 8;
    userCfg.wbufDataEntries = 4;
    userCfg.wbufWords = 2;
    userCfg.wbufTimecntWidth = 3;
    userCfg.rtabEntries = 4;
    userCfg.flushEntries = 4;
    userCfg.flushFifoDepth = 2;
    userCfg.memAddrWidth = 64;
    userCfg.memIdWidth = 4;
    userCfg.memDataWidth = 512;
    userCfg.wtEn = 1;
    userCfg.wbEn = 1;
    userCfg.lowLatency = 0;
    return userCfg;
  endfunction

  localparam hpdcache_pkg::hpdcache_user_cfg_t HPDcacheUserCfg = hpdcacheSetConfig();
  localparam hpdcache_pkg::hpdcache_cfg_t HPDcacheCfg = hpdcache_pkg::hpdcacheBuildConfig(
      HPDcacheUserCfg
  );
  //      Request Interface Definitions
  //      {{{
  localparam type wbuf_timecnt_t = logic unsigned [HPDcacheCfg.u.wbufTimecntWidth-1:0];
  localparam type hpdcache_tag_t = logic [HPDcacheCfg.tagWidth-1:0];
  localparam type hpdcache_data_word_t = logic [HPDcacheCfg.u.wordWidth-1:0];
  localparam type hpdcache_data_be_t = logic [(HPDcacheCfg.u.wordWidth+8-1)/8-1:0];
  localparam type hpdcache_req_offset_t = logic [HPDcacheCfg.reqOffsetWidth-1:0];
  localparam type hpdcache_req_data_t = hpdcache_data_word_t [HPDcacheCfg.u.reqWords-1:0];
  localparam type hpdcache_req_be_t = hpdcache_data_be_t [HPDcacheCfg.u.reqWords-1:0];
  localparam type hpdcache_req_sid_t = logic [HPDcacheCfg.u.reqSrcIdWidth-1:0];
  localparam type hpdcache_req_tid_t = logic [HPDcacheCfg.u.reqTransIdWidth-1:0];
  localparam type hpdcache_req_t =
          `HPDCACHE_DECL_REQ_T(
                  hpdcache_req_offset_t,
                  hpdcache_req_data_t,
                  hpdcache_req_be_t,
                  hpdcache_req_sid_t,
                  hpdcache_req_tid_t,
                  hpdcache_tag_t);
  localparam type hpdcache_rsp_t =
          `HPDCACHE_DECL_RSP_T(
                  hpdcache_req_data_t,
                  hpdcache_req_sid_t,
                  hpdcache_req_tid_t);
  localparam type hpdcache_mem_addr_t = logic [HPDcacheCfg.u.memAddrWidth-1:0];
  localparam type hpdcache_mem_id_t   = logic [HPDcacheCfg.u.memIdWidth-1:0];
  localparam type hpdcache_mem_data_t = logic [HPDcacheCfg.u.memDataWidth-1:0];
  localparam type hpdcache_mem_be_t   = logic [HPDcacheCfg.u.memDataWidth/8-1:0];

  //  Declaration of internal types
  //  {{{
  `HPDCACHE_TYPEDEF_MEM_REQ_T(hpdcache_mem_req_t, hpdcache_mem_addr_t, hpdcache_mem_id_t);
  `HPDCACHE_TYPEDEF_MEM_RESP_R_T(hpdcache_mem_resp_r_t, hpdcache_mem_id_t, hpdcache_mem_data_t);
  `HPDCACHE_TYPEDEF_MEM_REQ_W_T(hpdcache_mem_req_w_t, hpdcache_mem_data_t, hpdcache_mem_be_t);
  `HPDCACHE_TYPEDEF_MEM_RESP_W_T(hpdcache_mem_resp_w_t, hpdcache_mem_id_t);
  //  }}}

  // convert descriptor to hpdcache request
  function automatic hpdcache_req_t tagc_desc_to_hpdcache_req(tag_req_t desc);
    hpdcache_req_t req;
    req.addr_offset = 0;
    req.wdata = 0;
    req.op = desc.rw ? hpdcache_pkg::HPDCACHE_REQ_STORE : hpdcache_pkg::HPDCACHE_REQ_LOAD;
    req.be = 0;
    req.size = 0;
    req.sid = 0;
    req.tid = 0;
    req.need_rsp = 0;
    req.phys_indexed = 0;
    req.addr_tag = 0;
    req.pma = 0;
    return req;
  endfunction

  hpdcache #(
      .HPDcacheCfg          (HPDcacheCfg),
      .wbuf_timecnt_t       (wbuf_timecnt_t),
      .hpdcache_tag_t       (hpdcache_tag_t),
      .hpdcache_data_word_t (hpdcache_data_word_t),
      .hpdcache_data_be_t   (hpdcache_data_be_t),
      .hpdcache_req_offset_t(hpdcache_req_offset_t),
      .hpdcache_req_data_t  (hpdcache_req_data_t),
      .hpdcache_req_be_t    (hpdcache_req_be_t),
      .hpdcache_req_sid_t   (hpdcache_req_sid_t),
      .hpdcache_req_tid_t   (hpdcache_req_tid_t),
      .hpdcache_req_t       (hpdcache_req_t),
      .hpdcache_rsp_t       (hpdcache_rsp_t),
      .hpdcache_mem_addr_t  (hpdcache_mem_addr_t),
      .hpdcache_mem_id_t    (hpdcache_mem_id_t),
      .hpdcache_mem_data_t  (hpdcache_mem_data_t),
      .hpdcache_mem_be_t    (hpdcache_mem_be_t),
      .hpdcache_mem_req_t   (hpdcache_mem_req_t),
      .hpdcache_mem_req_w_t (hpdcache_mem_req_w_t),
      .hpdcache_mem_resp_r_t(hpdcache_mem_resp_r_t),
      .hpdcache_mem_resp_w_t(hpdcache_mem_resp_w_t)
  ) i_hpdcache (
      .clk_i,
      .rst_ni,

      .wbuf_flush_i('0),

      .core_req_valid_i('{default: '0}),
      .core_req_ready_o(),
      .core_req_i      ('{default: '0}),
      .core_req_abort_i('{default: '0}),
      .core_req_tag_i  ('{default: '0}),
      .core_req_pma_i  ('{default: '0}),

      .core_rsp_valid_o(),
      .core_rsp_o      (),

      .mem_req_read_ready_i('0),
      .mem_req_read_valid_o(),
      .mem_req_read_o      (),

      .mem_resp_read_ready_o(),
      .mem_resp_read_valid_i('0),
      .mem_resp_read_i      ('0),

      .mem_req_write_ready_i('0),
      .mem_req_write_valid_o(),
      .mem_req_write_o      (),

      .mem_req_write_data_ready_i('0),
      .mem_req_write_data_valid_o(),
      .mem_req_write_data_o      (),

      .mem_resp_write_ready_o(),
      .mem_resp_write_valid_i('0),
      .mem_resp_write_i      ('0),

      .evt_cache_write_miss_o(),
      .evt_cache_read_miss_o (),
      //.evt_uncached_req_o    (  /* unused */),
      //.evt_cmo_req_o         (  /* unused */),
      //.evt_write_req_o       (  /* unused */),
      //.evt_read_req_o        (  /* unused */),
      //.evt_prefetch_req_o    (  /* unused */),
      //.evt_req_on_hold_o     (  /* unused */),
      //.evt_rtab_rollback_o   (  /* unused */),
      //.evt_stall_refill_o    (  /* unused */),
      //.evt_stall_o           (  /* unused */),
      .evt_uncached_req_o    (),
      .evt_cmo_req_o         (),
      .evt_write_req_o       (),
      .evt_read_req_o        (),
      .evt_prefetch_req_o    (),
      .evt_req_on_hold_o     (),
      .evt_rtab_rollback_o   (),
      .evt_stall_refill_o    (),
      .evt_stall_o           (),

      .wbuf_empty_o(),

      .cfg_enable_i                       ('0),
      .cfg_wbuf_threshold_i               (3'd2),
      .cfg_wbuf_reset_timecnt_on_write_i  (1'b1),
      .cfg_wbuf_sequential_waw_i          (1'b0),
      .cfg_wbuf_inhibit_write_coalescing_i(1'b0),
      .cfg_prefetch_updt_plru_i           (1'b1),
      .cfg_error_on_cacheable_amo_i       (1'b0),
      .cfg_rtab_single_entry_i            (1'b0),
      .cfg_default_wb_i                   (1'b0)
  );

endmodule
