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

module tag_lookup_engine_table_lookups_read #(
  parameter type tag_req_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned MAX_IN_FLIGHT = 4
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

  // Scoreboard for tag read requests
  localparam int unsigned SB_IDX_W = $clog2(MAX_IN_FLIGHT);
  typedef struct packed {
    logic allocated;
    logic root_sent;
    logic leaf_sent;
    logic root_received;
    logic leaf_received;
    tag_read_resp_t root_resp;
    tag_read_resp_t leaf_resp;
    axi_addr_t root_idx;
    tag_req_t req_payload;
    logic [$bits(req_i.a_x_id)-1:0] og_id;
  } sb_entry_t;
  sb_entry_t [MAX_IN_FLIGHT-1:0] sb_q, sb_d;
  logic [SB_IDX_W-1:0] alloc_ptr_q, alloc_ptr_d;
  logic [SB_IDX_W-1:0] retire_ptr_q, retire_ptr_d;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_q <= '0;
      alloc_ptr_q <= '0;
      retire_ptr_q <= '0;
    end else begin
      sb_q <= sb_d;
      alloc_ptr_q <= alloc_ptr_d;
      retire_ptr_q <= retire_ptr_d;
    end
  end

  // Service tag read requests
  always_comb begin
    // Default register assignments
    sb_d = sb_q;
    alloc_ptr_d = alloc_ptr_q;
    retire_ptr_d = retire_ptr_q;

    // Score board entry allocation //
    // allow consumption of incoming request if score board entry pointed at by
    // the allocation pointer isn't already allocated
    req_ready_o = !sb_q[alloc_ptr_q].allocated;
    // if a request is presente and consumed, allocate it to the score board
    if (req_valid_i && req_ready_o) begin
      sb_d[alloc_ptr_q].allocated = 1'b1;
      sb_d[alloc_ptr_q].root_sent = 1'b0;
      sb_d[alloc_ptr_q].leaf_sent = 1'b0;
      sb_d[alloc_ptr_q].root_received = 1'b0;
      sb_d[alloc_ptr_q].leaf_received = 1'b0;
      sb_d[alloc_ptr_q].root_idx = root_idx_i;
      sb_d[alloc_ptr_q].req_payload = req_i;
      sb_d[alloc_ptr_q].og_id = req_i.a_x_id;
      alloc_ptr_d = alloc_ptr_q + 1; // bump allocation slot
    end

    // root requests handling //
    // don't send any root requests ...
    root_req_valid_o = 1'b0;
    for (int unsigned i = 0; i < MAX_IN_FLIGHT; i++) begin
      // keep idx stable by starting search from retire pointer
      // (in case of alloc wrap around, starting from 0 risks changing selected req)
      automatic logic [SB_IDX_W-1:0] idx = retire_ptr_q + i;
      // ... until we find an allocated entry without the root request sent
      if (sb_d[idx].allocated && !sb_d[idx].root_sent) begin
        root_req_valid_o = 1'b1;
        root_req_o = h.desc_with_addr(sb_d[idx].req_payload, sb_d[idx].root_idx);
        root_req_o.a_x_id = idx[$bits(req_i.a_x_id)-1:0]; // use scoreboard idx as id
        if (root_req_ready_i) sb_d[idx].root_sent = 1'b1;
        break; // maximum 1 request per cycle
      end
    end

    // leaf requests handling //
    leaf_req_valid_o = 1'b0;
    for (int unsigned i = 0; i < MAX_IN_FLIGHT; i++) begin
      automatic logic [SB_IDX_W-1:0] idx = retire_ptr_q + i;
      if (sb_d[idx].allocated && !sb_d[idx].leaf_sent) begin
        leaf_req_valid_o = 1'b1;
        leaf_req_o = sb_d[idx].req_payload;
        leaf_req_o.a_x_id = idx[$bits(req_i.a_x_id)-1:0];
        if (leaf_req_ready_i) sb_d[idx].leaf_sent = 1'b1;
        break;
      end
    end

    // root responses handling //
    // always accept and simply update the pointed scoreboard entry
    root_resp_ready_o = 1'b1;
    if (root_resp_valid_i) begin
      automatic logic [SB_IDX_W-1:0] r_idx = root_resp_i.id[SB_IDX_W-1:0];
      sb_d[r_idx].root_received = 1'b1;
      sb_d[r_idx].root_resp = root_resp_i;
    end

    // leaf responses handling //
    leaf_resp_ready_o = 1'b1;
    if (leaf_resp_valid_i) begin
      automatic logic [SB_IDX_W-1:0] l_idx = leaf_resp_i.id[SB_IDX_W-1:0];
      sb_d[l_idx].leaf_received = 1'b1;
      sb_d[l_idx].leaf_resp = leaf_resp_i;
    end

    // retire scoreboard entry //
    resp_valid_o = 1'b0; // don't send any response until ...
    // ... all responses are received for the entry in the retire slot
    if (sb_d[retire_ptr_q].allocated &&
        sb_d[retire_ptr_q].root_received &&
        sb_d[retire_ptr_q].leaf_received) begin
      resp_valid_o = 1'b1; // send response
      // TODO only test the relevant bit of the root_resp
      if (sb_d[retire_ptr_q].root_resp == 0) resp_o = sb_d[retire_ptr_q].root_resp;
      else resp_o = sb_d[retire_ptr_q].leaf_resp;
      resp_o.id = sb_d[retire_ptr_q].og_id; // overwrite id with original request id
      if (resp_ready_i) begin // when the response is consumed ...
        sb_d[retire_ptr_q].allocated = 1'b0; // deallocate scoreboard entry
        retire_ptr_d = retire_ptr_q + 1; // bump retire slot
      end
    end
  end

endmodule
