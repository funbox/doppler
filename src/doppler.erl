-module('doppler').

%% API exports
-export([
    start/0,
    start/1,
    stop/1,
    log/1,
    state/1,
    methods/1,
    def/3,
    stub/2,
    stub/3,
    call/2
]).

-type state() :: term().
-type methods() :: map().
-type log() :: list().

-record(doppler, {
    state :: state(),
    methods :: methods(),
    log :: log()
}).

-record(doppler_universal, {
    doppler_ref :: pid()
}).

-type init_fun() :: fun(() -> state()).

-type method_return() :: {term(), state()} | {error, term(), state()}.
-type method_fun() :: fun((...) -> method_return()).


%%====================================================================
%% API functions
%%====================================================================

-spec start() -> #doppler_universal{}.
start() ->
    start(no_initial_state_specified).

-spec start(init_fun() | state()) -> #doppler_universal{}.
start(InitFun) when is_function(InitFun) ->
    {ok, DopplerRef} = agent:start(fun() -> #doppler{
        state = InitFun(),
        methods = #{},
        log = []
    } end),
    #doppler_universal{
       doppler_ref = DopplerRef
    };

start(InitialState) ->
    start(fun() -> InitialState end).

-spec stop(#doppler_universal{}) -> ok.
stop(#doppler_universal{doppler_ref = DopplerRef}) ->
    ok = agent:stop(DopplerRef).

-spec log(#doppler_universal{}) -> log().
log(#doppler_universal{doppler_ref = DopplerRef}) ->
    agent:get(DopplerRef, fun(#doppler{log = Log}) -> lists:reverse(Log) end).

-spec state(#doppler_universal{}) -> state().
state(#doppler_universal{doppler_ref = DopplerRef}) ->
    agent:get(DopplerRef, fun(#doppler{state = State}) -> State end).

-spec methods(#doppler_universal{}) -> methods().
methods(#doppler_universal{doppler_ref = DopplerRef}) ->
    agent:get(DopplerRef, fun(#doppler{methods = Methods}) -> Methods end).

-spec def(#doppler_universal{}, atom(), method_fun()) -> ok.
def(#doppler_universal{doppler_ref = DopplerRef}, Name, Fun) when is_atom(Name) and is_function(Fun) ->
    {arity, Arity} = erlang:fun_info(Fun, arity),
    ok = add_method_stub(DopplerRef, Name, Arity, Fun).

-spec stub(#doppler_universal{}, atom()) -> ok.
stub(Doppler, Name) when is_atom(Name) ->
    stub(Doppler, Name, undefined).

-spec stub(#doppler_universal{}, atom(), method_fun() | term()) -> ok.
stub(Doppler, Name, Fun) when is_atom(Name) and is_function(Fun) ->
    {arity, Arity} = erlang:fun_info(Fun, arity),
    MethodFun = case Arity of
        0 -> fun(St) -> {Fun(), St} end;
        1 -> fun(St, P1) -> {Fun(P1), St} end;
        2 -> fun(St, P1, P2) -> {Fun(P1, P2), St} end;
        3 -> fun(St, P1, P2, P3) -> {Fun(P1, P2, P3), St} end;
        4 -> fun(St, P1, P2, P3, P4) -> {Fun(P1, P2, P3, P4), St} end;
        5 -> fun(St, P1, P2, P3, P4, P5) -> {Fun(P1, P2, P3, P4, P5), St} end;
        6 -> fun(St, P1, P2, P3, P4, P5, P6) -> {Fun(P1, P2, P3, P4, P5, P6), St} end;
        7 -> fun(St, P1, P2, P3, P4, P5, P6, P7) -> {Fun(P1, P2, P3, P4, P5, P6, P7), St} end;
        8 -> fun(St, P1, P2, P3, P4, P5, P6, P7, P8) -> {Fun(P1, P2, P3, P4, P5, P6, P7, P8), St} end;
        _Else -> throw({doppler_stub_error, more_than_8_args})
    end,
    def(Doppler, Name, MethodFun);
stub(#doppler_universal{doppler_ref = DopplerRef}, Name, Value) when is_atom(Name) ->
    Fun = fun(St) -> {Value, St} end,
    ok = add_method_stub(DopplerRef, Name, any_arity, Fun).

-spec call(atom(), list()) -> term() | no_return().
call(FunName, Args) ->
    {#doppler_universal{doppler_ref = DopplerRef}, FunArgs} = split_args(Args),
    case agent:get_and_update(DopplerRef, fun(Doppler) -> call(Doppler, FunName, FunArgs) end) of
        {unknown_method, State} -> erlang:error({doppler_undefined_method_called, [{doppler_state, State}, {name, FunName}, {args, FunArgs}]});
        {bad_return, Return, State} -> erlang:error({doppler_bad_method_return, [{doppler_state, State}, {name, FunName}, {args, FunArgs}, {return, Return}]});
        {call_error, Error, Stack, State} -> erlang:error({doppler_error_in_method, [{doppler_state, State}, {name, FunName}, {args, FunArgs}, {error, Error}, {stack, Stack}]});
        {custom_call_error, Error} -> raise_error(Error);
        {result, Result} -> Result
    end.

%%====================================================================
%% Internal functions
%%====================================================================

add_method_stub(DopplerRef, Name, Arity, Fun) ->
    Key = {Name, Arity},
    agent:update(DopplerRef, fun(#doppler{methods = Methods} = Doppler) ->
        Doppler#doppler{methods = maps:put(Key, Fun, Methods)}
    end).

split_args(Args) ->
    [Doppler | Rest] = lists:reverse(Args),
    {Doppler, lists:reverse(Rest)}.

call(#doppler{state = State, methods = Methods, log = Log} = Doppler, FunName, FunArgs) ->
    Key = {FunName, length(FunArgs) + 1},
    case maps:find(Key, Methods) of
        error ->
            case maps:find({FunName, any_arity}, Methods) of
                {ok, Method} ->
                    call_method(Doppler, FunName, FunArgs, [], Method);
                error ->
                    {{unknown_method, State}, Doppler#doppler{log = [{FunName, FunArgs} | Log]}}
            end;
        {ok, Method} ->
            call_method(Doppler, FunName, FunArgs, FunArgs, Method)
    end.

call_method(#doppler{state = State, log = Log} = Doppler, FunName, FunArgs, ArgsToApply, Fun) ->
    try
        case erlang:apply(Fun, [State | ArgsToApply]) of
            {Result, NewState} -> {{result, Result}, Doppler#doppler{log = [{FunName, FunArgs} | Log], state = NewState}};
            {error, CustomError, NewState} -> {{custom_call_error, CustomError}, Doppler#doppler{log = [{FunName, FunArgs} | Log], state = NewState}};
            BadReturn -> {{bad_return, BadReturn, State}, Doppler#doppler{log = [{FunName, FunArgs} | Log]}}
        end
    catch Class:Error ->
        {{call_error, {Class, Error}, erlang:get_stacktrace(), State}, Doppler#doppler{log = [{FunName, FunArgs} | Log]}}
    end.

raise_error({throw, What}) ->
    throw(What);
raise_error({exit, What}) ->
    exit(What);
raise_error({error, What}) ->
    erlang:error(What);
raise_error(BadError) ->
    erlang:error({doppler_bad_custom_error, BadError}).

