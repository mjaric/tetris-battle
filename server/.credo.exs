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
          {Credo.Check.Readability.MaxLineLength, max_length: 120}
        ]
      }
    }
  ]
}
