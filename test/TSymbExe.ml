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

open Beta
open SymbExe
open Utils
open TestUtils
open ExpressionReduction
open VariableDiscovery
open FPretty
open FuncTypes
open Format


type stv_type =
  | SymbScalar of fnExpr
  | Scalar of constants
  | Linear of (int * constants) list
  | SymbLinear of (int * fnExpr) list

let symbolic_execution_test tname vars ctx funct unfoldings efinal =
  let indexes =  create_symbol_map ctx.index_vars in
  let state = create_symbol_map ctx.state_vars in
  let xinfo =
    {
      context = ctx;
      state_exprs = state;
      index_exprs = indexes;
      inputs = ES.empty;
    }
  in
  let results, inputs = unfold_once ~silent:false xinfo funct in
  try
    List.iter
      (fun (vid, stv_type) ->
         let e = IM.find vid results in
         match stv_type, e with
         | Scalar c, FnConst c' -> if c = c' then () else failwith "Y"
         | SymbScalar sc, e -> if e = sc then () else failwith "YY"
         | Linear kl, FnVector ar ->
           (List.iter
              (fun (k, c) ->
                 if FnConst c = List.nth ar k then () else failwith "X") kl)
         | SymbLinear skl, FnVector ar ->
           (List.iter
              (fun (k, c) ->
                 if c = List.nth ar k then () else failwith "X") skl)
         | _ -> failwith "failed")
      efinal;
    msg_passed ("Test passed: "^tname)
  with Failure s ->
    IM.iter
      (fun k e -> printf "%a [%a]@." cp_fnexpr e pp_typ (type_of e)) results;
    msg_failed (tname^" : "^s)


let test_01 () =
  let vars = vardefs "((sum int) (i int) (c int_array) (A int_array))" in
  let cont = make_context vars "((sum c) (i) (A) (sum c i A) (sum c))" in
  let c = vars#get "c" in
  let sum = vars#get "sum" in
  let funct =
    _letin
      [(FnArray (FnVariable c, sk_zero), sk_zero);
       (FnVariable sum, sk_zero)]
      (_letin [(FnArray (FnVariable c, sk_one)), (FnVar (FnArray (FnVariable c, sk_zero)))]
         sk_tail_state)
  in
  symbolic_execution_test "sum0" vars cont funct 1
    [(sum.vid, Scalar (CInt 0));(c.vid, Linear [(0, CInt 0); (1,CInt 0)])]



let test_02 () =
  let vars = vardefs "((sum int) (i int) (c int_array) (A int_array))" in
  let cont = make_context vars "((sum c) (i) (A) (sum c i A) (sum c))" in
  let c = vars#get "c" in
  let sum = vars#get "sum" in
  let i = vars#get "i" in
  let inloop_state = VarSet.singleton c in
  let inloop_type = Record(VarSet.record inloop_state) in
  let state_binder = mkFnVar "_st" inloop_type in
  let funct =
    _letin
      [(FnArray (FnVariable c, sk_zero), sk_zero);
       (FnVariable sum, sk_zero)]
      (_letin [FnArray (FnVariable c, sk_one), FnVar (FnArray (FnVariable c, sk_zero))]
         (_letin [FnVariable state_binder,
                  (FnRec (
                      (* Initial value, guard and update of index of the loop. *)
                    (_ci 0, (flt (evar i) (_ci 10)),(fplus (evar i) sk_one)),
                    (* Initial state *)
                    (inloop_state, FnRecord(inloop_type, [mkVarExpr c])),
                      (* Body of the loop *)
                    (state_binder,
                     (_letin [FnVariable c, FnRecordMember(mkVarExpr state_binder, c.vname)]
                        (_letin [(FnArray (FnVariable c, _ci 2)), _ci 2]
                           (_let []))))))]
         (_let [FnVariable c, FnRecordMember(mkVarExpr state_binder, c.vname)])))
  in
  symbolic_execution_test "sum1" vars cont funct 1
    [(sum.vid, Scalar (CInt 0));(c.vid, Linear [(0, CInt 0); (1,CInt 0); (2, CInt 2)])]

let test_03 () =
  (* TODO: partial execution for indexes (partial exec for integers) *)
  let vars = vardefs "((sum int) (i int) (c int_array) (A int_array))" in
  let cont = make_context vars "((sum c) (i) (A) (sum c i A) (sum c))" in
  let c = vars#get "c" in
  let sum = vars#get "sum" in
  let i = vars#get "i" in
  let inst = VarSet.singleton c in
  let instt = Record (VarSet.record inst) in
  let xs = mkFnVar "xs" instt in
  let funct =
    _letin
      [(FnArray (FnVariable c, sk_zero), sk_zero);
       (FnVariable sum, sk_zero)]
      (_letin [(FnArray (FnVariable c, sk_one)), (FnVar (FnArray (FnVariable c, sk_zero)));
               (FnArray (FnVariable c, _ci 2)), (FnVar (FnArray (FnVariable c, sk_zero)))]
         (_let [FnVariable c,
                (FnRecordMember
                   (FnRec
                      (
                        (* Initial value, guard and update of index of the loop. *)
                        (_ci 0, (flt (evar i) (_ci 10)),(fplus (evar i) sk_one)),
                        (* Initial state *)
                        (inst, FnRecord(instt, [evar c])),
                        (* Body of the loop *)
                        (xs, (_letin [_self xs c]
                                (_letin [FnArray (var c,  _ci 2),
                                         fplus (c $ (_ci 2)) sk_one]
                                   (_let [var c, evar c]))))), c.vname))]))
  in
  symbolic_execution_test "sum2" vars cont funct 1
    [(sum.vid, Scalar (CInt 0));(c.vid, Linear [(0, CInt 0); (1,CInt 0); (2, CInt 10)])]


let test_04 () =
 (* (let ([tup$ (LoopFunc 0 (lambda (j) (< j 5)) (lambda (j) (+ j 1))
  *                         ($Vi_ii a c 0 0 i j)
  *                         (lambda ($6s j) (let ([sum (+ sum
  *                                                     (list-ref (list-ref a i) j))])
  *                                            (let ([c (list-set c j (+
  *                                                                    (list-ref c j)
  *                                                                    sum))])
  *                                               ($Vi_ii c
  *                                                 (max (list-ref c j) mtr)
  *                                                 sum)))))])
  *              (let ([c ($Vi_ii-c tup$)][mtr ($Vi_ii-mtr tup$)]
  *                [sum ($Vi_ii-sum tup$)])  ($Vi_iii c mtr (max mtr mtrl) sum))) *)
  let vars = vardefs "((sum int) (mtr int) (c int_array) (mtrl int) (a int_int_array) (i int) (j int))" in
  let cont = make_context vars "((sum mtr mtrl c) (i) (a) (sum mtr mtrl c i j a) (sum mtr mtrl c))" in
  let c = vars#get "c" in let mtr = vars#get "mtr" in let mtrl = vars#get "mtrl" in
  let a = vars#get "a" in let sum = vars#get "sum" in
  let j = vars#get "j" in let i = vars#get "i" in
  let inctx = make_context vars "((sum mtr c) (j) (a) (sum mtr mtrl c j a) (sum mtr c))" in
  let intype = Record (VarSet.record inctx.state_vars) in
  let tup = mkFnVar "tup" intype in
  let bnds = mkFnVar "bound" intype in
  let func =
    (_letin [FnVariable tup,
           FnRec((sk_zero, (flt (evar i) (_ci 5)), (fplus (evar j) sk_one)),
                 (inctx.state_vars, FnRecord(intype, [evar c; sk_zero; sk_zero])),
                 (bnds,
                  (_letin [var sum, fplus (a $$ (evar i, evar j)) (evar sum)]
                     (_letin [var c, FnArraySet(evar c, evar j, (fplus (c $ (evar j)) (evar sum)))]
                        (_let [var c, evar c;
                               var mtr, fmax (c $ (evar j)) (evar mtr);
                               var sum, evar sum])))))]
       (_let [_self tup c;
              _self tup mtr;
              var mtrl, fmax (evar mtrl) (_inrec tup mtr);
              _self tup sum]))
  in
  symbolic_execution_test "mtrl" vars cont func 2
    [sum.vid,
     SymbScalar
       (fplus  (a $$ (evar i, _ci 4))
          (fplus (a $$ (evar i, _ci 3))
             (fplus  (a $$ (evar i, _ci 2))
                (fplus (a $$ (evar i, _ci 1))
                   (fplus (a $$ (evar i, _ci 0))
                      (evar sum))))));
     c.vid,
     SymbLinear [
       0, (fplus (c $ (_ci 0))
             (fplus (a $$ (evar i, _ci 0)) (evar sum)));
       1, (fplus (c $ (_ci 1))
             (fplus  (a $$ (evar i, _ci 1))
                (fplus (a $$ (evar i, _ci 0)) (evar sum))));
     ]]



(* Normalization: file defined tests. *)
let test_load filename =
  let inchan = IO.input_channel (open_in filename) in
  let message = IO.read_line inchan in
  print_endline message;

  (* let title = IO.read_line inchan in
   * let unfoldings = int_of_string (IO.read_line inchan) in
   * let vars = vardefs (IO.read_line inchan) in
   * let context = make_context vars (IO.read_line inchan) in
   * let funct = expression vars (IO.read_line inchan) in
   * let efinal = expression vars (IO.read_line inchan) in *)
  ()

let file_defined_tests () =
  let test_files =
    glob (Conf.project_dir^"/test/symbolic_execution/*.test")
  in
  List.iter test_load test_files



let test () =
  test_01 ();
  test_02 ();
  test_03 ();
  test_04 ();
  file_defined_tests ()
