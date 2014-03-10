-module(ex_buyer).
%%% @doc the ex_buyer module represents buyers on the erlang_exchange.
%%%      Every buy request becomes a ex_buyer process that subscribes to sell
%%%      intentions on a gproc event using the pub/sub module gproc_ps.
%%%      All deals are done with a three-way handshake, where either the buyer or the
%%%      seller is the initiating part.
%%%
%%%      Seller initiated buys:
%%%      A new buyer publishes an intention to buy that matches the previously
%%%      published intention by a seller.
%%%      The seller reacts to the published intetion by sending a sell_offer to the
%%%      buyer stating how many shares at what price he is willing to sell.
%%%      The buyer then responds with a sell_offer_response stating how many he wants
%%%      to buy from that seller. A zero amount is possible and means no deal.
%%%      When the seller receives the sell_offer_response he closes off the deal on
%%%      his side and responds with a sell_complete message to the buyer, who can
%%%      then close the deal on his side.
%%%
%%%      Buyer initiated buys:
%%%      A new seller publishes an intetion to sell that matches the previously
%%%      published intetion by a buyer.
%%%      The buyer reacts to the published intetion by sending a buy_offer to the
%%%      seller stating how many shares he is willing to buy at the sellers price.
%%%      The seller responds with a buy_offer_response stating how many he will sell.
%%%      The buyer then closes the deal on his side and send a buy_complete message
%%%      to the seller, who can then close the deal on his side
%%%
%%%      Offers:
%%%      Once an offer has been made it is not off the table before a response has
%%%      been recevied.

-behaviour(gen_server).

-export([start_link/3,
         stop/1]).

-export([buy_offer_response/3,
         sell_offer/5,
         sell_complete/2,
         status/1]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-type ex_id() :: integer().

-record(state,
        { id :: integer(),
          amount :: integer(),
          price :: float(),
          pending_buys = [] :: [{erlang:ref(), ex_id(), integer(), float()}],
          bought = [] :: [{ex_id(),integer(), float()}]
        }).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_link(Id::integer(), Amount::integer(), Price::float()) ->
                    {'ok', pid()} | 'ignore' | {'error',term()}.
start_link(Id, Amount, Price) ->
  gen_server:start_link({via, gproc, {n,l,buyer_id(Id)}},?MODULE, [Id, Amount, Price], []).

stop(Id) ->
  gen_server:call(id_pid(Id), stop).

status(Id) ->
  gen_server:call(id_pid(Id), status).

buy_offer_response(Id, Ref, Amount) ->
  cast(Id, {buy_offer_response, Ref, Amount}).

sell_offer(Id, SellerId, Ref, SellAmount, SellPrice) ->
  cast(Id, {sell_offer, SellerId, Ref, SellAmount, SellPrice}).

sell_complete(Id, Ref) ->
  cast(Id, {sell_complete, Ref}).

cast(Id, Msg) ->
  gen_server:cast(id_pid(Id), Msg).                        

id_pid(Id) ->
  gproc:whereis_name({n,l,buyer_id(Id)}).

buyer_id(Id) ->
  {ex_buyer, Id}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([Id, Amount, Price]) ->
  gproc_ps:subscribe(l, {ex, sell}),
  gproc_ps:publish(l, {ex, buy}, {buyer_id(Id), Amount, Price}),
  {ok, #state{id=Id, amount=Amount, price=Price}}.

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};
handle_call(status, _From, #state{amount=Amount,
                                  price=Price,
                                  pending_buys=PendingBuys,
                                  bought=Bought}=State) ->
  Reply = [{amount,Amount}, {price,Price},
           {pending_buys, PendingBuys}, {bought, Bought}],
  {reply, Reply, State}.

handle_cast({buy_offer_response, Ref, BoughtAmount}, 
            #state{pending_buys=PendingBuys,
                   bought=Bought}=State) ->
  case lists:keytake(Ref, 1 , PendingBuys) of
    {vaule, {Ref, Seller, _, SellPrice}, NewPendingBuys} ->
      NewState= State#state{pending_buys=NewPendingBuys,
                            bought=[{Seller, BoughtAmount, SellPrice}|Bought]},
      ex_seller:buy_complete(Seller, Ref),
      {noreply, NewState};
    false ->
      %% log an error
      {noreply, State}
  end;
handle_cast({sell_offer, SellerId, Ref, SellAmount, SellPrice},
            #state{amount=Amount, price=Price}=State) when SellPrice =< Price ->
  DealAmount = min(Amount, SellAmount),
  PendingBuys =[{Ref, SellerId, DealAmount, SellPrice}|
                State#state.pending_buys],
  ex_seller:sell_offer_response(SellerId, Ref, DealAmount),
  {noreply, State#state{pending_buys=PendingBuys,
                        amount=Amount-DealAmount}};
handle_cast({sell_complete, Ref},
            #state{pending_buys=PendingBuys}=State) ->
  case lists:keytake(Ref, PendingBuys) of
    {value, {Ref, Seller, DealAmount, DealPrice}, NewPendingBuys} ->
      NewBought = [{Seller, DealAmount, DealPrice}|
                   State#state.bought],
      {noreply, State#state{pending_buys=NewPendingBuys,
                            bought=NewBought}};
    false ->
      %% log an error
      {noreply, State}
  end.



handle_info({gproc_ps_event, {ex, sell}, {Seller, SellAmount, SellPrice}},
            #state{id=Id,
                   amount=Amount,
                   price=Price}=State)
  when SellPrice =< Price ->
  Ref = make_ref(),
  BuyAmount = min(Amount, SellAmount),
  ex_seller:buy_offer(Seller, Id, BuyAmount),
  PendingBuys = [{Ref, Seller, BuyAmount, SellPrice} | State#state.pending_buys ],
  {noreply, State#state{amount=Amount-BuyAmount,
                        pending_buys=PendingBuys}}.




terminate(_Reason,_State) ->
  ok.

code_change(_, _State, _) ->
  {error, not_implemented}.
