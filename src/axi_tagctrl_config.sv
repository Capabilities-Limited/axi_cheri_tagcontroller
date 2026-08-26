module axi_tagctrl_config #(
  parameter int unsigned GROUPING_FACTOR = 512,
  parameter int unsigned TAGGED_CHUNK_SIZE = 16,
  parameter int unsigned COVERED_ALIGN = 8192,
  parameter int unsigned TAG_STORE_ALIGN = 64,
  parameter type slv_req_t = logic,
  parameter type slv_resp_t = logic,
  parameter type ar_chan_t = logic,
  parameter type r_chan_t = logic,
  parameter type aw_chan_t = logic,
  parameter type w_chan_t = logic,
  parameter type b_chan_t = logic,
  parameter type axi_addr_t = logic [63:0],
  parameter axi_addr_t init_covered_base = 64'd0,
  parameter axi_addr_t init_covered_top = 64'd0,
  parameter axi_addr_t init_tag_table_base = 64'd0,
  parameter logic init_start = 1'b0,
  parameter logic init_locked = 1'b1,
  parameter logic allow_resume = 1'b0, // TODO consider param
  parameter logic allow_flush_when_locked = 1'b0 // TODO consider param
) (
  input logic clk_i,
  input logic rst_ni,

  input slv_req_t slv_req_i,
  output slv_resp_t slv_resp_o,

  // signaling
  output logic isolate_o,
  input logic isolated_i,
  output logic ignore_tags_o,
  output logic perform_zeroing_o,
  input logic done_zeroing_i,
  output logic perform_flushing_o,
  input logic done_flushing_i,

  // reporting
  output axi_addr_t covered_base_addr_o,
  output axi_addr_t covered_top_addr_o,
  output axi_addr_t tag_store_base_addr_o,
  output axi_addr_t tag_store_top_addr_o,
  output axi_addr_t root_table_base_addr_o,
  output axi_addr_t root_table_top_addr_o,
  output axi_addr_t leaf_table_base_addr_o,
  output axi_addr_t leaf_table_top_addr_o,
  output logic [7:0] error_o
);

  // helper address functions //
  //////////////////////////////

  function automatic axi_addr_t ceil_div(axi_addr_t value, int unsigned divisor);
    return (value + (divisor - 1)) / divisor;
  endfunction

  function automatic axi_addr_t align_up(axi_addr_t value, int unsigned align);
    return (value + (align - 1)) & ~(align - 1);
  endfunction

  // FSM //
  /////////
  typedef enum logic [2:0] { INITIAL,
                             UNCONFIGURED,
                             ZEROING,
                             SERVING,
                             STOPPING,
                             FLUSHING
                           } fsm_state_t;
  fsm_state_t fsm_state_q, fsm_state_d;
  `FFL(fsm_state_q, fsm_state_d, 1'b1, INITIAL, clk_i, rst_ni)
  logic cmd_start, cmd_resume, cmd_stop;
  always_comb begin : config_fsm
    fsm_state_d = fsm_state_q;
    isolate_o = 1'b0;
    ignore_tags_o = 1'b0;
    perform_zeroing_o = 1'b0;
    perform_flushing_o = 1'b0;
    case (fsm_state_q)
      INITIAL: begin
        if (init_start) begin
          perform_zeroing_o = 1'b1;
          fsm_state_d = ZEROING;
        end else begin
          fsm_state_d = UNCONFIGURED;
        end
      end
      UNCONFIGURED: begin
        ignore_tags_o = 1'b1;
        if (cmd_start) begin
          perform_zeroing_o = 1'b1;
          fsm_state_d = ZEROING;
        end else if (cmd_resume) fsm_state_d = SERVING;
      end
      ZEROING: begin
        // isolate_o = 1'b1; TODO isolate
        if (done_zeroing_i) fsm_state_d = SERVING;
      end
      SERVING: begin
        if (cmd_stop) fsm_state_d = STOPPING;
      end
      STOPPING: begin
        // isolate_o = 1'b1; TODO isolate
        if (/*isolated_i*/ 1'b1 /* TODO isolate */) begin
          perform_flushing_o = 1'b1;
          fsm_state_d = FLUSHING;
        end
      end
      FLUSHING: begin
        // isolate_o = 1'b1; TODO isolate
        //if (done_flushing_i) fsm_state_d = UNCONFIGURED;
        fsm_state_d = UNCONFIGURED;
      end
    endcase
  end

  // module registers //
  //////////////////////
  // status
  typedef struct packed {
    logic [39:0] res_63_24;
    logic [7:0] error;
    logic [10:0] res_15_5;
    logic locked;
    logic unconfigured;
    logic stopping;
    logic zeroing;
    logic serving;
  } status_t;
  status_t status_w;
  logic locked_q, locked_d;
  `FFL(locked_q, locked_d, locked_d, init_locked, clk_i, rst_ni)
  // address registers
  axi_addr_t covered_base_q, covered_base_d;
  axi_addr_t covered_top_q, covered_top_d;
  axi_addr_t table_base_q, table_base_d;
  `FFL(covered_base_q, covered_base_d, 1'b1, init_covered_base, clk_i, rst_ni)
  `FFL(covered_top_q, covered_top_d, 1'b1, init_covered_top, clk_i, rst_ni)
  `FFL(table_base_q, table_base_d, 1'b1, init_tag_table_base, clk_i, rst_ni)

  // produce output signals //
  ////////////////////////////

  axi_addr_t covered_size_bytes;
  assign covered_size_bytes = covered_top_q - covered_base_q;
  axi_addr_t leaf_table_bits;
  assign leaf_table_bits = ceil_div(covered_size_bytes, TAGGED_CHUNK_SIZE);
  axi_addr_t leaf_table_bytes;
  assign leaf_table_bytes = ceil_div(leaf_table_bits, 8);
  axi_addr_t root_table_bits;
  assign root_table_bits = ceil_div(leaf_table_bits, GROUPING_FACTOR);
  axi_addr_t root_table_bytes;
  assign root_table_bytes = ceil_div(root_table_bits, 8);

  assign covered_base_addr_o = covered_base_q;
  assign covered_top_addr_o = covered_top_q;

  assign leaf_table_base_addr_o = table_base_q;
  assign leaf_table_top_addr_o = leaf_table_base_addr_o + leaf_table_bytes;

  assign root_table_base_addr_o = align_up(leaf_table_top_addr_o, TAG_STORE_ALIGN);
  assign root_table_top_addr_o = root_table_base_addr_o + root_table_bytes;

  assign tag_store_base_addr_o = leaf_table_base_addr_o;
  assign tag_store_top_addr_o = align_up(root_table_top_addr_o, TAG_STORE_ALIGN);

  assign error_o =
    (covered_top_q < covered_base_q)          ? 8'd1 :
    (tag_store_top_addr_o < table_base_q)     ? 8'd2 :
    (|(covered_base_q & (COVERED_ALIGN - 1))) ? 8'd3 :
    (|(covered_top_q & (COVERED_ALIGN - 1)))  ? 8'd4 :
    (|(table_base_q & (TAG_STORE_ALIGN - 1))) ? 8'd5 :
                                                8'd0;

  // handle reads //
  //////////////////
  // we latch requests to break the comb path
  // (read reqs are smaller than read resps)
  ar_chan_t read_req_q, read_req_d;
  logic read_req_valid_q, read_req_valid_d;
  `FFL(read_req_q, read_req_d, 1'b1, slv_req_t'{default: '0}, clk_i, rst_ni)
  `FFL(read_req_valid_q, read_req_valid_d, 1'b1, 1'b0, clk_i, rst_ni)
  always_comb begin : config_read
    // accept incoming request
    read_req_valid_d = read_req_valid_q;
    read_req_d = read_req_q;
    slv_resp_o.ar_ready = 1'b0;
    if (slv_req_i.ar_valid && !read_req_valid_q) begin
      read_req_valid_d = 1'b1;
      read_req_d = slv_req_i.ar;
      slv_resp_o.ar_ready = 1'b1;
    end
    // handle previously accepted request
    slv_resp_o.r_valid = 1'b0;
    slv_resp_o.r.data = '0;
    slv_resp_o.r.id = read_req_q.id;
    slv_resp_o.r.resp = axi_pkg::RESP_OKAY;
    slv_resp_o.r.last = 1'b1;
    slv_resp_o.r.user = '0;
    if (read_req_valid_q) begin
      case (read_req_q.addr[11:0])
        12'h000: begin
          automatic status_t status = status_t'{default: '0};
          status.error = error_o;
          status.locked = locked_q;
          status.unconfigured = (fsm_state_q == UNCONFIGURED);
          status.stopping = (fsm_state_q inside {STOPPING, FLUSHING});
          status.zeroing = (fsm_state_q == ZEROING);
          status.serving = (fsm_state_q == SERVING);
          slv_resp_o.r.data = status;
        end
        12'h010: slv_resp_o.r.data = covered_base_q;
        12'h018: slv_resp_o.r.data = covered_top_q;
        12'h020: slv_resp_o.r.data = table_base_q;
        12'h028: slv_resp_o.r.data = tag_store_top_addr_o;
      endcase
      // send response
      slv_resp_o.r_valid = 1'b1;
      // if the response is accepted, reset read interface state
      if (slv_req_i.r_ready) begin
        read_req_valid_d = 1'b0;
      end
    end
  end

  // handle writes //
  ///////////////////
  // we latch responses to break the comb path
  // (write resps are smaller than write reqs)
  b_chan_t write_resp_q, write_resp_d;
  logic write_resp_valid_q, write_resp_valid_d;
  `FFL(write_resp_q, write_resp_d, 1'b1, slv_req_t'{default: '0}, clk_i, rst_ni)
  `FFL(write_resp_valid_q, write_resp_valid_d, 1'b1, 1'b0, clk_i, rst_ni)
  always_comb begin : config_write
    automatic logic do_start, do_resume, do_stop, do_lock, do_config, accept, write_valid;
    // categorise write
    type(slv_req_i.w.data) bit_strb = '0;
    for (int unsigned i = 0; i < $bits(slv_req_i.w.strb); i++)
      bit_strb[i*8+:8] = slv_req_i.w.strb[i] ? '1 : '0;
    do_start  = (slv_req_i.aw.addr[11:0] == 12'h008) && |(slv_req_i.w.data & bit_strb & 'h00000001);
    do_resume = (slv_req_i.aw.addr[11:0] == 12'h008) && |(slv_req_i.w.data & bit_strb & 'h00000100);
    do_stop   = (slv_req_i.aw.addr[11:0] == 12'h008) && |(slv_req_i.w.data & bit_strb & 'h00010000);
    do_lock   = (slv_req_i.aw.addr[11:0] == 12'h008) && |(slv_req_i.w.data & bit_strb & 'h01000000);
    do_config = slv_req_i.aw.addr[11:0] inside {12'h010, 12'h018, 12'h020};
    // establish if write is ignored or accepted
    accept = (do_start && (fsm_state_q == UNCONFIGURED)) ||
             (do_resume && (fsm_state_q == UNCONFIGURED)) ||
             (do_stop && (fsm_state_q == SERVING)) ||
             (do_config && (fsm_state_q == UNCONFIGURED)) ||
             do_lock;
    write_valid = slv_req_i.aw_valid && slv_req_i.w_valid; // && slv_req_i.w.last // TODO assert last?
    // no register update by default
    covered_base_d = covered_base_q;
    covered_top_d = covered_top_q;
    table_base_d = table_base_q;
    cmd_start = 1'b0;
    cmd_resume = 1'b0;
    cmd_stop = 1'b0;
    write_resp_valid_d = write_resp_valid_q;
    write_resp_d = write_resp_q;
    slv_resp_o.aw_ready = 1'b0;
    slv_resp_o.w_ready = 1'b0;
    // when write request (AW & W) present and no write is pending
    if (write_valid && !write_resp_valid_q) begin
      // consume write
      slv_resp_o.aw_ready = 1'b1;
      slv_resp_o.w_ready = 1'b1;
      // prepare response
      write_resp_valid_d = 1'b1;
      write_resp_d.id = slv_req_i.aw.id;
      write_resp_d.resp = axi_pkg::RESP_OKAY;
      write_resp_d.user = '0;
      // when write is not ignored, perform desired effect
      if (accept) begin
        case (slv_req_i.aw.addr[11:0])
          12'h008: begin
            if (do_start) cmd_start = 1'b1;
            else if (do_resume) cmd_resume = 1'b1;
            else if (do_stop) cmd_stop = 1'b1;
          end
          12'h010: begin
            covered_base_d = slv_req_i.w.data & bit_strb;
          end
          12'h018: begin
            covered_top_d = slv_req_i.w.data & bit_strb;
          end
          12'h020: begin
            table_base_d = slv_req_i.w.data & bit_strb;
          end
        endcase
      end
    end

    slv_resp_o.b_valid = 1'b0;
    slv_resp_o.b = write_resp_q;
    // send response
    if (write_resp_valid_q) begin
      // default b response
      slv_resp_o.b_valid = 1'b1;
      // if the response is accepted, reset write interface state
      if (slv_req_i.b_ready) begin
        write_resp_valid_d = 1'b0;
      end
    end

  end

endmodule
