(**
   This file is part of Parsynt.

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


open Beta
open Expressions
open Format
open FnPretty
open Fn
open SymbExe
open Utils
open VUtils


let exec_foldl (aux : auxiliary) (acc : auxiliary) =
  let xinfo' =
    {xinfo with context = {xinfo.context with state_vars = VarSet.empty}}
  in
  let replace_cell aux j e =
    match aux.aexpr with
    | FnVector el ->
      replace_expression
        (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
        (el >> j)
        e
    | ex ->
      replace_expression
        (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
        ex
        e
  in
  let unfold_op e = fst (unfold_expr xinfo' e) in
  let e_unfolded =
    match aux.afunc with
    | FnVector el ->
      FnVector(List.mapi (fun i e -> replace_cell aux i (unfold_op e)) el)
    | _ ->
      failhere __FILE__ "find_accumulator" "Got non-vector while looking for map."
  in


let find_accumulator (xinfo : exec_info ) (ne : fnExpr) : AuxSet.t -> AuxSet.t =

  let find_scalar_accumulator aux =
    let xinfo' =
      {xinfo with context = {xinfo.context with state_vars = VarSet.empty}}
    in
    let unfold_op e = fst (unfold_expr xinfo' e) in
    let e_unfolded =
      replace_expression (mkVarExpr aux.avar) aux.aexpr (unfold_op aux.afunc)
    in
    printf "@[<v 4>Accumulation?@;%a==@;%a@.%b@]@."
      cp_fnexpr e_unfolded cp_fnexpr ne (e_unfolded @= ne);
    e_unfolded @= ne
  in

  let find_map_accumulator aux =
    let xinfo' =
      {xinfo with context = {xinfo.context with state_vars = VarSet.empty}}
    in
    let replace_cell aux j e =
      match aux.aexpr with
      | FnVector el ->
        replace_expression
          (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
          (el >> j)
          ep
      | ex ->
        replace_expression
          (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
          ex
          e
    in
    let unfold_op e = fst (unfold_expr xinfo' e) in
    let e_unfolded =
      match aux.afunc with
      | FnVector el ->
        FnVector(List.mapi (fun i e -> replace_cell aux i (unfold_op e)) el)
      | e ->
        replace_expression (mkVarExpr aux.avar) aux.aexpr (unfold_op e)
    in
    printf "@[<v 4>Accumulation?@;%a==@;%a@.%b@]@."
      cp_fnexpr e_unfolded cp_fnexpr ne (e_unfolded @= ne);
    e_unfolded @= ne
  in

  let find_foldl_accumulator aux acc =
    let e_unfolded = exec_foldl aux acc in
    printf "@[<v 4>Accumulation?@;%a==@;%a@.%b@]@."
      cp_fnexpr e_unfolded cp_fnexpr ne (e_unfolded @= ne);
    e_unfolded @= ne
  in

  let find_foldr_accumulator aux acc =
    let xinfo' =
      {xinfo with context = {xinfo.context with state_vars = VarSet.empty}}
    in
    let replace_cell aux j e =
      match aux.aexpr with
      | FnVector el ->
        replace_expression
          (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
          (el >> j)
          e
      | ex ->
        replace_expression
          (mkVarExpr ~offsets:[FnConst (CInt j)] aux.avar)
          ex
          e
    in
    let unfold_op e = fst (unfold_expr xinfo' e) in
    let e_unfolded =
      match aux.afunc with
      | FnVector el ->
        FnVector(List.mapi (fun i e -> replace_cell aux i (unfold_op e)) el)
      | e ->
        replace_expression (mkVarExpr aux.avar) aux.aexpr (unfold_op e)
    in
    printf "@[<v 4>Accumulation?@;%a==@;%a@.%b@]@."
      cp_fnexpr e_unfolded cp_fnexpr ne (e_unfolded @= ne);
    e_unfolded @= ne
  in

  AuxSet.filter
    (fun aux ->
       match aux.atype with
       | Scalar -> find_scalar_accumulator aux
       | Map -> find_map_accumulator aux
       | FoldL acc -> find_foldl_accumulator aux acc
       | FoldR acc -> find_foldr_accumulator aux acc
    )


let collect_input_subscripts (ctx : context) (e : fnExpr) : ES.t =
  let rec collect v =
    match v with
    | FnArray(a, e) -> ES.singleton e
    | _ -> ES.empty
  in
  rec_expr2
    {
      join = ES.union;
      init = ES.empty;
      case = (fun e -> false);
      on_case = (fun f e -> ES.empty);
      on_var = collect;
      on_const = (fun c -> ES.empty);
    } e



let is_map (ctx : context) (el : fnExpr list) : bool =
  List.for_all2
    (fun expr i ->
       let iset = collect_input_subscripts ctx expr in
       ES.cardinal iset = 1 &&
       (match ES.max_elt iset with
        | FnConst (CInt j) -> j = i
        | _ -> false))
    el
    (List.mapi (fun i a -> i) el)


let is_foldl (ctx : context) : fnExpr list -> bool =
  ListTools.for_all_i
    (fun (i,expr) ->
       let iset = collect_input_subscripts ctx expr in
       ES.cardinal iset <= (i + 1) &&
       ES.for_all
         (fun e ->
            match e with
            | FnConst (CInt j) -> j <= i
            | _ -> false) iset)


let is_foldr (ctx : context) (el : fnExpr list) : bool =
  let n = List.length el in
  ListTools.for_all_i
    (fun (i, expr) ->
       let iset = collect_input_subscripts ctx expr in
       ES.cardinal iset <= (i + 1) &&
       ES.for_all
         (fun e ->
            match e with
            | FnConst (CInt j) -> j >= (n - (i + 1))
            | _ -> false) iset) el


let create_foldl (ctx : context) (var : fnLVar) (sc_acc : fnV) (el : fnExpr list) =
  []

let create_foldr (ctx : context) (var : fnLVar) (sc_acc : fnV) (el : fnExpr list) =
  let acc_func =
    assert (List.length el >= 3);
    let maybe_func =
      replace_expression_in_subscripts
        ~to_replace:(FnConst (CInt 1))
        ~by:(mkVarExpr (mkFnVar "j" Integer))
        ~ine:
          (replace_AC ctx ~to_replace:(el >> 0) ~by:(mkVarExpr sc_acc) ~ine:(el >>1))
    in
    maybe_func
  in
  let t = FoldR
      {
        avar = sc_acc;
        aexpr = ListTools.last el;
        afunc = acc_func;
        atype = Scalar;
        depends = VarSet.empty;
      }
  in
  [FnVector(List.map (fun e -> mkVarExpr sc_acc) el), t]


let find_row_function (el : fnExpr list) =
  el



let get_base_accus (ctx : context) (var : fnLVar) (expr : fnExpr) :
  (fnExpr * aux_comp_type) list =

  match expr with
  | FnBinop (op, expr1, expr2) when is_constant expr1 && is_constant expr2 ->
    [FnBinop (op, FnVar var, expr2), Scalar;
     FnBinop (op, expr1, FnVar var), Scalar;
     FnBinop (op, expr1, expr2), Scalar]

  | FnVector el ->
    if is_map ctx el then
      [FnVector (List.mapi (fun i e -> FnVar(FnArray(var, FnConst(CInt i)))) el), Map]
    else if is_foldl ctx el then
      let scalar_acc = mkFnVar "foldr_acc" (type_of (List.hd el)) in
      create_foldl ctx var scalar_acc el

    else if is_foldr ctx el then
      let scalar_acc = mkFnVar "foldr_acc" (type_of (List.hd el)) in
      create_foldr ctx var scalar_acc el

    else
      [expr, Map]

  | _ -> [expr, Scalar]
