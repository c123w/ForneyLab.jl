module CompositeTest

using Base.Test
using ForneyLab
import ForneyLab: @composite, outboundType, isApplicable
import ForneyLab: SPClamp, SPGaussianMeanVarianceOutVPP, Product


# Define new node type called StateTransition, with exposed variables called (y, x_prev, x):
@composite StateTransition (y, x_prev, x) begin
    @RV x ~ GaussianMeanVariance(x_prev, constant(1.0))
    @RV y ~ GaussianMeanVariance(x, constant(1.0))
end

@testset "@composite" begin
    @test StateTransition <: FactorNode
end

@testset "Composite node construction" begin
    g = FactorGraph()
    nd = StateTransition(Variable(), Variable(), Variable())

    # Node fields should be of correct types
    @test isa(nd.id, Symbol)
    @test isa(nd.interfaces, Vector{Interface})
    @test isa(nd.i, Dict)
    @test isa(nd.inner_graph, FactorGraph)
    @test isa(nd.terminals, Vector{Terminal})

    # Node constructor should automatically assign an id
    @test nd.id == :statetransition_1

    # Node constructor should assign interfaces to itself
    for iface in nd.interfaces
        @test ===(iface.node, nd)
    end

    # Node constructor should add node to graph
    @test g.nodes[:statetransition_1] == nd
end


#-------------
# Update rules
#-------------

# Define custom rule for sum-product message towards x
@sumProductRule(:node_type     => StateTransition,
                :outbound_type => Message{Gaussian},
                :inbound_types => (Message{PointMass}, Message{Gaussian}, Void),
                :name          => SPStateTransitionX)

@testset "Custom SPStateTransitionX" begin
    @test SPStateTransitionX <: SumProductRule{StateTransition}
    @test outboundType(SPStateTransitionX) == Message{Gaussian}
    @test isApplicable(SPStateTransitionX, [Message{PointMass}, Message{Gaussian}, Void]) 
    @test !isApplicable(SPStateTransitionX, [Message{Gaussian}, Message{PointMass}, Void]) 
end

@testset "Composite node scheduling and algorithm compilation" begin
    g = FactorGraph()

    x_prev = Variable(id=:x_prev)
    nd = GaussianMeanVariance(x_prev, constant(0.0), constant(1.0))
    x = Variable(id=:x)
    y = Variable(id=:y)
    cnd = StateTransition(placeholder(y, :y), x_prev, x)

    # Build SP schedule
    schedule = sumProductSchedule(x)
    @test length(schedule) == 5
    @test ScheduleEntry(nd.i[:m].partner, SPClamp{Univariate}) in schedule
    @test ScheduleEntry(nd.i[:v].partner, SPClamp{Univariate}) in schedule
    @test ScheduleEntry(nd.i[:out], SPGaussianMeanVarianceOutVPP) in schedule
    @test ScheduleEntry(cnd.i[:y].partner, SPClamp{Univariate}) in schedule
    @test ScheduleEntry(cnd.i[:x], SPStateTransitionX) in schedule

    # Build marginal schedule
    marginal_schedule = marginalSchedule(x)
    @test length(marginal_schedule) == 1
    @test marginal_schedule[1].target == x
    @test marginal_schedule[1].interfaces[1] == cnd.i[:x]
    @test marginal_schedule[1].marginal_update_rule == Void

    # Build SP algorithm for Julia execution
    algo = ForneyLab.messagePassingAlgorithm(schedule, marginal_schedule)
    @test contains(algo, "Array{Message}(2)")
    @test contains(algo, "messages[1] = ruleSPGaussianMeanVarianceOutVPP(nothing, Message(Univariate, PointMass, m=0.0), Message(Univariate, PointMass, m=1.0))")
    @test contains(algo, "messages[2] = ruleSPStateTransitionX(Message(Univariate, PointMass, m=data[:y]), messages[1], nothing)")
    @test contains(algo, "marginals[:x] = messages[2].dist")
end

@testset "Composite node algorithm execution" begin
    # Implement custom rule for Julia execution
    ruleSPStateTransitionX{F<:Gaussian}(::Message{PointMass, Univariate}, ::Message{F, Univariate}, ::Void) = Message(Univariate, GaussianMeanVariance, m=2.0, v=3.0) # Send some dummy message

    # Resulting algorithm ---
    function step!(marginals::Dict, data::Dict)

    messages = Array{Message}(2)

    messages[1] = ruleSPGaussianMeanVarianceOutVPP(nothing, Message(Univariate, PointMass, m=0.0), Message(Univariate, PointMass, m=1.0))
    messages[2] = ruleSPStateTransitionX(Message(Univariate, PointMass, m=data[:y]), messages[1], nothing)

    marginals[:x] = messages[2].dist

    end
    # ---

    marginals = Dict()
    data = Dict(:y => 1.0)
    step!(marginals, data)

    @test marginals[:x] == ProbabilityDistribution(Univariate, GaussianMeanVariance, m=2.0, v=3.0)
end

end #module