function _finalselect(lsEl::SparseLeftTensor, RO::RightOrthComplement{N}) where {N}
     # contract truncated left environment tensor to the right one

     function f(El::LocalLeftTensor{2}, Er::LocalRightTensor{2})
          return El.A * Er.A
     end
     function f(El::LocalLeftTensor{3}, Er::LocalRightTensor{3})
          @tensor tmp[a; d] := El.A[a b c] * Er.A[c b d]
          return tmp
     end
     function f(El::LocalLeftTensor{2}, Ar::MPSTensor{4})
          @tensor tmp[a c; d e] := El.A[a b] * Ar.A[b c d e]
          return tmp
     end
     function f(El::LocalLeftTensor{3}, Ar::MPSTensor{5})
          @tensor tmp[a d; e f] := El.A[a b c] * Ar.A[c d e b f]
          return tmp
     end
     f(::Nothing, ::LocalRightTensor) = nothing
     f(::Nothing, ::MPSTensor) = nothing

     if get_num_workers() > 1 # multi-processing
     # TODO

     else # multi-threading
          Er::LocalRightTensor, Ar = let f = f
               @floop GlobalThreadsExecutor for i in 1:N
                    Er_i = f(lsEl[i], RO.Er[i])
                    Ar_i = f(lsEl[i], RO.Ar[i])
                    @reduce() do (Er = nothing; Er_i), (Ar = nothing; Ar_i)
                         Er = axpy!(true, Er_i, Er)
                         Ar = axpy!(true, Ar_i, Ar)
                    end
               end
               Er, Ar
          end
     end

     # orthogonal projection, Ar - Er*Ar_c
     return normalize!(axpy!(-1, _rightProj(Er, RO.Ar_c), Ar))
end

function _finalselect(LO::LeftOrthComplement{N}, lsEr::SparseRightTensor) where {N}
     # contract truncated right environment tensor to the left one

     function f(El::LocalLeftTensor{2}, Er::LocalRightTensor{2})
          return El.A * Er.A
     end
     function f(El::LocalLeftTensor{3}, Er::LocalRightTensor{3})
          @tensor tmp[a; d] := El.A[a b c] * Er.A[c b d]
          return tmp
     end
     function f(Al::MPSTensor{4}, Er::LocalRightTensor{2})
          @tensor tmp[a b; c f] := Al.A[a b c e] * Er.A[e f]
          return tmp
     end
     function f(Al::MPSTensor{5}, Er::LocalRightTensor{3})
          @tensor tmp[a b; c f] := Al.A[a b c d e] * Er.A[e d f]
          return tmp
     end
     f(::LocalRightTensor, ::Nothing) = nothing
     f(::MPSTensor, ::Nothing) = nothing

     if get_num_workers() > 1 # multi-processing
     # TODO

     else # multi-threading
          El::LocalLeftTensor, Al = let f = f
               @floop GlobalThreadsExecutor for i in 1:N
                    El_i = f(LO.El[i], lsEr[i])
                    Al_i = f(LO.Al[i], lsEr[i])
                    @reduce() do (El = nothing; El_i), (Al = nothing; Al_i)
                         El = axpy!(true, El_i, El)
                         Al = axpy!(true, Al_i, Al)
                    end
               end
               El, Al
          end
     end

     # orthogonal projection, Al - El*Al_c
     return normalize!(axpy!(-1, _leftProj(El, LO.Al_c), Al))
end