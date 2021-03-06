(** Equality checking and coercions *)

(** An option monad on top of Runtime.comp, which only uses Runtime.bind when necessary. *)
module Opt = struct
  type 'a opt =
    { k : 'r. ('a -> 'r Runtime.comp) -> 'r Runtime.comp -> 'r Runtime.comp }

  let return x =
    { k = fun sk _ -> sk x }

  let (>?=) m f =
    { k = fun sk fk -> m.k (fun x -> (f x).k sk fk) fk }

  let lift (m : 'a Runtime.comp) : 'a opt =
    { k = fun sk _ -> Runtime.bind m sk }

  let fail =
    { k = fun _ fk -> fk }

  let run m =
    m.k (fun x -> Runtime.return (Some x)) (Runtime.return None)
end

(*
let (>>=) = Runtime.bind
*)

let (>?=) = Opt.(>?=)

let (>!=) m f = (Opt.lift m) >?= f

module Internals = struct

(** Compare two terms *)
let equal ~loc sgn e1 e2 =
  match Jdg.mk_alpha_equal_term sgn e1 e2 with
    | Some eq -> Opt.return eq
    | None ->
      Predefined.operation_equal_term ~loc e1 e2 >!=
        begin function
          | None -> Opt.fail
          | Some eq ->
             let (Jdg.EqTerm (_asmp, e1', e2', _)) = Jdg.invert_eq_term eq in
             begin
               match Jdg.alpha_equal_term e1 e1' && Jdg.alpha_equal_term e2 e2' with
               | false -> Opt.lift (Runtime.(error ~loc (InvalidEqualTerm (e1, e2))))
               | true -> Opt.return eq
             end
        end

(* Compare two types *)
let equal_type ~loc t1 t2 =
  match Jdg.mk_alpha_equal_type t1 t2 with
    | Some eq -> Opt.return eq
    | None ->
      Predefined.operation_equal_type ~loc t1 t2 >!=
        begin function
          | None -> Opt.fail
          | Some eq ->
             let (Jdg.EqType (_asmp, t1', t2')) = Jdg.invert_eq_type eq in
             begin match Jdg.alpha_equal_type t1 t1' && Jdg.alpha_equal_type t2 t2' with
             | false -> Opt.lift (Runtime.(error ~loc (InvalidEqualType (t1, t2))))
             | true -> Opt.return eq
             end
        end

let coerce ~loc sgn e t =
  let t' = Jdg.type_of_term_abstraction sgn e in
  match Jdg.alpha_equal_abstraction Jdg.alpha_equal_type t' t with

  | true -> Opt.return e

  | false ->
     Predefined.operation_coerce ~loc e t >!=
       begin function

       | Predefined.NotCoercible -> Opt.fail

       | Predefined.Convertible eq ->
          failwith "TODO: convert e along eq if possible"
          (*
          let (Jdg.EqType (_asmp, u', u)) = Jdg.invert_eq_type eq in
          begin match Jdg.alpha_equal_type t' u' && Jdg.alpha_equal_type t u with
            | true ->
               Opt.return (Jdg.form_is_term_abstraction_convert sgn e eq)
            | false ->
               Runtime.(error ~loc (InvalidConvertible (t', t, eq)))
          end
          *)

       | Predefined.Coercible e' ->
          begin
            let u = Jdg.type_of_term_abstraction sgn e' in
            match Jdg.alpha_equal_abstraction Jdg.alpha_equal_type t u with
            | true -> Opt.return e'
            | false -> Runtime.(error ~loc (InvalidCoerce (t, e')))
          end
       end

end

(** Expose without the monad stuff *)

let equal ~loc sgn j1 j2 = Opt.run (Internals.equal ~loc sgn j1 j2)

let equal_type ~loc j1 j2 = Opt.run (Internals.equal_type ~loc j1 j2)

let coerce ~loc sgn je jt = Opt.run (Internals.coerce ~loc sgn je jt)
