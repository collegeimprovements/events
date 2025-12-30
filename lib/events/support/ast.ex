defmodule Events.Support.AST do
  @moduledoc """
  AST manipulation utilities for decorators.

  This module delegates to `FnDecorator.Support.AST`.
  See that module for full documentation.
  """

  defdelegate get_name(defun), to: FnDecorator.Support.AST
  defdelegate get_args(defun), to: FnDecorator.Support.AST
  defdelegate get_arity(defun), to: FnDecorator.Support.AST
  defdelegate get_guards(defun), to: FnDecorator.Support.AST
  defdelegate get_body(defun), to: FnDecorator.Support.AST
  defdelegate get_variables(pattern), to: FnDecorator.Support.AST

  defdelegate public?(defun), to: FnDecorator.Support.AST
  defdelegate guarded?(defun), to: FnDecorator.Support.AST

  defdelegate update_body(defun, transform), to: FnDecorator.Support.AST
  defdelegate inject_before(defun, code), to: FnDecorator.Support.AST
  defdelegate inject_after(defun, code), to: FnDecorator.Support.AST
  defdelegate wrap_try(defun, clauses), to: FnDecorator.Support.AST
  defdelegate rename(defun, new_name), to: FnDecorator.Support.AST
  defdelegate make_private(defun), to: FnDecorator.Support.AST
  defdelegate make_public(defun), to: FnDecorator.Support.AST
  defdelegate add_guard(defun, guard), to: FnDecorator.Support.AST

  @doc "Builds context from function definition (uses Events.Support.Context)"
  def build_context(defun, module) do
    Events.Support.Context.new(
      name: FnDecorator.Support.AST.get_name(defun),
      arity: FnDecorator.Support.AST.get_arity(defun),
      module: module,
      args: FnDecorator.Support.AST.get_args(defun),
      guards: FnDecorator.Support.AST.get_guards(defun)
    )
  end
end
