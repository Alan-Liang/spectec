open Util


(* Configuration *)

let name = "watsup"
let version = "0.3"


(* Flags and parameters *)

type target =
 | None
 | Latex of Backend_latex.Config.config
 | Prose
 | Haskell
 | Lean4

 let target = ref (Latex Backend_latex.Config.latex)

let log = ref false  (* log execution steps *)
let dst = ref false  (* patch files *)
let dry = ref false  (* dry run for patching *)
let warn = ref false (* warn about unused or reused splices *)

let srcs = ref []    (* src file arguments *)
let dsts = ref []    (* destination file arguments *)
let odst = ref ""    (* generation file argument *)

let print_elab_il = ref false
let print_final_il = ref false
let print_all_il = ref false

let pass_sub = ref false
let pass_totalize = ref false
let pass_sideconditions = ref false
let pass_else_elim = ref false

(* Argument parsing *)

let banner () =
  print_endline (name ^ " " ^ version ^ " generator")

let usage = "Usage: " ^ name ^ " [option] [file ...] [-p file ...]"

let add_arg source =
  let args = if !dst then dsts else srcs in args := !args @ [source]

let argspec = Arg.align
[
  "-v", Arg.Unit banner, " Show version";
  "-o", Arg.String (fun s -> odst := s), " Generate file";
  "-p", Arg.Set dst, " Patch files";
  "-d", Arg.Set dry, " Dry run (when -p) ";
  "-l", Arg.Set log, " Log execution steps";
  "-w", Arg.Set warn, " Warn about unsed or multiply used splices";

  "--print-il", Arg.Set print_elab_il, "Print il (after elaboration)";
  "--print-final-il", Arg.Set print_final_il, "Print final il";
  "--print-all-il", Arg.Set print_all_il, "Print il after each step";

  "--sub", Arg.Set pass_sub, "Synthesize explicit subtype coercions";
  "--totalize", Arg.Set pass_totalize, "Run function totalization";
  "--sideconditions", Arg.Set pass_sideconditions, "Infer side conditoins";
  "--else-elimination", Arg.Set pass_else_elim, "Eliminate otherwise/else";

  "--check-only", Arg.Unit (fun () -> target := None), " No output (just checking)";
  "--latex", Arg.Unit (fun () -> target := Latex Backend_latex.Config.latex), " Use Latex settings (default)";
  "--sphinx", Arg.Unit (fun () -> target := Latex Backend_latex.Config.latex), " Use Sphinx settings";
  "--prose", Arg.Unit (fun () -> target := Prose), " Generate prose";
  "--haskell", Arg.Unit (fun () -> target := Haskell), " Produce Haskell code";
  "--lean4", Arg.Unit (fun () -> target := Lean4), " Produce Lean4 code";

  "-help", Arg.Unit ignore, "";
  "--help", Arg.Unit ignore, "";
]


(* Main *)

let log s = if !log then Printf.printf "== %s\n%!" s

let () =
  Printexc.record_backtrace true;
  try
    Arg.parse argspec add_arg usage;
    log "Parsing...";
    let el = List.concat_map Frontend.Parse.parse_file !srcs in
    log "Elaboration...";
    let il = Frontend.Elab.elab el in
    if !print_elab_il || !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);
    log "IL Validation...";
    Il.Validation.valid il;

    let il = if !pass_sub || !target = Haskell || !target = Lean4 then begin
      log "Subtype injection...";
      let il = Middlend.Sub.transform il in
      if !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);
      log "IL Validation...";
      Il.Validation.valid il;
      il
    end else il in

    let il = if !pass_totalize || !target = Lean4 then begin
      log "Function totalization...";
      let il = Middlend.Totalize.transform il in
      if !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);
      log "IL Validation...";
      Il.Validation.valid il;
      il
    end else il in

    let il = if !pass_sideconditions || !target = Lean4 then begin
      log "Side condition inference";
      let il = Middlend.Sideconditions.transform il in
      if !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);
      log "IL Validation...";
      Il.Validation.valid il;
      il
    end else il in

    let il = if !pass_else_elim || !target = Lean4 then begin
      log "Else elimination";
      let il = Middlend.Else.transform il in
      if !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);
      log "IL Validation...";
      Il.Validation.valid il;
      il
    end else il in

    if !print_final_il && not !print_all_il then Printf.printf "%s\n%!" (Il.Print.string_of_script il);

    begin match !target with
    | None -> ()
    | Latex config ->
      log "Latex Generation...";
      if !odst = "" && !dsts = [] then
        print_endline (Backend_latex.Gen.gen_string el);
      if !odst <> "" then
        Backend_latex.Gen.gen_file !odst el;
      if !dsts <> [] then (
        let env = Backend_latex.Splice.(env config el) in
        List.iter (Backend_latex.Splice.splice_file ~dry:!dry env) !dsts;
        if !warn then Backend_latex.Splice.warn env;
      );
    | Prose ->
      log "Prose Generation...";
      let ir = true in
      if ir then
        let program = Backend_prose.Il2ir.translate il in
        List.map Backend_prose.Print.string_of_program program
        |> List.iter print_endline
      else (
        let prose = Backend_prose.Translate.translate el in
        print_endline prose
      )
    | Haskell ->
      if !odst = "" && !dsts = [] then
        print_endline (Backend_haskell.Gen.gen_string il);
      if !odst <> "" then
        Backend_haskell.Gen.gen_file !odst il;
    | Lean4 ->
      if !odst = "" && !dsts = [] then
        print_endline (Backend_haskell.Gen.gen_string il);
      if !odst <> "" then
        Backend_lean4.Gen.gen_file !odst il;
    end;
    log "Complete."
  with
  | Source.Error (at, msg) ->
    prerr_endline (Source.string_of_region at ^ ": " ^ msg);
    exit 1
  | exn ->
    flush_all ();
    prerr_endline
      (Sys.argv.(0) ^ ": uncaught exception " ^ Printexc.to_string exn);
    Printexc.print_backtrace stderr;
    exit 2
