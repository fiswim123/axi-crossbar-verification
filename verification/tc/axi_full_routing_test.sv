// Exercise every configured MxS path in both directions.  All four masters
// have MSTx_ROUTES=4'b1111 in top/dut_connect.svh; no path is excluded.
class axi_full_routing_test extends axi_base_test;
    `uvm_component_utils(axi_full_routing_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axi_full_routing_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_agent[0].driver.vif.aresetn);
        repeat (5) @(posedge env.mst_agent[0].driver.vif.aclk);

        for (int m = 0; m < 4; m++) begin
            for (int s = 0; s < 4; s++) begin
                seq = axi_full_routing_seq::type_id::create($sformatf("wr_m%0d_s%0d", m, s));
                seq.s_kind = axi_txn::WRITE;
                seq.s_id   = (m + 1) << 4;
                seq.s_addr = (s << 12) | (m << 2);
                seq.s_data = 32'hC0DE_0000 | (m << 8) | s;
                seq.start(env.mst_agent[m].sequencer);

                seq = axi_full_routing_seq::type_id::create($sformatf("rd_m%0d_s%0d", m, s));
                seq.s_kind = axi_txn::READ;
                seq.s_id   = (m + 1) << 4;
                seq.s_addr = (s << 12) | (m << 2);
                seq.start(env.mst_agent[m].sequencer);
            end
        end
        repeat (20) @(posedge env.mst_agent[0].driver.vif.aclk);
        phase.drop_objection(this);
    endtask
endclass
