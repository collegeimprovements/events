# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "priv/repo/migrations/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"/node_modules/",
          ~r"/priv/static/"
        ]
      },
      plugins: [],
      requires: [],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          #
          # Consistency Checks
          #
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          #
          # Design Checks
          #
          {Credo.Check.Design.AliasUsage,
           [
             priority: :low,
             if_nested_deeper_than: 2,
             if_called_more_often_than: 1,
             # Allow fully qualified names in macros and quotes
             excluded_namespaces: [
               "Events.Migration",
               "Events.Decorator",
               "Ecto.Migration"
             ]
           ]},
          {Credo.Check.Design.TagTODO, [exit_status: 0]},
          {Credo.Check.Design.TagFIXME, []},

          #
          # Readability Checks
          #
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, [files: %{excluded: ["test/"]}]},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithSingleClause, []},

          #
          # Refactoring Opportunities
          #
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 12]},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.FunctionArity, [max_arity: 6]},
          {Credo.Check.Refactor.LongQuoteBlocks, [max_line_count: 150]},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.UtcNowTruncate, []},
          {Credo.Check.Refactor.WithClauses, []},

          #
          # Warnings (catch real bugs)
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry,
           [
             files: %{
               excluded: [
                 ~r"/decorator/",
                 ~r"decorator",
                 ~r"/test/"
               ]
             }
           ]},
          {Credo.Check.Warning.IoInspect,
           [
             files: %{
               excluded: [
                 ~r"/decorator/",
                 ~r"decorator",
                 ~r"/test/",
                 ~r"demo\.ex$",
                 ~r"pipeline\.ex$",
                 ~r"examples\.ex$"
               ]
             }
           ]},
          {Credo.Check.Warning.LeakyEnvironment,
           [files: %{excluded: [~r"/test/", ~r"/mix/tasks/"]}]},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig,
           [files: %{excluded: [~r"/api_client/", ~r"/errors/", ~r"error\.ex$"]}]},
          {Credo.Check.Warning.MixEnv,
           [
             files: %{
               excluded: [
                 ~r"/decorator/",
                 ~r"decorator",
                 ~r"/test/",
                 ~r"/errors/",
                 ~r"examples\.ex$",
                 ~r"system_health/"
               ]
             }
           ]},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnsafeToAtom,
           [
             files: %{
               excluded: [
                 # Infrastructure code with controlled atom creation
                 ~r"/migration/",
                 ~r"/decorator/",
                 ~r"/identifiable/",
                 ~r"/normalizable/",
                 ~r"/context\.ex$",
                 ~r"/supervisor\.ex$",
                 ~r"/api_client/",
                 ~r"query\.ex$",
                 ~r"/query/",
                 ~r"pubsub\.ex$",
                 ~r"schema\.ex$",
                 ~r"pipeline\.ex$",
                 ~r"validation\.ex$",
                 ~r"errors/mappers/",
                 ~r"/schema/",
                 ~r"/behaviours/",
                 ~r"/mix/tasks/",
                 ~r"/test/"
               ]
             }
           ]},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},

          #
          # Events Project Custom Checks (from OmCredo lib)
          #
          {OmCredo.Checks.UseEnhancedSchema,
           [
             enhanced_module: OmSchema,
             raw_module: Ecto.Schema,
             files: %{excluded: [~r"/test/", ~r"/deps/"]}
           ]},
          {OmCredo.Checks.UseEnhancedMigration,
           [
             enhanced_module: OmMigration,
             raw_module: Ecto.Migration,
             files: %{excluded: [~r"/test/", ~r"/deps/"]}
           ]},
          {OmCredo.Checks.NoBangRepoOperations,
           [
             repo_modules: [:Repo, Events.Data.Repo],
             files: %{excluded: [~r"/test/", ~r"/deps/", ~r"/examples/"]}
           ]},
          {OmCredo.Checks.RequireResultTuples,
           [
             priority: :normal,
             paths: ["/lib/events/domains/", "/lib/events/services/"],
             excluded_names: ["changeset", "new", "build", "get", "fetch!"]
           ]},
          {OmCredo.Checks.PreferPatternMatching,
           [
             priority: :low,
             files: %{excluded: [~r"/test/", ~r"/mix/tasks/"]}
           ]},
          {OmCredo.Checks.UseDecorator,
           [
             priority: :low,
             decorator_module: FnDecorator,
             paths: ["/lib/events/domains/", "/lib/events/services/"],
             files: %{excluded: [~r"/test/"]}
           ]}
        ],
        disabled: [
          # Disabled because we use multi-alias imports
          {Credo.Check.Readability.MultiAlias, []},
          # Allow single pipes for clarity in some cases
          {Credo.Check.Readability.SinglePipe, []},
          # Specs are optional in this project (using decorators instead)
          {Credo.Check.Readability.Specs, []},
          # Not using @impl in all cases
          {Credo.Check.Readability.StrictModuleLayout, []},
          # ABCSize is too restrictive for macro-heavy code
          {Credo.Check.Refactor.ABCSize, []},
          # Allow modules over 500 lines for now
          {Credo.Check.Refactor.ModuleDependencies, []},
          # Pipeline length varies by use case
          {Credo.Check.Refactor.PipeChainStart, []},
          # Incompatible with Elixir 1.19+
          {Credo.Check.Warning.LazyLogging, []}
        ]
      }
    }
  ]
}
