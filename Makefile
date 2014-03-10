PROJECT=erlang_exchange

DEPS =  gproc 

dep_gproc = https://github.com/lehoff/gproc.git master

include erlang.mk

ERLC_OPTS = +debug_info

CT_SUITES = ex_buyer_eqc

##REBAR_DEPS_DIR=${DEPS_DIR}
ERL_LIBS:=./deps:${ERL_LIBS}

shell:
	erl -pz ebin -pz deps/*/ebin -pz test
