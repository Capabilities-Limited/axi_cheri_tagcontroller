module helpers #(
  parameter type tag_req_t = logic,
  parameter type axi_addr_t = logic
)();
  function automatic tag_req_t desc_with_addr(tag_req_t desc, axi_addr_t addr);
    tag_req_t ret = desc;
    ret.a_x_addr = addr;
    return ret;
  endfunction
endmodule

module tag_lookup_engine_table_lookups #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
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
  function automatic axi_addr_t addr_to_leaf_byte_idx(axi_addr_t addr);
    //return (addr >> 3) >> $clog2(TAGGED_CHUNK_SIZE);
    return addr >> 3;
  endfunction
  function automatic axi_addr_t addr_to_root_byte_idx(axi_addr_t addr);
    axi_addr_t leaf_idx = addr_to_leaf_byte_idx(addr);
    return leaf_idx >> $clog2(GROUPING_FACTOR);
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
    .leaf_idx_i(addr_to_leaf_byte_idx(read_req_i.a_x_addr)),
    .root_idx_i(addr_to_root_byte_idx(read_req_i.a_x_addr)),
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
  parameter int unsigned GROUPING_FACTOR = 256,
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

  helpers#(.tag_req_t, .axi_addr_t) h ();

  // registers for request sent / response seen
  logic root_sent_q, root_sent_d, leaf_sent_q, leaf_sent_d;
  logic root_resp_valid_d, root_resp_valid_q, leaf_resp_valid_d, leaf_resp_valid_q;
  tag_read_resp_t root_resp_d, root_resp_q, leaf_resp_d, leaf_resp_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      root_sent_q <= 1'b0;
      leaf_sent_q <= 1'b0;
      root_resp_valid_q <= 1'b0;
      leaf_resp_valid_q <= 1'b0;
    end else begin
      root_sent_q <= root_sent_d;
      leaf_sent_q <= leaf_sent_d;
      root_resp_valid_q <= root_resp_valid_d;
      leaf_resp_valid_q <= leaf_resp_valid_d;
      root_resp_q <= root_resp_d;
      leaf_resp_q <= leaf_resp_d;
    end
  end

  // REQUESTS //
  // produce request forwarding handshake signals
  logic root_req_valid, leaf_req_valid;
  assign root_req_valid = req_valid_i && !root_sent_q;
  assign leaf_req_valid = req_valid_i && !leaf_sent_q;
  // outgoing interface requests
  assign root_req_valid_o = root_req_valid;
  assign root_req_o = h.desc_with_addr(req_i, root_idx_i);
  assign leaf_req_valid_o = leaf_req_valid;
  assign leaf_req_o = req_i;

  // RESPONSES //
  assign root_resp_ready_o = 1'b1;
  assign leaf_resp_ready_o = 1'b1;
  tag_read_resp_t root_resp, leaf_resp;
  assign root_resp = root_resp_valid_i ? root_resp_i : root_resp_q;
  assign leaf_resp = leaf_resp_valid_i ? leaf_resp_i : leaf_resp_q;
  // TODO only test the relevant bit of the root_resp
  assign resp_o = (root_resp == 0) ? root_resp : leaf_resp;

  // bookkeeping signals
  logic all_sent, all_received;
  assign all_sent =    (root_sent_q || (root_req_valid && root_req_ready_i))
                    && (leaf_sent_q || (leaf_req_valid && leaf_req_ready_i));
  assign all_received =    (root_resp_valid_q || root_resp_valid_i)
                        && (leaf_resp_valid_q || leaf_resp_valid_i);

  // lookup control
  always_comb begin
    // default assignements
    root_sent_d = root_sent_q;
    leaf_sent_d = leaf_sent_q;
    root_resp_valid_d = root_resp_valid_q;
    leaf_resp_valid_d = leaf_resp_valid_q;
    root_resp_d = root_resp_q;
    leaf_resp_d = leaf_resp_q;
    // module outputs
    req_ready_o = 1'b0;
    resp_valid_o = 1'b0;

    // requests
    if (root_req_valid && root_req_ready_i) root_sent_d = 1'b1;
    if (leaf_req_valid && leaf_req_ready_i) leaf_sent_d = 1'b1;

    // responses
    if (root_resp_valid_i) begin
      root_resp_valid_d = 1'b1;
      root_resp_d = root_resp_i;
    end
    if (leaf_resp_valid_i) begin
      leaf_resp_valid_d = 1'b1;
      leaf_resp_d = leaf_resp_i;
    end

    // finalise request + reset state
    if (req_valid_i && all_sent && all_received) begin
      // outputs
      req_ready_o = 1'b1;
      resp_valid_o = 1'b1;
      // clear state
      root_sent_d = 1'b0;
      leaf_sent_d = 1'b0;
      root_resp_valid_d = 1'b0;
      leaf_resp_valid_d = 1'b0;
    end
  end

endmodule

module tag_lookup_engine_table_lookups_write #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
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

  localparam int unsigned ROOT_DATA_W = $bits(data_i.data);
  localparam int unsigned ROOT_STRB_W = $bits(data_i.strb);

  helpers #(
    .tag_req_t(tag_req_t),
    .axi_addr_t(axi_addr_t)
  ) h ();

  // book keeping latches:
  // did the root/leaf request and data get sent?
  logic root_req_sent_q, root_req_sent_d;
  logic root_data_sent_q, root_data_sent_d;
  logic leaf_req_sent_q, leaf_req_sent_d;
  logic leaf_data_sent_q, leaf_data_sent_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      root_req_sent_q <= 1'b0;
      root_data_sent_q <= 1'b0;
      leaf_req_sent_q <= 1'b0;
      leaf_data_sent_q <= 1'b0;
    end else begin
      root_req_sent_q <= root_req_sent_d;
      root_data_sent_q <= root_data_sent_d;
      leaf_req_sent_q <= leaf_req_sent_d;
      leaf_data_sent_q <= leaf_data_sent_d;
    end
  end

  // internal signals to determine root/leaf sending was dealt with
  logic root_needed, root_done, leaf_done;
  assign root_needed = |(data_i.bit_en & data_i.data);
  assign root_done = !root_needed || (root_req_sent_q && root_data_sent_q);
  assign leaf_done = leaf_req_sent_q && leaf_data_sent_q;

  localparam int unsigned ROOT_BIT_IDX_W = (ROOT_DATA_W > 1) ? $clog2(ROOT_DATA_W) : 1;
  logic [ROOT_BIT_IDX_W-1:0] root_bit_idx;
  assign root_bit_idx = root_idx_i[ROOT_BIT_IDX_W-1:0];

  // outgoing root interface
  assign root_req_valid_o = req_valid_i && root_needed && !root_req_sent_q;
  assign root_req_o = h.desc_with_addr(req_i, root_idx_i);

  assign root_data_valid_o = data_valid_i && root_needed && !root_data_sent_q;
  assign root_data_o.data = ROOT_DATA_W'('b1) << root_bit_idx;
  assign root_data_o.bit_en = ROOT_DATA_W'('b1) << root_bit_idx;
  assign root_data_o.strb = ROOT_STRB_W'('b1) << (root_bit_idx >> 3);

  assign root_resp_ready_o = 1'b1;

  // outgoing leaf interface
  assign leaf_req_valid_o = req_valid_i  && !leaf_req_sent_q;
  assign leaf_req_o = req_i;

  assign leaf_data_valid_o = data_valid_i && !leaf_data_sent_q;
  assign leaf_data_o = data_i;

  assign leaf_resp_ready_o = resp_ready_i;

  // state updates
  always_comb begin
    root_req_sent_d = root_req_sent_q;
    root_data_sent_d = root_data_sent_q;
    leaf_req_sent_d = leaf_req_sent_q;
    leaf_data_sent_d = leaf_data_sent_q;

    if (root_req_valid_o && root_req_ready_i) root_req_sent_d = 1'b1;
    if (root_data_valid_o && root_data_ready_i) root_data_sent_d = 1'b1;

    if (leaf_req_valid_o && leaf_req_ready_i) leaf_req_sent_d = 1'b1;
    if (leaf_data_valid_o && leaf_data_ready_i) leaf_data_sent_d = 1'b1;

    // transaction sent, reset for next request on incoming interface
    if (req_ready_o && req_valid_i) begin
      root_req_sent_d = 1'b0;
      root_data_sent_d = 1'b0;
      leaf_req_sent_d = 1'b0;
      leaf_data_sent_d = 1'b0;
    end
  end

  // incoming interface
  assign req_ready_o = root_done && leaf_done;
  assign data_ready_o = root_done && leaf_done;
  // TODO consider root responses
  assign resp_valid_o = leaf_resp_valid_i;
  assign resp_o = leaf_resp_i;

endmodule
