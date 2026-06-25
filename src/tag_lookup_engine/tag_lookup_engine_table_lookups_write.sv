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
