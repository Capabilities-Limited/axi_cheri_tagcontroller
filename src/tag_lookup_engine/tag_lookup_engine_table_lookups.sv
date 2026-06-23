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

  // TODO
  assign root_read_req_valid_o[1] = 1'b0;
  assign root_read_req_o[1] = '0;
  assign root_read_resp_ready_o[1]  = 1'b0;

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
    .req_valid_i(write_req_valid_mux),
    .req_ready_o(write_req_ready_mux),
    .req_i(write_req_i),
    .data_valid_i(write_data_req_valid_mux),
    .data_ready_o(write_data_req_ready_mux),
    .data_i(write_data_req_i),
    .resp_valid_o(write_resp_valid_o),
    .resp_ready_i(write_resp_ready_i),
    .resp_o(write_resp_o),
    // outgoing root interface
    .root_req_valid_o(root_write_req_valid_o[0]),
    .root_req_ready_i(root_write_req_ready_i[0]),
    .root_req_o(root_write_req_o[0]),
    .root_data_valid_o(root_write_data_req_valid_o[0]),
    .root_data_ready_i(root_write_data_req_ready_i[0]),
    .root_data_o(root_write_data_req_o[0]),
    .root_resp_valid_i(root_write_resp_valid_i[0]),
    .root_resp_ready_o(root_write_resp_ready_o[0]),
    .root_resp_i(root_write_resp_i[0]),
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

module tag_lookup_engine_root_init #(
  parameter type tag_req_t = logic,
  parameter type tag_data_req_t = logic,
  parameter type tag_write_resp_t = logic,
  parameter type axi_addr_t = logic
) (
  input logic clk_i,
  input logic rst_ni,
  input logic start_i,
  input axi_addr_t root_table_size_i,
  output logic ready_o,
  // write interface
  output logic            root_write_req_valid_o,
  input  logic            root_write_req_ready_i,
  output tag_req_t        root_write_req_o,
  output logic            root_write_data_req_valid_o,
  input  logic            root_write_data_req_ready_i,
  output tag_data_req_t   root_write_data_req_o,
  input  logic            root_write_resp_valid_i,
  output logic            root_write_resp_ready_o,
  input  tag_write_resp_t root_write_resp_i
);

  // FSM state elements
  typedef enum logic [1:0] {
    READY = 2'b00,
    INIT = 2'b01,
    INIT_WAIT_WRITE_RSP = 2'b10
  } state_t;
  state_t state_d, state_q;
  axi_addr_t req_cnt_d, req_cnt_q;
  axi_addr_t resp_cnt_d, resp_cnt_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= READY;
      req_cnt_q <= 0;
      resp_cnt_q <= 0;
    end else begin
      state_q <= state_d;
      req_cnt_q <= req_cnt_d;
      resp_cnt_q <= resp_cnt_d;
    end
  end

  // assert ready_o when in READY state
  assign ready_o = (state_q == READY);

  // prepare write request
  always_comb begin
    // TODO sanity check current place holder values here
    root_write_req_o = '0;
    root_write_req_o.a_x_addr = req_cnt_q;
    root_write_req_o.rw = 1'b1;
    root_write_data_req_o = '0;
  end

  // track hand shakes on each of req/data/resp channels
  logic req_hs, data_hs, resp_hs;
  assign req_hs = root_write_req_valid_o && root_write_req_ready_i;
  assign data_hs = root_write_data_req_valid_o && root_write_data_req_ready_i;
  assign resp_hs = root_write_resp_valid_i && root_write_resp_ready_o;

  // actual state machine
  always_comb begin
    // default assignments
    state_d = state_q;
    req_cnt_d = req_cnt_q;
    resp_cnt_d = resp_cnt_q;
    root_write_req_valid_o = 1'b0;
    root_write_data_req_valid_o = 1'b0;
    root_write_resp_ready_o = 1'b0;

    unique case (state_q)
      READY: begin
        // check whether to start the state machine
        if (start_i) begin
          state_d = INIT;
          req_cnt_d = 0;
          resp_cnt_d = 0;
        end
      end

      // ongoing initialisation
      INIT: begin
        // send a request
        root_write_req_valid_o = 1'b1;
        root_write_data_req_valid_o = 1'b1;

        // book keeping based on handshake happening
        if (req_hs) req_cnt_d = req_cnt_q + 1'b1;
        // check whether the last request was sent
        if (req_hs && (req_cnt_q == root_table_size_i - 1'b1)) begin
          state_d = INIT_WAIT_WRITE_RSP;
        end
        // book keep for responses
        root_write_resp_ready_o = 1'b1;
        if (resp_hs) resp_cnt_d = resp_cnt_q + 1'b1;
      end

      // drain remaining responses
      INIT_WAIT_WRITE_RSP: begin
        // book keep for responses
        root_write_resp_ready_o = 1'b1;
        if (resp_hs) resp_cnt_d = resp_cnt_q + 1'b1;
        // check whether the last response was received
        if (resp_cnt_d == root_table_size_i) begin
          state_d = READY;
        end
      end
    endcase
  end

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
