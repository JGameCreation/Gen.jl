include("scenes.jl")
include("path_planner.jl")
include("static_model.jl")

using Printf: @sprintf
import Random

function make_scene()
    scene = Scene(0, 1, 0, 1) 
    add!(scene, Tree(Point(0.30, 0.20), size=0.1))
    add!(scene, Tree(Point(0.83, 0.80), size=0.1))
    add!(scene, Tree(Point(0.80, 0.40), size=0.1))
    horiz = 1
    vert = 2
    wall_height = 0.30
    wall_thickness = 0.02
    walls = [
        Wall(Point(0.20, 0.40), horiz, 0.40, wall_thickness, wall_height)
        Wall(Point(0.60, 0.40), vert, 0.40, wall_thickness, wall_height)
        Wall(Point(0.60 - 0.15, 0.80), horiz, 0.15 + wall_thickness, wall_thickness, wall_height)
        Wall(Point(0.20, 0.80), horiz, 0.15, wall_thickness, wall_height)
        Wall(Point(0.20, 0.40), vert, 0.40, wall_thickness, wall_height)]
    for wall in walls
        add!(scene, wall)
    end
    return scene
end

const scene = make_scene()
const times = collect(range(0, stop=1, length=20))

@staticgen function stop_proposal(prev_trace::Any)
    @addr(uniform(0, 1), :stop_x)
    @addr(uniform(0, 1), :stop_y)
end

@staticgen function speed_proposal(prev_trace::Any)
    @addr(uniform(0, 1), :speed)
end

@staticgen function noise_proposal(prev_trace::Any)
    @addr(uniform(0, 0.1), :noise)
end

function inference(measurements::Vector{Point}, start::Point, iters::Int)
    t = length(measurements)

    constraints = DynamicAssignment()
    for (i, pt) in enumerate(measurements)
        constraints[:measurements => i => :x] = pt.x
        constraints[:measurements => i => :y] = pt.y
    end
    constraints[:start_x] = start.x
    constraints[:start_y] = start.y

    (trace, _) = initialize(model, (scene, times[1:t]), constraints)

    for iter=1:iters
        trace = custom_mh(model, stop_proposal, (), trace)
        trace = custom_mh(model, speed_proposal, (), trace)
        trace = custom_mh(model, noise_proposal, (), trace)
    end

    return trace
end

function experiment()

    # generate simulated ground truth
    Random.seed!(0)
    constraints = DynamicAssignment()
    constraints[:start_x] = 0.1
    constraints[:start_y] = 0.1
    constraints[:stop_x] = 0.5
    constraints[:stop_y] = 0.5
    constraints[:noise] = 0.01
    (trace, _) = initialize(model, (scene, times), constraints)

    figure(figsize=(4, 4))
    ax = gca()
    render(scene, trace, ax)
    savefig("ground_truth.png")

    assignment = get_assmt(trace)
    measurements = [Point(
        assignment[:measurements => i => :x],
        assignment[:measurements => i => :y]) for i=1:length(times)]
    start = Point(assignment[:start_x], assignment[:start_y])

    for t=1:length(times)
        println("t: $t")
        traces = []
        for i=1:100
            println(i)
            @time trace = inference(measurements[1:t], start, 100)
            push!(traces, trace)
        end
        figure(figsize=(4, 4))
        ax = gca()
        for (i, trace) in enumerate(traces)
            render(scene, trace, ax; show_measurements=i>1, show_start=i>1,
                   show_path=false, show_noise=false, stop_alpha=0.2, path_alpha=0.2)
        end
        fname = @sprintf("static_inferred_%03d.png", t)
        savefig(fname)
    end
end

function show_prior_samples()
    Random.seed!(0)
    figure(figsize=(32, 32))
    for i=1:15
        subplot(4, 4, i)
        ax = gca()
        trace = simulate(model, (scene, times))
        render(scene, trace, ax)
    end
    savefig("static_demo.png")
end

Gen.load_generated_functions()

show_prior_samples()
experiment()