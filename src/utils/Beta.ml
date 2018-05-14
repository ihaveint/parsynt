(**
   This file is part of Parsynt.

   Author: Victor Nicolet <victorn@cs.toronto.edu>

    Parsynt is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Parsynt is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
    along with Parsynt.  If not, see <http://www.gnu.org/licenses/>.
*)

open Utils
open Format

(** Internal type for building funces *)
type operator_type =
  | Arith                       (* Arithmetic only *)
  | Basic                       (* Airthmetic and min/max *)
  | NonLinear                   (* Non-linear operators *)
  | NotNum                        (* Not a numeral operator *)

type fn_type =
  | Bottom
  | Num
  | Unit
  (** Base types : only booleans, integers and reals *)
  | Integer
  | Real
  | Boolean
  (** Type tuple *)
  | Record of (string * fn_type) list
  (** Other lifted types *)
  | Bitvector of int
  (** A function in Rosette is an uninterpreted function *)
  | Function of fn_type * fn_type
  (** A procdedure is a reference to a procedure object *)
  | Procedure of fn_type * fn_type
  (** Pairs and lists *)
  | Pair of fn_type
  | List of fn_type * int option
  (** Vector and box *)
  | Vector of fn_type * int option
  | Box of fn_type
  (** User-defined structures *)
  | Struct of fn_type


type symb_unop =
  | Not | Add1 | Sub1
  | Abs | Floor | Ceiling | Truncate | Round
  | Neg
  (** Misc*)
  | Sgn
  | UnsafeUnop of symb_unsafe_unop

(* Binary operators available in Rosette *)
and symb_binop =
  (** Booleans*)
  | And | Nand | Or | Nor | Implies | Xor
  (** Integers and reals *)
  | Plus | Minus | Times | Div | Quot | Rem | Mod
  (** Max and min *)
  | Max | Min
  (** Comparison *)
  | Eq | Lt | Le | Gt | Ge | Neq
  (** Shift*)
  | ShiftL | ShiftR
  | Expt
  | UnsafeBinop of symb_unsafe_binop

(**
   Some racket functions that are otherwise unsafe
   to use in Racket, but we might still need them.
*)
and symb_unsafe_unop =
  (** Trigonometric + hyp. functions *)
  | Sin | Cos | Tan | Sinh | Cosh | Tanh
  (** Anti functions *)
  | ASin | ACos | ATan | ASinh | ACosh | ATanh
  (** Other functions *)
  | Log | Log2 | Log10
  | Exp | Sqrt


and symb_unsafe_binop =
  | TODO

(** Some pre-defined constants existing in C99 *)
and constants =
  | CNil
  | CInt of int
  | CInt64 of int64
  | CReal of float
  | CBool of bool
  | CBox of Cil.constant
  | CArrayInit of int * constants
  | CChar of char
  | CString of string
  | CUnop of symb_unop * constants
  | CBinop of symb_binop * constants * constants
  | CUnsafeUnop of symb_unsafe_unop * constants
  | CUnsafeBinop of symb_unsafe_binop * constants * constants
  | Infnty | NInfnty
  | Pi | SqrtPi
  | Sqrt2
  | Ln2 | Ln10 | E


let type_of_binop_args : symb_binop -> fn_type =
  function
  | Rem | Mod | Quot | Expt
  | Lt | Gt | Ge | Le | Max | Min
  | Plus | Minus | Times | Div  -> Num
  | Xor | And | Nand | Nor | Or | Implies -> Boolean
  | _ -> Unit

let type_of_unop_args : symb_unop -> fn_type=
  function
  | Not -> Boolean
  | _ -> Num


exception Tuple_fail            (* Tuples are not supported for the moment. *)



(* -------------------- 3 - VARIABLES MANAGEMENT -------------------- *)

let _GLOB_VARIDS = ref 3000
let _new_id () = incr _GLOB_VARIDS; !_GLOB_VARIDS

type fnV = {
  mutable vname : string;
  mutable vtype : fn_type;
  vinit : constants option;
  mutable vid : int;
  mutable vistmp : bool;
}


module FnVs =
  Set.Make
    (struct
      type t = fnV
      let compare  x y = Pervasives.compare x.vid y.vid
    end)

module VarSet =
struct
  include FnVs
  let find_by_id vs id : FnVs.elt =
    FnVs.max_elt (FnVs.filter (fun elt -> elt.vid = id) vs)
  let find_by_name vs name : FnVs.elt =
    FnVs.max_elt (FnVs.filter (fun elt -> elt.vname = name) vs)
  let vids_of_vs vs : int list =
    List.map (fun vi -> vi.vid) (FnVs.elements vs)
  let has_vid vs id : bool =
    List.mem id (vids_of_vs vs)
  let pp_var_names fmt vs =
    pp_print_list
      ~pp_sep:(fun fmt () -> fprintf fmt ", ")
      (fun fmt elt -> fprintf fmt "%s" elt.vname)
      fmt (FnVs.elements vs)
  let bindings vs =
    List.map (fun elt -> (elt.vid, elt)) (FnVs.elements vs)
  let names vs =
    List.map (fun elt -> elt.vname) (FnVs.elements vs)
  let types vs =
    List.map (fun elt -> elt.vtype) (FnVs.elements vs)
  let record vs =
    List.map (fun elt -> elt.vname, elt.vtype) (FnVs.elements vs)
  let add_prefix vs prefix =
    FnVs.of_list (List.map (fun v -> {v with vname = prefix^v.vname}) (FnVs.elements vs))
  let iset vs ilist =
    FnVs.of_list
      (List.filter (fun vi -> List.mem vi.vid ilist) (FnVs.elements vs))
end



type jcompletion = { cvi : fnV; cleft : bool; cright : bool;}

module CSet = Set.Make (struct
    type t = jcompletion
    let compare jcs0 jcs1  =
      if jcs0.cvi.vid = jcs1.cvi.vid then
        (match jcs0.cleft && jcs0.cright, jcs1.cleft && jcs1.cright with
         | true, true -> 0
         | true, false -> 1
         | false, true -> -1
         | false, false -> if jcs0.cleft then 1 else -1)
      else Pervasives.compare jcs0.cvi.vid jcs1.cvi.vid
  end)

(* Completions set: used in holes to express the set of possible expressions
   or variables to use. *)
module CS = struct
  include CSet
  let of_vs vs =
    VarSet.fold
      (fun vi cset -> CSet.add {cvi = vi; cleft = false; cright = false} cset)
      vs CSet.empty


  let map f cs =
    CSet.fold (fun jc cset -> CSet.add (f jc) cset)
      cs CSet.empty

  let complete_left cs =
    CSet.fold (fun jc cset -> CSet.add {jc with cleft = true} cset)
      cs CSet.empty

  let complete_right cs =
    CSet.fold (fun jc cset -> CSet.add {jc with cright = true} cset)
      cs CSet.empty

  let complete_all cs =
    map (fun jc -> {jc with cleft = true; cright = true;}) cs

  let to_jc_list cs =
    CSet.fold (fun jc jclist -> jc::jclist)
      cs []

  let to_vs cs =
    CSet.fold (fun jc vs -> VarSet.add jc.cvi vs) cs VarSet.empty

  let pp_cs index_string fmt cs =
    let lprefix = Conf.get_conf_string "rosette_join_left_state_prefix" in
    let rprefix = Conf.get_conf_string "rosette_join_right_state_prefix" in
    pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@;")
      (fun fmt jc ->
         match jc.cvi.vtype with
         | Vector _ ->
           (if jc.cleft then
              fprintf fmt "(list-ref %s%s %s)" lprefix jc.cvi.vname index_string;
            if jc.cright then
              fprintf fmt "%s(list-ref %s%s %s)"
                (if jc.cleft then " " else "") rprefix jc.cvi.vname index_string;)
         | _ ->
           (if jc.cleft then
              fprintf fmt "%s%s" lprefix jc.cvi.vname;
            if jc.cright then
              fprintf fmt "%s%s%s"
                (if jc.cleft then " " else "") rprefix jc.cvi.vname;)
      )
      fmt (to_jc_list cs)
end

(* General variable name generation. Can contain associated varinfo / fnV *)
let _VARS = SH.create 10
let register s =
  SH.add _VARS s [(_new_id (), None, None)]

let has_l_id l id =
  List.exists (fun (i, _, _) -> i = id) l

let register_vi (vi : Cil.varinfo) =
  if SH.mem _VARS vi.Cil.vname then
    let vars = SH.find _VARS vi.Cil.vname in
    SH.replace _VARS vi.Cil.vname
      (if has_l_id vars vi.Cil.vid then
         (List.map
            (fun (i, ovar, ovi) ->
               if i = vi.Cil.vid then
                 (i, ovar, Some vi)
               else
                 (i, ovar, ovi)) vars)
       else
         vars@[(vi.Cil.vid, None, Some vi)])
  else
    SH.add _VARS vi.Cil.vname [(vi.Cil.vid, None, Some vi)]

let register_vs (vs : VS.t) = VS.iter register_vi vs

let register_fnv (var : fnV) =
    if SH.mem _VARS var.vname then
    let vars = SH.find _VARS var.vname in
    SH.replace _VARS var.vname
      (if has_l_id vars var.vid then
         (List.map
            (fun (i, ovar, ovi) ->
               if i = var.vid then
                 (i, Some var, ovi)
               else
                 (i, ovar, ovi)) vars)
       else
         vars@[(var.vid, Some var, None)])
  else
    SH.add _VARS var.vname [(var.vid, Some var, None)]

let register_varset (vs : VarSet.t) = VarSet.iter register_fnv vs

let new_name_counter = ref 0

let get_new_name ?(base = "x") =
  if SH.mem _VARS base then
    let rec create_new_name x =
      let try_name = base^(string_of_int !new_name_counter) in
      incr new_name_counter;
      if SH.mem _VARS try_name then
        create_new_name base
      else
        try_name
    in
    create_new_name base
  else
    base

let find_var_name name =
  match snd3 (List.hd (SH.find _VARS name)) with
  | Some var -> var
  | None -> raise Not_found

let find_vi_name name =
  match third (List.hd (SH.find _VARS name)) with
  | Some vi -> vi
  | None -> raise Not_found

let find_vi_name_id name id =
  let vlist = SH.find _VARS name in
  match third (List.find (fun (i, _, _) -> i = id) vlist) with
  | Some vi -> vi
  | None -> raise Not_found

let find_var_name_id name id =
  let vlist = SH.find _VARS name in
  match snd3 (List.find (fun (i, _, _) -> i = id) vlist) with
  | Some var -> var
  | None -> raise Not_found


(* Bonus: mark array that are read by an outer loop. *)
let outer_used = IH.create 10

let mark_outer_used fnv : unit =
  IH.add outer_used fnv.vid true

let is_outer_used fnv : bool =
  IH.mem outer_used fnv.vid
