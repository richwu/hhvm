(**
 * Copyright (c) 2015, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

open Core
open Reordered_argument_collections

(*****************************************************************************)
(* The "static" environment, initialized first and then doesn't change *)
(*****************************************************************************)

type genv = {
    options          : ServerArgs.options;
    config           : ServerConfig.t;
    local_config     : ServerLocalConfig.t;
    workers          : Worker.t list option;
    (* Returns the list of files under .hhconfig, subject to a filter *)
    indexer          : (string -> bool) -> string MultiWorker.nextlist;
    (* Each time this is called, it should return the files that have changed
     * since the last invocation *)
    notifier         : unit -> SSet.t;
    (* If daemons are spawned as part of the init process, wait for them here *)
    wait_until_ready : unit -> unit;
    mutable debug_channels   : (Timeout.in_channel * out_channel) option;
  }

(*****************************************************************************)
(* The environment constantly maintained by the server *)
(*****************************************************************************)

(* In addition to this environment, many functions are storing and
 * updating ASTs, NASTs, and types in a shared space
 * (see respectively Parser_heap, Naming_heap, Typing_env).
 * The Ast.id are keys to index this shared space.
 *)
type env = {
    files_info     : FileInfo.t Relative_path.Map.t;
    tcopt          : TypecheckerOptions.t;
    errorl         : Errors.t;
    (* Keeps list of files containing parsing errors in the last iteration. File
     * need to be rechecked will also join this list during typecheck *)
    failed_parsing : Relative_path.Set.t;
    failed_decl    : Relative_path.Set.t;
    failed_check   : Relative_path.Set.t;
    persistent_client_fd : Unix.file_descr option;
    (* The map from full path to synchronized file contents *)
    edited_files   : File_content.t SMap.t;
    (* The list of full path of synchronized files need to be type checked *)
    files_to_check : SSet.t;
    (* The diagnostic subscription information of the current client *)
    diag_subscribe : Diagnostic_subscription.t;
    (* Highlight information cached for ide related commands *)
    symbols_cache  : IdentifySymbolService.cache;
  }

let file_filter f =
  (FindUtils.is_php f && not (FilesToIgnore.should_ignore f))
  || FindUtils.is_js f

let list_files env oc =
  let acc = List.fold_right
    ~f:begin fun error acc ->
      let pos = Errors.get_pos error in
      Relative_path.Set.add acc (Pos.filename pos)
    end
    ~init:Relative_path.Set.empty
    (Errors.get_error_list env.errorl) in
  Relative_path.Set.iter acc (fun s ->
    Printf.fprintf oc "%s\n" (Relative_path.to_absolute s));
  flush oc
