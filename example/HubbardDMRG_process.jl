using MKL
using Distributed
using FiniteMPS, FiniteLattices
using LinearAlgebra.BLAS

NWORKERS = 4 # number of workers
NTHREADS = 1 # number of threads of subworkers, suggestion = 1

include("Models/Hubbard.jl")

addprocs(NWORKERS,exeflags=["--threads=$(NTHREADS)"])


@show Distributed.workers()

@everywhere begin
     using MKL, FiniteMPS, LinearAlgebra.BLAS
     @show Threads.nthreads()
     @show BLAS.get_config()
     BLAS.set_num_threads(1) # set MKL nthreads, suggestion = 1
     @show BLAS.get_num_threads()
end

flush(stdout)

@show Latt = SquaLatt(8, 4; BCY=:PBC)
disk = false # store local tensors in disk or memory

Ψ = nothing

function mainDMRG(Ψ=nothing)

     Para = (t=1, t′=-0.2, U=8)
     Ndop = 0 # number of hole doping, negative value means elec doping

     # =============== list D ====================
     lsD = broadcast(Int64 ∘ round, 2 .^ vcat(6:10))
     Nsweep = 1
     lsD = repeat(lsD, inner=Nsweep)
     # ===========================================

     # finish with 1-DMRG 
     Nsweep_DMRG1 = 2

     # initial state
     if isnothing(Ψ)
          aspace = vcat(Rep[U₁×SU₂]((Ndop, 0) => 1), repeat([Rep[U₁×SU₂]((i, j) => 2 for i in -(abs(Ndop) + 1):(abs(Ndop)+1) for j in 0:1//2:1),], length(Latt) - 1))
          Ψ = randMPS(U₁SU₂Fermion.pspace, aspace; disk=disk)
     end

     H = AutomataMPO(U₁SU₂Hubbard(Latt; Para...))
     Env = Environment(Ψ', H, Ψ; disk=disk)

     lsEn = zeros(length(lsD))
     info = Vector{Tuple}(undef, length(lsD))
     midsi = Int64(round(length(Latt) / 2))
     for (i, D) in enumerate(lsD)
          @time info[i] = DMRGSweep2!(Env;
               distributed = true,
               GCstep=false, GCsweep=true,
               trunc=truncdim(D) & truncbelow(1e-6),
               LanczosOpt=(krylovdim=8, maxiter=1, tol=1e-4, orth=ModifiedGramSchmidt(), eager=true, verbosity=0))
          lsEn[i] = info[i][2][1].Eg
          println("D = $D, En = $(lsEn[i]), K = $(info[i][2][midsi].Lanczos.numops), TrunErr2 = $(info[i][2][midsi].TrunErr^2)")
          flush(stdout)
     end

     for i in 1:Nsweep_DMRG1
          @time info_DMRG1 = DMRGSweep1!(Env;
               distributed = true,
               GCstep=false, GCsweep=true,
               LanczosOpt=(krylovdim=8, maxiter=1, tol=1e-4, orth=ModifiedGramSchmidt(), eager=true, verbosity=0))
               push!(lsEn, info_DMRG1[2][1].Eg)
               push!(info, info_DMRG1)
          println("1-site DMRG: En = $(lsEn[end]), K = $(info_DMRG1[2][midsi].Lanczos.numops)")
          flush(stdout)

     end

     GC.gc()
     return Ψ, Env, lsD, lsEn, info
end

function mainObs(Ψ::MPS)

     Tree = ObservableTree(; disk=disk)
     for i in 1:length(Latt)
          addObs!(Tree, U₁SU₂Fermion.n, i, 1; name=:n)
          addObs!(Tree, U₁SU₂Fermion.nd, i, 1; name=:nd)
     end
     for i in 1:length(Latt), j in i+1:length(Latt)
          addObs!(Tree, U₁SU₂Fermion.SS, (i, j), 1; name=(:S, :S))
          addObs!(Tree, (U₁SU₂Fermion.n, U₁SU₂Fermion.n), (i, j), 1; name=(:n, :n))
          addObs!(Tree, U₁SU₂Fermion.FdagF, (i, j), 1; Z=U₁SU₂Fermion.Z, name=(:Fdag, :F))
     end
     for (i, j) in neighbor(Latt), (k, l) in neighbor(Latt)
          !isempty(intersect([i, j], [k, l])) && continue
          i > j && continue # note ⟨Δᵢⱼ^dag Δₖₗ⟩ = ⟨Δₖₗ^dag Δᵢⱼ⟩
          addObs!(Tree, U₁SU₂Fermion.ΔₛdagΔₛ, (i, j, k, l), 1; Z=U₁SU₂Fermion.Z, name=(:Fdag, :Fdag, :F, :F))
     end

     @time calObs!(Tree, Ψ)

     Obs = convert(Dict, Tree, [(:n,), (:nd,), (:S, :S), (:n, :n), (:Fdag, :F), (:Fdag, :Fdag, :F, :F)])
     GC.gc()

     return Obs

end

Ψ, Env, lsD, lsEn, info = mainDMRG(Ψ);
Obs = mainObs(Ψ)

rmprocs(workers())