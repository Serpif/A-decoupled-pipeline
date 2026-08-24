module pipeline_demo #(
    parameter   DEPTH = 32,
    parameter   DWIDTH = 16
) (
    input       clk,
    input       rstn,

    input   i_valid,     // 操作使能
    output  i_ready,
    input   i_opcode,
    input   [$clog2(DEPTH)-1:0] i_addr,
    input   [DWIDTH-1:0] i_ins,

    output  o_valid,
    input   o_ready,
    output  [$clog2(DEPTH)-1:0] o_addr,
    output  [DWIDTH-1:0] o_data
);

    localparam  RBUF_DEPTH = 6;
    localparam  WBUF_DEPTH = 8;
    localparam  BUSY_BOARD_DEPTH = 6;
    localparam  RAM_LAT = 2;

    logic   ram_wen;
    logic   [$clog2(DEPTH)-1:0] ram_waddr;
    logic   [DWIDTH-1:0]    ram_wdata;
    logic   ram_ren;
    logic   [$clog2(DEPTH)-1:0] ram_raddr;
    logic   [DWIDTH-1:0]    ram_rdata;
    logic   [RAM_LAT-1:0]   ram_ren_ff;
    logic   [RAM_LAT-1:0][$clog2(DEPTH)-1:0]   ram_raddr_ff;

    logic   rb_add_valid;
    logic   rb_add_ready;
    logic   [$clog2(DEPTH)-1:0] rb_add_addr;
    logic   [DWIDTH-1:0]    rb_add_ins;
    logic   [DWIDTH-1:0]    rb_add_data;

    logic   rb_mul_valid;
    logic   rb_mul_ready;
    logic   [$clog2(DEPTH)-1:0] rb_mul_addr;
    logic   [DWIDTH-1:0]    rb_mul_ins;
    logic   [DWIDTH-1:0]    rb_mul_data;

    logic   add_wb_valid;
    logic   add_wb_ready;
    logic   [$clog2(DEPTH)-1:0] add_wb_addr;
    logic   [DWIDTH-1:0]    add_wb_data;

    logic   mul_wb_valid;
    logic   mul_wb_ready;
    logic   [$clog2(DEPTH)-1:0] mul_wb_addr;
    logic   [DWIDTH-1:0]    mul_wb_data;

    read_buffer #(
        .RAM_DEPTH(DEPTH),
        .BUF_DEPTH(RBUF_DEPTH),
        .BUSY_BOARD_DEPTH(BUSY_BOARD_DEPTH),
        .DWIDTH(DWIDTH)
    ) u_read_buffer (
        .clk(clk),
        .rstn(rstn),

        .i_valid(i_valid),
        .i_ready(i_ready),
        .i_opcode(i_opcode),
        .i_addr(i_addr),
        .i_ins(i_ins),

        .o_ram_ren(ram_ren),
        .o_ram_raddr(ram_raddr),

        .i_ram_rvalid(ram_ren_ff[RAM_LAT-1]),
        .i_ram_raddr(ram_raddr_ff[RAM_LAT-1]),
        .i_ram_rdata(ram_rdata),

        .o_add_valid(rb_add_valid),
        .o_add_ready(rb_add_ready),
        .o_add_ins(rb_add_ins),
        .o_add_addr(rb_add_addr),
        .o_add_data(rb_add_data),

        .o_mul_valid(rb_mul_valid),
        .o_mul_ready(rb_mul_ready),
        .o_mul_ins(rb_mul_ins),
        .o_mul_addr(rb_mul_addr),
        .o_mul_data(rb_mul_data),

        .i_ram_wvalid(ram_wen),
        .i_ram_waddr(ram_waddr),
        .i_ram_wdata(ram_wdata)
    );

    always_ff @(posedge clk) begin
        if(~rstn)   
            ram_ren_ff[0] <= 1'b0;
        else 
            ram_ren_ff[0] <= ram_ren;
    end

    always_ff @(posedge clk) begin
        if(~rstn)
            ram_raddr_ff[0] <= 'd0;
        else if(ram_ren)
            ram_raddr_ff[0] <= ram_raddr;
    end

    always_ff @(posedge clk) begin
        for(int i = 1;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                ram_ren_ff[i] <= 1'b0;
            else 
                ram_ren_ff[i] <= ram_ren_ff[i-1];
        end
    end

    always_ff @(posedge clk) begin
        for(int i=1;i<RAM_LAT;i=i+1) begin
            if(~rstn)
                ram_raddr_ff[i] <= 'd0;
            else if(ram_ren_ff[i-1])
                ram_raddr_ff[i] <= ram_raddr_ff[i-1];
        end
    end

    ram_2p #(
        .DEPTH(DEPTH),
        .WIDTH(DWIDTH),
        .RAM_LAT(RAM_LAT)
    ) u_ram (
        .clk(clk),

        .wen(ram_wen),
        .waddr(ram_waddr),
        .wdata(ram_wdata),

        .ren(ram_ren),
        .raddr(ram_raddr),
        .rdata(ram_rdata)
    );

    pipeline_alu #(
        .DWIDTH(DWIDTH),
        .RAM_DEPTH(DEPTH)
    ) u_pipe_alu (
        .clk(clk),
        .rstn(rstn),

        .i_add_valid(rb_add_valid),
        .i_add_ready(rb_add_ready),
        .i_add_ins(rb_add_ins),
        .i_add_addr(rb_add_addr),
        .i_add_data(rb_add_data),

        .i_mul_valid(rb_mul_valid),
        .i_mul_ready(rb_mul_ready),
        .i_mul_ins(rb_mul_ins),
        .i_mul_addr(rb_mul_addr),
        .i_mul_data(rb_mul_data),

        .o_add_valid(add_wb_valid),
        .o_add_ready(add_wb_ready),
        .o_add_addr(add_wb_addr),
        .o_add_data(add_wb_data),

        .o_mul_valid(mul_wb_valid),
        .o_mul_ready(mul_wb_ready),
        .o_mul_addr(mul_wb_addr),
        .o_mul_data(mul_wb_data)
    );

    write_buffer #(
        .RAM_DEPTH(DEPTH),
        .DWIDTH(DWIDTH),
        .BUF_DEPTH(WBUF_DEPTH)
    )   u_write_buffer (
        .clk(clk),
        .rstn(rstn),
        
        .i_add_valid(add_wb_valid),
        .i_add_ready(add_wb_ready),
        .i_add_addr(add_wb_addr),
        .i_add_data(add_wb_data),

        .i_mul_valid(mul_wb_valid),
        .i_mul_ready(mul_wb_ready),
        .i_mul_addr(mul_wb_addr),
        .i_mul_data(mul_wb_data),

        .o_ram_wen(ram_wen),
        .o_ram_waddr(ram_waddr),
        .o_ram_wdata(ram_wdata),

        .o_valid(o_valid),
        .o_ready(o_ready),
        .o_addr(o_addr),
        .o_data(o_data)
    );

endmodule