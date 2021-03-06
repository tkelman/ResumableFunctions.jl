using MacroTools

"""
Function that replaces a `for` loop by a corresponding `while` loop saving explicitely the *iterator* and its *state*.
"""
function transform_for(expr, ui8::BoxedUInt8)
  @capture(expr, for element_ in iterator_ body__ end) || return expr
  ui8.n += one(UInt8)
  iter = Symbol("_iterator_", ui8.n)
  state = Symbol("_iterstate_", ui8.n)
  quote 
    $iter = $iterator
    $state = start($iter)
    while !done($iter, $state)
      $element, $state = next($iter, $state)
      $(body...)
    end
  end
end

"""
Function that replaces a variable `x` in an expression by `_fsmi.x` where `x` is a known slot.
"""
function transform_slots(expr, symbols::Base.KeyIterator{Dict{Symbol,Type}})
  @capture(expr, sym_ | sym_.inner_) || return expr
  sym isa Symbol && sym in symbols || return expr
  inner == nothing ? :(_fsmi.$sym) : :(_fsmi.$sym.$inner)
end

"""
Function that replaces a `arg = @yield ret` statement  by 
```julia 
  @yield ret; 
  arg = arg_
``` 
where `arg_` is the argument of the function containing the expression.
"""
function transform_arg(expr)
  @capture(expr, (arg_ = @yield ret_) | (arg_ = @yield)) || return expr
  quote
    @yield $ret
    $arg = _arg
  end
end

"""
Function that replaces a `@yield ret` or `@yield` statement by 
```julia
  @yield ret
  _arg isa Exception && throw(_arg)
```
to allow that an `Exception` can be thrown into a `@resumable function`.
"""
function transform_exc(expr)
  @capture(expr, (@yield ret_) | @yield) || return expr
  quote
    @yield $ret
    _arg isa Exception && throw(_arg)
  end
end

"""
Function that replaces a `try`-`catch`-`finally`-`end` expression having a top level `@yield` statement in the `try` part
```julia
  try
    before_statements...
    @yield ret
    after_statements...
  catch exc
    catch_statements...
  finally
    finally_statements...
  end
```
with a sequence of `try`-`catch`-`end` expressions:
```julia
  try
    before_statements...
  catch
    catch_statements...
    @goto _TRY_n
  end
  @yield ret
  try
    after_statements...
  catch
    catch_statements...
  end
  @label _TRY_n
  finally_statements...
```
"""
function transform_try(expr, ui8::BoxedUInt8)
  @capture(expr, (try body__ end) | (try body__ catch exc_; handling__ end) | (try body__ catch exc_; handling__ finally always__ end)) || return expr
  ui8.n += one(UInt8)
  new_body = []
  segment = []
  for ex in body
    if @capture(ex, (@yield ret_) | @yield)
      exc == nothing ? push!(new_body, :(try $(segment...) catch; $(handling...); @goto $(Symbol("_TRY_", :($(ui8.n)))) end)) : push!(new_body, :(try $(segment...) catch $exc; $(handling...) ; @goto $(Symbol("_TRY_", :($(ui8.n)))) end))
      push!(new_body, quote @yield $ret end)
      segment = []
    else
      push!(segment, ex)
    end
  end
  if segment != []
    exc == nothing ? push!(new_body, :(try $(segment...) catch; $(handling...) end)) : push!(new_body, :(try $(segment...) catch $exc; $(handling...) end))
  end
  push!(new_body, :(@label $(Symbol("_TRY_", :($(ui8.n))))))
  always == nothing || push!(new_body, quote $(always...) end)
  quote $(new_body...) end
end

"""
Function that replaces a `@yield ret` or `@yield` statement with 
```julia
  _fsmi._state = n
  return ret
  @label _STATE_n
  _fsmi._state = 0xff
```
"""
function transform_yield(expr, ui8::BoxedUInt8)
  @capture(expr, (@yield ret_) | @yield) || return expr
  ui8.n += one(UInt8)
  quote
    _fsmi._state = $(ui8.n)
    return $ret
    @label $(Symbol("_STATE_", :($(ui8.n))))
    _fsmi._state = 0xff
  end
end
