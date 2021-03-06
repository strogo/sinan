%% -*- mode: Erlang; fill-column: 80; comment-column: 75; -*-
%%%---------------------------------------------------------------------------
%%% @author Eric Merritt
%%% @doc
%%%  A group of utility functions for project automation.
%%% @end
%%% @copyright 2006 - 2011 Erlware
%%%---------------------------------------------------------------------------
-module(sin_utils).

-include_lib("kernel/include/file.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("internal.hrl").

%% API
-export([copy_dir/2,
	 copy_dir/3,
	 copy_dir/4,
	 delete_dir/1,
	 file_exists/1,
	 get_application_env/1,
	 get_ignore_dirs/1,
	 is_dir_ignorable/2,
	 remove_code_paths/1,
	 term_to_list/1,
	 to_bool/1]).

%%====================================================================
%% API
%%====================================================================

%% @doc Trivially convert a value to a boolean
-spec to_bool(any()) -> boolean().
to_bool(true) ->
    true;
to_bool("True") ->
    true;
to_bool("true") ->
    true;
to_bool(_) ->
    false.

%% @doc Delete the directory and all of its sub directories.
%% @private
-spec delete_dir(Dir::string()) -> ok.
delete_dir(Dir) ->
    case file:list_dir(Dir) of
	{ok, Files} ->
	    lists:foldl(fun (File, _Acc) ->
				NFile = filename:join([Dir, File]),
				case filelib:is_dir(NFile) of
				    true ->
					case is_symlink(NFile) of
					    true -> file:delete(NFile);
					    false -> delete_dir(NFile)
					end;
				    false -> file:delete(NFile)
				end
			end,
			[], Files),
	    file:del_dir(Dir);
	_ ->
	    ok
    end.

%% @doc Get the ignore dirs
-spec get_ignore_dirs(sin_config:config()) -> IgnoreDirs::[string()].
get_ignore_dirs(BuildConfig) ->
    BuildDir = sin_config:get_value(BuildConfig,
					  "build.dir"),
    IgnoreDirs = sin_config:get_value(BuildConfig,
					    "ignore_dirs", []),
    [BuildDir | IgnoreDirs].

%% @doc Check to see if a file exists.
-spec file_exists(FileName::string()) -> boolean().
file_exists(FileName) ->
    case file:read_file_info(FileName) of
	{error, enoent} ->
	    false;
	Error = {error, _} ->
	    throw(Error);
	_ ->
	    true
    end.

%% @doc Copies the specified directory down to the build dir on a file by file
%% basis. It only copies if the file has .
-spec copy_dir(BuilderDir::string(),
	       TargetDir::string()) -> ok.
copy_dir(BuildDir, TargetDir) ->
    copy_dir(BuildDir, TargetDir, [], []).

-spec copy_dir(BuilderDir::string(),
	       TargetDir::string(),
	       Subdirs::string()) -> ok.
copy_dir(BuildDir, TargetDir, Sub) ->
    copy_dir(BuildDir, TargetDir, Sub, []).

-spec copy_dir(BuilderDir::string(),
	       TargetDir::string(),
	       Subdirs::string(),
	       Ignorables::string()) -> ok.
copy_dir(BuildDir, TargetDir, SubDir, Ignorables) ->
    check_not_circular(BuildDir, TargetDir, SubDir),
    case are_dirs_ignorable(SubDir, Ignorables) of
	true ->
	    ok;
	false ->
	    Target = filename:join([BuildDir | SubDir]),
	    filelib:ensure_dir(filename:join([Target, "tmp"])),
	    CpyTarget = filename:join([TargetDir | SubDir]),
	    {ok, Files} = file:list_dir(CpyTarget),
	    lists:foldl(fun (IFile, _Acc) ->
				File = filename:join([CpyTarget, IFile]),
				case {is_dir_ignorable(IFile, Ignorables),
				      filelib:is_dir(File)}
				    of
				    {true, _} ->
					ok;
				    {_, true} ->
					copy_dir(BuildDir, TargetDir,
						 SubDir ++ [IFile], Ignorables);
				    {_, false} ->
					copy_file(Target, IFile, File)
				end
			end,
			[], Files)
    end.

%% @doc Remove the specified code paths from the system code paths.
-spec remove_code_paths(Paths::[string()]) -> ok.
remove_code_paths([Path | T]) ->
    code:del_path(Path), remove_code_paths(T);
remove_code_paths([]) ->
    ok.

%% @doc Return wether the directory is in the list of ignorables. If it is then
%%  return true, otherwise return false.
-spec is_dir_ignorable(Directory::string(), ListOfIgnores::[string()]) ->
    boolean().
is_dir_ignorable(Sub, [Ignore | Rest]) ->
    case ignore_dir(Sub, Ignore) of
	true ->
	    true;
	false ->
	    is_dir_ignorable(Sub, Rest)
    end;
is_dir_ignorable(_Sub, []) ->
    false.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Copies the file specified by file to the target specified by ifile.
-spec copy_file(Target::string(), IFile::string(), File::string()) -> ok.
copy_file(_Target, [$. | _], _File) ->
	     ok;
copy_file(Target, IFile, File) ->
    NFile = filename:join([Target, IFile]),
    case sin_sig:target_changed(File, NFile) of
	file_not_found ->
	    ewl_talk:say("File ~s is not does not exist in the "
		       "file System. This shouldn't happen.",
			 [File]),
	    throw(file_not_on_disc);
	unable_to_access ->
	    ewl_talk:say("File ~s exists but is inaccessable.",
			 [File]),
	    throw(file_inaccessable);
	true ->
	    {ok, FileInfo} = file:read_file_info(File),
	    file:copy(File, NFile),
	    file:write_file_info(NFile, FileInfo);
	_ ->
	    ok
    end.

%% @doc Check to see if the file is a symlink.
-spec is_symlink(FileName::string()) -> boolean.
is_symlink(FileName) ->
    case catch file:read_link_info(FileName) of
	{ok, Env} ->
	    Env#file_info.type == symlink;
	_Else ->
	    false
    end.

%% @doc Check the directory against the possible ignores to see if the prefix
%%  matches.
-spec ignore_dir(Directory::string(), PossibleIgnorePrefix::[string()]) ->
    boolean().
ignore_dir([Char | SubRest], [Char | IgRest]) ->
    ignore_dir(SubRest, IgRest);
ignore_dir(_Sub, []) ->
    true;
ignore_dir(_Sub, _Ignorable) ->
    false.

%% @doc If any dirs in the list are ignorable ignore it
-spec are_dirs_ignorable(ListOfDirs::[string()], Igs::[string()]) -> boolean().
are_dirs_ignorable([Dir | RestOfDirs], Igs) ->
    case is_dir_ignorable(Dir, Igs) of
	false ->
	    are_dirs_ignorable(RestOfDirs, Igs);
	true ->
	    true
    end;
are_dirs_ignorable([], _Igs) ->
    false.


%% @doc convert a list body to a string
-spec listify_list_body(I::term(), Acc::list()) -> list().
listify_list_body([H | T], []) ->
    listify_list_body(T, term_to_list(H));
listify_list_body([H | T], Acc) ->
    listify_list_body(T, [Acc, ",", term_to_list(H)]);
listify_list_body([], Acc) ->
    Acc.

%% @doc Convert an arbitrary term to a list
-spec term_to_list(I::term()) -> list().
term_to_list(I) when is_integer(I) ->
    integer_to_list(I);
term_to_list(I) when is_atom(I) ->
    atom_to_list(I);
term_to_list(I) when is_float(I) ->
    float_to_list(I);
term_to_list(I) when is_tuple(I) ->
    ["{", listify_list_body(tuple_to_list(I), []), "}"];
term_to_list(I) when is_binary(I) ->
    binary_to_list(I);
term_to_list(I) when is_list(I) ->
    case is_string(I) of
	true ->
	    ["\"", I, "\""];
	false ->
	    ["[", listify_list_body(I, []), "]"]
    end.

-spec is_character(Char::integer()) -> boolean().
is_character(Char) when Char < 0 ->
    false;
is_character(Char) when Char > 255 ->
    false;
is_character(_) ->
    true.

-spec is_string(String::string()) -> boolean().
is_string(XY) when is_list(XY) ->
    lists:all(fun is_character/1, XY);
is_string(_) ->
    false.

%% @doc Get an enviroment variable, throw error if unavailable.
-spec get_application_env(atom()) -> term().
get_application_env(Key) ->
    case application:get_env(sinan, Key) of
	{ok, Value} ->
	    Value;
      _ ->
	    ?SIN_RAISE_DA(variables_not_set,
			  "Key ~w not set, must be set as application "
			  "environment variable ",
			  [Key])
    end.

-spec check_not_circular(string(), string(), string()) ->
    ok.
check_not_circular(Target, Source, SubDir) ->
    case filename:split(Source) ++ SubDir ==
	filename:split(Target) of
	true ->
	    ewl_talk:say("Can't copy a directory to itself (~p "
			 "to ~p)",
			 [filename:join([Source | SubDir]), Target]),
	  throw(circular_recursion);
	false ->
	    ok
    end.


%%====================================================================
%% tests
%%====================================================================
copy_from_app_test_() ->
    % Create a directory in /tmp for the test. Clean everything afterwards
    {ok, BaseDir} = ewl_file:create_tmp_dir("/tmp"),
    {setup,
     fun () ->
	     ok = file:make_dir(filename:join(BaseDir, "app_name")),
	     ok = file:make_dir(filename:join(BaseDir, "ebin")),
	     ok = file:make_dir(filename:join(BaseDir, "doc"))
     end,
     fun (_) ->
	     ewl_file:delete_dir(BaseDir) end,
     fun (_) ->
	     TargetDir = filename:join(BaseDir, "app_name"),
	     BuildDir = filename:join(TargetDir,
				      "_build/development/apps/app_name"),
	     {timeout, 2,
	      ?_assertThrow(circular_recursion,
			    (sin_utils:copy_dir(BuildDir, TargetDir, [],
						["."])))}
     end}.
