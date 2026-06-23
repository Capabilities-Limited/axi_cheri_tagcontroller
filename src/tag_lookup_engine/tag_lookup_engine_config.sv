// This module dynamically produces derivative configuration values
// based off of the user provided addresses for covered region and
// store region, and produces configuration errors when relevant.
module tag_lookup_engine_config #(
  parameter type addr_t = logic [63:0],
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned COVERED_ALIGN = 8192,
  parameter int unsigned TAG_STORE_ALIGN = 64
) (
  input  addr_t covered_base_addr_i,
  input  addr_t covered_top_addr_i,
  input  addr_t tag_store_base_addr_i,

  output addr_t leaf_table_base_addr_o,
  output addr_t leaf_table_top_addr_o,
  output addr_t root_table_base_addr_o,
  output addr_t root_table_top_addr_o,
  output addr_t tag_store_top_addr_o,
  output logic [2:0] error_o
);

  function automatic addr_t align_up(addr_t value, int unsigned align);
    return (value + (align - 1)) & ~(align - 1);
  endfunction

  function automatic addr_t ceil_div(addr_t value, int unsigned divisor);
    return (value + (divisor - 1)) / divisor;
  endfunction

  addr_t covered_size_bytes = covered_top_addr_i - covered_base_addr_i;
  addr_t leaf_table_bits = ceil_div(covered_size_bytes, TAGGED_CHUNK_SIZE);
  addr_t leaf_table_bytes = ceil_div(leaf_table_bits, 8);
  addr_t root_table_bits = ceil_div(leaf_table_bits, GROUPING_FACTOR);
  addr_t root_table_bytes = ceil_div(root_table_bits, 8);

  assign leaf_table_base_addr_o = tag_store_base_addr_i;
  assign leaf_table_top_addr_o = leaf_table_base_addr_o + leaf_table_bytes;

  assign root_table_base_addr_o = align_up(leaf_table_top_addr_o, TAG_STORE_ALIGN);
  assign root_table_top_addr_o = root_table_base_addr_o + root_table_bytes;

  assign tag_store_top_addr_o = align_up(root_table_top_addr_o, TAG_STORE_ALIGN);

  assign error_o =
    (covered_top_addr_i < covered_base_addr_i)         ? 3'd1 :
    (tag_store_top_addr_o < tag_store_base_addr_i)     ? 3'd2 :
    (|(covered_base_addr_i & (COVERED_ALIGN - 1)))     ? 3'd3 :
    (|(covered_top_addr_i & (COVERED_ALIGN - 1)))      ? 3'd4 :
    (|(tag_store_base_addr_i & (TAG_STORE_ALIGN - 1))) ? 3'd5 :
                                                         3'd0;

endmodule
