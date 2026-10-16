// Which bitslices of a nibble with TX_GATING = ENABLE keep serializing while TBYTE_IN is 0.
//
// Some boards laid out with the MIG pin planner place address/command pins (e.g. act_n, odt, cke,
// adr[16]) in the spare slots of a data byte group. Those nibbles have TX_GATING = ENABLE and their
// tristate comes from TBYTE_IN, while a command pin can change in any cycle, also between writes.
//
// This bench builds one nibble with all seven slots populated, the tristate slice, a BITSLICE_CONTROL
// with data-nibble attributes as used by the MIG, and the bank PLL at DDR4-2000. Every slice is given
// 0x55, eight output edges per controller cycle if it serializes. It counts the edges of each slot with
// TBYTE_IN at 0, then across one write (TBYTE_IN = F for four cycles), and measures single-bit pulses
// on slots 1 and 6.
//
// Result seen with the Vivado 2025.1 unisim models (not confirmed on hardware):
//   TX_GATING = ENABLE:  slots 0, 2, 3, 4, 5 are silent while TBYTE_IN is 0 and serialize during the
//                        write. Slots 1 and 6 serialize all the time, at full rate (500 ps pulses).
//                        TX_OUTPUT_PHASE_90 and RX_DATA_TYPE made no difference to this.
//   TX_GATING = DISABLE: every slot serializes all the time.
//   SELF_CALIBRATE = DISABLE: DLY_RDY did not rise in this bench.
// Slot 1 of a lower nibble is pin N1 and slot 6 of an upper nibble is pin N12, the two spare pins of a
// data byte group.
//
// Run: ./run.sh [TX_GATING] [SELF_CALIBRATE]
`timescale 1ps/1ps
module tb;
    parameter       TX_GATING = "ENABLE";
    parameter       SELF_CAL  = "ENABLE";
    parameter [6:0] PHASE_90  = 7'b1000011; // per slot: an upper data nibble (DQS on 0, command on 6)

    reg clk = 0, riu_clk = 0;
    always #2000 clk = ~clk;         // 250 MHz controller clock, CK/4
    always #4000 riu_clk = ~riu_clk; // 125 MHz

    reg  pll_rst = 1, phy_en = 0, ctrl_rst = 1, bs_rst = 1, en_vtc = 0;
    wire pll_fb, pll_clk, pll_locked, dly_rdy, vtc_rdy;

    PLLE4_ADV #(
        .CLKFBOUT_MULT(4), .CLKFBOUT_PHASE(90.0), .CLKIN_PERIOD(4.0), .CLKOUT0_DIVIDE(1),
        .CLKOUTPHY_MODE("VCO_2X"), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(1)
    ) pll (
        .CLKIN(clk), .CLKFBIN(pll_fb), .CLKFBOUT(pll_fb), .CLKOUTPHY(pll_clk), .CLKOUTPHYEN(phy_en),
        .LOCKED(pll_locked), .RST(pll_rst), .PWRDWN(1'b0),
        .CLKOUT0(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0), .DO(), .DRDY()
    );

    reg  [3:0]  tbyte = 4'b0000;
    reg  [7:0]  d [0:6];
    wire [39:0] rx_c2b [0:6], rx_b2c [0:6], tx_c2b [0:6], tx_b2c [0:6], tri_c2b, tri_b2c;
    wire [6:0]  o, t_out;
    wire        tri_q;

    BITSLICE_CONTROL #(
        .CTRL_CLK("EXTERNAL"), .DIV_MODE("DIV4"), .EN_DYN_ODLY_MODE("TRUE"),
        .EN_OTHER_NCLK("FALSE"), .EN_OTHER_PCLK("FALSE"),
        .IDLY_VT_TRACK("TRUE"), .ODLY_VT_TRACK("TRUE"), .QDLY_VT_TRACK("TRUE"),
        .READ_IDLE_COUNT(6'h1F), .REFCLK_SRC("PLLCLK"), .ROUNDING_FACTOR(16),
        .RX_CLK_PHASE_N("SHIFT_90"), .RX_CLK_PHASE_P("SHIFT_90"), .RX_GATING("ENABLE"),
        .SELF_CALIBRATE(SELF_CAL), .SERIAL_MODE("FALSE"), .SIM_DEVICE("ULTRASCALE_PLUS"),
        .TX_GATING(TX_GATING)
    ) ctrl (
        .PLL_CLK(pll_clk), .REFCLK(1'b0), .RST(ctrl_rst), .EN_VTC(en_vtc),
        .DLY_RDY(dly_rdy), .VTC_RDY(vtc_rdy),
        .RIU_CLK(riu_clk), .RIU_ADDR(6'b0), .RIU_WR_DATA(16'b0), .RIU_WR_EN(1'b0), .RIU_NIBBLE_SEL(1'b0),
        .RIU_RD_DATA(), .RIU_VALID(),
        .PHY_RDCS0(4'b0), .PHY_RDCS1(4'b0), .PHY_WRCS0(4'b0), .PHY_WRCS1(4'b0), .PHY_RDEN(4'b0),
        .TBYTE_IN(tbyte), .DYN_DCI(),
        .CLK_FROM_EXT(1'b1), .CLK_TO_EXT_NORTH(), .CLK_TO_EXT_SOUTH(),
        .PCLK_NIBBLE_IN(1'b1), .NCLK_NIBBLE_IN(1'b1), .PCLK_NIBBLE_OUT(), .NCLK_NIBBLE_OUT(),
        .RX_BIT_CTRL_OUT0(rx_c2b[0]), .RX_BIT_CTRL_OUT1(rx_c2b[1]), .RX_BIT_CTRL_OUT2(rx_c2b[2]),
        .RX_BIT_CTRL_OUT3(rx_c2b[3]), .RX_BIT_CTRL_OUT4(rx_c2b[4]), .RX_BIT_CTRL_OUT5(rx_c2b[5]),
        .RX_BIT_CTRL_OUT6(rx_c2b[6]),
        .RX_BIT_CTRL_IN0(rx_b2c[0]), .RX_BIT_CTRL_IN1(rx_b2c[1]), .RX_BIT_CTRL_IN2(rx_b2c[2]),
        .RX_BIT_CTRL_IN3(rx_b2c[3]), .RX_BIT_CTRL_IN4(rx_b2c[4]), .RX_BIT_CTRL_IN5(rx_b2c[5]),
        .RX_BIT_CTRL_IN6(rx_b2c[6]),
        .TX_BIT_CTRL_OUT0(tx_c2b[0]), .TX_BIT_CTRL_OUT1(tx_c2b[1]), .TX_BIT_CTRL_OUT2(tx_c2b[2]),
        .TX_BIT_CTRL_OUT3(tx_c2b[3]), .TX_BIT_CTRL_OUT4(tx_c2b[4]), .TX_BIT_CTRL_OUT5(tx_c2b[5]),
        .TX_BIT_CTRL_OUT6(tx_c2b[6]), .TX_BIT_CTRL_OUT_TRI(tri_c2b),
        .TX_BIT_CTRL_IN0(tx_b2c[0]), .TX_BIT_CTRL_IN1(tx_b2c[1]), .TX_BIT_CTRL_IN2(tx_b2c[2]),
        .TX_BIT_CTRL_IN3(tx_b2c[3]), .TX_BIT_CTRL_IN4(tx_b2c[4]), .TX_BIT_CTRL_IN5(tx_b2c[5]),
        .TX_BIT_CTRL_IN6(tx_b2c[6]), .TX_BIT_CTRL_IN_TRI(tri_b2c)
    );

    TX_BITSLICE_TRI #(
        .DATA_WIDTH(8), .DELAY_FORMAT("TIME"), .DELAY_TYPE("FIXED"), .DELAY_VALUE(0), .INIT(1'b1),
        .OUTPUT_PHASE_90("TRUE"), .SIM_DEVICE("ULTRASCALE_PLUS")
    ) tri_slice (
        .BIT_CTRL_IN(tri_c2b), .BIT_CTRL_OUT(tri_b2c), .TRI_OUT(tri_q),
        .CE(1'b0), .CLK(clk), .INC(1'b0), .LOAD(1'b0), .CNTVALUEIN(9'b0), .CNTVALUEOUT(),
        .EN_VTC(1'b1), .RST(bs_rst), .RST_DLY(bs_rst)
    );

    integer edges [0:6];
    time    t_rise [0:6], width [0:6];
    genvar s;
    generate for (s = 0; s < 7; s = s + 1) begin : slot
        RXTX_BITSLICE #(
            .RX_DATA_TYPE(s == 0 ? "DATA_AND_CLOCK" : "DATA"),
            .TX_OUTPUT_PHASE_90(PHASE_90[s] ? "TRUE" : "FALSE"),
            .TBYTE_CTL("TBYTE_IN"), .INIT(1'b1),
            .RX_DATA_WIDTH(8), .TX_DATA_WIDTH(8), .SIM_DEVICE("ULTRASCALE_PLUS")
        ) slice (
            .D(d[s]), .O(o[s]), .T(1'b0), .T_OUT(t_out[s]), .TBYTE_IN(tri_q),
            .DATAIN(1'b0), .Q(), .FIFO_RD_CLK(clk), .FIFO_RD_EN(1'b0), .FIFO_EMPTY(), .FIFO_WRCLK_OUT(),
            .RX_BIT_CTRL_IN(rx_c2b[s]), .RX_BIT_CTRL_OUT(rx_b2c[s]),
            .TX_BIT_CTRL_IN(tx_c2b[s]), .TX_BIT_CTRL_OUT(tx_b2c[s]),
            .RX_CE(1'b0), .RX_CLK(clk), .RX_INC(1'b0), .RX_LOAD(1'b0), .RX_CNTVALUEIN(9'b0), .RX_CNTVALUEOUT(),
            .RX_EN_VTC(1'b1), .RX_RST(bs_rst), .RX_RST_DLY(bs_rst),
            .TX_CE(1'b0), .TX_CLK(clk), .TX_INC(1'b0), .TX_LOAD(1'b0), .TX_CNTVALUEIN(9'b0), .TX_CNTVALUEOUT(),
            .TX_EN_VTC(1'b1), .TX_RST(bs_rst), .TX_RST_DLY(bs_rst)
        );
        initial begin edges[s] = 0; t_rise[s] = 0; width[s] = 0; end
        always @(o[s]) edges[s] = edges[s] + 1;
        always @(posedge o[s]) t_rise[s] = $time;
        always @(negedge o[s]) width[s] = $time - t_rise[s];
    end endgenerate

    // Time the tristate of slot 2 (a DQ) is released for
    time t_fall = 0, t_low = 0;
    always @(negedge t_out[2]) t_fall = $time;
    always @(posedge t_out[2]) if (t_fall != 0) t_low = $time - t_fall;

    integer snap [0:6], got [0:6], q, n;
    reg [7:0] word [0:1];
    reg       ok;

    task set_all(input [7:0] v);
        for (q = 0; q < 7; q = q + 1) d[q] = v;
    endtask

    task count(input integer cycles);
        begin
            for (q = 0; q < 7; q = q + 1) snap[q] = edges[q];
            repeat (cycles) @(posedge clk);
            for (q = 0; q < 7; q = q + 1) got[q] = edges[q] - snap[q];
        end
    endtask

    task wait_for(input integer which);
        begin : w
            fork
                begin if (which == 0) wait (dly_rdy); else wait (vtc_rdy); disable w; end
                begin #2000000000; $display("RESULT FAIL: %0s never rose", which == 0 ? "DLY_RDY" : "VTC_RDY"); $finish; end
            join
        end
    endtask

    initial begin
        set_all(8'h00);
        #20000 pll_rst = 0;
        wait (pll_locked);
        #20000 @(posedge clk) phy_en = 1;
        #40000 @(posedge clk) bs_rst = 0;
        #40000 @(posedge clk) ctrl_rst = 0;
        wait_for(0);
        $display("RESULT DLY_RDY at %0t ps", $time);
        @(posedge clk) en_vtc = 1;
        wait_for(1);
        $display("RESULT VTC_RDY at %0t ps", $time);

        set_all(8'h55);
        repeat (20) @(posedge clk);

        // Between writes
        count(40);
        $display("RESULT TBYTE_IN=0, 40 cycles, edges on slots 0..6 (320 if serializing): %0d %0d %0d %0d %0d %0d %0d",
                 got[0], got[1], got[2], got[3], got[4], got[5], got[6]);
        ok = got[1] == 320 && got[6] == 320;
        if (TX_GATING == "ENABLE") ok = ok && got[0] == 0 && got[2] == 0 && got[3] == 0 && got[4] == 0 && got[5] == 0;
        else                       ok = ok && got[0] == 320 && got[2] == 320 && got[3] == 320 && got[4] == 320 && got[5] == 320;

        // One write: four cycles open
        for (q = 0; q < 7; q = q + 1) snap[q] = edges[q];
        @(posedge clk) tbyte <= 4'hF;
        repeat (4) @(posedge clk);
        tbyte <= 4'h0;
        repeat (15) @(posedge clk);
        for (q = 0; q < 7; q = q + 1) got[q] = edges[q] - snap[q];
        $display("RESULT one write in 20 cycles, edges on slots 0..6 (32 for a gated slot, 160 for a free one): %0d %0d %0d %0d %0d %0d %0d; tristate released for %0d ps",
                 got[0], got[1], got[2], got[3], got[4], got[5], got[6], t_low);
        if (TX_GATING == "ENABLE") ok = ok && got[0] == 32 && got[2] == 32 && got[5] == 32 && got[1] == 160 && got[6] == 160;

        // Slots 1 and 6 at full rate: one bit high per word gives a 500 ps pulse
        word[0] = 8'h01; word[1] = 8'h02;
        for (n = 0; n < 2; n = n + 1) begin
            set_all(word[n]);
            repeat (12) @(posedge clk);
            count(10);
            $display("RESULT word 0x%02h, TBYTE_IN=0: slot 1 %0d edges, pulse %0d ps; slot 6 %0d edges, pulse %0d ps (20 edges and 500 ps at full rate)",
                     word[n], got[1], width[1], got[6], width[6]);
            ok = ok && got[1] == 20 && got[6] == 20 && width[1] == 500 && width[6] == 500;
        end

        // No edges on a constant word: the counters are not counting noise
        set_all(8'hFF);
        repeat (12) @(posedge clk);
        count(20);
        $display("RESULT word 0xFF, 20 cycles, edges on slots 0..6 (0 expected): %0d %0d %0d %0d %0d %0d %0d",
                 got[0], got[1], got[2], got[3], got[4], got[5], got[6]);
        ok = ok && got[1] == 0 && got[6] == 0;

        if (TX_GATING == "ENABLE")
            $display("RESULT %0s: with TX_GATING enabled, slots 1 and 6 run free and slots 0, 2, 3, 4, 5 are gated", ok ? "PASS" : "FAIL");
        else
            $display("RESULT %0s: with TX_GATING disabled, every slot runs free", ok ? "PASS" : "FAIL");
        $finish;
    end
endmodule
