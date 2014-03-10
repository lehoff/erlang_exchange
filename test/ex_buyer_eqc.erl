-module(ex_buyer_eqc).

-compile(export_all).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_component.hrl").


api_spec() ->
  #api_spec{
     language = erlang,
     modules  = [ #api_module{
                     name = gproc,
                     functions = [ #api_fun{ name = register_name,  arity = 2 },
                                   #api_fun{ name = whereis_name,   arity = 1 }
                                 ]
                    },
                  #api_module{
                     name = gproc_ps,
                     functions = [ #api_fun{ name = subscribe, arity = 2},
                                   #api_fun{ name = publish,   arity = 3}
                                 ]
                    }
                ]}.
  
init_buyer_lang() ->
  ?PAR(?SEQ(?EVENT(gproc, register_name, [?WILDCARD, ?WILDCARD], yes),
            ?SEQ(?EVENT(gproc_ps, subscribe, [l, {ex, sell}], true),
                 ?EVENT(gproc_ps, publish,   [l, {ex, buy}, ?WILDCARD], ok)
                )
           ),
       ?REPLICATE(?EVENT(gproc, whereis_name, [?WILDCARD], ?WILDCARD))
      ).

initial_state() ->
  [].

%% @doc Default generated property
-spec prop_buyer() -> eqc:property().
prop_buyer() ->
  ?SETUP(fun() -> 
             %% setup mocking here 
             eqc_mocking:start_mocking(api_spec()),  
             fun() -> ok end %% Teardown function
         end, 
  ?FORALL(Cmds, commands(?MODULE),
    begin
      {H, S, Res} = run_commands(?MODULE,Cmds),
      pretty_commands(?MODULE, Cmds, {H, S, Res},
                      Res == ok)
    end)).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% buyer

buyer(Id, Amount, Price) ->
  eqc_mocking:init_lang(?MODULE:init_buyer_lang(), ?MODULE:api_spec()),
  ex_buyer:start_link(Id, Amount, Price).

buyer_args(_S) ->
  [buyer_id(), amount(), price()].

buyer_post(_S, [_,_,_], _)  ->
  eqc_mocking:check_callouts(?MODULE:init_buyer_lang()).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GENERATORS
buyer_id() ->
  pos_int().

amount() ->
  pos_int().

price() ->
  pos_int().

pos_int() ->
  ?SUCHTHAT(N, int(), N>0).

