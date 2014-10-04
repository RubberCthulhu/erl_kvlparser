%%%-------------------------------------------------------------------
%%% @author Danil Onishchenko <alevandal@kernelpanic>
%%% @copyright (C) 2014, Danil Onishchenko
%%% @doc
%%%
%%% @end
%%% Created : 21 Jun 2014 by Danil Onishchenko <alevandal@kernelpanic>
%%%-------------------------------------------------------------------
-module(kvlparser).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% API
-export([parse/2]).

-record(kvlparser_item_spec, {
	  key :: term(),
	  parse = fun (X) -> X end :: function(),
	  type = any :: atom(),
	  optional = false :: boolean(),
	  default = undefined :: term(),
	  alias :: term(),
	  value = any :: term()
}).

%%%===================================================================
%%% API
%%%===================================================================

parse(Specs, List) ->
    parse(Specs, List, []).

parse([Spec | Specs], In, Out) ->
    #kvlparser_item_spec{key = Key} = Spec1 = compile_item_spec(Spec),
    case parse_list_item(Spec1, In) of
	{ok, Item} ->
	    parse(Specs, In, [Item | Out]);
	false ->
	    parse(Specs, In, Out);
	{error, Reason} ->
	    {error, {Key, Reason}}
    end;
parse([], _, Out) ->
    {ok, lists:reverse(Out)}.

-ifdef(TEST).
parse_success_test() ->
    In = [{first, <<"first">>}, {second, 2}],
    Spec = [{first, [{parse, fun (X) -> binary_to_list(X) end}]},
 	    {second, [{type, integer}]},
 	    {third, [optional, {default, 3}]}],
    {ok, Out} = parse(Spec, In),
    "first" = proplists:get_value(first, Out),
    2 = proplists:get_value(second, Out),
    3 = proplists:get_value(third, Out),
    ok.

parse_missing_test() ->
    In = [{first, <<"first">>}, {second, 2}],
    Spec = [{first, [{parse, fun (X) -> binary_to_list(X) end}]},
 	    {second, [{type, integer}]},
 	    {third, []}],
     {error, {third, missing}} = parse(Spec, In),
     ok.

parse_badarg_test() ->
    In = [{first, <<"first">>}, {second, 2}],
    Spec = [{first, [{transform, fun (X) -> binary_to_list(X) end}]},
 	    {second, [{transform, fun (X) -> binary_to_list(X) end}]}],
     {error, {second, badarg}} = parse(Spec, In),
     ok.
-endif.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

%%%===================================================================
%%% Internal functions
%%%===================================================================

compile_item_spec({Key, Opts}) ->
    Spec = #kvlparser_item_spec{key = Key, alias = Key},
    compile_item_spec(Spec, Opts).

compile_item_spec(Spec, [{parse, F} | Opts]) when is_function(F) ->
    compile_item_spec(Spec#kvlparser_item_spec{parse = F}, Opts);
%% This option is deprecated.
%% It is used only for compatibility with older versions and will be removed in future.
%% Use option 'parse' instead.
compile_item_spec(Spec, [{transform, F} | Opts]) when is_function(F) ->
    compile_item_spec(Spec#kvlparser_item_spec{parse = F}, Opts);
compile_item_spec(Spec, [{type, Type} | Opts]) when is_atom(Type) ->
    compile_item_spec(Spec#kvlparser_item_spec{type = Type}, Opts);
compile_item_spec(Spec, [optional | Opts]) ->
    compile_item_spec(Spec#kvlparser_item_spec{optional = true}, Opts);
compile_item_spec(Spec, [{default, Default} | Opts]) ->
    compile_item_spec(Spec#kvlparser_item_spec{optional = true, default = Default}, Opts);
compile_item_spec(Spec, [{alias, Alias} | Opts]) ->
    compile_item_spec(Spec#kvlparser_item_spec{alias = Alias}, Opts);
%% This option is deprecated.
%% It is used only for compatibility with older versions and will be removed in future.
%% Use option 'alias' instead.
compile_item_spec(Spec, [{key, Alias} | Opts]) ->
    compile_item_spec(Spec#kvlparser_item_spec{alias = Alias}, Opts);
compile_item_spec(Spec, [{value, Value} | Opts]) ->
    compile_item_spec(Spec#kvlparser_item_spec{value = Value}, Opts);
compile_item_spec(_, [Opt | _]) ->
    throw({unsupported_option, Opt});
compile_item_spec(Spec, []) ->
    Spec.

parse_list_item(Spec, List) ->
    #kvlparser_item_spec{
       key = Key,
       optional = Optional,
       default = Default,
       alias = Alias
      } = Spec,
    case lists:keyfind(Key, 1, List) of
	false when Optional, Default =/= undefined ->
	    {ok, {Alias, Default}};
	false when Optional ->
	    false;
	false ->
	    {error, missing};
	{_, Value} ->
	    parse_value(Spec, Value)
    end.

parse_value(#kvlparser_item_spec{type = Type} = Spec, Value) ->
    case check_type(Type, Value) of
	true ->
	    parse_value1(Spec, Value);
	false ->
	    {error, invalid_type}
    end.

parse_value1(#kvlparser_item_spec{parse = Parse} = Spec, Value) ->
    case parse_value_safe(Parse, Value) of
	{ok, Value1} ->
	    parse_value2(Spec, Value1);
	Error ->
	    Error
    end.

parse_value2(#kvlparser_item_spec{alias = Alias, value = any}, Value) ->
    {ok, {Alias, Value}};
parse_value2(#kvlparser_item_spec{alias = Alias, value = Value}, Value) ->
    {ok, {Alias, Value}};
parse_value2(_, _) ->
    {error, not_satisfied_value}.

parse_value_safe(F, Value) ->
    try
	Value1 = F(Value),
	{ok, Value1}
    catch
	_:_ -> {error, badarg}
    end.

check_type(any, _) ->
    true;
check_type(atom, X) ->
    is_atom(X);
check_type(binary, X) ->
    is_binary(X);
check_type(bitstring, X) ->
    is_bitstring(X);
check_type(boolean, X) ->
    is_boolean(X);
check_type(float, X) ->
    is_float(X);
check_type(integer, X) ->
    is_integer(X);
check_type(non_neg_integer, X) ->
    is_integer(X) andalso X >= 0;
check_type(pos_integer, X) ->
    is_integer(X) andalso X > 0;
check_type(neg_integer, X) ->
    is_integer(X) andalso X < 0;
check_type(number, X) ->
    is_number(X).



