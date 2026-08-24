module read_buffer #(
    parameter   RAM_DEPTH = 32,
    parameter   BUF_DEPTH = 8,
    parameter   BUSY_BOARD_DEPTH = 3,
    parameter   DWIDTH = 16
)(
    input   clk,
    input   rstn,

    input   i_valid,     // 操作使能
    output  i_ready,
    input   i_opcode,
    input   [$clog2(RAM_DEPTH)-1:0] i_addr,
    input   [DWIDTH-1:0] i_ins,

// interface with ram
    output  o_ram_ren,
    output  [$clog2(RAM_DEPTH)-1:0] o_ram_raddr,

    input   i_ram_rvalid,
    input   [$clog2(RAM_DEPTH)-1:0] i_ram_raddr,
    input   [DWIDTH-1:0]            i_ram_rdata,

// interface with ALU
    output  logic o_add_valid,
    input   o_add_ready,
    output  [DWIDTH-1:0]    o_add_ins,
    output  [$clog2(RAM_DEPTH)-1:0] o_add_addr,
    output  [DWIDTH-1:0]    o_add_data,

    output  logic o_mul_valid,
    input   o_mul_ready,
    output  [DWIDTH-1:0]    o_mul_ins,
    output  [$clog2(RAM_DEPTH)-1:0] o_mul_addr,
    output  [DWIDTH-1:0]    o_mul_data,

    input   i_ram_wvalid,
    input   [$clog2(RAM_DEPTH)-1:0]    i_ram_waddr,
    input   [DWIDTH-1:0]    i_ram_wdata
);

    localparam  EWIDTH = 1 + 1 + 1 + 1 + DWIDTH + $clog2(RAM_DEPTH) + DWIDTH;  // {op,busy,w_rdy,r_rdy,ins,addr,data}
    localparam  DATA_BASE = 0;
    localparam  ADDR_BASE = DWIDTH;
    localparam  INS_BASE = ADDR_BASE + $clog2(RAM_DEPTH);
    localparam  R_RDY_BASE = INS_BASE + DWIDTH;
    localparam  W_RDY_BASE = R_RDY_BASE + 1;
    localparam  BUSY_BASE = W_RDY_BASE + 1;
    localparam  OP_BASE = BUSY_BASE + 1;

    logic   push;
    logic   pop;
    logic   add_pop;
    logic   mul_pop;

    logic   [BUF_DEPTH-1:0][EWIDTH-1:0] buf_entry;

    logic   [BUF_DEPTH-1:0]         buf_addr_match;
    logic   [BUF_DEPTH-1:0]         buf_entry_valid;
    logic   [$clog2(BUF_DEPTH)-1:0] buf_allocate_entry;

    logic   [$clog2(BUF_DEPTH)-1:0] op_pop_entry;
    logic   [BUF_DEPTH-1:0]         entry_addr_pop_match;

    logic   [$clog2(RAM_DEPTH)-1:0] pop_addr;
    logic   pop_opcode;
    logic   [DWIDTH-1:0] pop_data;
    logic   [DWIDTH-1:0] pop_ins;

// match with buf_entry
    logic   [BUF_DEPTH-1:0]     entry_raddr_match;
    logic   [BUF_DEPTH-1:0]     entry_waddr_match;
// match with waddr/raddr
    logic   [EWIDTH-1:0]    buf_entry_writein;

    logic   [BUSY_BOARD_DEPTH-1:0][$clog2(RAM_DEPTH)-1:0]   busy_board_addr;
    logic   [BUSY_BOARD_DEPTH-1:0]  busy_board_valid;
    logic   [$clog2(BUSY_BOARD_DEPTH)-1:0]  busy_board_allocate_entry;
    logic   [BUSY_BOARD_DEPTH-1:0]  busy_board_addr_match;
    logic   [RAM_DEPTH-1:0]         addr_accessed;

    logic   [BUF_DEPTH-1:0]     op_ready_for_arb;

// =============== common control ================== //

    assign  push = i_valid && i_ready;
    assign  add_pop = o_add_valid && o_add_ready;
    assign  mul_pop = o_mul_valid && o_mul_ready;
    assign  pop = add_pop | mul_pop;
    assign  i_ready = ~&buf_entry_valid;

// ================= entry_allocator for entry ==================== //

    always_ff @(posedge clk) begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            if(~rstn)
                buf_entry_valid[i] <= 1'b0;
            else if(push && (buf_allocate_entry == i))
                buf_entry_valid[i] <= 1'b1;
            else if(pop && (op_pop_entry == i))
                buf_entry_valid[i] <= 1'b0;
        end
    end
    
    always_comb begin
        buf_allocate_entry = 'd0;
        for(int i=BUF_DEPTH-1;i>=0;i=i-1) begin
            if(buf_entry_valid[i] == 1'b0)
                buf_allocate_entry = i;
        end
    end

// ===================== input ========================= //
// 1. detect addr match with raddr/waddr
// 2. detect addr match with busy_board
// 3. detect addr match with buf

    always_comb begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin 
            if(push && buf_entry_valid[i] && (i_addr == buf_entry[i][ADDR_BASE+:$clog2(RAM_DEPTH)]))
                buf_addr_match[i] = 1'b1;
            else
                buf_addr_match[i] = 1'b0;
        end     
    end

    always_comb begin
        for(int i=0;i<BUSY_BOARD_DEPTH;i=i+1) begin 
            if(push && busy_board_valid[i] && (i_addr == busy_board_addr[i]))
                busy_board_addr_match[i] = 1'b1;
            else
                busy_board_addr_match[i] = 1'b0;
        end       
    end

    always_comb begin
        // 初始化busy位，先查询busy board，其次匹配输入
        buf_entry_writein[BUSY_BASE] = (|busy_board_addr_match); 
        // 写入的优先级高于清零
        if(push && pop && (i_addr == pop_addr))
            buf_entry_writein[BUSY_BASE] = 1'b1;
        else if(push && i_ram_wvalid && (i_addr == i_ram_waddr))
            buf_entry_writein[BUSY_BASE] = 1'b0;      
    end


    always_comb begin
        buf_entry_writein[DATA_BASE+:DWIDTH] = 'd0;
        buf_entry_writein[ADDR_BASE+:$clog2(RAM_DEPTH)] = i_addr;
        buf_entry_writein[INS_BASE+:DWIDTH] = i_ins;
        buf_entry_writein[R_RDY_BASE] = 1'b0;
        buf_entry_writein[W_RDY_BASE] = 1'b0;
        buf_entry_writein[OP_BASE] = i_opcode;
        if(push && i_ram_wvalid && (i_addr == i_ram_waddr)) begin
            buf_entry_writein[DATA_BASE+:DWIDTH] = i_ram_wdata;
            buf_entry_writein[W_RDY_BASE] = 1'b1;
        end
        else if(push && i_ram_rvalid && (i_addr == i_ram_raddr)) begin
            buf_entry_writein[DATA_BASE+:DWIDTH] = i_ram_rdata;
            buf_entry_writein[R_RDY_BASE] = 1'b1;
        end
        else if(push && ~addr_accessed[i_addr]) begin // 当RAM未初始化，直接以0作为结果
            buf_entry_writein[R_RDY_BASE] = 1'b1;
        end
    end

// ======================= entry w/raddr match detect ======================== //

    always_comb begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            // 需要加上没有写更新的条件
            if(buf_entry_valid[i] && i_ram_rvalid && (i_ram_raddr == buf_entry[i][ADDR_BASE+:$clog2(RAM_DEPTH)]) && ~buf_entry[i][R_RDY_BASE])
                entry_raddr_match[i] = 1'b1;
            else 
                entry_raddr_match[i] = 1'b0;
        end
    end

    always_comb begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            if(buf_entry_valid[i] && i_ram_wvalid && (i_ram_waddr == buf_entry[i][ADDR_BASE+:$clog2(RAM_DEPTH)]))
                entry_waddr_match[i] = 1'b1;
            else 
                entry_waddr_match[i] = 1'b0;
        end
    end

// pop check
    always_comb begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            if(buf_entry_valid[i] && pop && (pop_addr == buf_entry[i][ADDR_BASE+:$clog2(RAM_DEPTH)]))
                entry_addr_pop_match[i] = 1'b1;
            else 
                entry_addr_pop_match[i] = 1'b0;
        end
    end

// ===================================== entry =========================================//

    always_ff @(posedge clk) begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            if(~rstn)
                buf_entry[i] <= 'd0;
            else if(push && (buf_allocate_entry == i)) begin    // write 
                buf_entry[i] <= buf_entry_writein;
            end
            else if(entry_waddr_match[i]) begin
                buf_entry[i][DATA_BASE+:DWIDTH] <= i_ram_wdata;
                buf_entry[i][W_RDY_BASE] <= 1'b1;
                buf_entry[i][BUSY_BASE] <= entry_addr_pop_match[i] ? 1'b1 : 1'b0;
            end
            else if(entry_raddr_match[i]) begin
                buf_entry[i][DATA_BASE+:DWIDTH] <= i_ram_rdata;
                buf_entry[i][R_RDY_BASE] <= 1'b1;
                buf_entry[i][BUSY_BASE] <= entry_addr_pop_match[i] ? 1'b1 : 1'b0;  
            end
            else if(entry_addr_pop_match[i])    // 当指令弹出的时候，既要更新busy board，也要更新表项的busy信号
                buf_entry[i][BUSY_BASE] <= 1'b1;
        end
    end

// =============================== address busy board =========================== //

    always_ff @(posedge clk) begin
        for(int i=0;i<BUSY_BOARD_DEPTH;i=i+1) begin
            if(~rstn)
                busy_board_valid[i] <= 1'b0;
            else if(pop && (busy_board_allocate_entry == i))
                busy_board_valid[i] <= 1'b1;
            else if(i_ram_wvalid && busy_board_valid[i] && (i_ram_waddr == busy_board_addr[i]))
                busy_board_valid[i] <= 1'b0;
        end
    end

    always_comb begin
        busy_board_allocate_entry = 'd0;
        for(int i=BUSY_BOARD_DEPTH-1;i>=0;i=i-1) begin
            if(busy_board_valid[i] == 1'b0)
                busy_board_allocate_entry = i;
        end
    end

    always_ff @(posedge clk) begin
        for(int i=0;i<BUSY_BOARD_DEPTH;i=i+1) begin
            if(~rstn)
                busy_board_addr[i] <= 'd0;
            else if(pop && (busy_board_allocate_entry == i))
                busy_board_addr[i] <= pop_addr;
        end
    end

// ================================= age matrix ================================= //

    always_comb begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            // 当没有busy，并且数据已经ready，可以申请仲裁
            if(buf_entry_valid[i] && ~buf_entry[i][BUSY_BASE] && (buf_entry[i][R_RDY_BASE] | buf_entry[i][W_RDY_BASE]))
                op_ready_for_arb[i] = 1'b1;
            else 
                op_ready_for_arb[i] = 1'b0;
        end
    end

    logic   [0:0][$clog2(BUF_DEPTH)-1:0]    tmp_push_way;
    logic   [0:0][BUF_DEPTH-1:0]            tmp_way_enable;
    logic   [0:0][$clog2(BUF_DEPTH)-1:0]    tmp_pop_oldest_way;

    assign  tmp_push_way[0] = buf_allocate_entry;
    // all op ready for arb
    assign  tmp_way_enable[0] = op_ready_for_arb;
    age_matrix #(.UD_NUM(1),.MK_NUM(1),.WAY_NUM(BUF_DEPTH)) u_age_matrix 
    (
        .clk(clk),
        .rstn(rstn),

        .i_update(push),
        .i_way(tmp_push_way),
        .i_enable(tmp_way_enable),

        .o_lru_way(tmp_pop_oldest_way)
    );

    assign  op_pop_entry = tmp_pop_oldest_way[0];

// =========================== addr accessed ========================== //

    logic [RAM_DEPTH-1:0] addr_accessed_set_mask;
    assign  addr_accessed_set_mask = 1 << i_addr;
    always_ff @(posedge clk ) begin
        if(~rstn)
            addr_accessed <= 'd0;
        else if(push)
            addr_accessed <= addr_accessed | addr_accessed_set_mask;
    end

// ============================== output =============================== //
// output with RAM
// 当buf_entry和busy_board地址匹配，不读取RAM，原因是所有指令都是atmoic的，必须写入RAM。因此总能通过写更新得到数据
    assign  o_ram_ren = push && addr_accessed[i_addr] && (~|buf_addr_match) && (~|busy_board_addr_match);
    assign  o_ram_raddr = i_addr;

    assign  pop_addr = buf_entry[op_pop_entry][ADDR_BASE+:$clog2(RAM_DEPTH)];
    assign  pop_opcode = buf_entry[op_pop_entry][OP_BASE];
    assign  pop_ins = buf_entry[op_pop_entry][INS_BASE+:DWIDTH];
    assign  pop_data = buf_entry[op_pop_entry][DATA_BASE+:DWIDTH];

// output with mul
    assign  o_mul_valid = (|op_ready_for_arb) && pop_opcode;
    assign  o_mul_addr = pop_addr;
    assign  o_mul_ins = pop_ins;
    assign  o_mul_data = pop_data;
// output with add
    assign  o_add_valid = (|op_ready_for_arb) && ~pop_opcode;
    assign  o_add_addr = pop_addr;
    assign  o_add_ins = pop_ins;
    assign  o_add_data = pop_data;

endmodule