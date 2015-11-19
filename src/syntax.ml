(** Desugared input syntax *)

(** Bound variables - represented by de Bruijn indices *)
type bound = int

(** Patterns *)

type tt_pattern = tt_pattern' * Location.t
and tt_pattern' =
  | Tt_Anonymous
  | Tt_As of tt_pattern * bound
  | Tt_Bound of bound
  | Tt_Type
  | Tt_Constant of Name.ident
  | Tt_Lambda of Name.ident * bound option * tt_pattern option * tt_pattern
  | Tt_App of tt_pattern * tt_pattern
  | Tt_Prod of Name.ident * bound option * tt_pattern option * tt_pattern
  | Tt_Eq of tt_pattern * tt_pattern
  | Tt_Refl of tt_pattern
  | Tt_Inhab
  | Tt_Bracket of tt_pattern
  | Tt_Signature of (Name.ident * Name.ident * bound option * tt_pattern) list
  | Tt_Structure of (Name.ident * Name.ident * bound option * tt_pattern) list
  | Tt_Projection of tt_pattern * Name.ident

type pattern = pattern' * Location.t
and pattern' =
  | Patt_Anonymous
  | Patt_As of pattern * bound
  | Patt_Bound of bound
  | Patt_Jdg of tt_pattern * tt_pattern
  | Patt_Tag of Name.ident * pattern list

(** Desugared expressions *)
type expr = expr' * Location.t
and expr' =
  | Type
  | Bound of bound
  | Function of Name.ident * comp
  | Rec of Name.ident * Name.ident * comp
  | Handler of handler

(** Desugared types - indistinguishable from expressions *)
and ty = expr

(** Desugared computations *)
and comp = comp' * Location.t
and comp' =
  | Return of expr
  | Operation of string * expr
  | With of expr * comp
  | Let of (Name.ident * comp) list * comp
  | Assume of (Name.ident * comp) * comp
  | Where of comp * expr * comp
  | Match of expr * match_case list
  | Beta of (string list * comp) list * comp
  | Eta of (string list * comp) list * comp
  | Hint of (string list * comp) list * comp
  | Inhabit of (string list * comp) list * comp
  | Unhint of string list * comp
  | Ascribe of comp * comp
  | Whnf of comp
  | Snf of comp
  | Typeof of comp
  | Constant of Name.ident * comp list
  | Lambda of (Name.ident * comp option) list * comp
  | Spine of expr * comp list (* spine arguments are computations because we want
                                 to evaluate in checking mode, once we know their types. *)
  | Prod of (Name.ident * comp) list * comp
  | Eq of comp * comp
  | Refl of comp
  | Bracket of comp
  | Inhab
  | Signature of (Name.ident * Name.ident * comp) list
  | Structure of (Name.ident * Name.ident * comp) list
  | Projection of comp * Name.ident
  | Tag of Name.ident * comp list

and handler = {
  handler_val: (Name.ident * comp) option;
  handler_ops: (string * (Name.ident * Name.ident * comp)) list;
  handler_finally : (Name.ident * comp) option;
}

and match_case = Name.ident list * pattern * comp


(** Desugared toplevel commands *)
type toplevel = toplevel' * Location.t
and toplevel' =
  | Axiom of Name.ident * (bool * (Name.ident * comp)) list * comp
  | TopLet of Name.ident * comp (** global let binding *)
  | TopCheck of comp (** infer the type of a computation *)
  | TopBeta of (string list * comp) list
  | TopEta of (string list * comp) list
  | TopHint of (string list * comp) list
  | TopInhabit of (string list * comp) list
  | TopUnhint of string list
  | Verbosity of int
  | Include of string list
  | Quit (** quit the toplevel *)
  | Help (** print help *)
  | Environment (** print the current environment *)


let opt_map f = function
  | None -> None
  | Some x -> Some (f x)

let rec shift_pattern k lvl ((p', loc) as p) =
  match p' with
    | Patt_Anonymous -> p
    | Patt_As (p,k) ->
      let p = shift_pattern k lvl p in
      Patt_As (p,k), loc
    | Patt_Bound m ->
       if m >= lvl then (Patt_Bound (m + k), loc) else p
    | Patt_Jdg (p1,p2) ->
      let p1 = shift_tt_pattern k lvl p1
      and p2 = shift_tt_pattern k lvl p2 in
      Patt_Jdg (p1,p2), loc
    | Patt_Tag (t,ps) ->
      let ps = List.map (shift_pattern k lvl) ps in
      Patt_Tag (t,ps), loc

and shift_tt_pattern k lvl ((p',loc) as p) =
  match p' with
    | Tt_Anonymous | Tt_Type | Tt_Constant _ | Tt_Inhab -> p
    | Tt_As (p,k) ->
      let p = shift_tt_pattern k lvl p in
      Tt_As (p,k), loc
    | Tt_Bound m -> if m >= lvl then (Tt_Bound (m + k), loc) else p
    | Tt_Lambda (x,bopt,copt,c) ->
      let copt = opt_map (shift_tt_pattern k lvl) copt
      and c = shift_tt_pattern k (lvl+1) c in
      Tt_Lambda (x,bopt,copt,c), loc
    | Tt_App (c1,c2) ->
      let c1 = shift_tt_pattern k lvl c1
      and c2 = shift_tt_pattern k lvl c2 in
      Tt_App (c1,c2), loc
    | Tt_Prod (x,bopt,copt,c) ->
      let copt = opt_map (shift_tt_pattern k lvl) copt
      and c = shift_tt_pattern k (lvl+1) c in
      Tt_Prod (x,bopt,copt,c), loc
    | Tt_Eq (c1,c2) ->
      let c1 = shift_tt_pattern k lvl c1
      and c2 = shift_tt_pattern k lvl c2 in
      Tt_Eq (c1,c2), loc
    | Tt_Refl c ->
      let c = shift_tt_pattern k lvl c in
      Tt_Refl c, loc
    | Tt_Bracket c ->
      let c = shift_tt_pattern k lvl c in
      Tt_Bracket c, loc
    | Tt_Signature xcs ->
      let rec fold lvl xcs = function
        | [] ->
          let xcs = List.rev xcs in
          Tt_Signature xcs, loc
        | (l,x,bopt,c)::rem ->
          let c = shift_tt_pattern k lvl c in
          fold (lvl+1) ((l,x,bopt,c)::xcs) rem
        in
      fold lvl [] xcs
    | Tt_Structure xcs ->
      let rec fold lvl xcs = function
        | [] ->
          let xcs = List.rev xcs in
          Tt_Structure xcs, loc
        | (l,x,bopt,c)::rem ->
          let c = shift_tt_pattern k lvl c in
          fold (lvl+1) ((l,x,bopt,c)::xcs) rem
        in
      fold lvl [] xcs
    | Tt_Projection (c,l) ->
      let c = shift_tt_pattern k lvl c in
      Tt_Projection (c,l), loc

let rec shift_comp k lvl (c', loc) =
  let c' =
    match c' with

    | Return e ->
       let e = shift_expr k lvl e in
       Return e

    | Operation (op, e) ->
       let e = shift_expr k lvl e in
       Operation (op, e)

    | With (e, c) ->
       let c = shift_comp k lvl c
       and e = shift_expr k lvl e in
       With (e, c)

    | Let (xcs, c) ->
       let xcs = List.map (fun (x,c) -> (x, shift_comp k lvl c)) xcs
       and c = shift_comp k (lvl + List.length xcs) c in
       Let (xcs, c)

    | Assume ((x, t), c) ->
       let t = shift_comp k lvl t
       and c = shift_comp k lvl c in
       Assume ((x, t), c)

    | Where (c1, e, c2) ->
       let c1 = shift_comp k lvl c1
       and e = shift_expr k lvl e
       and c2 = shift_comp k lvl c2 in
       Where (c1, e, c2)

    | Match (e, lst) ->
      let e = shift_expr k lvl e in
      let lst = List.map (shift_case k lvl) lst in
      Match (e, lst)

    | Beta (xscs, c) ->
       let xscs = List.map (fun (xs, c) -> (xs, shift_comp k lvl c)) xscs
       and c = shift_comp k lvl c in
       Beta (xscs, c)

    | Eta (xscs, c) ->
       let xscs = List.map (fun (xs, c) -> (xs, shift_comp k lvl c)) xscs
       and c = shift_comp k lvl c in
       Eta (xscs, c)

    | Hint (xscs, c) ->
       let xscs = List.map (fun (xs, c) -> (xs, shift_comp k lvl c)) xscs
       and c = shift_comp k lvl c in
       Hint (xscs, c)

    | Inhabit (xscs, c) ->
       let xscs = List.map (fun (xs, c) -> (xs, shift_comp k lvl c)) xscs
       and c = shift_comp k lvl c in
       Inhabit (xscs, c)

    | Unhint (xs, c) ->
       let c = shift_comp k lvl c in
       Unhint (xs, c)

    | Ascribe (c1, c2) ->
       let c1 = shift_comp k lvl c1
       and c2 = shift_comp k lvl c2 in
       Ascribe (c1, c2)

    | Whnf c -> Whnf (shift_comp k lvl c)

    | Snf c -> Snf (shift_comp k lvl c)

    | Typeof c -> Typeof (shift_comp k lvl c)

    | Constant (x, cs) ->
       let cs = List.map (shift_comp k lvl) cs in
       Constant (x, cs)

    | Lambda (xcs, c) ->
       let rec fold lvl xcs' = function
         | [] ->
            let xcs' = List.rev xcs'
            and c = shift_comp k lvl c in
            Lambda (xcs', c)
         | (x,copt) :: xcs ->
            let copt = (match copt with None -> None | Some c -> Some (shift_comp k lvl c)) in
            fold (lvl+1) ((x,copt) :: xcs') xcs
       in
       fold lvl [] xcs

    | Spine (e, cs) ->
       let e = shift_expr k lvl e
       and cs = List.map (shift_comp k lvl) cs in
       Spine (e, cs)

    | Prod (xes, c) ->
       let rec fold lvl xes' = function
         | [] ->
            let xes' = List.rev xes'
            and c = shift_comp k lvl c in
            Prod (xes', c)
         | (x,c) :: xes ->
            let c = shift_comp k lvl c in
            fold (lvl+1) ((x,c) :: xes') xes
       in
       fold lvl [] xes

    | Eq (c1, c2) ->
       let c1 = shift_comp k lvl c1
       and c2 = shift_comp k lvl c2 in
       Eq (c1, c2)

    | Refl c ->
        let c = shift_comp k lvl c in
        Refl c

    | Bracket c ->
        let c = shift_comp k lvl c in
        Bracket c

    | Inhab -> Inhab

    | Signature lst ->
        let lst = List.map (fun (x,x',c) -> x, x', shift_comp k lvl c) lst in
        Signature lst

    | Structure lst ->
        let lst = List.map (fun (x, x',c) -> (x, x', shift_comp k lvl c)) lst in
        Structure lst

    | Projection (c,x) ->
        let c = shift_comp k lvl c in
        Projection (c,x)

    | Tag (t,cs) ->
      let cs = List.map (shift_comp k lvl) cs in
      Tag (t,cs)
  in
  c', loc

and shift_handler k lvl {handler_val; handler_ops; handler_finally} =
  { handler_val =
      (match handler_val with
       | None -> None
       | Some (x, c) -> let c = shift_comp k (lvl+1) c in Some (x, c)) ;
    handler_ops =
      List.map
        (fun (op, (x, y, c)) -> let c = shift_comp k (lvl+2) c in (op, (x, y, c)))
        handler_ops ;
    handler_finally =
      (match handler_finally with
       | None -> None
       | Some (x, c) -> let c = shift_comp k (lvl+1) c in Some (x, c)) ;
  }

and shift_expr k lvl ((e', loc) as e) =
  match e' with
  | Bound m -> if m >= lvl then (Bound (m + k), loc) else e
  | Function (x, c) -> Function (x, shift_comp k (lvl+1) c), loc
  | Rec (f, x, c) -> Rec (f, x, shift_comp k (lvl+2) c), loc
  | Handler h -> Handler (shift_handler k lvl h), loc
  | Type -> e

and shift_case k lvl (xs, p, c) =
  let p = shift_pattern k lvl p
  and c = shift_comp k (lvl + List.length xs) c in
  xs, p, c

