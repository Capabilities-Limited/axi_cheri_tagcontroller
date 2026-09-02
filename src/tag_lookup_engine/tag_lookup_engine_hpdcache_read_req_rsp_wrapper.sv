module hpdcache_read_req_rsp_wrapper #(
    parameter hpdcache_pkg::hpdcache_cfg_t HPDcacheCfg = '0,
    parameter type sid_t = logic [HPDcacheCfg.u.reqSrcIdWidth-1:0],
    parameter type tag_req_t = logic,
    parameter type tag_read_resp_t = logic,
    parameter type hpdcache_req_t = logic,
    parameter type hpdcache_rsp_t = logic
  ) (
    input logic clk_i,
    input logic rst_ni,

    input sid_t sid_i,

    input logic read_req_valid_i,
    output logic read_req_ready_o,
    input tag_req_t read_req_i,

    output logic hpdcache_read_req_valid_o,
    input logic hpdcache_read_req_ready_i,
    output hpdcache_req_t hpdcache_read_req_o,

    output logic read_resp_valid_o,
    output tag_read_resp_t read_resp_o,

    input logic hpdcache_read_resp_valid_i,
    input hpdcache_rsp_t hpdcache_read_resp_i
  );


  // remember how to shift read responses based on the address
  logic [$clog2($bits(read_resp_o.data))-1:0] shifts [(2**$bits(read_req_i.a_x_id))-1:0];
  always_ff @(posedge clk_i) begin
    if (read_req_valid_i && hpdcache_read_req_ready_i) begin
      shifts[read_req_i.a_x_id] <= read_req_i.a_x_addr;
    end
  end

  // convert read descriptor to hpdcache request
  function automatic hpdcache_req_t read_req_to_hpdcache_req(tag_req_t desc);

    hpdcache_req_t req;

    // make sure we have a single flit transaction
    assert(desc.a_x_len == 0);
    //assert(desc.x_last == 1'b1); // TODO only check if there is a valid request
    // TODO check remaining descriptor fields
    //axi_pkg::burst_t a_x_burst;  // AXI burst type
    //logic a_x_lock;  // AXI lock signal
    //axi_pkg::cache_t a_x_cache;  // AXI cache signal
    //axi_pkg::prot_t a_x_prot;  // AXI protection signal
    //axi_pkg::resp_t x_resp;  // AXI response signal, for error propagation
    //logic x_last;  // Last descriptor of a burst
    //// Cache specific descriptor signals
    //logic [Cfg.tagc_cfg.SetAssociativity-1:0] way_ind;  // way we have to perform an operation on

    // prepare hpdcache req
    req.addr_offset = desc.a_x_addr[0 +: HPDcacheCfg.reqOffsetWidth];
    req.wdata = 0; // read req, no data
    req.op = hpdcache_pkg::HPDCACHE_REQ_LOAD;
    req.be = 0; // read req, no byte enable
    req.size = 0;
    req.sid = sid_i;
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
  function automatic tag_read_resp_t hpdcache_read_rsp_to_tagctrl_read_rsp( hpdcache_rsp_t rsp
                                                                          , logic [$clog2($bits(read_resp_o.data))-1:0] shamnt );
    tag_read_resp_t resp;
    resp.id = rsp.tid;
    shamnt[1:0] = 2'b00;
    resp.data = rsp.rdata << shamnt;
    resp.resp = (rsp.error || rsp.aborted) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    resp.last = 1'b1;
    return resp;
  endfunction

  // connect up input / output signals
  assign read_req_ready_o = hpdcache_read_req_ready_i;

  assign hpdcache_read_req_valid_o = read_req_valid_i;
  assign hpdcache_read_req_o = read_req_to_hpdcache_req(read_req_i);

  assign read_resp_valid_o = hpdcache_read_resp_valid_i;
  assign read_resp_o = hpdcache_read_rsp_to_tagctrl_read_rsp( hpdcache_read_resp_i
                                                            , shifts[hpdcache_read_resp_i.tid] );

endmodule
