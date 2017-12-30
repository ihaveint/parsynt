(** General settings *)
val project_dir: string
val output_dir:string ref
val get_conf_string: string -> string
(** Builtin variables *)
type builtins =
  | Min_Int
  | Max_Int
  | False
  | True
val is_builtin_var: string -> bool
val get_builtin: string -> builtins
(** Verification parameters *)
val verification_parameters : (int * int * int) list
(* Naming conventions *)
val inner_loop_func_name : string -> int -> string
val is_inner_loop_func_name : string -> bool
