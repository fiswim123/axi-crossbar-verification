//==========================================================================
// Full Routing Test — 补全缺失的路由交叉覆盖
// 注: MST3 只能访问 SLV3（DUT 路由限制），其余 3 条路由无法覆盖
//==========================================================================
class axi_full_routing_test extends axi_base_test;
    `uvm_component_utils(axi_full_routing_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_full_routing_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // MST1 → SLV1, SLV2, SLV3
        seq = axi_full_routing_seq::type_id::create("m1_s1");
        seq.s_addr = 16'h1000; seq.s_id = 8'h20; seq.start(env.sqr[1]);
        seq = axi_full_routing_seq::type_id::create("m1_s2");
        seq.s_addr = 16'h2000; seq.s_id = 8'h20; seq.start(env.sqr[1]);
        seq = axi_full_routing_seq::type_id::create("m1_s3");
        seq.s_addr = 16'h3000; seq.s_id = 8'h20; seq.start(env.sqr[1]);

        // MST2 → SLV0, SLV2, SLV3
        seq = axi_full_routing_seq::type_id::create("m2_s0");
        seq.s_addr = 16'h0000; seq.s_id = 8'h30; seq.start(env.sqr[2]);
        seq = axi_full_routing_seq::type_id::create("m2_s2");
        seq.s_addr = 16'h2000; seq.s_id = 8'h30; seq.start(env.sqr[2]);
        seq = axi_full_routing_seq::type_id::create("m2_s3");
        seq.s_addr = 16'h3000; seq.s_id = 8'h30; seq.start(env.sqr[2]);

        #200;
        phase.drop_objection(this);
    endtask
endclass
