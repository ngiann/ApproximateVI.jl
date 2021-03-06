function coreVIdiag(logl::Function, μarray::Array{Array{Float64,1},1}, Σarray::Array{Array{Float64,1},1}; gradlogl = gradlogl, seed = 1, S = 100, optimiser=Optim.LBFGS(), iterations = 1, numerical_verification = false, Stest=0, show_every=-1, inititerations=0)

    D = length(μarray[1])

    @assert(D == length(Σarray[1]))

    @assert(length(μarray) == length(Σarray))

    @printf("Running VI diagonal with S=%d, D=%d for %d iterations\n", S, D, iterations)


    #----------------------------------------------------
    # generate latent variables
    #----------------------------------------------------

    Ztrain = generatelatentZ(S = S, D = D, seed = seed)

    Ztest  = generatelatentZ(S = Stest, D = D, seed = seed+1)


    #----------------------------------------------------
    function unpack(param)
    #----------------------------------------------------

        @assert(length(param) == D+D)

        local μ = param[1:D]

        local Cdiag = reshape(param[D+1:D+D], D)

        return μ, Cdiag

    end


    #----------------------------------------------------
    function minauxiliary(param)
    #----------------------------------------------------

        local μ, Cdiag = unpack(param)

        return -1.0 * elbo(μ, Cdiag, Ztrain)

    end


    #----------------------------------------------------
    function minauxiliary_grad(param)
    #----------------------------------------------------

        local μ, Cdiag = unpack(param)

        return -1.0 * elbo_grad(μ, Cdiag, Ztrain)

    end


    #----------------------------------------------------
    function getcov(Cdiag)
    #----------------------------------------------------

        Diagonal(Cdiag.^2)

    end


    #----------------------------------------------------
    function getcovroot(Cdiag)
    #----------------------------------------------------

        return Cdiag

    end


    #----------------------------------------------------
    function elbo(μ, Cdiag, Z)
    #----------------------------------------------------

        mean(map(z -> logl(μ .+ Cdiag.*z), Z)) + ApproximateVI.entropy(Cdiag)

    end


    #----------------------------------------------------
    function elbo_grad(μ, Cdiag, Z)
    #----------------------------------------------------

        local gradC = 1.0 ./ Cdiag # entropy contribution

        local gradμ = zeros(eltype(μ), D)

        local S     = length(Z)

        for s=1:S
            g      = gradlogl(μ .+ Cdiag .* Z[s])
            gradC += g .* Z[s] / S
            gradμ += g / S
        end

        return [vec(gradμ); gradC]

    end


    gradhelper(storage, param) = copyto!(storage, minauxiliary_grad(param))


    #----------------------------------------------------
    # Numerically verify gradient
    #----------------------------------------------------

    if numerical_verification

        local C = sqrt.(Σarray[1])
        adgrad = ForwardDiff.gradient(minauxiliary, [μarray[1]; C])
        angrad = minauxiliary_grad([μarray[1]; C])
        @printf("gradient from AD vs analytical gradient\n")
        display([vec(adgrad) vec(angrad)])
        @printf("maximum absolute difference is %f\n", maximum(abs.(vec(adgrad) - vec(angrad))))

    end


    #----------------------------------------------------
    # Evaluate initial solutions for few iterations
    #----------------------------------------------------

    initoptimise(μ, Σ) = Optim.optimize(minauxiliary, gradhelper, [μ; vec(sqrt.(Σ))], optimiser, Optim.Options(iterations = inititerations))

    results = if inititerations>0
        @showprogress "Initial search with random start " map(initoptimise, μarray, Σarray)
    else
        map(initoptimise, μarray, Σarray)
    end

    bestindex = argmin(map(r -> r.minimum, results))

    bestinitialsolution = results[bestindex].minimizer


    #----------------------------------------------------
    # Call optimiser
    #----------------------------------------------------

    options = Optim.Options(extended_trace = false, store_trace = false, show_trace = true, show_every=show_every, iterations = iterations, g_tol = 1e-6)

    result  = Optim.optimize(minauxiliary, gradhelper, bestinitialsolution, optimiser, options)

    μopt, Copt = unpack(result.minimizer)


    #----------------------------------------------------
    # Return results
    #----------------------------------------------------

    Σ = getcov(Copt)

    return MvNormal(μopt, Σ), elbo(μopt, Copt, generatelatentZ(S = 10*S, D = D, seed = seed+2))

end
