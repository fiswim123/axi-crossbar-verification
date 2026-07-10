//==========================================================================
// Environment
//==========================================================================
class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)

    axi_mst_drv    mst_drv[4];
    axi_slv_drv    slv_drv[4];
    axi_monitor    mst_mon[4];
    axi_monitor    slv_mon[4];
    uvm_sequencer #(axi_txn) sqr[4];
    axi_scoreboard scbd;
    axi_coverage   cov;

    // Slave configs (for error injection tests)
    axi_slv_cfg    slv_cfg[4];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i] = axi_mst_drv::type_id::create($sformatf("mst_drv%0d", i), this);
            slv_drv[i] = axi_slv_drv::type_id::create($sformatf("slv_drv%0d", i), this);
            mst_mon[i] = axi_monitor::type_id::create($sformatf("mst_mon%0d", i), this);
            slv_mon[i] = axi_monitor::type_id::create($sformatf("slv_mon%0d", i), this);
            sqr[i]     = uvm_sequencer#(axi_txn)::type_id::create($sformatf("sqr%0d", i), this);

            // Create slave config
            slv_cfg[i] = axi_slv_cfg::type_id::create($sformatf("slv_cfg%0d", i));
            uvm_config_db#(axi_slv_cfg)::set(this, $sformatf("slv_drv%0d", i), "cfg", slv_cfg[i]);
        end
        scbd = axi_scoreboard::type_id::create("scbd", this);
        cov  = axi_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        for (int i = 0; i < 4; i++) begin
            mst_drv[i].seq_item_port.connect(sqr[i].seq_item_export);
            mst_mon[i].ap.connect(scbd.imp);
            mst_mon[i].ap.connect(cov.analysis_export);
            // Only connect master monitor to scoreboard to avoid duplicate counting
        end
    endfunction
endclass
