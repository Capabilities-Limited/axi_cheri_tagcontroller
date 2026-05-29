module table_lookups #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic
) (
  // Rising-edge clock of all ports.
  input logic clk_i,
  // Asynchronous reset, active low
  input logic rst_ni,

  // incoming requests interface //
  //////////////////////////////////////////////////////////////////////////////
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
  //////////////////////////////////////////////////////////////////////////////

  // outgoing interfaces (2 lvls, root, leaf) //
  //////////////////////////////////////////////////////////////////////////////
  // root level interface
  ////////////////////////////////////////////////
  // tag read request descriptor
  output logic root_read_req_valid_o,
  input logic root_read_req_ready_i,
  output tag_req_t root_read_req_o,
  // tag write request descriptor
  output logic root_write_req_valid_o,
  input logic root_write_req_ready_i,
  output tag_req_t root_write_req_o,
  // write data
  output logic root_write_data_req_valid_o,
  input logic root_write_data_req_ready_i,
  output tag_data_req_t root_write_data_req_o,
  // write response
  input logic root_write_resp_valid_i,
  output logic root_write_resp_ready_o,
  input tag_write_resp_t root_write_resp_i,
  // read response
  input logic root_read_resp_valid_i,
  output logic root_read_resp_ready_o,
  input tag_read_resp_t root_read_resp_i,
  // leaf level interface
  ////////////////////////////////////////////////
  // tag read request descriptor
  output logic leaf_read_req_valid_o,
  input logic leaf_read_req_ready_i,
  output tag_req_t leaf_read_req_o,
  // tag write request descriptor
  output logic leaf_write_req_valid_o,
  input logic leaf_write_req_ready_i,
  output tag_req_t leaf_write_req_o,
  // write data
  output logic leaf_write_data_req_valid_o,
  input logic leaf_write_data_req_ready_i,
  output tag_data_req_t leaf_write_data_req_o,
  // write response
  input logic leaf_write_resp_valid_i,
  output logic leaf_write_resp_ready_o,
  input tag_write_resp_t leaf_write_resp_i,
  // read response
  input logic leaf_read_resp_valid_i,
  output logic leaf_read_resp_ready_o,
  input tag_read_resp_t leaf_read_resp_i,
  //////////////////////////////////////////////////////////////////////////////

  // configuration interfaces (2 lvls) //
  ///////////////////////////////////////
  input axi_addr_t root_table_start_addr_i,
  input axi_addr_t leaf_table_start_addr_i
);

  // TODO
  // TODO split the incomming request into a root and a leaf access
  // TODO handle hit-related abort where possible
  // TODO

  // place holder, pass through as leaf only //
  /////////////////////////////////////////////
  // first, tie off the root (flat, leaf only)
  // empty source, infinite sink
  assign root_read_req_valid_o = 1'b0;
  assign root_write_req_valid_o = 1'b0;
  assign root_write_data_req_valid_o = 1'b0;
  assign root_read_resp_ready_o= 1'b1;
  assign root_write_resp_ready_o = 1'b1;
  // then, simply pass through the incoming request as the leaf request
  // DBG
  //assign leaf_read_req_valid_o = 1'b0;
  //assign leaf_write_req_valid_o = 1'b0;
  //assign leaf_write_data_req_valid_o = 1'b0;
  //assign leaf_read_resp_ready_o= 1'b1;
  //assign leaf_write_resp_ready_o = 1'b1;
  //
  assign leaf_read_req_valid_o = read_req_valid_i;
  assign read_req_ready_o = leaf_read_req_ready_i;
  assign leaf_read_req_o = read_req_i;
  assign leaf_write_req_valid_o = write_req_valid_i;
  assign write_req_ready_o = leaf_write_req_ready_i;
  assign leaf_write_req_o = write_req_i;
  assign leaf_write_data_req_valid_o = write_data_req_valid_i;
  assign write_data_req_ready_o = leaf_write_data_req_ready_i;
  assign leaf_write_data_req_o = write_data_req_i;
  assign write_resp_valid_o = leaf_write_resp_valid_i;
  assign leaf_write_resp_ready_o = write_resp_ready_i;
  assign write_resp_o = leaf_write_resp_i;
  assign read_resp_valid_o = leaf_read_resp_valid_i;
  assign leaf_read_resp_ready_o = read_resp_ready_i;
  assign read_resp_o = leaf_read_resp_i;

endmodule

module tag_lookup_engine #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  `ifndef PULP_LLC
  parameter int unsigned cache_req_words = 64'd4,
  `endif
  parameter int unsigned AxiIdWidth = 64'd6,
  parameter int unsigned AxiAddrWidth = 64'd64,
  parameter int unsigned AxiDataWidth = 64'd64,
  parameter int unsigned AxiUserWidth = 64'd1,
  parameter type mem_req_t = logic,
  parameter type mem_resp_t = logic,
  parameter type axi_addr_t = logic [AxiAddrWidth-1:0]
  `ifdef PULP_LLC
  , parameter type tagc_desc_t = logic
  `endif
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

  // local signals for per table-level accesses (root, leaf)
  logic root_read_req_valid, leaf_read_req_valid;
  logic root_read_req_ready, leaf_read_req_ready;
  tag_req_t root_read_req, leaf_read_req;
  logic root_write_req_valid, leaf_write_req_valid;
  logic root_write_req_ready, leaf_write_req_ready;
  tag_req_t root_write_req, leaf_write_req;
  logic root_write_data_req_valid, leaf_write_data_req_valid;
  logic root_write_data_req_ready, leaf_write_data_req_ready;
  tag_data_req_t root_write_data_req, leaf_write_data_req;
  logic root_write_resp_valid, leaf_write_resp_valid;
  logic root_write_resp_ready, leaf_write_resp_ready;
  tag_write_resp_t root_write_resp, leaf_write_resp;
  logic root_read_resp_valid, leaf_read_resp_valid;
  logic root_read_resp_ready, leaf_read_resp_ready;
  tag_read_resp_t root_read_resp, leaf_read_resp;

  // generate per table-level accesses
  table_lookups #(
    .tag_req_t,
    .tag_data_req_t,
    .tag_write_resp_t,
    .tag_read_resp_t,
    .axi_addr_t
  ) i_table_lookups (
    .clk_i,
    .rst_ni,
    // incoming requests interface
    .read_req_valid_i,
    .read_req_ready_o,
    .read_req_i,
    .write_req_valid_i,
    .write_req_ready_o,
    .write_req_i,
    .write_data_req_valid_i,
    .write_data_req_ready_o,
    .write_data_req_i,
    .write_resp_valid_o,
    .write_resp_ready_i,
    .write_resp_o,
    .read_resp_valid_o,
    .read_resp_ready_i,
    .read_resp_o,
    // outgoing interfaces (2 lvls, root, leaf)
    // root level interface
    .root_read_req_valid_o(root_read_req_valid),
    .root_read_req_ready_i(root_read_req_ready),
    .root_read_req_o(root_read_req),
    .root_write_req_valid_o(root_write_req_valid),
    .root_write_req_ready_i(root_write_req_ready),
    .root_write_req_o(root_write_req),
    .root_write_data_req_valid_o(root_write_data_req_valid),
    .root_write_data_req_ready_i(root_write_data_req_ready),
    .root_write_data_req_o(root_write_data_req),
    .root_write_resp_valid_i(root_write_resp_valid),
    .root_write_resp_ready_o(root_write_resp_ready),
    .root_write_resp_i(root_write_resp),
    .root_read_resp_valid_i(root_read_resp_valid),
    .root_read_resp_ready_o(root_read_resp_ready),
    .root_read_resp_i(root_read_resp),
    // leaf level interface
    .leaf_read_req_valid_o(leaf_read_req_valid),
    .leaf_read_req_ready_i(leaf_read_req_ready),
    .leaf_read_req_o(leaf_read_req),
    .leaf_write_req_valid_o(leaf_write_req_valid),
    .leaf_write_req_ready_i(leaf_write_req_ready),
    .leaf_write_req_o(leaf_write_req),
    .leaf_write_data_req_valid_o(leaf_write_data_req_valid),
    .leaf_write_data_req_ready_i(leaf_write_data_req_ready),
    .leaf_write_data_req_o(leaf_write_data_req),
    .leaf_write_resp_valid_i(leaf_write_resp_valid),
    .leaf_write_resp_ready_o(leaf_write_resp_ready),
    .leaf_write_resp_i(leaf_write_resp),
    .leaf_read_resp_valid_i(leaf_read_resp_valid),
    .leaf_read_resp_ready_o(leaf_read_resp_ready),
    .leaf_read_resp_i(leaf_read_resp),
    // configuration interfaces
    .root_table_start_addr_i(/*TODO*/),
    .leaf_table_start_addr_i(/*TODO*/)
  );

  // Backing cache
  `ifndef PULP_LLC
  hpdcache_wrapper #(
  `else
  llc_cache_wrapper #(
  `endif
    .tag_req_t,
    .tag_data_req_t,
    .tag_write_resp_t,
    .tag_read_resp_t,
    .AxiIdWidth,
    .AxiAddrWidth,
    .AxiDataWidth,
    .AxiUserWidth,
    `ifndef PULP_LLC
    .cache_req_words,
    `endif
    .mem_req_t,
    .mem_resp_t,
    .axi_addr_t
    `ifdef PULP_LLC
    , .tagc_desc_t
    `endif
  ) i_tag_cache_wrapper (
    .clk_i,
    .rst_ni,

    // incoming read tag request descriptor
    .read_req_valid_i(leaf_read_req_valid),
    .read_req_ready_o(leaf_read_req_ready),
    .read_req_i(leaf_read_req),
    // incoming write tag request descriptor
    .write_req_valid_i(leaf_write_req_valid),
    .write_req_ready_o(leaf_write_req_ready),
    .write_req_i(leaf_write_req),
    // incoming write data
    .write_data_req_valid_i(leaf_write_data_req_valid),
    .write_data_req_ready_o(leaf_write_data_req_ready),
    .write_data_req_i(leaf_write_data_req),
    // outgoing read response
    .read_resp_valid_o(leaf_read_resp_valid),
    .read_resp_ready_i(leaf_read_resp_ready),
    .read_resp_o(leaf_read_resp),
    // outgoing write response
    .write_resp_valid_o(leaf_write_resp_valid),
    .write_resp_ready_i(leaf_write_resp_ready),
    .write_resp_o(leaf_write_resp),

    .isolate_o,
    .isolated_i,
    .cached_start_addr_i,
    .cached_end_addr_i,

    //// tag store memory interfaces //
    ///////////////////////////////////
    .mem_req_o,
    .mem_resp_i
  );
endmodule
