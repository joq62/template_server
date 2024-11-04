%%%-------------------------------------------------------------------
%%% @author c50 <joq62@c50>
%%% @copyright (C) 2024, c50
%%% @doc
%%%
%%% @end
%%% Created : 27 Oct 2024 by c50 <joq62@c50>
%%%-------------------------------------------------------------------
-module(test_t).

-behaviour(gen_server).

-include("log.api").

-include("t.hrl").
-include("t.rd").

-define(Appl,t).

%% API

-export([
	 ping/0,
	 start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, {
		control_node_active,
		target_resources_status
	       }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec ping() -> pong | Error::term().
ping()-> 
    gen_server:call(?SERVER, {ping},infinity).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Pid :: pid()} |
	  {error, Error :: {already_started, pid()}} |
	  {error, Error :: term()} |
	  ignore.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()} |
	  {ok, State :: term(), Timeout :: timeout()} |
	  {ok, State :: term(), hibernate} |
	  {stop, Reason :: term()} |
	  ignore.
init([]) ->
    process_flag(trap_exit, true),
    

    {ok, #state{
	    control_node_active=false,
	    target_resources_status=[]
	   },0}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
	  {reply, Reply :: term(), NewState :: term()} |
	  {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
	  {reply, Reply :: term(), NewState :: term(), hibernate} |
	  {noreply, NewState :: term()} |
	  {noreply, NewState :: term(), Timeout :: timeout()} |
	  {noreply, NewState :: term(), hibernate} |
	  {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
	  {stop, Reason :: term(), NewState :: term()}.


handle_call({ping}, _From, State) ->
    Reply=pong,
    {reply, Reply, State};

handle_call(UnMatchedSignal, From, State) ->
   ?LOG_WARNING("Unmatched signal",[UnMatchedSignal]),
    io:format("unmatched_signal ~p~n",[{UnMatchedSignal, From,?MODULE,?LINE}]),
    Reply = {error,[unmatched_signal,UnMatchedSignal, From]},
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: term()) ->
	  {noreply, NewState :: term()} |
	  {noreply, NewState :: term(), Timeout :: timeout()} |
	  {noreply, NewState :: term(), hibernate} |
	  {stop, Reason :: term(), NewState :: term()}.

handle_cast(UnMatchedSignal, State) ->
    ?LOG_WARNING("Unmatched signal",[UnMatchedSignal]),
    io:format("unmatched_signal ~p~n",[{UnMatchedSignal,?MODULE,?LINE}]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
	  {noreply, NewState :: term()} |
	  {noreply, NewState :: term(), Timeout :: timeout()} |
	  {noreply, NewState :: term(), hibernate} |
	  {stop, Reason :: normal | term(), NewState :: term()}.

handle_info(timeout, State) ->
    pong=?Appl:ping(),
    {Y,M,D}=date(),
    {ok,Y,M,D}=?Appl:template_call(args),
    ok=?Appl:template_cast(args),


    %%-------- Initial testing access to ctrl node and needed applications

    CtrlNode=lib_vm:get_node(?ControlNodeName),
    NewControlStatus=case net_adm:ping(CtrlNode) of
			 pang->
			     ?LOG_WARNING("Error Control node ctrl is not available ",[CtrlNode]),
			     false; 
			 pong->
			     ?LOG_NOTICE("Control node ctrl is availablel",[CtrlNode]),
			     true
		     end,
    
    initial_trade_resources(),
    TargetTypes=rd_store:get_target_resource_types(),
    NonActiveTargetTypes=lists:sort([TargetType||TargetType<-TargetTypes,
						 []=:=rd:fetch_resources(TargetType)]),
    TargetStatus=State#state.target_resources_status,
    NewTargetStatus=if 
			TargetStatus=:=NonActiveTargetTypes->
			    NonActiveTargetTypes;
			true->
			    case NonActiveTargetTypes of
				[]->
				    ?LOG_NOTICE("All needed target types are availablel",[TargetTypes]);	    
				Error ->
				    ?LOG_WARNING("Error Target types missing ",[Error])
			    end,
			    NonActiveTargetTypes
		    end,
    NewState=State#state{target_resources_status=NewTargetStatus,
			 control_node_active=NewControlStatus},	    
    Self=self(),
    spawn_link(fun()->rd_loop(Self) end),
    {noreply, NewState};

handle_info(rd_loop_timeout, State) ->
    CtrlNode=lib_vm:get_node(?ControlNodeName),
    Pong=net_adm:ping(CtrlNode),
    NewControlStatus=case net_adm:ping(CtrlNode) of
			 pang->
			     case State#state.control_node_active of
				 false->
				     false;
				 true->
				     ?LOG_WARNING("Error Control node ctrl is not available ",[CtrlNode]),
				     false
			     end; 
			 pong->
			     case State#state.control_node_active of
				 true->
				     true;
				 false->
				     ?LOG_NOTICE("Control node ctrl is availablel",[CtrlNode]),
				     true
			     end
		     end,
    TargetTypes=rd_store:get_target_resource_types(),
    NonActiveTargetTypes=lists:sort([TargetType||TargetType<-TargetTypes,
						 []=:=rd:fetch_resources(TargetType)]),
    
    TargetStatus=State#state.target_resources_status,
  %  io:format("--------------------------------------------------------- ~n"),
  %  io:format("State#state.control_node_active  ~p~n",[{State#state.control_node_active ,?MODULE,?LINE}]),
   % io:format("Pong ~p~n",[{Pong,?MODULE,?LINE}]),

   % io:format("TargetTypes ~p~n",[{TargetTypes,?MODULE,?LINE}]),
   % io:format("TargetStatus ~p~n",[{TargetStatus,?MODULE,?LINE}]),
   % io:format("NonActiveTargetTypes ~p~n",[{NonActiveTargetTypes,?MODULE,?LINE}]),

    NewTargetStatus=if 
			TargetStatus=:=NonActiveTargetTypes->
			    NonActiveTargetTypes;
			true->
			    case NonActiveTargetTypes of
				[]->
				    ?LOG_NOTICE("All needed target types are availablel",[TargetTypes]);	    
				Error ->
				    ?LOG_WARNING("Error Target types missing ",[Error])
			    end,
			    NonActiveTargetTypes
		    end,
    NewState=State#state{target_resources_status=NewTargetStatus,
			 control_node_active=NewControlStatus},	    
    Self=self(),
    spawn_link(fun()->rd_loop(Self) end),
    {noreply, NewState};

handle_info({'EXIT',_Pid,normal}, State) ->
    {noreply, State};

handle_info(Info, State) ->
    ?LOG_WARNING("Unmatched signal",[Info]),
    io:format("unmatched_signal ~p~n",[{Info,?MODULE,?LINE}]),
    {noreply, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: term()) -> any().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()},
		  State :: term(),
		  Extra :: term()) -> {ok, NewState :: term()} |
	  {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for changing the form and appearance
%% of gen_server status when it is returned from sys:get_status/1,2
%% or when it appears in termination error logs.
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt :: normal | terminate,
		    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
rd_loop(Parent)->
    CtrlNode=lib_vm:get_node("ctrl"),
    net_adm:ping(CtrlNode),
  %  [rd:add_local_resource(ResourceType,Resource)||{ResourceType,Resource}<-?LocalResourceTuples],
  %  [rd:add_target_resource_type(TargetType)||TargetType<-?TargetTypes],
    rd:trade_resources(),
    timer:sleep(?RdTradeInterval),
    Parent!rd_loop_timeout.


initial_trade_resources()->
    [rd:add_local_resource(ResourceType,Resource)||{ResourceType,Resource}<-?LocalResourceTuples],
    [rd:add_target_resource_type(TargetType)||TargetType<-?TargetTypes],
    rd:trade_resources(),
    timer:sleep(3000),
    rd:trade_resources(),
    timer:sleep(3000).
