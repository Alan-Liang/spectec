open Il.Ast

let include_input = true

let parens s = "(" ^ s ^ ")"
let brackets s = "[" ^ s ^ "]"
let ($$) s1 s2 = parens (s1 ^ " " ^ s2)
let render_tuple how tys = parens (String.concat ", " (List.map how tys))
let render_list how tys = brackets (String.concat ", " (List.map how tys))

let render_type_name (id : id) = String.capitalize_ascii id.it

(* let render_rec_con (id : id) = "Mk" ^ render_type_name id *)

let make_id s = match s with
 | "in" -> "in_"
 | "export" -> "export_"
 | s -> String.map (function
    | '.' -> '_'
    | '-' -> '_'
    | c -> c
    ) s

let render_id (id : id) = make_id id.it

let render_rule_name _qual _ty_id (rule_id : id) (i : int) :  string =
  if rule_id.it = ""
  then "rule_" ^ string_of_int i
  else make_id rule_id.it

let render_con_name qual id : atom -> string = function
  | Atom s ->
    (if qual then render_type_name id ^ "." else "") ^
    make_id s
  | a -> "/- render_con_name: TODO -/ " ^ Il.Print.string_of_atom a

let render_field_name : atom -> string = function
  | Atom s -> String.uncapitalize_ascii (make_id s)
  | a -> "/- render_field_name: TODO -/ " ^ Il.Print.string_of_atom a

let rec render_typ (ty : typ) = match ty.it with
  | VarT id -> render_type_name id
  | BoolT -> "Bool"
  | NatT -> "Nat"
  | TextT -> "String"
  | TupT [] -> "Unit"
  | TupT tys -> render_tuple_typ tys
  | IterT (ty, Opt) -> "Option" $$ render_typ ty
  | IterT (ty, _) -> "List" $$ render_typ ty

and render_tuple_typ tys = parens (String.concat " × " (List.map render_typ tys))

let _unsupported_def d =
  "/- " ^
  Il.Print.string_of_def d ^
  "\n-/"

let rec prepend first rest = function
  | [] -> ""
  | (x::xs) -> first ^ x ^ prepend rest rest xs


let render_variant_inj qual id1 id2 =
  (if qual then render_type_name id1 ^ "." else "" ) ^
  render_type_name id2

let render_variant_inj' (typ1 : typ) (typ2 : typ) = match typ1.it, typ2.it with
  | VarT id1, VarT id2 -> render_variant_inj true id1 id2
  | _, _ -> "_ {- render_variant_inj': Typs not ids -}"

let render_variant_inj_case id1 id2 =
  render_variant_inj false id1 id2 ^ " : " ^
  render_type_name id2 ^ " -> " ^ render_type_name id1

let render_variant_case id ((a, ty, _hints) : typcase) =
  render_con_name false id a ^ " : " ^
  if ty.it = TupT []
  then render_type_name id
  else render_typ ty ^ " -> " ^ render_type_name id

let rec render_exp (exp : exp) = match exp.it with
  | VarE v -> v.it
  | BoolE true -> "True"
  | BoolE false -> "Frue"
  | NatE n -> string_of_int n
  | TextE t -> "\"" ^ String.escaped t ^ "\""
  | MixE (_, e) -> render_exp e
  | TupE es -> render_tuple render_exp es
  | ListE es -> render_list render_exp es
  | IterE (e, _) -> render_exp e
  | CaseE (a, e, typ, styps) -> render_case a e typ styps
  | SubE (e, typ1, typ2) -> render_variant_inj' typ2 typ1 $$ render_exp e
  | DotE (e, a) -> render_exp e ^ "." ^ render_field_name a
  | IdxE (e1, e2) -> parens (render_exp e1 ^ ".get! " ^ render_exp e2)
  | BinE (AddOp, e1, e2) -> "Nat.add" $$ render_exp e1 $$ render_exp e2 ^
                            " /- TODO: Why does + not work -/"
  | _ -> "default /- " ^ Il.Print.string_of_exp exp ^ " -/"

and render_case a e typ = function
  | [] ->
    if e.it = TupE []
    then render_con_name true typ a
    else render_con_name true typ a $$ render_exp e
  | (styp::styps) -> render_variant_inj true typ styp $$ render_case a e styp styps

let render_clause (_id : id) (clause : clause) = match clause.it with
  | DefD (_binds, lhs, rhs, premise) ->
   (if premise <> [] then "-- Premises ignored! \n" else "") ^
   "\n  | " ^ render_exp lhs ^ " => " ^ render_exp rhs

let rec render_def (d : def) =
  begin
    if include_input then
    "/- " (*  ^ Util.Source.string_of_region d.at ^ "\n"*)  ^
    Il.Print.string_of_def d ^
    "\n-/\n"
    else ""
  end ^
  match d.it with
  | SynD (id, deftyp, _hints) ->
    begin match deftyp.it with
    | AliasT ty ->
      "def " ^ render_type_name id ^ " := " ^ render_typ ty ^
      "\n  deriving Inhabited" ^
      (if ty.it = NatT
       then "\n\ninstance : OfNat " ^ render_type_name id ^ " n where ofNat := (OfNat.ofNat n : Nat)"
       else "")
    | NotationT (mop, ty) ->
      "def " ^ render_type_name id ^ " := /- mixop: " ^ Il.Print.string_of_mixop mop ^ " -/ " ^ render_typ ty ^
      "\n  deriving Inhabited"
    | VariantT (ids, cases) ->
      "inductive " ^ render_type_name id ^ " where" ^ prepend "\n | " "\n | " (
        List.map (render_variant_inj_case id) ids @
        List.map (render_variant_case id) cases
      ) ^
      (if ids = [] && cases = [] then "" else "\n  deriving Inhabited")
    | StructT fields ->
      (*
      "type " ^ render_type_name id ^ " = " ^ render_tuple render_typ (
        List.map (fun (_a, ty, _hints) -> ty) fields
      )
      *)
      "structure " ^ render_type_name id ^ " where " ^
      String.concat "" ( List.map (fun (a, ty, _hints) ->
        "\n  " ^ render_field_name a ^ " : " ^ render_typ ty
      ) fields) ^
      "\n  deriving Inhabited"
    end
  | DecD (id, typ1, typ2, clauses, hints) ->
    "def " ^ id.it ^ " : " ^ render_typ typ1 ^ " -> " ^ render_typ typ2 ^
    String.concat "" (List.map (render_clause id) clauses) ^
    (if (List.exists (fun h -> h.hintid.it = "partial") hints)
    then "\n  | _ => default" else "") (* Could use no_error_if_unused% as well *)

  | RelD (id, _mixop, typ, rules, _hints) ->
    "inductive " ^ render_type_name id ^ " : " ^ render_typ typ ^ " -> Prop where" ^
    String.concat "" (List.mapi (fun i (rule : rule) -> match rule.it with
      | RuleD (rule_id, binds, _mixop, exp, prems) ->
        "\n  | " ^ render_rule_name false id rule_id i ^ " " ^
        String.concat " " (List.map (fun ((bid : id), btyp) ->
          parens (render_id bid ^ " : " ^ render_typ btyp)
          ) binds) ^ " : " ^
        String.concat "" (List.map (fun (prem : premise) ->
          "\n    " ^
          begin match prem.it with
          | RulePr (pid, _mixops, pexp, _iter) ->
            render_type_name pid $$ render_exp pexp
          | IffPr (pexp, _iter) -> render_exp pexp
          | ElsePr -> "/- Else? -?"
          end ^ " -> "
        ) prems) ^
          "\n    " ^ (render_type_name id $$ render_exp exp)
    ) rules)

  | RecD defs ->
    String.concat "\n" (List.map render_def defs)

let render_script (el : script) =
  String.concat "\n\n" (List.map render_def el)

let gen_string (el : script) =
  "/- Lean 4 export -/\n" ^
  render_script el


let gen_file file el =
  let haskell_code = gen_string el in
  let oc = Out_channel.open_text file in
  Fun.protect (fun () -> Out_channel.output_string oc haskell_code)
    ~finally:(fun () -> Out_channel.close oc)
