open Il
open Ast
open Util.Source
open El.Atom
open Def
open Il2al_util


(* Pre-process a premise *)
let rec preprocess_prem prem =
  match prem.it with
  | IterPr (prem, iterexp) ->
    prem
    |> preprocess_prem
    |> List.map (fun new_prem -> IterPr (new_prem, iterexp) $ prem.at)
  | RulePr (id, mixop, exp) when id.it = "Expand" ->
    (match mixop, exp.it with
    (* Expand: `dt` ~~ `ct` *)
    | [[]; [approx]; []], TupE [dt; ct] when approx.it = Approx ->
      (* `$expanddt(dt) = ct` *)
      let expanddt =
        CallE ("expanddt" $ prem.at, [ExpA dt $ dt.at]) $$ prem.at % ct.note
      in
      let new_prem =
        IfPr (CmpE (EqOp, expanddt, ct) $$ prem.at % (BoolT $ no_region))
      in

      (* Add function definition to AL environment *)
      if not (Env.mem_def !Al.Valid.env id) then (
        let param = ExpP ("_" $ no_region, dt.note) $ dt.at in
        Al.Valid.env := Env.bind_def !Al.Valid.env id ([param], ct.note, [])
      );

      [ new_prem $ prem.at ]
    (* Expand: ??? *)
    | _ -> [ prem ]
    )
  | RulePr (id, mixop, exp) ->
    (match mixop, exp.it with
    (* `id`: |- `lhs` : `rhs` *)
    | [[turnstile]; [colon]; []], TupE [lhs; rhs]
    (* `id`: C |- `lhs` : `rhs` *)
    | [[]; [turnstile]; [colon]; []], TupE [_; lhs; rhs]
    when turnstile.it = Turnstile && colon.it = Colon ->
      (* $`id`(`lhs`) = `rhs` *)
      let typing_function_call =
        CallE (id, [ExpA lhs $ lhs.at]) $$ exp.at % rhs.note
      in
      let new_prem =
        IfPr (CmpE (EqOp, typing_function_call, rhs) $$ exp.at % (BoolT $ no_region))
      in

      (* Add function definition to AL environment *)
      if not (Env.mem_def !Al.Valid.env id) then (
        let param = ExpP ("_" $ no_region, lhs.note) $ lhs.at in
        Al.Valid.env := Env.bind_def !Al.Valid.env id ([param], rhs.note, [])
      );

      [ new_prem $ prem.at ]
    | _ -> [ prem ]
    )
  (* Split -- if e1 /\ e2 *)
  | IfPr ( { it = BinE (AndOp, e1, e2); _ } ) ->
    preprocess_prem (IfPr e1 $ prem.at) @ preprocess_prem (IfPr e2 $ prem.at)
  | _ -> [ prem ]

let preprocess_rule (rule: rule) : rule =
  let RuleD (id, binds, mixop, exp, prems) = rule.it in
  RuleD (id, binds, mixop, exp, List.concat_map preprocess_prem prems) $ rule.at

let preprocess_clause (clause: clause) : clause =
  let DefD (binds, args, exp, prems) = clause.it in
  DefD (binds, args, exp, List.concat_map preprocess_prem prems) $ clause.at

let preprocess_def (def: def) : def =
  match def.it with
  | TypD (id, ps, insts) ->
    Al.Valid.env := Env.bind_typ !Al.Valid.env id (ps, insts); def
  | RelD (id, mixop, t, rules) ->
    Al.Valid.env := Env.bind_rel !Al.Valid.env id (mixop, t, rules);
    RelD (id, mixop, t, List.map preprocess_rule rules) $ def.at
  | DecD (id, ps, t, clauses) ->
    Al.Valid.env := Env.bind_def !Al.Valid.env id (ps, t, clauses);
    DecD (id, ps, t, List.map preprocess_clause clauses) $ def.at
  | GramD (id, ps, t, prods) ->
    Al.Valid.env := Env.bind_gram !Al.Valid.env id (ps, t, prods); def
  | RecD _ -> assert (false);
  | HintD _ -> def

let flatten_rec def =
  match def.it with
  | RecD defs -> defs
  | _ -> [ def ]


let preprocess (il: script) : rule_def list * helper_def list =

  let not_translate = ["typing.watsup"] in
  let is_al_target def =
    let f = fun name -> String.ends_with ~suffix:name def.at.left.file in
    match def.it with
    | _ when List.exists f not_translate -> None
    | DecD (id, _, _, _) when id.it = "utf8" -> None
    | RelD (id, mixop, t, rules) when List.mem id.it [ "Step"; "Step_read"; "Step_pure" ] ->
      (* HARDCODE: Exclude administrative rules *)
      let filter_rule rule =
        ["pure"; "read"; "trap"; "ctxt"]
        |> List.mem (name_of_rule rule)
        |> not
      in
      Some (RelD (id, mixop, t, List.filter filter_rule rules) $ def.at)
    | RelD _ -> None
    | _ -> Some def
  in

  il
  |> List.concat_map flatten_rec
  |> List.filter_map is_al_target
  |> List.map preprocess_def
  |> Encode.transform
  |> Animate.transform
  |> Unify.unify
