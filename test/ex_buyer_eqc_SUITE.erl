-module(ex_buyer_eqc_SUITE).

-compile(export_all).

-include_lib("eqc/include/eqc_ct.hrl").

all() -> [check_prop_buyer].

check_prop_buyer(_) ->
    ?quickcheck((ex_buyer_eqc:prop_buyer())).

