-module(ex_buyer_eqc).

-compile(export_all).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_component.hrl").


api_spec() ->
  #api_spec{
     language = erlang,
     modules  = [
                  #api_module{
                     name = gproc_ps,
                     functions = [ #api_fun{ name = subscribe, arity = 2},
                                   #api_fun{ name = publish,   arity = 3}
                                 ]
                    }
                ]}.
  

init_buyer_lang(Id, Amount, Price) ->
  ?SEQ(?EVENT(gproc_ps, subscribe, [l, {ex, sell}], true),
       ?EVENT(gproc_ps, publish,   [l, {ex, buy}, {{ex_buyer,Id},Amount, Price}], ok)
      ).

initial_state() ->
  [].

%% @doc Default generated property
-spec prop_buyer() -> eqc:property().
prop_buyer() ->
  ?SETUP(fun() -> 
             %% setup mocking here
             eqc_mocking:start_mocking(api_spec()),  
             fun() -> application:stop(gproc) end %% Teardown function
         end, 
  ?FORALL(Cmds, commands(?MODULE),
          begin
            start(),
            {H, S, Res} = run_commands(?MODULE,Cmds),
            stop(S),
            pretty_commands(?MODULE, Cmds, {H, S, Res},
                            Res == ok)
          end)).


start() ->
  application:start(gproc).

stop(S) ->
  [ ex_buyer:stop(Id) || Id <- S ],
  application:stop(gproc).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% buyer

buyer(Id, Amount, Price) ->
  eqc_mocking:init_lang(?MODULE:init_buyer_lang(Id, Amount, Price), ?MODULE:api_spec()),
  ex_buyer:start_link(Id, Amount, Price).

buyer_args(S) ->
  [buyer_id(S), amount(), price()].

buyer_post(_S, [Id,Amount,Price], _)  ->
  eqc_mocking:check_callouts(?MODULE:init_buyer_lang(Id, Amount, Price)).

buyer_next(S, _V, [Id, _Amount, _Price]) ->
  [Id|S].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GENERATORS
buyer_id(S) ->
  ?SUCHTHAT(N, pos_int(),
            not lists:member(N, S)).

amount() ->
  pos_int().

price() ->
  pos_int().

pos_int() ->
  ?SUCHTHAT(N, int(), N>0).

