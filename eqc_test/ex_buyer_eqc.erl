-module(ex_buyer_eqc).

-compile(export_all).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_component.hrl").

-record(state,
  { processes = []
}).


api_spec() ->
  #api_spec{
     language = erlang,
     modules  = [
                  #api_module{
                     name = gproc_ps,
                     functions = [ #api_fun{ name = subscribe, arity = 2},
                                   #api_fun{ name = publish,   arity = 3}
                                 ]
                    },
                 #api_module{
                    name = ex_seller,
                    functions = [ #api_fun{ name = buy_offer, arity=4}
                                ]
                   }
                ]}.
  


initial_state() ->
  #state{}.

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

stop(#state { processes = Ps }) ->
  [ ex_buyer:stop(Id) || {Id, _Pid} <- Ps ],
  ok.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% buyer

buyer(Id, Amount, Price) ->
  {ok, Pid} = ex_buyer:start_link(Id, Amount, Price),
  Pid.

buyer_args(_S) ->
  [buyer_id(), amount(), price()].

buyer_pre(S, [Id, _, _]) ->
  not lists:member(Id, buyer_ids(S)).

buyer_callouts(_S, [Id, Amount, Price]) ->
  ?SEQ(?CALLOUT(gproc_ps, subscribe, [l, {ex, sell}], true),
       ?CALLOUT(gproc_ps, publish,   [l, {ex, buy},
                                      {Id,Amount, Price}],
                ok)
      ).


buyer_next(#state { processes = Ps } = S, Pid, [Id, _Amount, _Price]) ->
  S#state { processes = [{Id, Pid}|Ps]}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% broadcast of a {ex,sell} intention
%% for testing we only try it on one of the buyers

publish_sell({_BuyerId,BuyerPid}, SellerId, SellAmount, SellPrice) ->
  BuyerPid ! {gproc_ps_event, {ex, sell}, {SellerId, SellAmount, SellPrice}},
  sync(BuyerPid),
  ok.

publish_sell_pre(#state { processes = Ps}) ->
  Ps /= [].

publish_sell_args(S) ->
  [existing_buyer(S), seller_id(), amount(), price()].

publish_sell_callouts(_S, [{BuyerId, _}, SellerId, SellAmount, _SellPrice]) ->
  ?CALLOUT(ex_seller, buy_offer, [SellerId, BuyerId, ?WILDCARD, SellAmount], ok).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% sending of a buy offer
%% buy_offer_pre(S) -> buyers_present(S).

%% buy_offer_callouts(_S, [{BuyerId, _}, SellerId, SellAmount, _SellPrice] = Args) ->
%%   ?SEQ( ?SELFCALL(publish_sell, Args),
%%         ?CALLOUT(ex_seller, buy_offer, [SellerId, BuyerId, ?WILDCARD, SellAmount], ok) ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GENERATORS
buyer_id() ->
  pos_int().

existing_buyer(#state { processes = Ps }) ->
  elements(Ps).

seller_id() ->
  pos_int().

amount() ->
  pos_int().

price() ->
  pos_int().

pos_int() ->
  ?LET(N, nat(), N+1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% helpers

buyer_ids(#state { processes = Ps }) ->
  [ Id ||  {Id, _} <- Ps ].

buyers_present(#state { processes = [] }) -> false;
buyers_present(#state { processes = [_|_] }) -> true.

sync(Id) ->
  ex_buyer:sync(Id).
