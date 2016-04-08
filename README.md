doppler
=======

[![Build Status](https://travis-ci.org/funbox/doppler.svg?branch=master)](https://travis-ci.org/funbox/doppler)

`doppler` is a simple moking library for Erlang. The key features are:

* Orientation to DI-specific code. I.e. *it does not allow* to stub arbitrary module calls (`foo:bar(baz)`) like `em`, `meck` etc. See examples for details.
* Simplicity. It does not use any complicated features like module code reload, etc.
* Preserving state between calls of mock's methods. This allows to easily mock `gen_server` interfaces.

NB. There are many kinds of objects which are often refered to as "mocks", see, for example, [The Little Mocker](https://blog.8thlight.com/uncle-bob/2014/05/14/TheLittleMocker.html). According to this notation, objects that `doppler` constructs are close to "spies", but they also can be used as "stubs", "dummies", etc.

Why "doppler"?
--------------

> ...A doppler only needs to know or examine the victim to adapt his own shape immediately and perfectly to the structure of the original. I would point out that this is no illusion, but an extremely fine metamorphosis that imitates even the smallest details. How do mimics manage this? That, we don't know. Sorcerers presume that we are dealing with a process similar to that of lycanthropy, but I think that this is an entirely different mechanism, or something like lycanthropy but with an underlying force a thousand times greater. A werewolf can only take two or perhaps three forms at most, while the mimic can transform infinitely so long as what he copies corresponds more or less to his body mass.
>
> -- <cite>Andrzej Sapkowski, THE SWORD OF DESTINY</cite>

Build
-----

    $ make

Tests
-----

    $ make test

Sample usage
------------

Consider the following example. We need to compose a function which prints current time to stdout. A common implementation is:

```erlang
print_time() ->
    Time = erlang:system_time(seconds),
    io:format("~p", [Time]).
```

How could we test it? The possible way is to "mock" `erlang:system_time` and `io:format` calls. But if we then change `io:format` call to `io:fwrite` or use `os:timestamp` instead of `erlang:system_time`, our code will still work, but tests will fail. This generally shouldn't happen: if a function's interface does not change, the tests shouldn't fail. This points out that our function's contract is wider than it's interface: it implicitly uses "global" functions. Such code is difficult to test and support.

One way to improve the situation is to make contract explicit.


```erlang

-module(system).
-export([time/0, print/1]).

time() ->
    erlang:system_time(seconds).

print(Str) ->
    io:format(Str).
```


```erlang
print_time(System) ->
    Time = System:time(),
    System:print(io_lib:format("~p", [Time])).
```

Now we are able to write tests which do not break as long as our function keeps its interface.

```erlang
print_time_test(_Config) ->
    PredefinedTime = 1459246205,
    System = doppler:start(undefined),
    doppler:def(System, time, fun(State) ->  {PredefinedTime, State} end),
    doppler:def(System, print, fun(_State, Str) ->
        NewState = Str,
        {ok, NewState}
    end),

    print_time(System),

    PrintedTime = doppler:state(System),
    doppler:stop(System).

    "1459246205" = lists:flatten(PrintedTime).

```

Here we use `doppler` to mock `system` module and keep printed time in our doppler's state. We also can view the whole history of calls to our module:

```erlang
> doppler:log(System).
[{time,[]},{print,[["1459246205"]]}]
```

Of course, one can write a mock for `System` from scratch as a plain module, but this is a tedious job: we need to have a seperate module for each mock used, and also we should write a lot of boilerplate code for passing state between mocked calls.

Usage
----

Initialization with function:

```erlang
D = doppler:start(fun() -> 123 end),
123 = doppler:state(D),
ok = doppler:stop(D).
```

Initialization with value:

```erlang
D = doppler:start(123),
123 = doppler:state(D),
ok = doppler:stop(D).
```

Defining methods and obtaining log of calls.

To define a method, we call `doppler:def`. We pass to it:
* The doppler object itself.
* A name of the function.
* A lambda implementing the method.

When the method is called, it receives the doppler's state as first argument (this may be considered as `this` or `self`) and all original arguments of the call.
The method should return:
* A tuple `{Result, NewState}`. Then `Result` will be returned from the function when called, and `NewState` will be memoized and passed to further calls.
* A tuple `{error, Error, NewState}`. Then `NewState` will be memoized and `Error` will be thrown as an exception from the called method.


```erlang
D = doppler:start(123),
[] = doppler:log(D),

doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),
doppler:def(D, decr, fun(N, Inc) -> {N-Inc, N-Inc} end),

D:incr(1),
D:decr(2),

[{incr, [1]}, {decr, [2]}] = doppler:log(D),

ok = doppler:stop(D).
```

Calling an undefined method (this can happen if we changed the mocked interface, but haven't updated tests yet):

```erlang
D = doppler:start(123),

ok = try
    D:incr(1)
catch error:{doppler_undefined_method_called, [{doppler_state,123}, {name,incr}, {args,[1]}]} ->
    ok
end,

ok = doppler:stop(D).
```

This what happens when mocked method is not defined properly:

```erlang
D = doppler:start(123),

doppler:def(D, incr, fun(_State, _Arg) -> bad_return end),

ok = try
    D:incr(1)
catch error:{doppler_bad_method_return, [{doppler_state,123}, {name,incr}, {args,[1]}, {return, bad_return}]} ->
    ok
end,

ok = doppler:stop(D).
```

Having an exception inside mocked method (this should not happen):

```erlang
D = doppler:start(123),

doppler:def(D, incr, fun(_, _) -> erlang:error(bad_return) end),

ok = try
    D:incr(1)
catch error:{doppler_error_in_method, [{doppler_state,123}, {name,incr}, {args,[1]}, {error, {error, bad_return}}]} ->
    ok
end,

ok = doppler:stop(D).
```

Emulating exceptions:

```erlang
D = doppler:start(123),

doppler:def(D, incr, fun(N, _) -> {error, {error, bar}, N} end),
ok = try
    D:incr(1)
catch error:bar ->
    ok
end,

doppler:def(D, incr, fun(N, _) -> {error, {throw, bar}, N} end),
ok = try
    D:incr(1)
catch throw:bar ->
    ok
end,

doppler:def(D, incr, fun(N, _) -> {error, {exit, bar}, N} end),
ok = try
    D:incr(1)
catch exit:bar ->
    ok
end,

ok = doppler:stop(D).
```


