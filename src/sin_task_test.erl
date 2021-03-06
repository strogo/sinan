%% -*- mode: Erlang; fill-column: 80; comment-column: 75; -*-
%%%-------------------------------------------------------------------
%%%---------------------------------------------------------------------------
%%% @author Eric Merritt <ericbmerritt@gmail.com>
%%% @doc
%%%   Runs the 'test' function on all modules in an application
%%%   if that function exits.
%%% @end
%%% @copyright (C) 2007-2011 Erlware
%%%---------------------------------------------------------------------------
-module(sin_task_test).

-behaviour(sin_task).

-include("internal.hrl").

%% API
-export([description/0, do_task/1]).

-define(TASK, test).
-define(DEPS, [build]).

%%====================================================================
%% API
%%====================================================================

%% @doc provides a description of this task
-spec description() ->  sin_task:task_description().
description() ->
    Desc = "Runs all of the existing eunit unit tests in the project",
    #task{name = ?TASK,
	  task_impl = ?MODULE,
	  bare = false,
	  deps = ?DEPS,
	  desc = Desc,
	  opts = []}.

%% @doc run all tests for all modules in the system
do_task(BuildRef) ->
    case sin_config:get_value(BuildRef, "eunit") of
        "disabled" ->
	    ewl_talk:say("Unit testing is disabled for this project. "
			 "If you wish to change this change the eunit "
			 "value of the build config from 'disabled' to "
			 "'enabled' or remove it.");
        _ ->
            Apps = lists:map(fun({App, _Vsn, _Deps, _}) ->
                                     atom_to_list(App)
                             end, sin_config:get_value(BuildRef,
                                                  "project.apps")),
            test_apps(BuildRef, Apps)
    end,
    BuildRef.


%%====================================================================
%%% Internal functions
%%====================================================================

%% @doc Run tests for all the applications specified.
%% @private
-spec test_apps(sin_config:config(), [string()]) -> ok.
test_apps(BuildRef, [AppName | T]) ->
    io:format("Testing ~s~n", [AppName]),
    Modules = sin_config:get_value(BuildRef,
                              "apps." ++ AppName ++ ".modules"),
    case Modules == undefined orelse length(Modules) =< 0 of
        true ->
	    ewl_talk:say("No modules defined for ~s.",
			 [AppName]),
            ok;
        false ->
            prepare_for_tests(BuildRef, AppName, Modules)
    end,
    test_apps(BuildRef, T);
test_apps(_, []) ->
    ok.

%% @doc Prepare for running the tests. This mostly means seting up the
%% coverage tools.
%% @private
-spec prepare_for_tests(sin_config:config(), string(), [atom()]) -> ok.
prepare_for_tests(BuildRef, AppName, Modules) ->
    BuildDir = sin_config:get_value(BuildRef, "build.dir"),
    DocDir = filename:join([BuildDir, "docs", "coverage", AppName]),
    filelib:ensure_dir(filename:join([DocDir, "tmp"])),
    Paths = sin_config:get_value(BuildRef,
                                       "apps." ++ AppName ++ ".code_paths"),
    code:add_pathsa(Paths),
    setup_code_coverage(BuildRef, Modules),
    run_module_tests(Modules),
    CoverageFiles = output_code_coverage(BuildRef, DocDir, Modules, []),
    output_coverage_index(DocDir, AppName, CoverageFiles),
    sin_utils:remove_code_paths(Paths).

%% @doc Output coverage information to make accessing the coverage files a bit
%%  easier.
%%@private
-spec output_coverage_index(string(), string(),
			    [{Name::string(), Module::atom()}]) ->
    ok.
output_coverage_index(_DocDir, _AppName, []) ->
    % no coverage files created
    ok;
output_coverage_index(DocDir, AppName, CoverageFiles=[{Name, _Module} | _T]) ->
    Frame = ["<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Frameset//EN\" \n"
             "   \"http://www.w3.org/TR/html4/frameset.dtd\">\n"
             "<HTML>\n"
             "<HEAD>\n"
             "<TITLE> Unit Test Coverage : ", AppName, " </TITLE>\n",
             "</HEAD>"
             "<FRAMESET cols=\"20%, 80%\">\n"
             "    <FRAME src=\"coverage_index.html\">\n"
             "    <FRAME name=\"bodyarea\" src=\"", Name, "\">\n"
             "    <NOFRAMES>\n"
             "      <P>This frameset document contains:\n"
             "        <A href=\"coverage_index.html\">Index of coverage reports</A>\n"
             "      </P>\n"
             "    </NOFRAMES>\n"
             "</FRAMESET>\n"
             "</HTML>\n"],
    CoverageIndex = ["<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"\n"
                     "   \"http://www.w3.org/TR/html4/loose.dtd\">\n"
                     "<HTML>\n"
                     "<HEAD>\n"
                     "  <TITLE>Coverage Index</TITLE>\n"
                     "</HEAD>\n"
                     "<BODY>\n"
                     " <P> \n"
                     "   <UL> \n",
                     make_index(CoverageFiles, []),
                     "   </UL>\n"
                     " </P> \n"
                     "</BODY> \n"
                     "</HTML> \n"],
    IndexFile = filename:join([DocDir, "index.html"]),
    CList = filename:join([DocDir, "coverage_index.html"]),
    file:write_file(IndexFile, list_to_binary(Frame), [write]),
    file:write_file(CList, list_to_binary(CoverageIndex), [write]).

%% @doc
%%  Render the list of modules into a deep list of links.
%% @private
-spec make_index([{string(), atom()}], list()) -> list().
make_index([{File, Module} | T], Acc) ->
    Acc2 = ["<LI><A href=\"", File, "\" target=\"bodyarea\">", atom_to_list(Module),
            "</A></LI>" | Acc],
    make_index(T, Acc2);
make_index([], Acc) ->
    Acc.

%% @doc Instrument all of the modules for code coverage checks.
%% @private
-spec setup_code_coverage(sin_config:config(), [atom()]) -> ok.
setup_code_coverage(BuildRef, [Module | T]) ->
    case cover:compile_beam(Module) of
        {error, _} ->
            ewl_talk:say("Couldn't add code coverage to ~w", [Module]);
        _ ->
            ok
    end,
    setup_code_coverage(BuildRef, T);
setup_code_coverage(_, []) ->
    ok.

%% @doc Take the analysis from test running and output it to an html file.
%%  @private
-spec output_code_coverage(sin_config:config(), string(), [atom()], list()) ->
    list().
output_code_coverage(BuildRef, DocDir, [Module | T], Acc) ->
    File = lists:flatten([atom_to_list(Module), ".html"]),
    OutFile = filename:join([DocDir, File]),
    case cover:analyse_to_file(Module, OutFile, [html]) of
        {ok, _} ->
            output_code_coverage(BuildRef, DocDir, T, [{File, Module} | Acc]);
        {error, _} ->
	    ewl_talk:say("Unable to write coverage information for ~w",
			 [Module]),
            output_code_coverage(BuildRef, DocDir, T, Acc)
    end;
output_code_coverage(_, _DocDir, [], Acc) ->
    Acc.

%% @doc Run tests for each module that has a test/0 function @private
-spec run_module_tests([atom()]) -> ok.
run_module_tests([Module | T]) ->
    eunit:test(Module),
    run_module_tests(T);
run_module_tests([]) ->
    ok.
