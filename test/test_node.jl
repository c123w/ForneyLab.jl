#####################
# Unit tests
#####################

facts("General node properties unit tests") do
    FactorGraph()
    c = 0
    for node_type in [subtypes(Node); subtypes(ForneyLab.WrapableNode)]
        if (node_type != MockNode) && (node_type != ForneyLab.WrapableNode)
            context("$(node_type) properties should include interfaces and id") do
                test_node = node_type()
                @fact typeof(test_node) <: node_type --> true
                @fact typeof(test_node.interfaces) --> Array{Interface, 1} # Check for interface array
                @fact length(test_node.interfaces) >= 1 --> true # Check length of interface array
                @fact typeof(test_node.id) --> Symbol
                @fact typeof(test_node.i) <: Dict --> true
                @fact_throws deepcopy(test_node)
            end

            context("$(node_type) constructor should assign an id") do
                my_node = node_type(;id=Symbol("my_id_$(c)"))
                @fact my_node.id --> Symbol("my_id_$(c)")
            end

            context("$(node_type) constructor should assign interfaces to itself") do
                my_node = node_type()
                for interface_index in 1:length(my_node.interfaces)
                    # Check if the node interfaces couple back to the same node
                    @fact my_node.interfaces[interface_index].node --> my_node
                end
            end

            context("$(node_type) constructor should add node to the current graph") do
                my_node = node_type()
                @fact currentGraph().nodes[my_node.id] --> my_node
            end

            context("$(node_type) constructor should check for unique id") do
                MockNode(id=Symbol("mock_$(c)"))
                @fact_throws MockNode(id=Symbol("mock_$(c)"))
            end

            if (node_type <: ForneyLab.WrapableNode)
                context("$(node_type) should have a value field") do
                    my_node = node_type()
                    @fact (:value in fieldnames(my_node)) --> true
                end
            end
        end

        c += 1
    end
end


#####################
# Integration tests
#####################

facts("Connections between nodes integration tests") do
    context("Nodes can directly be coupled through interfaces by using the interfaces array") do
        initializePairOfNodes()
        # Couple the interfaces that carry GeneralMessage
        n(:node1).interfaces[1].partner = n(:node2).interfaces[1]
        n(:node2).interfaces[1].partner = n(:node1).interfaces[1]
        testInterfaceConnections(n(:node1), n(:node2))
    end

    context("Nodes can directly be coupled through interfaces by using the explicit interface handles") do
        initializePairOfNodes()
        # Couple the interfaces that carry GeneralMessage
        n(:node1).i[:in].partner = n(:node2).i[:out]
        n(:node2).i[:out].partner = n(:node1).i[:in]
        testInterfaceConnections(n(:node1), n(:node2))
    end

    context("Nodes can be coupled by edges by using the interfaces array") do
        initializePairOfNodes()
        # Couple the interfaces that carry GeneralMessage
        edge = Edge(n(:node2).interfaces[1], n(:node1).interfaces[1]) # Edge from node 2 to node 1
        testInterfaceConnections(n(:node1), n(:node2))
    end
end

facts("Nodes can be sorted") do
    FactorGraph()
    node_a = TerminalNode(id=:a)
    node_b = GainNode(id=:b)
    node_c = GainNode(id=:c)
    node_d = TerminalNode(id=:d)
    sorted = sort!([node_d, node_b, node_a, node_c])
    @fact sorted --> [node_a, node_b, node_c, node_d]
end


facts("copy(::Node)") do
    g1 = initializePairOfNodes()
    test_edge = Edge(n(:node2).interfaces[1], n(:node1).interfaces[1])
    g2 = FactorGraph() # Add a copy of node2 to a new graph
    node2 = n(:node2, g1)
    node2_copy = copy(node2, id=:node2_copy)
    @fact is(node2, node2_copy) --> false
    @fact node2_copy.id --> :node2_copy
    # Edges should be removed from copy but not from original
    @fact node2.interfaces[1].edge --> test_edge
    @fact node2_copy.interfaces[1].edge --> nothing
    @fact node2.interfaces[1].partner --> n(:node1, g1).interfaces[1]
    @fact node2_copy.interfaces[1].partner --> nothing
    @fact node2_copy in nodes(g1) --> false
    @fact node2_copy in nodes(g2) --> true
end
