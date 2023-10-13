"""
     abstract type AbstractProjectiveHamiltonian
Abstract type of all projective Hamiltonian.
"""
abstract type AbstractProjectiveHamiltonian end

# TODO simple version

"""
     struct SparseProjectiveHamiltonian{N} <: AbstractProjectiveHamiltonian  
          El::SparseLeftTensor
          Er::SparseRightTensor
          H::NTuple{N, SparseMPOTensor}
          si::Vector{Int64}
          validIdx::Vector{Tuple}
     end

`N`-site projective Hamiltonian, sparse version.

Convention:
      --               --       --                          --
     |         |         |     |         |          |         |
     El-- i -- H1 -- j --Er    El-- i -- H1 -- j -- H2 -- k --Er    ...
     |         |         |     |         |          |         |
      --               --       --                          --

`validIdx` stores all tuples `(i, j, ...)` which are valid, i.e. all `El[i]`, `H1[i, j]` and `Er[j]` are not `nothing` (`N == 1`). 
"""
struct SparseProjectiveHamiltonian{N} <: AbstractProjectiveHamiltonian
     El::SparseLeftTensor
     Er::SparseRightTensor
     H::NTuple{N, SparseMPOTensor}
     si::Vector{Int64}
     validIdx::Vector{Tuple}
     function  SparseProjectiveHamiltonian(El::SparseLeftTensor,
          Er::SparseRightTensor,
          H::NTuple{N,SparseMPOTensor},
          si::Vector{Int64}
          ) where N
          validIdx = NTuple{N+1, Int64}[]
          obj = new{N}(El, Er, H, si, validIdx)
          push!(obj.validIdx, _countIntr(obj)...)
          return obj
     end
end

"""
     ProjHam(Env::SparseEnvironment, siL::Int64 [, siR::Int64 = siL])

Generic constructor for N-site projective Hamiltonian, where `N = siL - siR + 1`.
"""
function ProjHam(Env::SparseEnvironment{L,3,T}, siL::Int64, siR::Int64) where {L,T<:Tuple{AdjointMPS,SparseMPO,MPS}}
     @assert Env[1]' === Env[3]
     @assert 1 ≤ siL ≤ Center(Env[3])[1] && Center(Env[3])[2] ≤ siR ≤ L
     @assert siL ≤ Env.Center[1] && siR ≥ Env.Center[2] # make sure El and Er are valid
     N = siR - siL + 1
     @assert N ≥ 0
     return SparseProjectiveHamiltonian(Env.El[siL], Env.Er[siR], Tuple(Env[2][siL:siR]), [siL, siR])
end
function ProjHam(Env::SparseEnvironment{L,3,T}, si::Int64) where {L,T<:Tuple{AdjointMPS,SparseMPO,MPS}}
     return ProjHam(Env, si, si)
end

function show(io::IO, obj::AbstractProjectiveHamiltonian)
     println(io, "$(typeof(obj)): site = $(obj.si), total channels = $(length(_countIntr(obj)))")
     _showDinfo(io, obj)
end

function _showDinfo(io::IO, obj::SparseProjectiveHamiltonian{N}) where N 
     D, DD = dim(obj.El[1], rank(obj.El[1]))
     println(io, "State[L]: $(domain(obj.El[1])[end]), dim = $(D) -> $(DD)")
     D, DD = dim(obj.Er[1], 1)
     println(io, "State[R]: $(domain(obj.Er[1])[end]), dim = $(D) -> $(DD)")
     for i in 1:N
          DL, DDL = dim(obj.H[i], 1)
          DR, DDR = dim(obj.H[i], 2)
          println(io, "Ham[site = $(obj.si[1] + i - 1)]: $(sum(DL)) × $(sum(DR)) -> $(sum(DDL)) × $(sum(DDR)) ($DL × $DR -> $DDL × $DDR)")
     end
end


function _countIntr(obj::SparseProjectiveHamiltonian{2})
     # count the valid interactions
     idx = Vector{NTuple{3, Int64}}(undef, 0)
     for i in 1:length(obj.El), j in 1:size(obj.H[1], 2), k in 1:length(obj.Er)
          isnothing(obj.El[i]) && continue
          isnothing(obj.H[1][i,j]) && continue
          isnothing(obj.H[2][j,k]) && continue
          isnothing(obj.Er[k]) && continue
          push!(idx, (i,j,k))
     end
     return idx
end

function _countIntr(obj::SparseProjectiveHamiltonian{1})
     idx = Vector{NTuple{2, Int64}}(undef, 0)
     for i in 1:length(obj.El), j in 1:length(obj.Er)
          isnothing(obj.El[i]) && continue
          isnothing(obj.H[1][i,j]) && continue
          isnothing(obj.Er[j]) && continue
          push!(idx, (i,j))
     end
     return idx
end

function _countIntr(obj::SparseProjectiveHamiltonian{0})
     idx = Tuple{Int64}[]
     for i in 1:length(obj.El)
          isnothing(obj.El[i]) && continue
          isnothing(obj.Er[i]) && continue
          push!(idx, (i,))
     end
     return idx
end

