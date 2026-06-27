module write_lookup_helpers #(
  parameter type tag_req_t = logic,
  parameter type axi_addr_t = logic,
  parameter type axi_slv_id_t = logic
)();
  function automatic tag_req_t desc_with_addr(tag_req_t desc, axi_addr_t addr);
    tag_req_t ret = desc;
    ret.a_x_addr = addr;
    return ret;
  endfunction
  function automatic tag_req_t simple_read_desc(axi_slv_id_t id, axi_addr_t addr);
    tag_req_t ret = '0;
    ret.a_x_id = id;
    ret.a_x_addr = addr;
    ret.a_x_len = '0;
    ret.a_x_size = '0;
    ret.a_x_burst = '0;
    ret.a_x_lock = '0;
    ret.a_x_cache = '0;
    ret.a_x_prot = '0;
    ret.x_resp = '0;
    ret.x_last = 1'b1;
    // Cache specific descriptor signals
    ret.spm = '0;
    ret.rw = '0; // read
    ret.way_ind = '0;
    ret.evict = '0;
    ret.evict_tag = '0;
    ret.refill = '0;
    ret.flush = '0;
    return ret;
  endfunction
endmodule

module tag_lookup_engine_table_lookups_write #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type tag_read_resp_t = logic,
  parameter type axi_addr_t = logic,
  parameter type axi_slv_id_t = logic,
  parameter int unsigned GROUPING_FACTOR = 256,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned MAX_IN_FLIGHT = 4
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
  // outgoing root read interface
  output logic            root_rd_req_valid_o,
  input  logic            root_rd_req_ready_i,
  output tag_req_t        root_rd_req_o,
  input  logic            root_rd_resp_valid_i,
  output logic            root_rd_resp_ready_o,
  input  tag_read_resp_t  root_rd_resp_i,
  // outgoing root write interface
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

  localparam int unsigned SB_IDX_W = $clog2(MAX_IN_FLIGHT);
  localparam int unsigned ROOT_STRB_W = $bits(data_i.strb);
  localparam int unsigned ROOT_DATA_W = $bits(data_i.data);
  localparam int unsigned ROOT_BIT_IDX_W = (ROOT_DATA_W > 1) ? $clog2(ROOT_DATA_W) : 1;

  write_lookup_helpers #(.tag_req_t, .axi_addr_t, .axi_slv_id_t) h ();

  // Scoreboard tracking structure
  typedef struct packed {
    logic allocated;
    logic write_is_nonzero;
    logic root_is_one;
    logic root_rd_sent;
    logic root_rd_received;
    logic root_wr_sent;
    logic root_wr_data_sent;
    logic root_wr_received;
    logic leaf_wr_sent;
    logic leaf_wr_data_sent;
    logic leaf_wr_received;
    logic leaf_wr_resp;
    axi_addr_t root_idx;
    tag_req_t req;
    tag_data_req_t data;
  } sb_entry_t;

  sb_entry_t [MAX_IN_FLIGHT-1:0] sb_d, sb_q;
  logic [SB_IDX_W-1:0] alloc_ptr_d, alloc_ptr_q;
  logic [SB_IDX_W-1:0] retire_ptr_d, retire_ptr_q;

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

  logic accept_req;
  logic [SB_IDX_W-1:0] root_rd_req_idx;
  logic [SB_IDX_W-1:0] root_rd_resp_idx;
  logic [ROOT_BIT_IDX_W-1:0] root_rd_bit_idx;
  logic [SB_IDX_W-1:0] root_wr_req_idx;
  logic [SB_IDX_W-1:0] root_wr_resp_idx;
  logic root_wr_rd_ready, root_wr_needed;
  logic [ROOT_BIT_IDX_W-1:0] root_wr_bit_idx;
  logic [SB_IDX_W-1:0] leaf_wr_req_idx;
  logic [SB_IDX_W-1:0] leaf_wr_resp_idx;
  logic leaf_wr_rd_ready, leaf_wr_needed;
  sb_entry_t curr_sb;
  logic root_rd_done;
  logic root_wr_done;
  logic leaf_wr_done;

  always_comb begin

    // default assignements
    sb_d = sb_q;
    alloc_ptr_d = alloc_ptr_q;
    retire_ptr_d = retire_ptr_q;

    // accept incoming request and allocate score-board entry
    accept_req = !sb_q[alloc_ptr_q].allocated && req_valid_i && data_valid_i;
    req_ready_o = accept_req;
    data_ready_o = accept_req;
    if (accept_req) begin
      sb_d[alloc_ptr_q].allocated = 1'b1;
      sb_d[alloc_ptr_q].write_is_nonzero = |(data_i.bit_en & data_i.data);
      sb_d[alloc_ptr_q].root_is_one = 1'b0;
      sb_d[alloc_ptr_q].root_rd_sent = 1'b0;
      sb_d[alloc_ptr_q].root_rd_received = 1'b0;
      sb_d[alloc_ptr_q].root_wr_sent = 1'b0;
      sb_d[alloc_ptr_q].root_wr_data_sent = 1'b0;
      sb_d[alloc_ptr_q].root_wr_received = 1'b0;
      sb_d[alloc_ptr_q].leaf_wr_sent = 1'b0;
      sb_d[alloc_ptr_q].leaf_wr_data_sent = 1'b0;
      sb_d[alloc_ptr_q].leaf_wr_received = 1'b0;
      sb_d[alloc_ptr_q].root_idx = root_idx_i;
      sb_d[alloc_ptr_q].req = req_i;
      sb_d[alloc_ptr_q].data = data_i;
      alloc_ptr_d = alloc_ptr_q + 1;
    end

    // root reads //
    ////////////////
    // send needed root read requests
    root_rd_req_valid_o = 1'b0;
    for (int unsigned i = 0; i < MAX_IN_FLIGHT; i++) begin
      root_rd_req_idx = retire_ptr_q + i;
      if ( sb_d[root_rd_req_idx].allocated &&
           !sb_d[root_rd_req_idx].write_is_nonzero &&
           !sb_d[root_rd_req_idx].root_rd_sent ) begin
        root_rd_req_valid_o = 1'b1;
        root_rd_req_o = h.simple_read_desc(root_rd_req_idx[$bits(req_i.a_x_id)-1:0], sb_d[root_rd_req_idx].root_idx);
        if (root_rd_req_ready_i) sb_d[root_rd_req_idx].root_rd_sent = 1'b1;
        break;
      end
    end
    // collect root read responses
    root_rd_resp_ready_o = 1'b1;
    if (root_rd_resp_valid_i) begin
      root_rd_resp_idx = root_rd_resp_i.id[SB_IDX_W-1:0];
      root_rd_bit_idx = sb_d[root_rd_resp_idx].root_idx[ROOT_BIT_IDX_W-1:0];
      sb_d[root_rd_resp_idx].root_rd_received = 1'b1;
      sb_d[root_rd_resp_idx].root_is_one = root_rd_resp_i.data[root_rd_bit_idx];
    end

    // root writes //
    /////////////////
    // send needed root write requests
    root_req_valid_o = 1'b0;
    root_data_valid_o = 1'b0;
    for (int unsigned i = 0; i < MAX_IN_FLIGHT; i++) begin
      root_wr_req_idx = retire_ptr_q + i;
      root_wr_rd_ready = sb_d[root_wr_req_idx].write_is_nonzero || sb_d[root_wr_req_idx].root_rd_received;
      root_wr_needed = sb_d[root_wr_req_idx].write_is_nonzero && !sb_d[root_wr_req_idx].root_is_one;
      root_wr_bit_idx = sb_d[root_wr_req_idx].root_idx[ROOT_BIT_IDX_W-1:0];

      if (sb_d[root_wr_req_idx].allocated && root_wr_rd_ready && root_wr_needed) begin
        if (!sb_d[root_wr_req_idx].root_wr_sent) begin
          root_req_valid_o = 1'b1;
          root_req_o = h.desc_with_addr(sb_d[root_wr_req_idx].req, sb_d[root_wr_req_idx].root_idx);
          root_req_o.a_x_id = root_wr_req_idx[$bits(req_i.a_x_id)-1:0];
          if (root_req_ready_i) sb_d[root_wr_req_idx].root_wr_sent = 1'b1;
        end
        if (!sb_d[root_wr_req_idx].root_wr_data_sent) begin
          root_data_valid_o = 1'b1;
          root_data_o.data = ROOT_DATA_W'('b1) << root_wr_bit_idx;
          root_data_o.bit_en = ROOT_DATA_W'('b1) << root_wr_bit_idx;
          root_data_o.strb = ROOT_STRB_W'('b1) << (root_wr_bit_idx >> 3);
          if (root_data_ready_i) sb_d[root_wr_req_idx].root_wr_data_sent = 1'b1;
        end
        if (!sb_d[root_wr_req_idx].root_wr_sent || !sb_d[root_wr_req_idx].root_wr_data_sent) break;
      end
    end
    // collect root write responses
    root_resp_ready_o = 1'b1;
    if (root_resp_valid_i) begin
      root_wr_resp_idx = root_resp_i.id[SB_IDX_W-1:0];
      sb_d[root_wr_resp_idx].root_wr_received = 1'b1;
    end

    // leaf writes //
    /////////////////
    // send needed leaf write requests
    leaf_req_valid_o = 1'b0;
    leaf_data_valid_o = 1'b0;
    for (int unsigned i = 0; i < MAX_IN_FLIGHT; i++) begin
      leaf_wr_req_idx = retire_ptr_q + i;
      leaf_wr_rd_ready = sb_d[leaf_wr_req_idx].write_is_nonzero || sb_d[leaf_wr_req_idx].root_rd_received;
      leaf_wr_needed = sb_d[leaf_wr_req_idx].write_is_nonzero || sb_d[leaf_wr_req_idx].root_is_one;

      if (sb_d[leaf_wr_req_idx].allocated && leaf_wr_rd_ready && leaf_wr_needed) begin
        if (!sb_d[leaf_wr_req_idx].leaf_wr_sent) begin
          leaf_req_valid_o = 1'b1;
          leaf_req_o = sb_d[leaf_wr_req_idx].req;
          leaf_req_o.a_x_id = leaf_wr_req_idx[$bits(req_i.a_x_id)-1:0];
          if (leaf_req_ready_i) sb_d[leaf_wr_req_idx].leaf_wr_sent = 1'b1;
        end
        if (!sb_d[leaf_wr_req_idx].leaf_wr_data_sent) begin
          leaf_data_valid_o = 1'b1;
          leaf_data_o = sb_d[leaf_wr_req_idx].data;
          if (leaf_data_ready_i) sb_d[leaf_wr_req_idx].leaf_wr_data_sent = 1'b1;
        end
        if (!sb_d[leaf_wr_req_idx].leaf_wr_sent || !sb_d[leaf_wr_req_idx].leaf_wr_data_sent) break;
      end
    end
    // collect leaf write responses
    leaf_resp_ready_o = 1'b1;
    if (leaf_resp_valid_i) begin
      leaf_wr_resp_idx = leaf_resp_i.id[SB_IDX_W-1:0];
      sb_d[leaf_wr_resp_idx].leaf_wr_received = 1'b1;
      sb_d[leaf_wr_resp_idx].leaf_wr_resp = leaf_resp_i;
    end

    // retire //
    ////////////
    resp_valid_o = 1'b0;
    resp_o = '0;

    curr_sb = sb_d[retire_ptr_q];
    root_rd_done = curr_sb.write_is_nonzero || curr_sb.root_rd_received;
    root_wr_done = !(curr_sb.write_is_nonzero && !curr_sb.root_is_one) || curr_sb.root_wr_received;
    leaf_wr_done = !(curr_sb.write_is_nonzero ||  curr_sb.root_is_one) || curr_sb.leaf_wr_received;

    if (curr_sb.allocated && root_rd_done && root_wr_done && leaf_wr_done) begin
      resp_valid_o = 1'b1;
      resp_o = curr_sb.leaf_wr_resp;
      resp_o.id = curr_sb.req.a_x_id;

      if (resp_ready_i) begin
        sb_d[retire_ptr_q].allocated = 1'b0;
        retire_ptr_d = retire_ptr_q + 1;
      end
    end
  end

endmodule
