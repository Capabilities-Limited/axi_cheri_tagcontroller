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
  parameter int unsigned GROUPING_FACTOR = 256
) (
  // Rising-edge clock of all ports.
  input logic clk_i,
  // Asynchronous reset, active low
  input logic rst_ni,

  // tag store signals //
  ///////////////////////
  input axi_addr_t root_table_base_addr_i,
  input axi_addr_t root_table_top_addr_i,
  input axi_addr_t leaf_table_base_addr_i,
  input axi_addr_t leaf_table_top_addr_i,

  // commands and reporting signals //
  ////////////////////////////////////
  input logic ignore_tags_i,
  input logic perform_zeroing_i,
  output logic done_zeroing_o,
  input logic perform_flushing_i,
  output logic done_flushing_o,

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
  // local signals for per table-level accesses (root, leaf)
  //////////////////////////////////////////////////////////////////////////////
  logic read_req_valid, read_req_ready;
  tag_req_t read_req;
  logic read_resp_valid, read_resp_ready;
  tag_read_resp_t read_resp;
  logic write_req_valid, write_req_ready;
  tag_req_t write_req;
  logic write_data_req_valid, write_data_req_ready;
  tag_data_req_t write_data_req;
  logic write_resp_valid, write_resp_ready;
  tag_write_resp_t write_resp;

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
  // serve ignored tag requests
  //////////////////////////////////////////////////////////////////////////////
  tag_lookup_engine_ignore_request #(
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .tag_read_resp_t(tag_read_resp_t)
  ) i_tag_lookup_engine_ignore_request (
    .clk_i,
    .rst_ni,
    // commands / reporting signals
    .ignore_i(ignore_tags_i),
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
    // forwarded requests interface
    .read_req_valid_o(read_req_valid),
    .read_req_ready_i(read_req_ready),
    .read_req_o(read_req),
    .read_resp_valid_i(read_resp_valid),
    .read_resp_ready_o(read_resp_ready),
    .read_resp_i(read_resp),
    .write_req_valid_o(write_req_valid),
    .write_req_ready_i(write_req_ready),
    .write_req_o(write_req),
    .write_data_req_valid_o(write_data_req_valid),
    .write_data_req_ready_i(write_data_req_ready),
    .write_data_req_o(write_data_req),
    .write_resp_valid_i(write_resp_valid),
    .write_resp_ready_o(write_resp_ready),
    .write_resp_i(write_resp)
  );

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
    .BITS_PER_ROOT_FLIT(root_hpdcache_cfg.reqWords * root_hpdcache_cfg.wordWidth),
    .BITS_PER_LEAF_FLIT(leaf_hpdcache_cfg.reqWords * leaf_hpdcache_cfg.wordWidth)
  ) i_tag_lookup_engine_table_lookups (
    .clk_i,
    .rst_ni,
    .root_table_size_i(root_table_top_addr_i-root_table_base_addr_i),
    // commands / reporting signals
    .perform_zeroing_i,
    .done_zeroing_o,
    .perform_flushing_i,
    .done_flushing_o,
    // incoming requests interface
    .read_req_valid_i(read_req_valid),
    .read_req_ready_o(read_req_ready),
    .read_req_i(read_req),
    .read_resp_valid_o(read_resp_valid),
    .read_resp_ready_i(read_resp_ready),
    .read_resp_o(read_resp),
    .write_req_valid_i(write_req_valid),
    .write_req_ready_o(write_req_ready),
    .write_req_i(write_req),
    .write_data_req_valid_i(write_data_req_valid),
    .write_data_req_ready_o(write_data_req_ready),
    .write_data_req_i(write_data_req),
    .write_resp_valid_o(write_resp_valid),
    .write_resp_ready_i(write_resp_ready),
    .write_resp_o(write_resp),
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
  hpdcache_wrapper #(
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
    .axi_addr_t(axi_addr_t),
    .HPDcacheUserCfg(root_hpdcache_cfg)
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

    //// tag store memory interfaces //
    ///////////////////////////////////
    .mem_req_o(root_mem_req),
    .mem_resp_i(root_mem_resp)
  );

  // leaf accesses
  localparam int unsigned nLeafReadPorts = 64'd2;
  localparam int unsigned nLeafWritePorts = 64'd1;
  localparam hpdcache_pkg::hpdcache_user_cfg_t leaf_hpdcache_cfg = leaf_hpdcache_user_cfg(nLeafReadPorts+nLeafWritePorts);
  hpdcache_wrapper #(
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
    .axi_addr_t(axi_addr_t),
    .HPDcacheUserCfg(leaf_hpdcache_cfg)
  ) i_leaf_tag_cache_wrapper (
    .clk_i,
    .rst_ni,

    // incoming read tag request descriptor
    .read_req_valid_i(leaf_read_req_valid),
    .read_req_ready_o(leaf_read_req_ready),
    .read_req_i(leaf_read_req),
    // incoming write tag request descriptor
    .write_req_valid_i('{leaf_write_req_valid}),
    .write_req_ready_o('{leaf_write_req_ready}),
    .write_req_i('{leaf_write_req}),
    // incoming write data
    .write_data_req_valid_i('{leaf_write_data_req_valid}),
    .write_data_req_ready_o('{leaf_write_data_req_ready}),
    .write_data_req_i('{leaf_write_data_req}),
    // outgoing read response
    .read_resp_valid_o(leaf_read_resp_valid),
    .read_resp_ready_i(leaf_read_resp_ready),
    .read_resp_o(leaf_read_resp),
    // outgoing write response
    .write_resp_valid_o('{leaf_write_resp_valid}),
    .write_resp_ready_i('{leaf_write_resp_ready}),
    .write_resp_o('{leaf_write_resp}),

    //// tag store memory interfaces //
    ///////////////////////////////////
    .mem_req_o(leaf_mem_req),
    .mem_resp_i(leaf_mem_resp)
  );

  //////////////////////////////////////////////////////////////////////////////
  // converge tag store memory traffic
  //////////////////////////////////////////////////////////////////////////////

  function automatic slv_req_t table_offset_req(axi_addr_t table_base_addr, slv_req_t req);
    slv_req_t ret = req;
    ret.aw.addr = req.aw.addr + table_base_addr;
    ret.ar.addr = req.ar.addr + table_base_addr;
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
    .slv_reqs_i ({table_offset_req(root_table_base_addr_i, root_mem_req),
                  table_offset_req(leaf_table_base_addr_i, leaf_mem_req)}),
    .slv_resps_o({root_mem_resp, leaf_mem_resp}),
    .mst_req_o  (mem_req_o),
    .mst_resp_i (mem_resp_i)
  );

  //// debug
  //assign mem_req_o = leaf_mem_req;
  //assign leaf_mem_resp = mem_resp_i;

endmodule

module tag_lookup_engine_ignore_request #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic
) (
  input logic clk_i,
  input logic rst_ni,
  // ignore
  input logic             ignore_i,
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
  // forwarded requests interface
  output logic            read_req_valid_o,
  input  logic            read_req_ready_i,
  output tag_req_t        read_req_o,
  input  logic            read_resp_valid_i,
  output logic            read_resp_ready_o,
  input  tag_read_resp_t  read_resp_i,
  output logic            write_req_valid_o,
  input  logic            write_req_ready_i,
  output tag_req_t        write_req_o,
  output logic            write_data_req_valid_o,
  input  logic            write_data_req_ready_i,
  output tag_data_req_t   write_data_req_o,
  input  logic            write_resp_valid_i,
  output logic            write_resp_ready_o,
  input  tag_write_resp_t write_resp_i
);

  function automatic tag_read_resp_t dflt_read_resp(type(read_req_i.a_x_id) id);
    tag_read_resp_t resp = tag_write_resp_t'{default: '0};
    resp.id = id;
    resp.data = '0;
    resp.resp = axi_pkg::RESP_OKAY;
    resp.last = 1'b1;
    return resp;
  endfunction

  function automatic tag_write_resp_t dflt_write_resp(type(write_req_i.a_x_id) id);
    tag_write_resp_t resp = tag_write_resp_t'{default: '0};
    resp.id = id;
    resp.resp = axi_pkg::RESP_OKAY;
    resp.user = '0;
    return resp;
  endfunction

  type(read_req_i.a_x_id) read_id_q, read_id_d;
  logic read_valid_q, read_valid_d;
  `FFL(read_id_q, read_id_d, 1'b1, 1'b0, clk_i, rst_ni)
  `FFL(read_valid_q, read_valid_d, 1'b1, 1'b0, clk_i, rst_ni)
  type(write_req_i.a_x_id) write_id_q, write_id_d;
  logic write_valid_q, write_valid_d;
  `FFL(write_id_q, write_id_d, 1'b1, 1'b0, clk_i, rst_ni)
  `FFL(write_valid_q, write_valid_d, 1'b1, 1'b0, clk_i, rst_ni)

  always_comb begin

    // default latch values
    read_id_d = read_id_q;
    read_valid_d = read_valid_q;
    write_id_d = write_id_q;
    write_valid_d = write_valid_q;

    // handle requests
    if (ignore_i) begin
      // handle ignored read
      if (read_req_valid_i && !read_valid_q) begin
        read_valid_d = 1'b1;
        read_id_d = read_req_i.a_x_id;
        read_resp_ready_o = 1'b1;
      end
      // handle ignored write
      if (write_req_valid_i && !write_valid_q) begin
        write_valid_d = 1'b1;
        write_id_d = write_req_i.a_x_id;
        write_resp_ready_o = 1'b1;
      end
    end else begin
      // single flit read requests
      read_req_valid_o = read_req_valid_i;
      read_req_ready_o = read_req_ready_i;
      read_req_o = read_req_i;
      // assume single flit write data
      // assume simultaneous write and write data
      write_req_valid_o = write_req_valid_i && write_data_req_valid_i;
      write_req_ready_o = write_req_ready_i;
      write_req_o = write_req_i;
      write_data_req_valid_o = write_req_valid_i && write_data_req_valid_i;
      write_data_req_ready_o = write_data_req_ready_i;
      write_data_req_o = write_data_req_i;
    end

    // handle read responses
    if (read_valid_q) begin
      read_resp_valid_o = 1'b1;
      read_resp_o = dflt_read_resp(read_id_q);
      if (read_resp_ready_i) read_valid_d = 1'b0;
    end else begin
      read_resp_valid_o = read_resp_valid_i;
      read_resp_ready_o = read_resp_ready_i;
      read_resp_o = read_resp_i;
    end

    // handle write responses
    if (write_valid_q) begin
      write_resp_valid_o = 1'b1;
      write_resp_o = dflt_write_resp(write_id_q);
      if (write_resp_ready_i) write_valid_d = 1'b0;
    end else begin
      write_resp_valid_o = write_resp_valid_i;
      write_resp_ready_o = write_resp_ready_i;
      write_resp_o = write_resp_i;
    end

  end

endmodule

module tag_lookup_engine_table_lookups #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter type axi_slv_id_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
  parameter int unsigned BITS_PER_ROOT_FLIT = 4,
  parameter int unsigned BITS_PER_LEAF_FLIT = 4
) (
  input logic clk_i,
  input logic rst_ni,
  input axi_addr_t root_table_size_i,
  // commands / reporting signals
  input logic perform_zeroing_i,
  output logic done_zeroing_o,
  input logic perform_flushing_i, // TODO implement
  output logic done_flushing_o, // TODO implement
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
    return addr >> 3;
  endfunction
  function automatic axi_addr_t addr_to_root_byte_idx(axi_addr_t addr);
    axi_addr_t leaf_idx = addr_to_leaf_byte_idx(addr);
    return leaf_idx >> $clog2(GROUPING_FACTOR);
  endfunction

  // root table management fsm
  tag_lookup_engine_root_init #(
    .tag_req_t(tag_req_t),
    .tag_data_req_t(tag_data_req_t),
    .tag_write_resp_t(tag_write_resp_t),
    .axi_addr_t(axi_addr_t),
    .BITS_PER_ROOT_FLIT(BITS_PER_ROOT_FLIT)
  ) i_tag_lookup_engine_root_init (
    .clk_i,
    .rst_ni,
    .root_table_size_i,
    .start_i(perform_zeroing_i),
    .ready_o(done_zeroing_o),
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

  // tag reads //
  tag_lookup_engine_table_lookups_read #(
    .tag_req_t(tag_req_t),
    .tag_read_resp_t(tag_read_resp_t),
    .axi_addr_t(axi_addr_t),
    .GROUPING_FACTOR(GROUPING_FACTOR)
  ) i_tag_lookup_engine_table_lookups_read (
    .clk_i,
    .rst_ni,
    // incoming interface
    .leaf_idx_i(addr_to_leaf_byte_idx(read_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_byte_idx(read_req_i.a_x_addr)),
    .req_valid_i(read_req_valid_i),
    .req_ready_o(read_req_ready_o),
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
    .BITS_PER_ROOT_FLIT(BITS_PER_ROOT_FLIT),
    .BITS_PER_LEAF_FLIT(BITS_PER_LEAF_FLIT)
  ) i_tag_lookup_engine_table_lookups_write (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    // incoming interface
    .leaf_idx_i(addr_to_leaf_byte_idx(write_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_byte_idx(write_req_i.a_x_addr)),
    .req_valid_i(write_req_valid_i),
    .req_ready_o(write_req_ready_o),
    .req_i(write_req_i),
    .data_valid_i(write_data_req_valid_i),
    .data_ready_o(write_data_req_ready_o),
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
