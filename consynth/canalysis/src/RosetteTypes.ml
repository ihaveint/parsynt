open Cil
open Utils


type symbolicType =
  | Unit
  (** Base types : only booleans, integers and reals *)
  | Integer
  | Real
  | Boolean
  (** Type tuple *)
  | Tuple of symbolicType list
  (** Other lifted types *)
  | Bitvector of symbolicType * int
  (** A function in Rosette is an uniterpreted function *)
  | Function of symbolicType * symbolicType
  (** A procdedure is a reference to a procedure object *)
  | Procedure of symbolicType * symbolicType
  (** Pairs and lists *)
  | Pair of symbolicType
  | List of symbolicType * int option
  (** Vector and box *)
  | Vector of symbolicType * int option
  | Box of symbolicType
  (** User-defined structures *)
  | Struct of symbolicType

let string_of_baseSymbolicType =
  function
  | Integer -> "integer?"
  | Real -> "real?"
  | Boolean -> "boolean?"
  | _ -> failwith "not a symbolic type."

let rec symb_type_of_ciltyp =
  function
  | TInt (ik, _) ->
     begin
       match ik with
       | IBool -> Boolean
       | _ -> Integer
     end

  | TFloat _ -> Real

  | TArray (t, _, _) ->
     Vector (symb_type_of_ciltyp t, None)

  | TFun (t, arglisto, _, _) ->
     Procedure (symb_type_of_args arglisto, symb_type_of_ciltyp t)
  | TComp (ci, _) -> Unit
  | TVoid _ -> Unit
  | TPtr (t, _) ->
     Vector (symb_type_of_ciltyp t, None)
  | TNamed (ti, _) ->
     symb_type_of_ciltyp ti.ttype
  | TEnum _ | TBuiltin_va_list _ -> failwith "Not implemented"

and symb_type_of_args argslisto =
  try
    let argslist = checkOption argslisto in
    let symb_types_list =
      List.map
        (fun (s, t, atr) -> symb_type_of_ciltyp t)
        argslist
    in
    match symb_types_list with
    | [] -> Unit
    | [st] -> st
    | _ -> Tuple symb_types_list
  with Failure s -> Unit


(*
  Operators : Cil operators and C function names.
*)

type symbUnops =
  | Not | Add1 | Sub1
(**
   From C++11 : 4 different ops.
   value   round   floor   ceil    trunc
   -----   -----   -----   ----    -----
   2.3     2.0     2.0     3.0     2.0
   3.8     4.0     3.0     4.0     3.0
   5.5     6.0     5.0     6.0     5.0
   -2.3    -2.0    -3.0    -2.0    -2.0
   -3.8    -4.0    -4.0    -3.0    -3.0
   -5.5    -6.0    -6.0    -5.0    -5.0
*)
  | Abs | Floor | Ceiling | Truncate | Round
  | Neg
  (** Misc*)
  | Expt | Sgn

type symbBinops =
  (** Booleans*)
  | And | Nand | Or | Nor | Implies | Xor
  (** Integers and reals *)
  | Plus | Minus | Times | Div | Quot | Rem | Mod
  | Max | Min
  (** Comparison *)
  | Eq | Lt | Le | Gt | Ge | Neq
  (** Shift*)
  | ShiftL | ShiftR

type constants =
  | Int of int
  | Real of float
  | Bool of bool
  | CUnop of symbUnops * constants
  | CBinop of symbBinops * constants * constants
  | Pi | SqrtPi | Ln2 | Ln10 | E

let symb_unop_of_cil =
  function
  | LNot | BNot -> Not
  | Neg -> Neg

let symb_binop_of_cil =
  function
  | IndexPI -> Plus
  | PlusA | PlusPI -> Plus
  | MinusA | MinusPI | MinusPP-> Minus
  | Mult -> Times
  | Div -> Div
  | Mod -> Mod
  | BXor -> Xor
  | BAnd | LAnd -> And
  | BOr | LOr -> Or
  | Lt -> Lt | Le -> Le | Gt -> Gt | Ge -> Ge
  | Eq -> Eq | Ne -> Neq
  | Shiftlt -> ShiftL | Shiftrt -> ShiftR

  (* number?, real?, integer?, zero?, positive?, negative?, even?, odd?, *)
  (* inexact->exact, exact->inexact, quotient , sgn *)

(** C Standard Library function names -> Rosette supported functions *)
let symb_unop_of_fname =
  function
  | "exp" -> Some Expt
  | "floor" | "floorf" | "floorl" -> Some Floor
  | "abs"
  | "fabs" | "fabsf" | "fabsl"
  | "labs" | "llabs" | "imaxabs" -> Some Abs
  | "ceil" -> Some Ceiling
  (** C++11 *)
  | "trunc" | "truncf" | "truncl"  -> Some Truncate
  | "llround"
  | "lround" | "lroundf" | "lroundl"
  | "round" | "roundf" | "roundl"
  | "nearbyint" | "nearbyintf" | "nearbyintl"
  | "lround" | "lroundf" | "lroundl"
  | "llround" | "llroundf" | "llroundl"
  | "rint" | "rintf" | "rintl" -> Some Round
  | _ -> None

let symb_binop_of_fname =
  function
  | "modf" | "modff" | "modfl" -> None (** TODO *)
  | "fmod" | "fmodl" | "fmodf" -> Some Mod
  | "remainder" | "remainderf" | "remainderl"
  | "drem" | "dremf" | "dreml" -> Some Rem
  | "fmax" -> Some Max
  | "fmin" -> Some Min
  (**
      Comparison macros/functions in C++11
      /!\ Unsafe
  *)
  | "isgreater" -> Some Gt
  | "isgreaterequal" -> Some Ge
  | "isless" -> Some Lt
  | "islessequal" -> Some Le
  | "islessgreater" -> Some Neq
  | "isunordered" -> Some Neq
  | _ -> None

(**
    Mathematical constants defined in GNU-GCC math.h.
   ****   ****   ****   ****   ****   ****   ****
    TODO : integrate log/ln/pow function, not in
    rosette/safe AFAIK.
*)
let c_constant =
  function
  | "M_E" -> Some E
  | "M_LOG2E" -> None
  | "M_LOG10E" -> None
  | "M_LN2" -> Some Ln2
  | "M_LN10" -> Some Ln10
  | "M_PI" -> Some Pi
  | "M_PI_2" -> Some (CBinop (Div, Pi, (Int 2)))
  | "M_PI_4" -> Some (CBinop (Div, Pi, (Int 2)))
  | "M_1_PI" -> Some (CBinop (Div, (Real 1.0), Pi))
  | "M_2_PI" -> Some (CBinop (Div, (Real 2.0), Pi))
  | "M_2_SQRTPI" -> None
  | "M_SQRT2" -> None
  | "M_SQRT1_2" -> None
  | _ -> None


(**
    A function name not appearing in the cases above
    will be treated as an "uninterpreted function" by
    default.
    TODO :
    -> Unless it is a user-specified function that can
    be interpreted easily (ex : custom max)
*)

let uninterpeted fname =
  match symb_unop_of_fname fname with
  | Some _ -> false
  | None ->
     begin
       match symb_binop_of_fname fname with
       | Some _ -> false
       | None ->
          begin
            match c_constant fname with
            | Some _ -> false
            | None -> true
          end
     end
