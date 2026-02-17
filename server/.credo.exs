%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      strict: true,
      checks: %{
        extra: [
          {Credo.Check.Readability.MaxLineLength, max_length: 120},
          {Credo.Check.Design.FunctionLength, max_function_length: 100}
        ]
      }
    }
  ]
}
