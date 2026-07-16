// This module is the toplevel module of the tag lookup engine
// it instanciates
// * a tag_lookup_engine_config module
// * tag_lookup_engine_table_lookups module
// * per lookup stream caches
// * an axi_mux to produce a single stream of tag requests

import lookup_engine_hpdcache_cfg_pkg::*;

module tag_lookup_engine #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter int unsigned AxiMstIdWidth = 64'd6,
  parameter int unsigned AxiAddrWidth = 64'd64,
  parameter int unsigned AxiDataWidth = 64'd64,
  parameter int unsigned AxiUserWidth = 64'd0,
  parameter type mem_req_t = logic,
  parameter type mem_resp_t = logic,
  parameter type axi_addr_t = logic [AxiAddrWidth-1:0],
  `ifdef PULP_LLC
  parameter type tagc_desc_t = logic,
  `endif
  parameter int unsigned GROUPING_FACTOR = 256,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned COVERED_ALIGN = 4096,
  parameter int unsigned TAG_STORE_ALIGN = 64
) (
  // Rising-edge clock of all ports.
  input logic clk_i,
  // Asynchronous reset, active low
  input logic rst_ni,

  // cache cfg signals //
  ///////////////////////
  output logic isolate_o,
  input logic isolated_i,
  input axi_addr_t cached_start_addr_i,
  input axi_addr_t cached_end_addr_i,

  // tag store signals //
  ///////////////////////
  input axi_addr_t covered_base_addr_i,
  input axi_addr_t covered_top_addr_i,
  input axi_addr_t tag_store_base_addr_i,

  // tag controller slave interfaces //
  /////////////////////////////////////
  // incoming tag read request descriptor
  input logic read_req_valid_i,
  output logic read_req_ready_o,
  input tag_req_t read_req_i,
  // outgoing read response
  output logic read_resp_valid_o,
  input logic read_resp_ready_i,
  output tag_read_resp_t read_resp_o,
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

  // tag store master interfaces //
  /////////////////////////////////
  output mem_req_t mem_req_o,
  input mem_resp_t mem_resp_i
);

  //////////////////////////////////////////////////////////////////////////////
  // local types and assertions
  //////////////////////////////////////////////////////////////////////////////
  // TODO assert that inner AXI id witdh + max Trans fix in outer id width
  //assert (AxiAddrWidth < 2) $error("tag_lookup_engine: the AXI ID width configuration is not supported");

  // derive AXI types for inner (axi_mux slave) and outer (axi_mux master) traffic
  typedef logic [AxiMstIdWidth-2:0] axi_slv_id_t;
  typedef logic [AxiMstIdWidth-1:0] axi_mst_id_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [(AxiDataWidth/8)-1:0] axi_strb_t;
  typedef logic [0:0] axi_user_t;

  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, axi_addr_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(slv_r_chan_t, axi_data_t, axi_slv_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(slv_req_t, slv_aw_chan_t, w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(slv_resp_t, slv_b_chan_t, slv_r_chan_t)

  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_chan_t, axi_addr_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_chan_t, axi_addr_t, axi_mst_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(mst_r_chan_t, axi_data_t, axi_mst_id_t, axi_user_t)

  //////////////////////////////////////////////////////////////////////////////
  // tag lookup engine configuration module
  //////////////////////////////////////////////////////////////////////////////

  axi_addr_t root_table_base_addr, leaf_table_base_addr;
  axi_addr_t root_table_top_addr, leaf_table_top_addr;

  tag_lookup_engine_config #(
    .addr_t(axi_addr_t),
    .GROUPING_FACTOR(GROUPING_FACTOR),
    .TAGGED_CHUNK_SIZE(TAGGED_CHUNK_SIZE),
    .COVERED_ALIGN(COVERED_ALIGN),
    .TAG_STORE_ALIGN(TAG_STORE_ALIGN)
  ) i_tag_lookup_engine_config (
    .covered_base_addr_i,
    .covered_top_addr_i,
    .tag_store_base_addr_i,
    .leaf_table_base_addr_o(leaf_table_base_addr),
    .leaf_table_top_addr_o(leaf_table_top_addr),
    .root_table_base_addr_o(root_table_base_addr),
    .root_table_top_addr_o(root_table_top_addr),
    .tag_store_top_addr_o(/* TODO */),
    .error_o(/* TODO */)
  );

  //////////////////////////////////////////////////////////////////////////////
  // local signals for per table-level accesses (root, leaf)
  //////////////////////////////////////////////////////////////////////////////

  logic root_read_req_valid[2], leaf_read_req_valid[2];
  logic root_read_req_ready[2], leaf_read_req_ready[2];
  tag_req_t root_read_req[2], leaf_read_req[2];
  logic root_write_req_valid[2], leaf_write_req_valid;
  logic root_write_req_ready[2], leaf_write_req_ready;
  tag_req_t root_write_req[2], leaf_write_req;
  logic root_write_data_req_valid[2], leaf_write_data_req_valid;
  logic root_write_data_req_ready[2], leaf_write_data_req_ready;
  tag_data_req_t root_write_data_req[2], leaf_write_data_req;
  logic root_write_resp_valid[2], leaf_write_resp_valid;
  logic root_write_resp_ready[2], leaf_write_resp_ready;
  tag_write_resp_t root_write_resp[2], leaf_write_resp;
  logic root_read_resp_valid[2], leaf_read_resp_valid[2];
  logic root_read_resp_ready[2], leaf_read_resp_ready[2];
  tag_read_resp_t root_read_resp[2], leaf_read_resp[2];

  slv_req_t root_mem_req, leaf_mem_req;
  slv_resp_t root_mem_resp, leaf_mem_resp;

  //////////////////////////////////////////////////////////////////////////////
  // generate per table-level accesses
  //////////////////////////////////////////////////////////////////////////////
  tag_lookup_engine_table_lookups #(
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .tag_read_resp_t(tag_read_resp_t),
    .axi_addr_t(axi_addr_t),
    .axi_slv_id_t(axi_slv_id_t),
    .GROUPING_FACTOR(GROUPING_FACTOR),
    .TAGGED_CHUNK_SIZE(TAGGED_CHUNK_SIZE),
    .BITS_PER_ROOT_FLIT(root_hpdcache_cfg.reqWords * root_hpdcache_cfg.wordWidth),
    .BITS_PER_LEAF_FLIT(leaf_hpdcache_cfg.reqWords * leaf_hpdcache_cfg.wordWidth)
  ) i_tag_lookup_engine_table_lookups (
    .clk_i,
    .rst_ni,
    .root_table_size_i(root_table_top_addr-root_table_base_addr),
    // incoming requests interface
    .read_req_valid_i,
    .read_req_ready_o,
    .read_req_i,
    .read_resp_valid_o,
    .read_resp_ready_i,
    .read_resp_o,
    .write_req_valid_i,
    .write_req_ready_o,
    .write_req_i,
    .write_data_req_valid_i,
    .write_data_req_ready_o,
    .write_data_req_i,
    .write_resp_valid_o,
    .write_resp_ready_i,
    .write_resp_o,
    // outgoing interfaces (2 lvls, root, leaf)
    // root level interface
    .root_read_req_valid_o(root_read_req_valid),
    .root_read_req_ready_i(root_read_req_ready),
    .root_read_req_o(root_read_req),
    .root_read_resp_valid_i(root_read_resp_valid),
    .root_read_resp_ready_o(root_read_resp_ready),
    .root_read_resp_i(root_read_resp),
    .root_write_req_valid_o(root_write_req_valid),
    .root_write_req_ready_i(root_write_req_ready),
    .root_write_req_o(root_write_req),
    .root_write_data_req_valid_o(root_write_data_req_valid),
    .root_write_data_req_ready_i(root_write_data_req_ready),
    .root_write_data_req_o(root_write_data_req),
    .root_write_resp_valid_i(root_write_resp_valid),
    .root_write_resp_ready_o(root_write_resp_ready),
    .root_write_resp_i(root_write_resp),
    // leaf level interface
    .leaf_read_req_valid_o(leaf_read_req_valid),
    .leaf_read_req_ready_i(leaf_read_req_ready),
    .leaf_read_req_o(leaf_read_req),
    .leaf_read_resp_valid_i(leaf_read_resp_valid),
    .leaf_read_resp_ready_o(leaf_read_resp_ready),
    .leaf_read_resp_i(leaf_read_resp),
    .leaf_write_req_valid_o(leaf_write_req_valid),
    .leaf_write_req_ready_i(leaf_write_req_ready),
    .leaf_write_req_o(leaf_write_req),
    .leaf_write_data_req_valid_o(leaf_write_data_req_valid),
    .leaf_write_data_req_ready_i(leaf_write_data_req_ready),
    .leaf_write_data_req_o(leaf_write_data_req),
    .leaf_write_resp_valid_i(leaf_write_resp_valid),
    .leaf_write_resp_ready_o(leaf_write_resp_ready),
    .leaf_write_resp_i(leaf_write_resp)
  );

  //////////////////////////////////////////////////////////////////////////////
  // Backing caches
  //////////////////////////////////////////////////////////////////////////////

  // root accesses
  localparam int unsigned nRootReadPorts = 64'd2;
  localparam int unsigned nRootWritePorts = 64'd2;
  localparam hpdcache_pkg::hpdcache_user_cfg_t root_hpdcache_cfg = root_hpdcache_user_cfg(nRootReadPorts+nRootWritePorts);
  `ifndef PULP_LLC
  hpdcache_wrapper #(
  `else
  llc_cache_wrapper #(
  `endif
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .tag_read_resp_t(tag_read_resp_t),
    .nReadPorts(nRootReadPorts),
    .nWritePorts(nRootWritePorts),
    .AxiIdWidth(AxiMstIdWidth-1),
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiUserWidth(AxiUserWidth),
    .mem_req_t(slv_req_t),
    .mem_resp_t(slv_resp_t),
    .axi_addr_t(axi_addr_t)
    `ifdef PULP_LLC
    , .tagc_desc_t(tagc_desc_t)
    `else
    , .HPDcacheUserCfg(root_hpdcache_cfg)
    `endif
  ) i_root_tag_cache_wrapper (
    .clk_i,
    .rst_ni,

    // incoming read tag request descriptor
    .read_req_valid_i(root_read_req_valid),
    .read_req_ready_o(root_read_req_ready),
    .read_req_i(root_read_req),
    // incoming write tag request descriptor
    .write_req_valid_i(root_write_req_valid),
    .write_req_ready_o(root_write_req_ready),
    .write_req_i(root_write_req),
    // incoming write data
    .write_data_req_valid_i(root_write_data_req_valid),
    .write_data_req_ready_o(root_write_data_req_ready),
    .write_data_req_i(root_write_data_req),
    // outgoing read response
    .read_resp_valid_o(root_read_resp_valid),
    .read_resp_ready_i(root_read_resp_ready),
    .read_resp_o(root_read_resp),
    // outgoing write response
    .write_resp_valid_o(root_write_resp_valid),
    .write_resp_ready_i(root_write_resp_ready),
    .write_resp_o(root_write_resp),

    .isolate_o,
    .isolated_i,
    .cached_start_addr_i,
    .cached_end_addr_i,

    //// tag store memory interfaces //
    ///////////////////////////////////
    .mem_req_o(root_mem_req),
    .mem_resp_i(root_mem_resp)
  );

  // leaf accesses
  localparam int unsigned nLeafReadPorts = 64'd2;
  localparam int unsigned nLeafWritePorts = 64'd1;
  localparam hpdcache_pkg::hpdcache_user_cfg_t leaf_hpdcache_cfg = leaf_hpdcache_user_cfg(nLeafReadPorts+nLeafWritePorts);
  `ifndef PULP_LLC
  hpdcache_wrapper #(
  `else
  llc_cache_wrapper #(
  `endif
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .tag_read_resp_t(tag_read_resp_t),
    .nReadPorts(nLeafReadPorts),
    .nWritePorts(nLeafWritePorts),
    .AxiIdWidth(AxiMstIdWidth-1),
    .AxiAddrWidth(AxiAddrWidth),
    .AxiDataWidth(AxiDataWidth),
    .AxiUserWidth(AxiUserWidth),
    .mem_req_t(slv_req_t),
    .mem_resp_t(slv_resp_t),
    .axi_addr_t(axi_addr_t)
    `ifdef PULP_LLC
    , .tagc_desc_t(tagc_desc_t)
    `else
    , .HPDcacheUserCfg(leaf_hpdcache_cfg)
    `endif
  ) i_leaf_tag_cache_wrapper (
    .clk_i,
    .rst_ni,

    // incoming read tag request descriptor
    .read_req_valid_i(leaf_read_req_valid),
    .read_req_ready_o(leaf_read_req_ready),
    .read_req_i(leaf_read_req),
    // incoming write tag request descriptor
    .write_req_valid_i({leaf_write_req_valid}),
    .write_req_ready_o({leaf_write_req_ready}),
    .write_req_i({leaf_write_req}),
    // incoming write data
    .write_data_req_valid_i({leaf_write_data_req_valid}),
    .write_data_req_ready_o({leaf_write_data_req_ready}),
    .write_data_req_i({leaf_write_data_req}),
    // outgoing read response
    .read_resp_valid_o(leaf_read_resp_valid),
    .read_resp_ready_i(leaf_read_resp_ready),
    .read_resp_o(leaf_read_resp),
    // outgoing write response
    .write_resp_valid_o({leaf_write_resp_valid}),
    .write_resp_ready_i({leaf_write_resp_ready}),
    .write_resp_o({leaf_write_resp}),

    .isolate_o,
    .isolated_i,
    .cached_start_addr_i,
    .cached_end_addr_i,

    //// tag store memory interfaces //
    ///////////////////////////////////
    .mem_req_o(leaf_mem_req),
    .mem_resp_i(leaf_mem_resp)
  );

  //////////////////////////////////////////////////////////////////////////////
  // converge tag store memory traffic
  //////////////////////////////////////////////////////////////////////////////

  function automatic slv_req_t to_tag_table_byte_req(axi_addr_t table_base_addr, slv_req_t req);
    slv_req_t ret = req;
`ifdef PULP_LLC
    ret.aw.addr = req.aw.addr + table_base_addr;
    ret.ar.addr = req.ar.addr + table_base_addr;
`else
    ret.aw.addr = (req.aw.addr>>3) + table_base_addr;
    ret.aw.size = req.aw.size - 3;
    ret.ar.addr = (req.ar.addr>>3) + table_base_addr;
    ret.ar.size = req.ar.size - 3;
`endif
    return ret;
  endfunction

  axi_mux #(
    .SlvAxiIDWidth(AxiMstIdWidth-1),
    .slv_aw_chan_t(slv_aw_chan_t),
    .mst_aw_chan_t(mst_aw_chan_t),
    .w_chan_t     (w_chan_t),
    .slv_b_chan_t (slv_b_chan_t),
    .mst_b_chan_t (mst_b_chan_t),
    .slv_ar_chan_t(slv_ar_chan_t),
    .mst_ar_chan_t(mst_ar_chan_t),
    .slv_r_chan_t (slv_r_chan_t),
    .mst_r_chan_t (mst_r_chan_t),
    .slv_req_t    (slv_req_t),
    .slv_resp_t   (slv_resp_t),
    .mst_req_t    (mem_req_t),
    .mst_resp_t   (mem_resp_t),
    .NoSlvPorts   (32'd2),
    .MaxWTrans    (32'd8),
    .FallThrough  (1'b0),                   // No registers
    .SpillAw      (1'b0),                   // No registers
    .SpillW       (1'b0),                   // No registers
    .SpillB       (1'b0),                   // No registers
    .SpillAr      (1'b0),                   // No registers
    .SpillR       (1'b0)                    // No registers
  ) i_axi_mux (
    .clk_i,
    .rst_ni,
    .test_i(1'b0),
    .slv_reqs_i ({to_tag_table_byte_req(root_table_base_addr, root_mem_req),
                  to_tag_table_byte_req(leaf_table_base_addr, leaf_mem_req)}),
    .slv_resps_o({root_mem_resp, leaf_mem_resp}),
    .mst_req_o  (mem_req_o),
    .mst_resp_i (mem_resp_i)
  );

  //// debug
  //assign mem_req_o = leaf_mem_req;
  //assign leaf_mem_resp = mem_resp_i;

endmodule

module tag_lookup_engine_table_lookups #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter type axi_slv_id_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned BITS_PER_ROOT_FLIT = 4,
  parameter int unsigned BITS_PER_LEAF_FLIT = 4
) (
  input logic clk_i,
  input logic rst_ni,
  input axi_addr_t root_table_size_i,
  // incoming requests interface
  input  logic            read_req_valid_i,
  output logic            read_req_ready_o,
  input  tag_req_t        read_req_i,
  output logic            read_resp_valid_o,
  input  logic            read_resp_ready_i,
  output tag_read_resp_t  read_resp_o,
  input  logic            write_req_valid_i,
  output logic            write_req_ready_o,
  input  tag_req_t        write_req_i,
  input  logic            write_data_req_valid_i,
  output logic            write_data_req_ready_o,
  input  tag_data_req_t   write_data_req_i,
  output logic            write_resp_valid_o,
  input  logic            write_resp_ready_i,
  output tag_write_resp_t write_resp_o,
  // root level interface
  output logic            root_read_req_valid_o[2],
  input  logic            root_read_req_ready_i[2],
  output tag_req_t        root_read_req_o[2],
  input  logic            root_read_resp_valid_i[2],
  output logic            root_read_resp_ready_o[2],
  input  tag_read_resp_t  root_read_resp_i[2],
  output logic            root_write_req_valid_o[2],
  input  logic            root_write_req_ready_i[2],
  output tag_req_t        root_write_req_o[2],
  output logic            root_write_data_req_valid_o[2],
  input  logic            root_write_data_req_ready_i[2],
  output tag_data_req_t   root_write_data_req_o[2],
  input  logic            root_write_resp_valid_i[2],
  output logic            root_write_resp_ready_o[2],
  input  tag_write_resp_t root_write_resp_i[2],
  // leaf level interface
  output logic            leaf_read_req_valid_o[2],
  input  logic            leaf_read_req_ready_i[2],
  output tag_req_t        leaf_read_req_o[2],
  input  logic            leaf_read_resp_valid_i[2],
  output logic            leaf_read_resp_ready_o[2],
  input  tag_read_resp_t  leaf_read_resp_i[2],
  output logic            leaf_write_req_valid_o,
  input  logic            leaf_write_req_ready_i,
  output tag_req_t        leaf_write_req_o,
  output logic            leaf_write_data_req_valid_o,
  input  logic            leaf_write_data_req_ready_i,
  output tag_data_req_t   leaf_write_data_req_o,
  input  logic            leaf_write_resp_valid_i,
  output logic            leaf_write_resp_ready_o,
  input  tag_write_resp_t leaf_write_resp_i
);

  // helpers //
  function automatic axi_addr_t addr_to_leaf_byte_idx(axi_addr_t addr);
    //return (addr >> 3) >> $clog2(TAGGED_CHUNK_SIZE);
    return addr >> 3;
  endfunction
  function automatic axi_addr_t addr_to_root_byte_idx(axi_addr_t addr);
    axi_addr_t leaf_idx = addr_to_leaf_byte_idx(addr);
    return leaf_idx >> $clog2(GROUPING_FACTOR);
  endfunction

  // initialization fsm
  logic start_init;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      start_init <= 1'b1;
    end else begin
      start_init <= 1'b0;
    end
  end
  tag_lookup_engine_root_init #(
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .axi_addr_t(axi_addr_t)
  ) i_tag_lookup_engine_root_init (
    .clk_i,
    .rst_ni,
    .root_table_size_i,
    .start_i(start_init),
    .ready_o(init_ready),
    .root_write_req_valid_o(root_write_req_valid_o[1]),
    .root_write_req_ready_i(root_write_req_ready_i[1]),
    .root_write_req_o(root_write_req_o[1]),
    .root_write_data_req_valid_o(root_write_data_req_valid_o[1]),
    .root_write_data_req_ready_i(root_write_data_req_ready_i[1]),
    .root_write_data_req_o(root_write_data_req_o[1]),
    .root_write_resp_valid_i(root_write_resp_valid_i[1]),
    .root_write_resp_ready_o(root_write_resp_ready_o[1]),
    .root_write_resp_i(root_write_resp_i[1])
  );

  // block standard interfaces when the init fsm is not ready
  logic init_ready;
  logic read_req_valid_mux, read_req_ready_mux;
  assign read_req_valid_mux = init_ready ? read_req_valid_i : 1'b0;
  assign read_req_ready_o = init_ready ? read_req_ready_mux : 1'b0;
  logic write_req_valid_mux, write_req_ready_mux;
  assign write_req_valid_mux = init_ready ? write_req_valid_i : 1'b0;
  assign write_req_ready_o = init_ready ? write_req_ready_mux : 1'b0;
  logic write_data_req_valid_mux, write_data_req_ready_mux;
  assign write_data_req_valid_mux = init_ready ? write_data_req_valid_i : 1'b0;
  assign write_data_req_ready_o = init_ready ? write_data_req_ready_mux : 1'b0;

  // tag reads //
  tag_lookup_engine_table_lookups_read #(
    .tag_req_t(tag_req_t),
    .tag_read_resp_t(tag_read_resp_t),
    .axi_addr_t(axi_addr_t),
    .GROUPING_FACTOR(GROUPING_FACTOR),
    .TAGGED_CHUNK_SIZE(TAGGED_CHUNK_SIZE)
  ) i_tag_lookup_engine_table_lookups_read (
    .clk_i,
    .rst_ni,
    // incoming interface
    .leaf_idx_i(addr_to_leaf_byte_idx(read_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_byte_idx(read_req_i.a_x_addr)),
    .req_valid_i(read_req_valid_mux),
    .req_ready_o(read_req_ready_mux),
    .req_i(read_req_i),
    .resp_valid_o(read_resp_valid_o),
    .resp_ready_i(read_resp_ready_i),
    .resp_o(read_resp_o),
    // outgoing root interface
    .root_req_valid_o(root_read_req_valid_o[0]),
    .root_req_ready_i(root_read_req_ready_i[0]),
    .root_req_o(root_read_req_o[0]),
    .root_resp_valid_i(root_read_resp_valid_i[0]),
    .root_resp_ready_o(root_read_resp_ready_o[0]),
    .root_resp_i(root_read_resp_i[0]),
    // outgoing leaf interface
    .leaf_req_valid_o(leaf_read_req_valid_o[0]),
    .leaf_req_ready_i(leaf_read_req_ready_i[0]),
    .leaf_req_o(leaf_read_req_o[0]),
    .leaf_resp_valid_i(leaf_read_resp_valid_i[0]),
    .leaf_resp_ready_o(leaf_read_resp_ready_o[0]),
    .leaf_resp_i(leaf_read_resp_i[0])
  );
  // tag writes //
  tag_lookup_engine_table_lookups_write #(
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .tag_read_resp_t(tag_read_resp_t),
    .axi_addr_t(axi_addr_t),
    .axi_slv_id_t(axi_slv_id_t),
    .GROUPING_FACTOR(GROUPING_FACTOR),
    .TAGGED_CHUNK_SIZE(TAGGED_CHUNK_SIZE),
    .BITS_PER_ROOT_FLIT(BITS_PER_ROOT_FLIT),
    .BITS_PER_LEAF_FLIT(BITS_PER_LEAF_FLIT)
  ) i_tag_lookup_engine_table_lookups_write (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    // incoming interface
    .leaf_idx_i(addr_to_leaf_byte_idx(write_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_byte_idx(write_req_i.a_x_addr)),
    .req_valid_i(write_req_valid_mux),
    .req_ready_o(write_req_ready_mux),
    .req_i(write_req_i),
    .data_valid_i(write_data_req_valid_mux),
    .data_ready_o(write_data_req_ready_mux),
    .data_i(write_data_req_i),
    .resp_valid_o(write_resp_valid_o),
    .resp_ready_i(write_resp_ready_i),
    .resp_o(write_resp_o),
    // outgoing root read interface
    .root_rd_req_valid_o(root_read_req_valid_o[1]),
    .root_rd_req_ready_i(root_read_req_ready_i[1]),
    .root_rd_req_o(root_read_req_o[1]),
    .root_rd_resp_valid_i(root_read_resp_valid_i[1]),
    .root_rd_resp_ready_o(root_read_resp_ready_o[1]),
    .root_rd_resp_i(root_read_resp_i[1]),
    // outgoing root write interface
    .root_req_valid_o(root_write_req_valid_o[0]),
    .root_req_ready_i(root_write_req_ready_i[0]),
    .root_req_o(root_write_req_o[0]),
    .root_data_valid_o(root_write_data_req_valid_o[0]),
    .root_data_ready_i(root_write_data_req_ready_i[0]),
    .root_data_o(root_write_data_req_o[0]),
    .root_resp_valid_i(root_write_resp_valid_i[0]),
    .root_resp_ready_o(root_write_resp_ready_o[0]),
    .root_resp_i(root_write_resp_i[0]),
    // outgoing leaf write interface
    .leaf_req_valid_o(leaf_write_req_valid_o),
    .leaf_req_ready_i(leaf_write_req_ready_i),
    .leaf_req_o(leaf_write_req_o),
    .leaf_data_valid_o(leaf_write_data_req_valid_o),
    .leaf_data_ready_i(leaf_write_data_req_ready_i),
    .leaf_data_o(leaf_write_data_req_o),
    .leaf_resp_valid_i(leaf_write_resp_valid_i),
    .leaf_resp_ready_o(leaf_write_resp_ready_o),
    .leaf_resp_i(leaf_write_resp_i)
  );

endmodule
