module tag_lookup_engine_table_lookups #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16
) (
  input logic clk_i,
  input logic rst_ni,
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
  output logic            root_read_req_valid_o,
  input  logic            root_read_req_ready_i,
  output tag_req_t        root_read_req_o,
  input  logic            root_read_resp_valid_i,
  output logic            root_read_resp_ready_o,
  input  tag_read_resp_t  root_read_resp_i,
  output logic            root_write_req_valid_o,
  input  logic            root_write_req_ready_i,
  output tag_req_t        root_write_req_o,
  output logic            root_write_data_req_valid_o,
  input  logic            root_write_data_req_ready_i,
  output tag_data_req_t   root_write_data_req_o,
  input  logic            root_write_resp_valid_i,
  output logic            root_write_resp_ready_o,
  input  tag_write_resp_t root_write_resp_i,
  // leaf level interface
  output logic            leaf_read_req_valid_o,
  input  logic            leaf_read_req_ready_i,
  output tag_req_t        leaf_read_req_o,
  input  logic            leaf_read_resp_valid_i,
  output logic            leaf_read_resp_ready_o,
  input  tag_read_resp_t  leaf_read_resp_i,
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
  function automatic axi_addr_t addr_to_leaf_idx(axi_addr_t addr);
    return (addr / axi_addr_t'(TAGGED_CHUNK_SIZE)) / 8;
  endfunction
  function automatic axi_addr_t addr_to_root_idx(axi_addr_t addr);
    axi_addr_t leaf_idx = addr_to_leaf_idx(addr);
    return leaf_idx / axi_addr_t'(GROUPING_FACTOR);
  endfunction
  // tag reads //
  tag_lookup_engine_table_lookups_read #(
    .tag_req_t,
    .tag_read_resp_t,
    .axi_addr_t,
    .GROUPING_FACTOR,
    .TAGGED_CHUNK_SIZE
  ) i_tag_lookup_engine_table_lookups_read (
    .clk_i,
    .rst_ni,
    // incoming interface
    .leaf_idx_i(addr_to_leaf_idx(read_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_idx(read_req_i.a_x_addr)),
    .req_valid_i(read_req_valid_i),
    .req_ready_o(read_req_ready_o),
    .req_i(read_req_i),
    .resp_valid_o(read_resp_valid_o),
    .resp_ready_i(read_resp_ready_i),
    .resp_o(read_resp_o),
    // outgoing root interface
    .root_req_valid_o(root_read_req_valid_o),
    .root_req_ready_i(root_read_req_ready_i),
    .root_req_o(root_read_req_o),
    .root_resp_valid_i(root_read_resp_valid_i),
    .root_resp_ready_o(root_read_resp_ready_o),
    .root_resp_i(root_read_resp_i),
    // outgoing leaf interface
    .leaf_req_valid_o(leaf_read_req_valid_o),
    .leaf_req_ready_i(leaf_read_req_ready_i),
    .leaf_req_o(leaf_read_req_o),
    .leaf_resp_valid_i(leaf_read_resp_valid_i),
    .leaf_resp_ready_o(leaf_read_resp_ready_o),
    .leaf_resp_i(leaf_read_resp_i)
  );
  // tag writes //
  tag_lookup_engine_table_lookups_write #(
    .tag_req_t,
    .tag_data_req_t,
    .tag_write_resp_t,
    .axi_addr_t,
    .GROUPING_FACTOR,
    .TAGGED_CHUNK_SIZE
  ) i_tag_lookup_engine_table_lookups_write (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    // incoming interface
    .leaf_idx_i(addr_to_leaf_idx(write_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_idx(write_req_i.a_x_addr)),
    .req_valid_i(write_req_valid_i),
    .req_ready_o(write_req_ready_o),
    .req_i(write_req_i),
    .data_valid_i(write_data_req_valid_i),
    .data_ready_o(write_data_req_ready_o),
    .data_i(write_data_req_i),
    .resp_valid_o(write_resp_valid_o),
    .resp_ready_i(write_resp_ready_i),
    .resp_o(write_resp_o),
    // outgoing root interface
    .root_req_valid_o(root_write_req_valid_o),
    .root_req_ready_i(root_write_req_ready_i),
    .root_req_o(root_write_req_o),
    .root_data_valid_o(root_write_data_req_valid_o),
    .root_data_ready_i(root_write_data_req_ready_i),
    .root_data_o(root_write_data_req_o),
    .root_resp_valid_i(root_write_resp_valid_i),
    .root_resp_ready_o(root_write_resp_ready_o),
    .root_resp_i(root_write_resp_i),
    // outgoing leaf interface
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

module tag_lookup_engine_table_lookups_read #(
  parameter type tag_req_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16
) (
  input  logic           clk_i,
  input  logic           rst_ni,
  // incoming interface
  input  axi_addr_t      leaf_idx_i,
  input  axi_addr_t      root_idx_i,
  input  logic           req_valid_i,
  output logic           req_ready_o,
  input  tag_req_t       req_i,
  output logic           resp_valid_o,
  input  logic           resp_ready_i,
  output tag_read_resp_t resp_o,
  // outgoing root interface
  output logic           root_req_valid_o,
  input  logic           root_req_ready_i,
  output tag_req_t       root_req_o,
  input  logic           root_resp_valid_i,
  output logic           root_resp_ready_o,
  input  tag_read_resp_t root_resp_i,
  // outgoing leaf interface
  output logic           leaf_req_valid_o,
  input  logic           leaf_req_ready_i,
  output tag_req_t       leaf_req_o,
  input  logic           leaf_resp_valid_i,
  output logic           leaf_resp_ready_o,
  input  tag_read_resp_t leaf_resp_i
);

  function automatic tag_req_t desc_with_addr(tag_req_t desc, axi_addr_t addr);
    desc_with_addr = desc;
    desc_with_addr.a_x_addr = addr;
    return desc_with_addr;
  endfunction

  // remember if we sent a request on outgoing interface
  logic root_sent_q, root_sent_d;
  logic leaf_sent_q, leaf_sent_d;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      root_sent_q <= 1'b0;
      leaf_sent_q <= 1'b0;
    end else begin
      root_sent_q <= root_sent_d;
      leaf_sent_q <= leaf_sent_d;
    end
  end

  // produce handshake signals
  logic root_req_valid, leaf_req_valid, req_ready;
  assign root_req_valid = req_valid_i && !root_sent_q;
  assign leaf_req_valid = req_valid_i && !leaf_sent_q;
  assign req_ready = req_valid_i && (root_sent_q || (root_req_valid && root_req_ready_i))
                                 && (leaf_sent_q || (leaf_req_valid && leaf_req_ready_i));
  always_comb begin
    root_sent_d = root_sent_q;
    leaf_sent_d = leaf_sent_q;
    if (root_req_valid && root_req_ready_i) root_sent_d = 1'b1;
    if (leaf_req_valid && leaf_req_ready_i) leaf_sent_d = 1'b1;
    if (req_valid_i && req_ready) begin
      root_sent_d = 1'b0;
      leaf_sent_d = 1'b0;
    end
  end

  // outgoing interface requests
  assign root_req_valid_o = root_req_valid;
  assign root_req_o = desc_with_addr(req_i, root_idx_i);
  assign leaf_req_valid_o = leaf_req_valid;
  assign leaf_req_o = req_i;
  // incoming interface request
  assign req_ready_o = req_ready;

  // TODO responses, leaf only for now, drop root
  assign root_resp_ready_o = 1'b1;
  assign leaf_resp_ready_o = resp_ready_i;
  assign resp_valid_o = leaf_resp_valid_i;
  assign resp_o = leaf_resp_i;

endmodule

module tag_lookup_engine_table_lookups_write #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16
) (
  input  logic            clk_i,
  input  logic            rst_ni,
  // incoming interface
  input  axi_addr_t       leaf_idx_i,
  input  axi_addr_t       root_idx_i,
  input  logic            req_valid_i,
  output logic            req_ready_o,
  input  tag_req_t        req_i,
  input  logic            data_valid_i,
  output logic            data_ready_o,
  input  tag_data_req_t   data_i,
  output logic            resp_valid_o,
  input  logic            resp_ready_i,
  output tag_write_resp_t resp_o,
  // outgoing root interface
  output logic            root_req_valid_o,
  input  logic            root_req_ready_i,
  output tag_req_t        root_req_o,
  output logic            root_data_valid_o,
  input  logic            root_data_ready_i,
  output tag_data_req_t   root_data_o,
  input  logic            root_resp_valid_i,
  output logic            root_resp_ready_o,
  input  tag_write_resp_t root_resp_i,
  // outgoing leaf interface
  output logic            leaf_req_valid_o,
  input  logic            leaf_req_ready_i,
  output tag_req_t        leaf_req_o,
  output logic            leaf_data_valid_o,
  input  logic            leaf_data_ready_i,
  output tag_data_req_t   leaf_data_o,
  input  logic            leaf_resp_valid_i,
  output logic            leaf_resp_ready_o,
  input  tag_write_resp_t leaf_resp_i
);

  // TODO
  // This module will also require a read interface to enable folding back 0 to the root when
  // possible... reading 512 leaf bits is not feasible with the 4-bit cache interface we are using..
  // or instead, if as a result of a write into a 512 bit chunk aligned, the word becomes 0, this in the
  // write resp...

  // outgoing root interface //
  /////////////////////////////
  assign root_req_valid_o = 1'b0;
  assign root_data_valid_o = 1'b0;
  assign root_resp_ready_o = 1'b1;

  // outgoing leaf interface //
  /////////////////////////////
  assign leaf_req_valid_o = req_valid_i;
  assign leaf_req_o = req_i;
  assign leaf_data_valid_o = data_valid_i;
  assign leaf_data_o = data_i;
  assign leaf_resp_ready_o = resp_ready_i;

  // incoming interface //
  ////////////////////////
  assign req_ready_o = leaf_req_ready_i;
  assign data_ready_o = leaf_data_ready_i;
  assign resp_valid_o = leaf_resp_valid_i;
  assign resp_o = leaf_resp_i;

endmodule
