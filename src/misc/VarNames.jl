import MacroTools as MT
import Printf

@assert VarName === Union{Symbol, AbstractString, Char}
const VarNames = Union{
    VarName,
    AbstractArray{<:VarName},
    Pair{<:VarName},
}

req(cond, msg) = cond || throw(ArgumentError(msg))
# The macro version will only evaluate `msg` if needed
macro req(cond, msg) :($cond || throw(ArgumentError($msg))) end

@doc raw"""
    variable_names(a...) -> Vector{Symbol}
    variable_names(a::Tuple) -> Vector{Symbol}

Create proper variable names from `a`.
Each argument can be either an Array of `VarName`s, `s::VarName => (iter...)`, or `s::VarName => iter`.
The `iter` version is equivalent to `["s[$i]" for i in iter]`; the `(iter...)` version is the same for multiple indices.

By default `:x => axes` and `"x" => axes` create variables like `x[1,1]`.
By using `"x#" => axes` instead, `x[1,1]` becomes `x11`, `x[10,10]` becomes `x10_10`, and `x[-1]` becomes `xm1`.
If one does not want to replace the chars "-./" by "mpq", use '@' instead of '#'.
Using multiple '#' or multiple '@' as in "x#y#", one gets variables like `x1y1`.
By including a '%' one gets `printf` formatting.

# Examples

```jldoctest; setup = :(using AbstractAlgebra)
julia> AbstractAlgebra.variable_names(:x, :y)
2-element Vector{Symbol}:
 :x
 :y

julia> AbstractAlgebra.variable_names(:x => (0:0, 0:1), :y => 0:1, :z)
5-element Vector{Symbol}:
 Symbol("x[0,0]")
 Symbol("x[0,1]")
 Symbol("y[0]")
 Symbol("y[1]")
 :z

julia> AbstractAlgebra.variable_names("x#" => (0:0, 0:1), "y#" => 0:1)
4-element Vector{Symbol}:
 :x00
 :x01
 :y0
 :y1

julia> AbstractAlgebra.variable_names("x#" => (0:0, [-1,3,10]), "y#" => [-1,1])
5-element Vector{Symbol}:
 :x0_m1
 :x0_3
 :x0_10
 :ym1
 :y1

julia> AbstractAlgebra.variable_names("x#y#" => (0:0, [-1,3,10]))
3-element Vector{Symbol}:
 :x0ym1
 :x0y3
 :x0y10

julia> AbstractAlgebra.variable_names("x_{@}" => (0:0, [-1,3,10]))
3-element Vector{Symbol}:
 Symbol("x_{0,-1}")
 Symbol("x_{0,3}")
 Symbol("x_{0,10}")

julia> AbstractAlgebra.variable_names("x^{(@)}_{@}" => (0:0, [-1,3,10]))
3-element Vector{Symbol}:
 Symbol("x^{(0)}_{-1}")
 Symbol("x^{(0)}_{3}")
 Symbol("x^{(0)}_{10}")

julia> AbstractAlgebra.variable_names("x%02d_%02d" => (9:10,9:10))
4-element Vector{Symbol}:
 :x09_09
 :x10_09
 :x09_10
 :x10_10

julia> AbstractAlgebra.variable_names(["x$i$i" for i in 1:3])
3-element Vector{Symbol}:
 :x11
 :x22
 :x33

julia> AbstractAlgebra.variable_names('a':'c', 'z')
4-element Vector{Symbol}:
 :a
 :b
 :c
 :z

```
"""
variable_names(as::VarNames...) = variable_names(as)
variable_names(as::Tuple{Vararg{VarNames}}) = Symbol[x for a in as for x in _variable_names(a)]

# note: additionally `:x => missing` is equivalent to `:x`, so that we can use the `:symbol => multiplicity` syntax throughout. This simplifies the macro implementation.

_variable_names(s::VarName) = [Symbol(s)]
_variable_names(a::AbstractArray{<:VarName}) = Symbol.(a)
_variable_names((s, _)::Pair{<:VarName, Missing}) = [Symbol(s)]
_variable_names((s, axe)::Pair{<:VarName}) = Symbol.(s, '[', axe, ']')
_variable_names((s, axe)::Pair{<:AbstractString}) = _variable_names(s => (axe,))
_variable_names((s, axes)::Pair{<:VarName, <:Tuple}) = Symbol.(s, '[', join.(Iterators.product(axes...), ','), ']')
function _variable_names((s, axes)::Pair{<:AbstractString, <:Tuple})
    indices = Iterators.product(axes...)
    return if '%' in s
        [Symbol(Printf.format(Printf.Format(s), i...)) for i in indices]
    else
        c_massage = count("#", s) # From v"1.7" on, we could use a `Char` instead.
        c_no_massage = count("@", s)
        req(c_massage == 0 || c_no_massage == 0, """In "$s" both '#' and '@' occur. If you need both, please make up an issue.""")
        c = c_massage | c_no_massage
        if c == 0
            Symbol.(s, '[', join.(indices, ','), ']')
        else
            massage = c_massage > 0
            x = massage ? '#' : '@'
            if massage
                indices = [_replace_bad_chars.(i) for i in indices]
            end
            if c == 1
                delim = !massage ? "," : maximum(i->maximum(length, i), indices) > 1 ? "_" : ""
                [Symbol(replace(s, x => join(i, delim))) for i in indices]
            else
                req(c == length(axes), """In "$s" there occurs a '$x' $c times, but only 0, 1, or $(length(axes)) (= number of indices) times is allowed.""")
                parts = split(s, x)
                [Symbol(Iterators.flatten(zip(parts, i))..., parts[end]) for i in indices]
            end
        end
    end
end

_replace_bad_chars(s) = replace(replace(replace(string(s), '-' => 'm'), '.' => 'p'), r"/+" => 'q')

@doc raw"""
    reshape_to_varnames(vec::Vector{T}, varnames...) :: Tuple{Array{<:Any, T}}
    reshape_to_varnames(vec::Vector{T}, varnames::Tuple) :: Tuple{Array{<:Any, T}}

Turn `vec` into the shape of `varnames`. Reverse flattening from [`variable_names`](@ref).

# Examples

```jldoctest; setup = :(using AbstractAlgebra)
julia> s = ([:a, :b], "x#" => (1:1, 1:2), "y#" => 1:2, :z);

julia> AbstractAlgebra.reshape_to_varnames(AbstractAlgebra.variable_names(s...), s...)
([:a, :b], [:x11 :x12], [:y1, :y2], :z)

julia> R, vec = polynomial_ring(ZZ, AbstractAlgebra.variable_names(s...))
(Multivariate polynomial ring in 7 variables over integers, AbstractAlgebra.Generic.MPoly{BigInt}[a, b, x11, x12, y1, y2, z])

julia> (a, b), x, y, z = AbstractAlgebra.reshape_to_varnames(vec, s...)
(AbstractAlgebra.Generic.MPoly{BigInt}[a, b], AbstractAlgebra.Generic.MPoly{BigInt}[x11 x12], AbstractAlgebra.Generic.MPoly{BigInt}[y1, y2], z)

julia> R, (a, b), x, y, z = polynomial_ring(ZZ, s...)
(Multivariate polynomial ring in 7 variables over integers, AbstractAlgebra.Generic.MPoly{BigInt}[a, b], AbstractAlgebra.Generic.MPoly{BigInt}[x11 x12], AbstractAlgebra.Generic.MPoly{BigInt}[y1, y2], z)

```
"""
reshape_to_varnames(vec::Vector, varnames::VarNames...) = reshape_to_varnames(vec, varnames)
function reshape_to_varnames(vec::Vector, varnames::Tuple{Vararg{VarNames}})
    iter = Iterators.Stateful(vec)
    result = Tuple(_reshape_to_varnames(iter, x) for x in varnames)
    @assert isempty(iter)
    return result
end

_reshape_to_varnames(iter::Iterators.Stateful, ::VarName) = popfirst!(iter)
_reshape_to_varnames(iter::Iterators.Stateful, a::AbstractArray{<:VarName}) = _reshape(iter, size(a))
_reshape_to_varnames(iter::Iterators.Stateful, (_, shape)::Pair{<:VarName}) = __reshape(iter, shape)

_reshape(iter, dims) = reshape(collect(Iterators.take(iter, prod(dims))), Tuple(dims))
__reshape(iter, ::Missing) = popfirst!(iter)
__reshape(iter, axes::Tuple) = _reshape(iter, Int[d for axe in axes for d in size(axe)])
__reshape(iter, axe) = _reshape(iter, size(axe))

# `Int` only syntax
_reshape(_, n::Int) = _int_axe_error(:s, n)
# _reshape(iter, n::Int) = collect(Iterators.take(iter, n))

function _varname_interface(e::Expr, @nospecialize s::Union{Expr, Symbol})
    ex = Meta.isexpr(e, (:(=), :function)) ? e : Expr(:(=), e, :())
    d = MT.splitdef(ex)

    callf = esc(d[:name])
    f = esc(MT.postwalk(x -> MT.@capture(x, a_.b_) ? b : x, d[:name]))
    wheres = esc.(d[:whereparams])

    args = d[:args][begin:end-1]
    splitargs = MacroTools.splitarg.(args)
    args = esc.(args)
    req(all(((_, _, slurp, default),) -> (slurp, default) === (false, nothing), splitargs),
        "Default and slurp arguments currently not supported")
    req(isempty(d[:kwargs]), "Keyword arguments currently not supported")
    argnames = first.(splitargs)
    req(all(!isnothing, argnames), "Nameless arguments currently not supported")
    argnames = esc.(argnames)

    s = esc(s)
    argtypes = esc.(a[2] for a in splitargs)
    argtypes = :(Tuple{$(argtypes...), $s} where {$(wheres...)})
    base = f == callf ?
        :(req(hasmethod($f, $argtypes), "base method of `$($f)` for $($argtypes) missing")) :
        :($f($(args...), s::$s; kv...) where {$(wheres...)} = $callf($(argnames...), s; kv...))

    return f, args, argnames, wheres, base
end

@doc raw"""
    @varnames_interface [M.]f(args..., varnames) macros=:yes n=1:n

Add methods `X, vars = f(args..., varnames...)` and macro `X = @f args... varnames...` to current scope.

# Created methods

    X, gens::Vector{T} = f(args..., varnames::Vector{Symbol})

Base method. If `M` is given, this calls `M.f`. Otherwise, it has to exist already.

---

    X, vars... = f(args..., varnames...; kv...)
    X, vars... = f(args..., varnames::Tuple; kv...)

Compute `X` and `gens` via the base method. Then reshape `gens` into the shape defined by `varnames` according to [`variable_names`](@ref).

The vararg `varnames...` method needs at least one argument to avoid confusion.
Moreover a single `VarName` argument will be dispatched to use a univariate method of `f` if it exists (e.g. `polynomial_ring(R, :x)`).
If you need those cases, use the `Tuple` method.

Keyword arguments are passed on to the base method.

---

    X, x::Vector{T} = f(args..., n::Int, s::VarName = :x; kv...)

Shorthand for `X, x = f(args..., "$s#", 1:n)`. Can be changed via the `n` option. Setting `n=:no` disables creation of this method.

Keyword arguments are passed on to the base method.

---

    X = @f args... varname[iter...] ... option=value ...
    X = @f args... (varname[iter...] ...) option=value ...

As `f(args..., "varname#" => iter, ...)`, and also introduce the indexed `varname` into the current scope.
Giving `[iter...]` is optional. A `varname` without that stands for a single symbol.
Can be disabled via `macros=:no`.
As for the `f(args..., varnames...)` method above, we require at least one `varname`.
If there is only one `varname` argument and this is a `Symbol` the univariate method base method will be called if it exists (e.g. `polynomial_ring(R, x)`).
You can still use the `Tuple` version for such edge cases.

Any `option=value` pairs at the end of the macro are passed on as keyword arguments.

# Examples

```jldoctest; setup = :(using AbstractAlgebra)
julia> f(a, s::Vector{Symbol}) = a, String.(s)
f (generic function with 1 method)

julia> AbstractAlgebra.@varnames_interface f(a, s)
@f (macro with 1 method)

julia> f
f (generic function with 5 methods)

julia> f("hello", :x, :y, :z)
("hello", "x", "y", "z")

julia> f("hello", :x => (1:1, 1:2), :y => 1:2, :z)
("hello", ["x[1,1]" "x[1,2]"], ["y[1]", "y[2]"], "z")

julia> f("projective", ["x$i$j" for i in 0:1, j in 0:1], [:y0, :y1], :z)
("projective", ["x00" "x01"; "x10" "x11"], ["y0", "y1"], "z")

julia> f("fun inputs", 'a':'g', Symbol.('x':'z', [0 1]))
("fun inputs", ["a", "b", "c", "d", "e", "f", "g"], ["x0" "x1"; "y0" "y1"; "z0" "z1"])

julia> @f "hello" x[1:1, 1:2] y[1:2] z
"hello"

julia> (x11, x12, y1, y2, z)
("x11", "x12", "y1", "y2", "z")

```
"""
macro varnames_interface(e::Expr, options::Expr...)
    f, args, argnames, wheres, base = _varname_interface(e, :(Vector{Symbol}))
    fancy_method = quote
        $f($(args...), s1::VarNames, s::VarNames...; kv...) where {$(wheres...)} = $f($(argnames...), (s1, s...); kv...)
        function $f($(args...), s::Tuple{Vararg{VarNames}}; kv...) where {$(wheres...)}
            X, gens = $f($(argnames...), variable_names(s...); kv...)
            return X, reshape_to_varnames(gens, s...)...
        end
    end

    opts = parse_options(options, Dict(:n => :n, :macros => :(:yes)), Dict(:macros => QuoteNode.([:no, :yes])))
    one_to_n = n = opts[:n]
    fancy_n_method = if n === :(:no)
        :()
    else
        req(n isa Symbol || Meta.isexpr(n, :call), "Value to option `n` must be `:no`, an alternative name like `m` or some expression like `0:n`, not `$n`")
        if n isa Symbol
            one_to_n = :(Base.OneTo($n))
        elseif n isa Expr
            n = only(x -> x isa Symbol, n.args[2:end])
        end
        @assert n isa Symbol
        quote
            $f($(args...), $n::Int, s::VarName=:x; kv...) where {$(wheres...)} =
                $f($(argnames...), Symbol.(s, $one_to_n); kv...)
        end
    end

    opts[:macros] === :(:no) && return :($base; $fancy_method; $fancy_n_method)
    fancy_macro = quote
        macro $f($(argnames...), s1::Union{Expr, Symbol}, s::Union{Expr, Symbol}...)
            s, kv = extract_options(s)
            return if isempty(s) && s1 isa Symbol
                # use vararg method respectively the univariate method if it exists
                quote
                    X, $(esc(s1)) = $$f($$(argnames...), $(QuoteNode(s1)))
                    X
                end
            else
                # use base method directly
                gens = variable_names(_eval_shapes(Main, s1, s...))
                quote
                    X, ($(esc.(gens)...),) = $$f($$(argnames...), $gens; $(esc.(kv)...)) # the need for `esc` is probably a bug in julia
                    X
                end
            end
        end
    end

    return :($base; $fancy_method; $fancy_n_method; $fancy_macro)
end

function parse_options(kvs::Tuple{Vararg{Expr}}, default::Dict{Symbol}, valid::Dict{Symbol, <:Vector} = Dict{Symbol, Vector{Any}}()) :: Dict{Symbol}
    result = Dict{Symbol, Any}(default)
    for o in kvs
        req(MT.@capture(o, k_ = v_), "Only key value options allowed")
        req(k in keys(result), "Invalid key value option key `$k`")
        k in keys(valid) && req(v in valid[k], "Invalid option `$v` to key `$k`")
        result[k] = v
    end
    return result
end

function extract_options(es) # -> args, options
    options_start = findfirst(e -> Meta.isexpr(e, :(=)), es)
    options_start === nothing && return es, es[end+1:end]
    args = es[begin:options_start-1]
    options = map(e -> (req(MT.@capture(e, k_ = v_), "The argument `$e` comes after an option, so it also must be of the form `option=value`"); :($(QuoteNode(k::Symbol)) => $v)), es[options_start:end])
    return args, options
end

_eval_shapes(m::Core.Module, es::Union{Expr, Symbol}...) :: Tuple{Vararg{Union{<:Pair{String, Tuple}, Symbol}}} = _eval_shape.((m,), es)
_eval_shapes(m::Core.Module, e::Expr) :: Tuple{Vararg{Union{<:Pair{String, Tuple}, Symbol}}} =
    MT.@capture(e, (es__,)) ? # Are we in the case of the `@f args... (varnames...,)` variant?
    _eval_shape.((m,), (es...,)) : # Yes, we are, `es` is like `(x[0:5], y)`.
    (_eval_shape(m, e),) # No, we are in the ordinary case and have only one varname, `es` is like `x[0:5]`.
_eval_shape(m::Core.Module, e::Expr) :: Pair{String, Tuple} = (req(MT.@capture(e, x_[a__]), "Variable name must be like `x` or `x[...]`, not `$e`"); "$x#" => (_eval.((m,), a)...,))
_eval_shape(::Core.Module, s::Symbol) = s

function _eval(m::Core.Module, e::Expr)
    try
        Base.eval(m, e)
    catch err
        if isa(err, UndefVarError)
            @error "Inconveniently, you may only use literals and variables from `Main`s global scope when using fancy variable name macros"
        end
        rethrow()
    end
end

@doc raw"""
    @varname_interface [M.]f(args..., varname) macros=:yes

Add method `X, vars = f(args..., varname::VarName)` and macro `X = @f args... varname::Symbol` to current scope.

# Created methods

    X, gen::T = f(args..., varname::Symbol)

Base method. If `M` is given, this calls `M.f`, otherwise, it has to exist already.

---

    f(args..., varname::VarName)

Call `f(args..., Symbol(varname))`.

---

    X = @f args... varname::Symbol

As `f(args..., varname)`, and also introduce `varname` into the current scope.
Must be disabled via `macros=:no` option, when also using the multivariate `@varnames_interface [M.]f(args..., varnames)`.

# Examples

```jldoctest; setup = :(using AbstractAlgebra)
julia> f(a, s::Symbol) = a, s
f (generic function with 1 method)

julia> AbstractAlgebra.@varname_interface f(a, s)
@f (macro with 1 method)

julia> f
f (generic function with 2 methods)

julia> f("hello", "x")
("hello", :x)

julia> @f "hello" x
"hello"

julia> x
:x
```
"""
macro varname_interface(e::Expr, options::Expr...)
    f, args, argnames, wheres, base = _varname_interface(e, :Symbol)
    fancy_method = :($f($(args...), s::Union{AbstractString, Char}; kv...) where {$(wheres...)} = $f($(argnames...), Symbol(s); kv...))
    opts = parse_options(options, Dict(:macros => :(:yes)), Dict(:macros => QuoteNode.([:no, :yes])))
    opts[:macros] == :(:yes) || return :($base; $fancy_method)
    fancy_macro = :(
        macro $f($(argnames...), s::Symbol, options::Expr...)
            rest, kv = extract_options(options)
            @req(isempty(rest), "The univariate macro `@$($f)` accepts only one Symbol and following `option=value` pairs, but `$(first(rest))` given." *
                "If you intended to use a multivariate version of `@$($f)`, check that `@varname_interface $($f)(...)` is followed by `macros=:no`.")
            quote
                X, $(esc(s)) = $$f($$(argnames...), $(QuoteNode(s)); $(esc.(kv)...))
                X
            end
        end
        )
    return :($base; $fancy_method; $fancy_macro)
end


@varname_interface Generic.SparsePolynomialRing(R::Ring, s)
@varname_interface Generic.number_field(p::PolyRingElem, s)
@varname_interface Generic.FunctionField(p::PolyRingElem, s)
@varname_interface Generic.laurent_series_ring(R::Ring, prec::Int, s)
@varname_interface Generic.laurent_series_field(K::Field, prec::Int, s)
@varname_interface Generic.PuiseuxSeriesRing(R::Ring, prec::Int, s)

@varnames_interface Generic.free_associative_algebra(R::Ring, s)
@varnames_interface Generic.LaurentPolynomialRing(R::Ring, s)

@varname_interface Generic.power_series_ring(R::Ring, prec::Int, s) macros=:no
@varnames_interface Generic.power_series_ring(R::Ring, prec::Int, s)
@varnames_interface Generic.power_series_ring(R::Ring, weights::Vector{Int}, prec::Int, s) macros=:no # use keyword `weights=...` instead
@varnames_interface Generic.power_series_ring(R::Ring, prec::Vector{Int}, s) n=:no macros=:no # `n` variant would clash with line above; macro would be the same as for `prec::Int`

@varname_interface Generic.RationalFunctionField(K::Field, s) macros=:no
@varnames_interface Generic.RationalFunctionField(K::Field, s)

@varname_interface polynomial_ring(R::NCRing, s) macros=:no
@varnames_interface polynomial_ring(R::Ring, s)
# With `Ring <: NCRing`, we need to resolve ambiguities of `polynomial_ring(::Ring, s...)`
polynomial_ring(R::Ring, s::Symbol; kv...) = invoke(polynomial_ring, Tuple{NCRing, Symbol}, R, s; kv...)
polynomial_ring(R::Ring, s::Union{AbstractString, Char}; kv...) = polynomial_ring(R, Symbol(s); kv...)
