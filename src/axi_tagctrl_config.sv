module axi_tagctrl_config #(
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned COVERED_ALIGN = 8192,
  parameter int unsigned TAG_STORE_ALIGN = 64,
  parameter type slv_req_t = logic,
  parameter type slv_resp_t = logic,
  parameter type axi_addr_t = logic [63:0],
  parameter axi_addr_t init_covered_base = 64'd0,
  parameter axi_addr_t init_covered_top = 64'd0,
  parameter axi_addr_t init_tag_table_base = 64'd0,
  parameter logic init_start = 1'b0,
  parameter logic init_locked = 1'b1,
  parameter logic allow_resume = 1'b0,
  parameter logic allow_flush_when_locked = 1'b0
) (
  input logic clk_i,
  input logic rst_ni,

  input slv_req_t slv_req_i,
  output slv_resp_t slv_resp_o,

  output axi_addr_t covered_base_addr_o,
  output axi_addr_t covered_top_addr_o,
  output axi_addr_t tag_store_base_addr_o,
  output axi_addr_t tag_store_top_addr_o,
  output axi_addr_t root_table_base_addr_o,
  output axi_addr_t root_table_top_addr_o,
  output axi_addr_t leaf_table_base_addr_o,
  output axi_addr_t leaf_table_top_addr_o,
  output logic [2:0] error_o
);

  function automatic axi_addr_t ceil_div(axi_addr_t value, int unsigned divisor);
    return (value + (divisor - 1)) / divisor;
  endfunction

  function automatic axi_addr_t align_up(axi_addr_t value, int unsigned align);
    return (value + (align - 1)) & ~(align - 1);
  endfunction

  axi_addr_t covered_size_bytes = init_covered_top - init_covered_base;
  axi_addr_t leaf_table_bits = ceil_div(covered_size_bytes, TAGGED_CHUNK_SIZE);
  axi_addr_t leaf_table_bytes = ceil_div(leaf_table_bits, 8);
  axi_addr_t root_table_bits = ceil_div(leaf_table_bits, GROUPING_FACTOR);
  axi_addr_t root_table_bytes = ceil_div(root_table_bits, 8);

  assign covered_base_addr_o = init_covered_base;
  assign covered_top_addr_o = init_covered_top;

  assign leaf_table_base_addr_o = init_tag_table_base;
  assign leaf_table_top_addr_o = leaf_table_base_addr_o + leaf_table_bytes;

  assign root_table_base_addr_o = align_up(leaf_table_top_addr_o, TAG_STORE_ALIGN);
  assign root_table_top_addr_o = root_table_base_addr_o + root_table_bytes;

  assign tag_store_base_addr_o = leaf_table_base_addr_o;
  assign tag_store_top_addr_o = align_up(root_table_top_addr_o, TAG_STORE_ALIGN);

  assign error_o =
    (init_covered_top < init_covered_base)           ? 3'd1 :
    (tag_store_top_addr_o < init_tag_table_base)     ? 3'd2 :
    (|(init_covered_base & (COVERED_ALIGN - 1)))     ? 3'd3 :
    (|(init_covered_top & (COVERED_ALIGN - 1)))      ? 3'd4 :
    (|(init_tag_table_base & (TAG_STORE_ALIGN - 1))) ? 3'd5 :
                                                       3'd0;

endmodule
