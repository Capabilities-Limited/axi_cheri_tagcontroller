// TODO header

module hpdcache_wrapper #(
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
    parameter type axi_addr_t = logic [AxiAddrWidth-1:0]
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

  // configurations and types
  //////////////////////////////////////////////////////////////////////////////

  function automatic hpdcache_pkg::hpdcache_user_cfg_t hpdcacheSetConfig();
    hpdcache_pkg::hpdcache_user_cfg_t userCfg;
    userCfg.nRequesters = 2;
    userCfg.paWidth = 49;
    userCfg.wordWidth = 1;
    userCfg.sets = 64;
    userCfg.ways = 8;
    userCfg.clWords = 512;
    userCfg.reqWords = 4;
    userCfg.reqTransIdWidth = 6;
    userCfg.reqSrcIdWidth = 2;  // Up to 4 requesters
    userCfg.victimSel = hpdcache_pkg::HPDCACHE_VICTIM_PLRU;
    userCfg.dataWaysPerRamWord = 2;
    userCfg.dataSetsPerRam = 64;
    userCfg.dataRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
    userCfg.accessWords = 64;
    userCfg.mshrSets = 32;
    userCfg.mshrWays = 2;
    userCfg.mshrWaysPerRamWord = 2;
    userCfg.mshrSetsPerRam = 32;
    userCfg.mshrRamByteEnable = 1'b1; // XXX TODO check the 1'b0 option
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
    userCfg.wtEn = 1'b0;
    userCfg.wbEn = 1'b1;
    userCfg.lowLatency = 1'b0;
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

  // tag controller <-> hpdcache converters
  //////////////////////////////////////////////////////////////////////////////

  // convert read descriptor to hpdcache request
  function automatic hpdcache_req_t read_req_to_hpdcache_req(tag_req_t desc);

    hpdcache_req_t req;

    // make sure we are receiving a read request
    assert(!desc.rw);
    // make sure we have a single flit transaction
    assert(desc.a_x_len == 0);
    assert(desc.x_last == 1'b1);
    // TODO check remaining descriptor fields
    //axi_pkg::burst_t a_x_burst;  // AXI burst type
    //logic a_x_lock;  // AXI lock signal
    //axi_pkg::cache_t a_x_cache;  // AXI cache signal
    //axi_pkg::prot_t a_x_prot;  // AXI protection signal
    //axi_pkg::resp_t x_resp;  // AXI response signal, for error propagation
    //logic x_last;  // Last descriptor of a burst
    //// Cache specific descriptor signals
    //logic spm;  // this descriptor targets a SPM region in the cache
    //logic rw;  // this descriptor is a read:0 or write:1 access
    //logic [Cfg.tagc_cfg.SetAssociativity-1:0] way_ind;  // way we have to perform an operation on
    //logic evict;  // evict what is standing in the line
    //logic [Cfg.tagc_cfg.TagLength -1:0] evict_tag;  // tag for evicting a line
    //logic refill;  // refill the cache line
    //logic flush;  // flush this line, comes from config

    // prepare hpdcache req
    req.addr_offset = desc.a_x_addr[0 +: HPDcacheCfg.reqOffsetWidth];
    req.wdata = 0; // read req, no data
    req.op = hpdcache_pkg::HPDCACHE_REQ_LOAD;
    req.be = 0; // read req, no byte enable
    req.size = desc.a_x_size;
    req.sid = 0; // read requestor port idx
    req.tid = desc.a_x_id;
    req.need_rsp = 1'b1;
    req.phys_indexed = 1'b1;
    req.addr_tag = desc.a_x_addr[HPDcacheCfg.reqOffsetWidth +: HPDcacheCfg.tagWidth];
    req.pma.uncacheable = 1'b0;
    req.pma.io = 1'b0;
    req.pma.wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_WB;
    //req.pma.wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_WT;
    return req;

  endfunction

  // convert write descriptor to hpdcache request
  function automatic hpdcache_req_t write_req_to_hpdcache_req(tag_req_t desc, tag_data_req_t wdata);

    hpdcache_req_t req;

    // make sure we are receiving a write request
    assert(desc.rw);
    // make sure we have a single flit transaction
    assert(desc.a_x_len == 0);
    assert(desc.x_last == 1'b1);
    // TODO check remaining descriptor fields
    //axi_pkg::burst_t a_x_burst;  // AXI burst type
    //logic a_x_lock;  // AXI lock signal
    //axi_pkg::cache_t a_x_cache;  // AXI cache signal
    //axi_pkg::prot_t a_x_prot;  // AXI protection signal
    //axi_pkg::resp_t x_resp;  // AXI response signal, for error propagation
    //logic x_last;  // Last descriptor of a burst
    //// Cache specific descriptor signals
    //logic spm;  // this descriptor targets a SPM region in the cache
    //logic rw;  // this descriptor is a read:0 or write:1 access
    //logic [Cfg.tagc_cfg.SetAssociativity-1:0] way_ind;  // way we have to perform an operation on
    //logic evict;  // evict what is standing in the line
    //logic [Cfg.tagc_cfg.TagLength -1:0] evict_tag;  // tag for evicting a line
    //logic refill;  // refill the cache line
    //logic flush;  // flush this line, comes from config

    // prepare hpdcache req
    req.addr_offset = desc.a_x_addr[0 +: HPDcacheCfg.reqOffsetWidth];
    req.wdata = wdata.data;
    req.op = hpdcache_pkg::HPDCACHE_REQ_STORE;
    req.be = wdata.bit_en; // XXX TODO verify what to do with be Vs bit_en
    req.size = desc.a_x_size;
    req.sid = 1; // write requestor port idx
    req.tid = desc.a_x_id;
    req.need_rsp = 1'b1;
    req.phys_indexed = 1'b1;
    req.addr_tag = desc.a_x_addr[HPDcacheCfg.reqOffsetWidth +: HPDcacheCfg.tagWidth];
    req.pma.uncacheable = 1'b0;
    req.pma.io = 1'b0;
    req.pma.wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_WB;
    //req.pma.wr_policy_hint = hpdcache_pkg::HPDCACHE_WR_POLICY_WT;
    return req;
  endfunction

  // convert hpdcache read response to tag controller read response
  function automatic tag_read_resp_t hpdcache_read_rsp_to_tagctrl_read_rsp(hpdcache_rsp_t rsp);
    tag_read_resp_t resp;
    resp.id = rsp.tid;
    resp.data = rsp.rdata;
    resp.resp = (rsp.error || rsp.aborted) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    resp.last = 1'b1;
    return resp;
  endfunction

  function automatic tag_write_resp_t hpdcache_write_rsp_to_tagctrl_write_rsp(hpdcache_rsp_t rsp);
    tag_write_resp_t resp;
    resp.id = rsp.tid;
    resp.resp = (rsp.error || rsp.aborted) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    resp.user = 1'b0; // unused
    return resp;
  endfunction

  // hpdcache <-> mem converters
  //////////////////////////////////////////////////////////////////////////////
  /////////////////////////////
  // Axi channel definitions //
  /////////////////////////////
  localparam int unsigned AxiStrbWidth = AxiDataWidth / 32'd8;
  typedef logic [AxiIdWidth-1:0] axi_id_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiStrbWidth-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  `AXI_TYPEDEF_AW_CHAN_T(axi_aw_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(axi_w_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(axi_b_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(axi_ar_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_r_t, axi_data_t, axi_id_t, axi_user_t)

  logic mem_req_read_ready;
  logic mem_req_read_valid;
  hpdcache_mem_req_t mem_req_read;
  logic mem_resp_read_ready;
  logic mem_resp_read_valid;
  hpdcache_mem_resp_r_t mem_resp_read;
  logic mem_req_write_ready;
  logic mem_req_write_valid;
  hpdcache_mem_req_t mem_req_write;
  logic mem_req_write_data_ready;
  logic mem_req_write_data_valid;
  hpdcache_mem_req_w_t mem_req_write_data;
  logic mem_resp_write_ready;
  logic mem_resp_write_valid;
  hpdcache_mem_resp_w_t mem_resp_write;

  hpdcache_mem_to_axi_read #(
    .hpdcache_mem_req_t(hpdcache_mem_req_t),
    .hpdcache_mem_resp_r_t(hpdcache_mem_resp_r_t),
    .ar_chan_t(axi_ar_t),
    .r_chan_t(axi_r_t)
  ) i_hpdcache_mem_to_axi_read (
    .req_ready_o(mem_req_read_ready),
    .req_valid_i(mem_req_read_valid),
    .req_i(mem_req_read),
    .resp_ready_i(mem_resp_read_ready),
    .resp_valid_o(mem_resp_read_valid),
    .resp_o(mem_resp_read),
    .axi_ar_valid_o(mem_req_o.ar_valid),
    .axi_ar_o(mem_req_o.ar),
    .axi_ar_ready_i(mem_resp_i.ar_ready),
    .axi_r_valid_i(mem_resp_i.r_valid),
    .axi_r_i(mem_resp_i.r),
    .axi_r_ready_o(mem_req_o.r_ready)
  );
  hpdcache_mem_to_axi_write #(
    .hpdcache_mem_req_t   (hpdcache_mem_req_t),
    .hpdcache_mem_req_w_t (hpdcache_mem_req_w_t),
    .hpdcache_mem_resp_w_t(hpdcache_mem_resp_w_t),
    .aw_chan_t(axi_aw_t),
    .w_chan_t(axi_w_t),
    .b_chan_t(axi_b_t)
  ) i_hpdcache_mem_to_axi_write (
    .req_ready_o(mem_req_write_ready),
    .req_valid_i(mem_req_write_valid),
    .req_i(mem_req_write),
    .req_data_ready_o(mem_req_write_data_ready),
    .req_data_valid_i(mem_req_write_data_valid),
    .req_data_i(mem_req_write_data),
    .resp_ready_i(mem_resp_write_ready),
    .resp_valid_o(mem_resp_write_valid),
    .resp_o(mem_resp_write),
    .axi_aw_valid_o(mem_req_o.aw_valid),
    .axi_aw_o(mem_req_o.aw),
    .axi_aw_ready_i(mem_resp_i.aw_ready),
    .axi_w_valid_o(mem_req_o.w_valid),
    .axi_w_o(mem_req_o.w),
    .axi_w_ready_i(mem_resp_i.w_ready),
    .axi_b_valid_i(mem_resp_i.b_valid),
    .axi_b_i(mem_resp_i.b),
    .axi_b_ready_o(mem_req_o.b_ready)
  );

  // connect the internal hpdcache instance
  //////////////////////////////////////////////////////////////////////////////

  // cache requestors req and resp
  // reqs...
  logic cache_req_valid [HPDcacheCfg.u.nRequesters];
  logic cache_req_ready [HPDcacheCfg.u.nRequesters];
  hpdcache_req_t cache_req [HPDcacheCfg.u.nRequesters];

  assign cache_req_valid[0] = read_req_valid_i;
  assign read_req_ready_o = cache_req_ready[0];
  assign cache_req[0] = read_req_to_hpdcache_req(read_req_i);

  logic write_req_valid;
  assign write_req_valid = write_req_valid_i & write_data_req_valid_i;
  assign cache_req_valid[1] = write_req_valid;
  assign write_req_ready_o = write_req_valid && cache_req_ready[1];
  assign write_data_req_ready_o = write_req_valid && cache_req_ready[1];
  assign cache_req[1] = write_req_to_hpdcache_req(write_req_i, write_data_req_i);

  // resps...
  logic cache_rsp_valid [HPDcacheCfg.u.nRequesters];
  hpdcache_rsp_t cache_rsp [HPDcacheCfg.u.nRequesters];

  assign read_resp_valid_o = cache_rsp_valid[0];
  assign read_resp_o = hpdcache_read_rsp_to_tagctrl_read_rsp(cache_rsp[0]);
  assign write_resp_valid_o = cache_rsp_valid[1];
  assign write_resp_o = hpdcache_write_rsp_to_tagctrl_write_rsp(cache_rsp[1]);

  // internal hpdcache instance
  //////////////////////////////////////////////////////////////////////////////

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

      .core_req_valid_i(cache_req_valid),
      .core_req_ready_o(cache_req_ready),
      .core_req_i      (cache_req),
      .core_req_abort_i('{default: '0}), // no req abortion
      .core_req_tag_i  ('{default: '0}), // unused as physical indexing is used
      .core_req_pma_i  ('{default: '0}), // unused as physical indexing is used

      .core_rsp_valid_o(cache_rsp_valid),
      .core_rsp_o      (cache_rsp),

      .mem_req_read_ready_i(mem_req_read_ready),
      .mem_req_read_valid_o(mem_req_read_valid),
      .mem_req_read_o(mem_req_read),

      .mem_resp_read_ready_o(mem_resp_read_ready),
      .mem_resp_read_valid_i(mem_resp_read_valid),
      .mem_resp_read_i(mem_resp_read),

      .mem_req_write_ready_i(mem_req_write_ready),
      .mem_req_write_valid_o(mem_req_write_valid),
      .mem_req_write_o(mem_req_write),

      .mem_req_write_data_ready_i(mem_req_write_data_ready),
      .mem_req_write_data_valid_o(mem_req_write_data_valid),
      .mem_req_write_data_o(mem_req_write_data),

      .mem_resp_write_ready_o(mem_resp_write_ready),
      .mem_resp_write_valid_i(mem_resp_write_valid),
      .mem_resp_write_i(mem_resp_write),

      .wbuf_flush_i('0),
      .wbuf_empty_o(),

      // events unused
      //.evt_cache_write_miss_o(),
      //.evt_cache_read_miss_o (),
      //.evt_uncached_req_o    (),
      //.evt_cmo_req_o         (),
      //.evt_write_req_o       (),
      //.evt_read_req_o        (),
      //.evt_prefetch_req_o    (),
      //.evt_req_on_hold_o     (),
      //.evt_rtab_rollback_o   (),
      //.evt_stall_refill_o    (),
      //.evt_stall_o           (),

      .cfg_enable_i                       (1'b1), // enable the cache
      .cfg_wbuf_threshold_i               (3'd2),
      .cfg_wbuf_reset_timecnt_on_write_i  (1'b1),
      .cfg_wbuf_sequential_waw_i          (1'b0),
      .cfg_wbuf_inhibit_write_coalescing_i(1'b0),
      .cfg_prefetch_updt_plru_i           (1'b1),
      .cfg_error_on_cacheable_amo_i       (1'b0),
      .cfg_rtab_single_entry_i            (1'b0),
      .cfg_default_wb_i                   (1'b0)
  );

  // pragma translate_off
`ifndef VERILATOR
  initial begin : proc_assert_axi_params
    // check the address rule fields for the right size
    axi_start_addr :
    assert ($bits(cached_addr_rule.start_addr) == AxiAddrWidth)
    else $fatal(1, "rule_t.start_addr field does not match AxiAddrWidth!");
    axi_end_addr :
    assert ($bits(cached_addr_rule.end_addr) == AxiAddrWidth)
    else $fatal(1, "rule_t.start_addr field does not match AxiAddrWidth!");
`endif
  // pragma translate_on

endmodule
