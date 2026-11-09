// Master-side specialization of the common AXI bus monitor.
class axi_mst_monitor extends axi_monitor;
    `uvm_component_utils(axi_mst_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
