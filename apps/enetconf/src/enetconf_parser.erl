%%------------------------------------------------------------------------------
%% Copyright 2012 FlowForwarding.org
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%-----------------------------------------------------------------------------

%% @author Erlang Solutions Ltd. <openflow@erlang-solutions.com>
%% @author Krzysztof Rutka <krzysztof.rutka@erlang-solutions.com>
%% @copyright 2012 FlowForwarding.org
%% @doc Module for parsing NETCONF's XML.
-module(enetconf_parser).

%% API
-export([parse/1]).

-include_lib("xmerl/include/xmerl.hrl").
-include("enetconf.hrl").

%%------------------------------------------------------------------------------
%% API functions
%%------------------------------------------------------------------------------

%% @doc Parse incoming XML using NETCONF's XML schema.
-spec parse(string()) -> ok | {error, Reason :: term()}.
parse(XML) ->
    %% Get the schema
    [{schema, Schema}] = ets:lookup(enetconf, schema),

    %% Scan the XML
    {ScannedXML, _Rest} = xmerl_scan:string(XML),

    %% Validated XML against the schema
    case xmerl_xsd:validate(ScannedXML, Schema) of
        {error, Reason} ->
	    %% TODO: If a peer receives an <rpc> message that is not well-
	    %% formed XML or not encoded in UTF-8, it SHOULD reply with a
	    %% "malformed-message" error.  If a reply cannot be sent for
	    %% any reason, the server MUST terminate the session.
            {error, Reason};
        {ValidatedXML, _} ->
            parse_rpc(ValidatedXML)
    end.

%%------------------------------------------------------------------------------
%% Internal functions
%%------------------------------------------------------------------------------

%% @private
parse_rpc(#xmlElement{name = rpc, attributes = Attrs, content = Content}) ->
    MessageId = get_attr_value('message-id', Attrs),
    {ok, #rpc{message_id = MessageId, operation = parse_operation(Content)}};
parse_rpc(#xmlElement{name = hello, content = Content}) ->
    CapList = lists:keyfind(capabilities, #xmlElement.name, Content),
    Capabilities = parse_capabilities(CapList#xmlElement.content, []),
    {ok, #hello{capabilities = Capabilities,
		session_id = get_optional('session-id', Content)}}.

%% @private
parse_capabilities([], Capabilities) ->
    lists:reverse(Capabilities);
parse_capabilities([#xmlElement{name = capability,
				content = Content} | Rest], Capabilities) ->
    [#xmlText{value = NewCap}] = Content,
    parse_capabilities(Rest, [string:strip(NewCap) | Capabilities]);
parse_capabilities([_ | Rest], Capabilities) ->
    parse_capabilities(Rest, Capabilities).

%% @private
parse_operation([#xmlElement{name = 'edit-config', content = Content} | _]) ->
    #edit_config{target = get_target(Content),
                 default_operation = get_optional('default-operation', Content),
                 test_option = get_optional('test-option', Content),
                 error_option = get_optional('error-option', Content)};
parse_operation([#xmlElement{name = 'get-config', content = Content} | _]) ->
    #get_config{source = get_source(Content),
                filter = get_filter(Content)};
parse_operation([#xmlElement{name = 'copy-config', content = Content} | _]) ->
    #copy_config{source = get_source(Content),
                 target = get_target(Content)};
parse_operation([#xmlElement{name = 'delete-config', content = Content} | _]) ->
    #delete_config{target = get_target(Content)};
parse_operation([_ | Rest]) ->
    parse_operation(Rest).

%% @private
get_source(Content) ->
    Source = lists:keyfind(source, #xmlElement.name, Content),
    find_source(Source#xmlElement.content).

%% @private
find_source([#xmlElement{name = startup} | _]) ->
    startup;
find_source([#xmlElement{name = candidate} | _]) ->
    candidate;
find_source([#xmlElement{name = running} | _]) ->
    running;
find_source([#xmlElement{name = url, content = Content} | _]) ->
    [#xmlText{value = Value}] = Content,
    {url, string:strip(Value)};
find_source([_ | Rest]) ->
    find_source(Rest).

%% @private
get_target(Content) ->
    Source = lists:keyfind(target, #xmlElement.name, Content),
    hd([Name || #xmlElement{name = Name} <- Source#xmlElement.content]).

%% @private
get_optional(Element, Content) ->
    case lists:keyfind(Element, #xmlElement.name, Content) of
        false ->
            undefined;
        #xmlElement{content = [#xmlText{value = Value}]} ->
            list_to_atom(string:strip(Value))
    end.

%% @private
get_filter(Content) ->
    case lists:keyfind(filter, #xmlElement.name, Content) of
        false ->
            undefined;
        #xmlElement{attributes = Attrs} ->
            case string:strip(get_attr_value(type, Attrs)) of
                "subtree" ->
                    #filter{type = subtree};
                "xpath" ->
                    Select = get_attr_value(select, Attrs),
                    #filter{type = xpath, select = Select}
            end
    end.

%%------------------------------------------------------------------------------
%% Helper functions
%%------------------------------------------------------------------------------

%% @private
get_attr_value(Name, Attrs) ->
    Attribute = lists:keyfind(Name, #xmlAttribute.name, Attrs),
    Attribute#xmlAttribute.value.
