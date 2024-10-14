Overview:

- Instrs using evaluation contexts:
  - throw_ref: T
  - br: B^l
  - return: B^*
  - return_invoke: B^*
  - almost every instruction in stack switching
    - cont.new
    - cont.bind
    - resume
    - resume_throw
    - handle

- additions to AST
  - EL Types (spectec/src/el/ast.ml:58):
    - CtxHoleT

    Expressions (spectec/src/el/ast.ml:117):
    - CtxHoleE
    - CtxSubstE (e1, e2)

  - IL Types (spectec/src/il/ast.ml:38):
    - CtxHoleT

    Expressions (spectec/src/il/ast.ml:105):
    - CtxHoleE
    - CtxSubstE (e1, args, e3)

- Elab
  - requires lhs of CtxSubstE to be VarE (spectec/src/frontend/elab.ml:982),
    and moves args of the VarE to Il.CtxSubstE

  - binds that variable in env if not already bound
    - the type is VarT (id, args) which *includes* the arguments

Hacks around IL:

- IL's variant type (spectec/src/il/ast.ml:41) requires the first expr
  in the list to be a mixop, but evalctx does not conform due to `[_]`
  and `val* E instr*` (spectec/spec/wasm-3.0/4-runtime.watsup:172);
  besides being a data structure, a evalctx is also a pattern match.

  Currently a atom is used (`HOLE [_] | STACK val* E instr*`).
  This is not ideal for substitution.

- `syntax` should begin with lowercase letters (in order to be a varid,
  not atom), but conventionally evalctx is uppercase (E, B, C, T, ...)

- EL surface syntax for evalctx substitution/initiation

  Currently it is `evalctx[- val* instr* -]`, bc `[]` is for array
  indexing, and arith (spectec/src/frontend/parser.mly:663) is
  incompatible with exp (spectec/src/frontend/parser.mly:604);
  `[[]]` would cause lexing errors on `a[b[c]]` if treated as a single
  token and parsing ambiguity if treated as two brackets.

- VarE is without args in IL, but we need args to encode `B^n`.

  Currently it works by destructing El.VarE in El.CtxSubstE elab,
  and record the argument in Il.CtxSubstE.

- In semantics of return, we have block context written as `B^*`.
  How to deal with it?

  Currently the type of the argument of B is `idx`, and `*` is not an
  idx. We may want to use an `IterE (B, List)`, but that makes defining
  evalctx hard (there is no such EL syntax for `syntax` definition.)

Observations on AL:

- We can pop at most one context in one step, but can enter multiple
  contexts. With the introduction of (proper) evaluation contexts,
  this assumption breaks.

  e.g. FRAME_ n `{...} (LABEL_ ...) ~> ... is illegal, but reversing the
  relation makes it okay

- there should be no contexts inside an evalctx
  e.g. no B[(FRAME_ n `{...} instr*)]

- if an instruction has step rules with and without contexts, then the
  rule without has an inner if

- i.e., there are four kinds of rules:

  1. val* TARGET
  2. CONTEXT val* TARGET
  3. CONTEXT evalctx\[val* TARGET]
  4. evalctx\[val* TARGET]

  we might need to process the two context rules one by one.

  - if 1 matches, stop.
  - else:
    - could 2 and 3 coexist?
    - if they coexist, what is the semantics?
    - if not, decide evalctx first
    - could 3 and 4 coexist?
    - could 2 and 4 coexist?

- previously Conrad suggested to use "shallow" contexts; but it stopped
  working with the introduction of exceptions:

  block contexts works that way as a result of there are only label and
  frame contexts, so when we execute a branch, we could count the number
  of label contexts that we exited, while refusing to exit a frame
  context. With the introduction of exceptions, we could also skip over
  handler contexts, but skipping over multiple levels of handler
  contexts should still be "shallow" in terms of label nest depth.

  If we insist on going that way, that would differ significantly from
  the current spec, which uses an auxiliary context definition.
  This is okay for human to parse, but not straightforward to translate
  into AL.
