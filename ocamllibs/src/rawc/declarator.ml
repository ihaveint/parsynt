(**************************************************************************)
(*                    Jacques-Henri Jourdan, Inria Paris                  *)
(*                      François Pottier, Inria Paris                     *)
(*                                                                        *)
(*  Copyright Inria. All rights reserved. This file is distributed under  *)
(*  the terms of the GNU General Public License as published by the Free  *)
(*  Software Foundation, either version 2 of the License, or (at your     *)
(*  option) any later version.                                            *)
(**************************************************************************)

open Context

(* We distinguish between three kinds of declarators: 1- identifiers,
   2- function declarators, and 3- everything else. In the case of a
   function declarator, we save a snapshot of the context at the END
   of the parameter-type-list. *)

(* K&R function declarators are considered part of "other" declarators. *)

type declarator_kind =
| DeclaratorIdentifier
| DeclaratorFunction of context
| DeclaratorOther

(* With a declarator, we associate two pieces of information: 1- the
   identifier that is being declared; 2- the declarator's kind, as
   defined above. *)

type declarator = {
  identifier: string;
  kind: declarator_kind
}

(* This accessor returns the identifier that is being declared. *)

let identifier d =
  d.identifier

(* Three functions for constructing declarators. *)

let identifier_declarator i =
  { identifier = i; kind = DeclaratorIdentifier }

let function_declarator d ctx =
  match d.kind with
  | DeclaratorIdentifier -> { d with kind = DeclaratorFunction ctx }
  | _                    ->   d

let other_declarator d =
  match d.kind with
  | DeclaratorIdentifier -> { d with kind = DeclaratorOther }
  | _                    ->   d

(* A function for restoring the context that was saved in a function
   declarator and, on top of that, declaring the function itself as a
   variable. *)

let reinstall_function_context d =
  match d.kind with
  | DeclaratorFunction ctx ->
      restore_context ctx;
      declare_varname d.identifier
  | _ ->
      (* If we are here, then we have encountered a declarator that is
         not a function declarator yet is followed by (the first symbol
         of) [declaration_list? compound_statement]. Either this is a
         K&R function declarator (in which case we should do nothing)
         or this is an error. *)
      ()
