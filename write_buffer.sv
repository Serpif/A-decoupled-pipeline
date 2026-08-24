module write_buffer #(
    parameter   RAM_DEPTH = 4,
    parameter   DWIDTH = 16,
    parameter   BUF_DEPTH = 6
)(
    input   clk,
    input   rstn,

    input   i_add_valid,
    output  logic i_add_ready,
    input   [$clog2(RAM_DEPTH)-1:0] i_add_addr,
    input   [DWIDTH-1:0]    i_add_data,

    input   i_mul_valid,
    output  logic i_mul_ready,
    input   [$clog2(RAM_DEPTH)-1:0] i_mul_addr,
    input   [DWIDTH-1:0]    i_mul_data,

    output  o_ram_wen,
    output  [$clog2(RAM_DEPTH)-1:0] o_ram_waddr,
    output  [DWIDTH-1:0]    o_ram_wdata,

// 流水线出口信号
    output  o_valid,
    input   o_ready,
    output  [$clog2(RAM_DEPTH)-1:0] o_addr,
    output  [DWIDTH-1:0]    o_data
);  

    localparam  EWIDTH = $clog2(RAM_DEPTH) + DWIDTH;
    logic   [BUF_DEPTH-1:0][EWIDTH-1:0]     buf_entry;

    logic   empty;
    logic   full;
    logic   one_entry_remain;
    logic   pop;
    logic   ram_pop;
    logic   add_push;
    logic   mul_push;
    logic   two_push;
    logic   one_push;
    logic   [$clog2(BUF_DEPTH):0]    wr_ptr;
    logic   [$clog2(BUF_DEPTH):0]    wr_ptr_plus_1;
    logic   [$clog2(BUF_DEPTH):0]    rd_ptr;
    logic   [$clog2(BUF_DEPTH):0]    ram_rd_ptr;

// ===================== common control logic ======================== //

    assign  empty = wr_ptr == rd_ptr;
    assign  full = (wr_ptr[$clog2(BUF_DEPTH)] ^ rd_ptr[$clog2(BUF_DEPTH)]) && (wr_ptr[$clog2(BUF_DEPTH)-1:0] == rd_ptr[$clog2(BUF_DEPTH)-1:0]); 
    assign  one_entry_remain = (wr_ptr_plus_1[$clog2(BUF_DEPTH)] ^ rd_ptr[$clog2(BUF_DEPTH)]) && (wr_ptr_plus_1[$clog2(BUF_DEPTH)-1:0] == rd_ptr[$clog2(BUF_DEPTH)-1:0]); 

    assign  add_push = i_add_valid && i_add_ready;
    assign  mul_push = i_mul_valid && i_mul_ready;
    assign  two_push = add_push && mul_push;
    assign  one_push = add_push ^ mul_push;
    assign  pop = o_valid && o_ready;
    assign  ram_pop = ~(wr_ptr == ram_rd_ptr);

    logic   [1:0]   token;
    always_ff @(posedge clk) begin
        if(~rstn)
            token <= 2'b01;
        else if(two_push)
            token <= {token[0],token[1]};
    end

    always_comb begin
        case({full,one_entry_remain})
        2'b00:  begin
            i_add_ready = 1'b1;
            i_mul_ready = 1'b1;
        end
        2'b10:  begin   // 已经满了，不能再进入任何请求
            i_add_ready = 1'b0;
            i_mul_ready = 1'b0;
        end
        2'b01:  begin   // 还有1个空闲表项采用仲裁器
            if(i_add_valid && i_mul_valid) begin    // 同时为高采用round-robin仲裁器
                i_add_ready = token[0];
                i_mul_ready = token[1];
            end
            else begin
                i_add_ready = 1'b1;
                i_mul_ready = 1'b1;
            end
        end
        default: begin  // 2'b11 这个条件不可能出现
            i_add_ready = 1'b0;
            i_mul_ready = 1'b0;
        end
        endcase
    end

// ======================== pointer ======================= //

    always_ff @(posedge clk) begin
        if(~rstn)
            wr_ptr <= 'd0;
        else if(two_push)
            wr_ptr <= wr_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 2 ? {~wr_ptr[$clog2(BUF_DEPTH)],{$clog2(BUF_DEPTH){1'b0}}} :
                    wr_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 1 ?  {~wr_ptr[$clog2(BUF_DEPTH)],{($clog2(BUF_DEPTH)-1){1'b0}},1'b1} : wr_ptr + 2'd2;
        else if(one_push)
            wr_ptr <= wr_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 1 ? {~wr_ptr[$clog2(BUF_DEPTH)],{$clog2(BUF_DEPTH){1'b0}}} : wr_ptr + 1'b1;
    end

    assign  wr_ptr_plus_1 = wr_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 1 ? {~wr_ptr[$clog2(BUF_DEPTH)],{$clog2(BUF_DEPTH){1'b0}}} : wr_ptr + 1'b1;

    always_ff @(posedge clk) begin
        if(~rstn)
            rd_ptr <= 'd0;
        else if(pop)
            rd_ptr <= rd_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 1 ? {~rd_ptr[$clog2(BUF_DEPTH)],{$clog2(BUF_DEPTH){1'b0}}} : rd_ptr + 1'b1;
    end
    
    always_ff @(posedge clk) begin
        if(~rstn)
            ram_rd_ptr <= 'd0;
        else if(ram_pop)
            ram_rd_ptr <= ram_rd_ptr[$clog2(BUF_DEPTH)-1:0] == BUF_DEPTH - 1 ? {~ram_rd_ptr[$clog2(BUF_DEPTH)],{$clog2(BUF_DEPTH){1'b0}}} : ram_rd_ptr + 1'b1;
    end

// =========================  buf entry ======================= //

    always_ff @(posedge clk) begin
        for(int i=0;i<BUF_DEPTH;i=i+1) begin
            if(~rstn)
                buf_entry[i] <= 'd0;
            else if(two_push && (i == wr_ptr[$clog2(BUF_DEPTH)-1:0])) // 隐含add优先级更高
                buf_entry[i] <= {i_add_addr,i_add_data};
            else if(two_push && (i == wr_ptr_plus_1[$clog2(BUF_DEPTH)-1:0]))  
                buf_entry[i] <= {i_mul_addr,i_mul_data};
            else if(one_push && (i == wr_ptr[$clog2(BUF_DEPTH)-1:0]))
                buf_entry[i] <= (i_add_valid) ? {i_add_addr,i_add_data} : {i_mul_addr,i_mul_data};
        end
    end

// ========================= output ============================ //

    assign  o_valid = ~empty; // 只要fifo非空就写
    assign  o_addr = buf_entry[rd_ptr[$clog2(BUF_DEPTH)-1:0]][DWIDTH+:$clog2(RAM_DEPTH)];
    assign  o_data = buf_entry[rd_ptr[$clog2(BUF_DEPTH)-1:0]][0+:DWIDTH];

    assign  o_ram_wen = ram_pop;
    assign  o_ram_waddr = buf_entry[ram_rd_ptr[$clog2(BUF_DEPTH)-1:0]][DWIDTH+:$clog2(RAM_DEPTH)];
    assign  o_ram_wdata = buf_entry[ram_rd_ptr[$clog2(BUF_DEPTH)-1:0]][0+:DWIDTH];

endmodule