import MacroTools as MT

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

Create a vector of variable names from a variable name specification.

Each argument can be either an Array of `VarName`s,
or of the form `s::VarName => iter`, or of the form `s::VarName => (iter...)`.
Here `iter` is supposed to be any iterable, typically a range like `1:5`.
The `:s => iter` specification is shorthand for `["s[$i]" for i in iter]`.
Similarly `:s => (iter1, iter2)` is shorthand for `["s[$i,$j]" for i in iter1, j in iter2]`,
and likewise for three and more iterables.

As an alternative `"s#" => iter` is shorthand for `["s$i" for i in iter]`.
This also works for multiple iterators in that`"s#" => (iter1, iter2)`
is shorthand for `["s$i$j" for i in iter1, j in iter2]`.
If you need anything else, feel free to open an issue with AbstractAlgebra.

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

julia> AbstractAlgebra.variable_names("x#" => 9:11)
3-element Vector{Symbol}:
 :x9
 :x10
 :x11

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
    c = count("#", s)
    req(c <= 1, """Only a single '#' allowed, but "$s" contains $c of them.""")
    return c == 0 ? Symbol.(s, '[', join.(indices, ','), ']') :
        [Symbol(replace(s, '#' => join(i))) for i in indices]
end

_replace_bad_chars(s) = replace(replace(replace(string(s), '-' => 'm'), '.' => 'p'), r"/+" => 'q') # becomes simpler with julia 1.7

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
reshape_to_varnames(vec::Vector, varnames::VarNames...) =
    reshape_to_varnames(vec, varnames)
function reshape_to_varnames(vec::Vector, varnames::Tuple{Vararg{VarNames}})
    iter = Iterators.Stateful(vec)
    result = Tuple(_reshape_to_varnames(iter, x) for x in varnames)
    @assert isempty(iter)
    return result
end

_reshape_to_varnames(iter::Iterators.Stateful, ::VarName) = popfirst!(iter)
_reshape_to_varnames(iter::Iterators.Stateful, a::AbstractArray{<:VarName}) =
    _reshape(iter, size(a))
_reshape_to_varnames(iter::Iterators.Stateful, (_, shape)::Pair{<:VarName}) =
    __reshape(iter, shape)

__reshape(iter, ::Missing) = popfirst!(iter)
__reshape(iter, axes::Tuple) = _reshape(iter, Int[d for axe in axes for d in size(axe)])
__reshape(iter, axe) = _reshape(iter, size(axe))

_reshape(iter, dims) = reshape(collect(Iterators.take(iter, prod(dims))), Tuple(dims))

"""
    keyword_arguments((kvs::Expr...), default::Dict, [valid::Dict]) :: Dict

Mimic usual keyword arguments for usage in macros.

* `kvs`: tuple of Expr of form :(k = v)
* `default`: dictionary providing the allowed keys and their default values
* `valid`: optional `Dict{Symbol, <:AbstractVector}` constraining the valid values for some keys

Return a copy of `default` with the key value pairs from `kvs` applied.

# Example
```jldoctest; setup = :(using AbstractAlgebra)
julia> AbstractAlgebra.keyword_arguments((:(a=1), :(b=:yes)),
       Dict(:a=>0, :b=>:no, :c=>0),
       Dict(:b => [:(:yes), :(:no)]))
Dict{Symbol, Any} with 3 entries:
  :a => 1
  :b => :(:yes)
  :c => 0
```
"""
function keyword_arguments(kvs::Tuple{Vararg{Expr}}, default::Dict{Symbol},
        valid::Dict{Symbol, <:AbstractVector} = Dict{Symbol, Vector{Any}}()) ::
        Dict{Symbol}
    result = Dict{Symbol, Any}(default)
    for o in kvs
        req(MT.@capture(o, k_ = v_), "Only key value options allowed")
        req(k in keys(result), "Invalid key value option key `$k`")
        k in keys(valid) && req(v in valid[k], "Invalid option `$v` to key `$k`")
        result[k] = v
    end
    return result
end

function _eval(m::Core.Module, e::Expr)
    try
        Base.eval(m, e)
    catch err
        if isa(err, UndefVarError)
            @error "Inconveniently, you may only use literals and variables " *
                "from the global scope of the current module (`$m`) " *
                "when using variable name constructor macros"
        end
        rethrow()
    end
end

# input is :([M.]f(args..., s) where {wheres} [ = ... ])
function _splitdef(e::Expr)
    Meta.isexpr(e, (:(=), :function)) || (e = Expr(:(=), e, :()))
    d = MT.splitdef(e)

    req(isempty(d[:kwargs]), "Keyword arguments currently not supported")

    args = d[:args][begin:end-1] # the last argument is just a placeholder
    splitargs = MT.splitarg.(args)
    req(all(((_, _, slurp, default),) -> (slurp, default) === (false, nothing), splitargs),
        "Default and slurp arguments currently not supported")

    argnames = first.(splitargs)
    req(all(!isnothing, argnames), "Nameless arguments currently not supported")

    base_f = d[:name]
    return Dict{Symbol, Any}(
        :base_f => esc(base_f),
        :f => esc(unqualified_name(base_f)),
        :wheres => esc.(d[:whereparams]),
        :args => esc.(args),
        :argnames => esc.(argnames),
        :argtypes => (esc(a[2]) for a in splitargs),
    )
end

unqualified_name(name::Symbol) = name
unqualified_name(name::QuoteNode) = name.value
function unqualified_name(name::Expr)
    req(Meta.isexpr(name, :., 2), "Expected a binding, but `$name` given")
    unqualified_name(name.args[2])
end

function base_method(d::Dict{Symbol},
        @nospecialize s_type::Union{Symbol, Expr})
    f, base_f, wheres = d[:f], d[:base_f], d[:wheres]
    if f == base_f
        argtypes = :(Tuple{$(d[:argtypes]...), $s_type} where {$(wheres...)})
        :(req(hasmethod($f, $argtypes),
              "base method of `$($f)` for $($argtypes) missing"))
    else
        :($f($(d[:args]...), s::$s_type; kv...) where {$(wheres...)} =
            $base_f($(d[:argnames]...), s; kv...))
    end
end

function varname_method(d::Dict{Symbol})
    f, args, argnames, wheres = d[:f], d[:args], d[:argnames], d[:wheres]
    quote
        $f($(args...), s::Union{AbstractString, Char}; kv...) where {$(wheres...)} =
            $f($(argnames...), Symbol(s); kv...)
    end
end

function varnames_method(d::Dict{Symbol})
    f, args, argnames, wheres = d[:f], d[:args], d[:argnames], d[:wheres]
    quote
        $f($(args...), s1::VarNames, s::VarNames...; kv...) where {$(wheres...)} =
            $f($(argnames...), (s1, s...); kv...)
        function $f($(args...), s::Tuple{Vararg{VarNames}}; kv...) where {$(wheres...)}
            X, gens = $f($(argnames...), variable_names(s...); kv...)
            return X, reshape_to_varnames(gens, s...)...
        end
    end
end

function n_vars_method(d::Dict{Symbol}, n, range)
    f, args, argnames, wheres = d[:f], d[:args], d[:argnames], d[:wheres]
    n === :(:no) && return :()
    req(n isa Symbol, "Value to option `n` must be `:no` or " *
        "an alternative name like `m`, not `$n`")
    quote
        $f($(args...), $n::Int, s::VarName=:x; kv...) where {$(wheres...)} =
            $f($(argnames...), Symbol.(s, $range); kv...)
    end
end

function varnames_macro(f, args_count, opt_in)
    opt_in === :(:yes) || return :()
    quote
        macro $f(args...)
            # Keyword arguments after `;` end up in `kv`.
            # Those without previous `;` get evaluated and end up in `kv2`.
            # Note: one could work around evaluating the latter if necessary.
            kv = Meta.isexpr(first(args), :parameters) ?
                popfirst!(args).args : Expr(:parameters)

            req(length(args) >= $args_count+1, "Not enough arguments")
            base_args = args[1:$args_count]

            m = VERSION > v"9999" ? __module__ : $(esc(:__module__)) # julia issue #51602
            s, kv2 = _eval(m, :($$_varnames_macro($(args[$args_count+1:end]...))))

            append!(kv.args, (Expr(:kw, k, v) for (k, v) in kv2))
            kv = isempty(kv.args) ? () : (kv,)

            varnames_macro_code($f, base_args, s, kv)
        end
    end
end
const varname_macro = varnames_macro

_varnames_macro(arg::VarName; kv...) = Symbol(arg), kv
_varnames_macro(args::VarNames...; kv...) = variable_names(args...), kv

function varnames_macro_code(f, base_args, s::Symbol, kv)
    quote
        X, $(esc(s)) = $f($(kv...), $(base_args...), $(QuoteNode(s)))
        X
    end
end

function varnames_macro_code(f, base_args, s::Vector{Symbol}, kv)
    quote
        X, ($(esc.(s)...),) = $f($(kv...), $(base_args...), $s)
        X
    end
end

@doc raw"""
    @varnames_interface [M.]f(args..., varnames) macros=:yes n=n range=1:n

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

Shorthand for `X, x = f(args..., "$s#", 1:n; kv...)`.
The name `n` can be changed via the `n` option. The range `1:n` is given via the `range` option.

Setting `n=:no` disables creation of this method.

---

    X = @f(args..., varnames...; kv...)
    X = @f(args..., varnames::Tuple; kv...)
    X = @f(args..., varname::VarName; kv...)

As `f(args..., varnames; kv...)` and also introduce the indexed `varnames` into the current scope.
The first version needs at least one `varnames` argument.
The third version calls the univariate method base method if it exists (e.g. `polynomial_ring(R, varname)`).

Setting `macros=:no` disables macro creation.

!!! warning
    Turning `varnames` into a vector of symbols happens by evaluating `variable_names(varnames)` in the global scope of the current module.
    For interactive usage in the REPL this is fine, but in general you have no access to local variables and should not use any side effects in `varnames`.

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

julia> @f("hello", "x#" => (1:1, 1:2), "y#" => (1:2), :z)
"hello"

julia> (x11, x12, y1, y2, z)
("x11", "x12", "y1", "y2", "z")

```
"""
macro varnames_interface(e::Expr, options::Expr...)
    d = _splitdef(e)

    opts = keyword_arguments(options,
        Dict(:n => :n, :range => :(1:n), :macros => :(:yes)),
        Dict(:macros => QuoteNode.([:no, :yes])))

    quote
        $(base_method(d, :(Vector{Symbol})))
        $(varnames_method(d))
        $(n_vars_method(d, opts[:n], opts[:range]))
        $(varnames_macro(d[:f], length(d[:argnames]), opts[:macros]))
    end
end

@doc raw"""
    @varname_interface [M.]f(args..., varname) macros=:yes

Add method `X, vars = f(args..., varname::VarName)` and macro `X = @f args... varname::Symbol` to current scope.

# Created methods

    X, gen::T = f(args..., varname::Symbol)

Base method. If `M` is given, this calls `M.f`, otherwise, it has to exist already.

---

    f(args..., varname::VarName; kv...)

Call `f(args..., Symbol(varname); kv...)`.

---

    X = @f(args..., varname::VarName; kv...)

As `f(args..., varname; kv...)`, and also introduce `varname` into the current scope.
Can be disabled via `macros=:no` option.

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

julia> @f("hello", :x)
"hello"

julia> x
:x
```
"""
macro varname_interface(e::Expr, options::Expr...)
    d = _splitdef(e)

    opts = keyword_arguments(options, Dict(:macros => :(:yes)),
        Dict(:macros => QuoteNode.([:no, :yes])))

    quote
        $(base_method(d, :Symbol))
        $(varname_method(d))
        $(varname_macro(d[:f], length(d[:argnames]), opts[:macros]))
    end
end

@varname_interface Generic.SparsePolynomialRing(R::Ring, s)
@varname_interface Generic.number_field(p::PolyRingElem, s)
@varname_interface Generic.function_field(p::PolyRingElem, s)
@varname_interface Generic.laurent_series_ring(R::Ring, prec::Int, s)
@varname_interface Generic.laurent_series_field(K::Field, prec::Int, s)
@varname_interface Generic.PuiseuxSeriesRing(R::Ring, prec::Int, s)

@varnames_interface Generic.free_associative_algebra(R::Ring, s)
@varnames_interface Generic.laurent_polynomial_ring(R::Ring, s)

@varname_interface Generic.power_series_ring(R::Ring, prec::Int, s) macros=:no
@varnames_interface Generic.power_series_ring(R::Ring, prec::Int, s)
@varnames_interface Generic.power_series_ring(R::Ring, weights::Vector{Int}, prec::Int, s) macros=:no # use keyword `weights=...` instead
@varnames_interface Generic.power_series_ring(R::Ring, prec::Vector{Int}, s) n=:no macros=:no # `n` variant would clash with line above; macro would be the same as for `prec::Int`

@varname_interface Generic.rational_function_field(K::Field, s) macros=:no
@varnames_interface Generic.rational_function_field(K::Field, s)

@varname_interface polynomial_ring(R::NCRing, s) macros=:no
@varnames_interface polynomial_ring(R::Ring, s)
# With `Ring <: NCRing`, we need to resolve ambiguities of `polynomial_ring(::Ring, s...)`
polynomial_ring(R::Ring, s::Symbol; kv...) = invoke(polynomial_ring, Tuple{NCRing, Symbol}, R, s; kv...)
polynomial_ring(R::Ring, s::Union{AbstractString, Char}; kv...) = polynomial_ring(R, Symbol(s); kv...)
