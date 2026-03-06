locals_without_parens = [
  attribute: 1,
  attribute: 2,
  argument: 1,
  argument: 2,
  calculation: 1,
  calculation: 2,
  action: 1,
  action: 2,
  title: 1,
  description: 1,
  example: 1,
  lang: 1,
  label: 1,
  source: 1,
  code_sample: 1
]

[
  import_deps: [:ash, :spark],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
