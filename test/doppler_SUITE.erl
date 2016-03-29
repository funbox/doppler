-module(doppler_SUITE).

-export([all/0]).
-export([
    start_with_fun/1,
    start_with_state/1,
    stop/1,
    log/1,
    state/1,
    methods/1,
    def/1,
    call_ok/1,
    call_unknown_method/1,
    call_bad_return/1,
    call_error/1,
    call_custom_error/1
]).

all() -> [
    start_with_fun,
    start_with_state,
    stop,
    log,
    state,
    methods,
    def,
    call_ok,
    call_unknown_method,
    call_bad_return,
    call_error,
    call_custom_error
].

start_with_fun(_Config) ->
    D = doppler:start(fun() -> 123 end),
    123 = doppler:state(D),
    ok = doppler:stop(D).

start_with_state(_Config) ->
    D = doppler:start(123),
    123 = doppler:state(D),
    ok = doppler:stop(D).

stop(_Config) ->
    D = doppler:start(123),
    ok = doppler:stop(D),
    {noproc, _} = expect_exit(fun() -> doppler:state(D) end).

log(_Config) ->
    D = doppler:start(123),
    [] = doppler:log(D),

    doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),
    doppler:def(D, decr, fun(N, Inc) -> {N-Inc, N-Inc} end),

    D:incr(1),
    D:decr(2),

    [{incr, [1]}, {decr, [2]}] = doppler:log(D),

    ok = doppler:stop(D).

state(_Config) ->
    D = doppler:start(fun() -> 123 end),
    123 = doppler:state(D),
    ok = doppler:stop(D).

methods(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),
    doppler:def(D, decr, fun(N, Inc) -> {N-Inc, N-Inc} end),

    #{{incr, 2} := _Incr, {decr, 2} := _Decr} = doppler:methods(D),

    doppler:stop(D).

def(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),

    124 = D:incr(1),
    125 = D:incr(1),

    ok = doppler:stop(D).

call_ok(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),

    124 = D:incr(1),

    ok = doppler:stop(D).

call_unknown_method(_Config) ->
    D = doppler:start(123),

    {doppler_undefined_method_called, [{doppler_state,123}, {name,incr}, {args,[1]}]} = expect_error(fun() -> D:incr(1) end),

    doppler:def(D, incr, fun(N, Inc) -> {N+Inc, N+Inc} end),
    124 = D:incr(1),

    {doppler_undefined_method_called, [{doppler_state,124}, {name,incr}, {args,[1,2]}]} = expect_error(fun() -> D:incr(1,2) end),

    ok = doppler:stop(D).

call_bad_return(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(_, _) -> bad_return end),

    {doppler_bad_method_return, [{doppler_state,123}, {name,incr}, {args,[1]}, {return, bad_return}]} = expect_error(fun() -> D:incr(1) end),

    ok = doppler:stop(D).

call_error(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(_, _) -> erlang:error(bad_return) end),

    {doppler_error_in_method, [{doppler_state,123}, {name,incr}, {args,[1]}, {error, {error, bad_return}}]} = expect_error(fun() -> D:incr(1) end),

    ok = doppler:stop(D).

call_custom_error(_Config) ->
    D = doppler:start(123),

    doppler:def(D, incr, fun(N, _) -> {error, {error, bar}, N} end),
    bar = expect_exception(error, fun() -> D:incr(1) end),

    doppler:def(D, incr, fun(N, _) -> {error, {throw, bar}, N} end),
    bar = expect_exception(throw, fun() -> D:incr(1) end),

    doppler:def(D, incr, fun(N, _) -> {error, {exit, bar}, N} end),
    bar = expect_exception(exit, fun() -> D:incr(1) end),

    doppler:def(D, incr, fun(N, _) -> {error, {bad_error, bar}, N} end),
    {doppler_bad_custom_error, {bad_error, bar}} = expect_exception(error, fun() -> D:incr(1) end),

    ok = doppler:stop(D).

expect_exit(Fun) ->
    expect_exception(exit, Fun).

expect_error(Fun) ->
    expect_exception(error, Fun).

expect_exception(Class, Fun) ->
    try
        Fun(),
        ok
    catch Class:Error ->
        Error
    end.
