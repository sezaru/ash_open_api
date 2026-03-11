defmodule AshOpenApi do
  @moduledoc """
  Ash extension for OpenAPI metadata.
  """

  defmodule Attribute do
    @moduledoc false
    defstruct [:name, :title, :description, :example, :__spark_metadata__]
  end

  defmodule Calculation do
    @moduledoc false
    defstruct [:name, :title, :description, :example, :__spark_metadata__]
  end

  defmodule Relationship do
    @moduledoc false
    defstruct [:name, :title, :description, :example, :__spark_metadata__]
  end

  defmodule ActionArgument do
    @moduledoc false
    defstruct [:name, :title, :description, :example, :__spark_metadata__]
  end

  defmodule ActionAttribute do
    @moduledoc false
    defstruct [:name, :title, :description, :example, :__spark_metadata__]
  end

  defmodule ActionTitle do
    @moduledoc false
    defstruct [:value, :__spark_metadata__]
  end

  defmodule ActionDescription do
    @moduledoc false
    defstruct [:value, :__spark_metadata__]
  end

  defmodule CodeSample do
    @moduledoc false
    defstruct [:lang, :label, :source, :__spark_metadata__]
  end

  defmodule CodeSampleMfa do
    @moduledoc false
    defstruct [:mfa, :__spark_metadata__]
  end

  defmodule Action do
    @moduledoc false
    defstruct [
      :name,
      :title,
      :description,
      :code_samples,
      :code_sample_mfas,
      :arguments,
      :attributes,
      :__spark_metadata__
    ]
  end

  @attribute %Spark.Dsl.Entity{
    name: :attribute,
    describe: "Define OpenAPI metadata for a resource attribute",
    target: Attribute,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      title: [type: :string],
      description: [type: :string],
      example: [type: :any]
    ]
  }

  @calculation %Spark.Dsl.Entity{
    name: :calculation,
    describe: "Define OpenAPI metadata for a resource calculation",
    target: Calculation,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      title: [type: :string],
      description: [type: :string],
      example: [type: :any]
    ]
  }

  @relationship %Spark.Dsl.Entity{
    name: :relationship,
    describe: "Define OpenAPI metadata for a resource relationship",
    target: Relationship,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      title: [type: :string],
      description: [type: :string],
      example: [type: :any]
    ]
  }

  @action_argument %Spark.Dsl.Entity{
    name: :argument,
    describe: "Define OpenAPI metadata for an action argument",
    target: ActionArgument,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      title: [type: :string],
      description: [type: :string],
      example: [type: :any]
    ]
  }

  @action_attribute %Spark.Dsl.Entity{
    name: :attribute,
    describe: "Define OpenAPI metadata for an action attribute",
    target: ActionAttribute,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      title: [type: :string],
      description: [type: :string],
      example: [type: :any]
    ]
  }

  @action_title %Spark.Dsl.Entity{
    name: :title,
    describe: "Define OpenAPI title for an action",
    target: ActionTitle,
    args: [:value],
    schema: [
      value: [type: :string, required: true]
    ]
  }

  @action_description %Spark.Dsl.Entity{
    name: :description,
    describe: "Define OpenAPI description for an action",
    target: ActionDescription,
    args: [:value],
    schema: [
      value: [type: :string, required: true]
    ]
  }

  @code_sample %Spark.Dsl.Entity{
    name: :code_sample,
    describe: "Define a code sample for an action",
    target: CodeSample,
    schema: [
      lang: [type: :string, required: true, doc: "Programming language of the sample"],
      label: [type: :string, doc: "Optional label for the code sample"],
      source: [type: :string, required: true, doc: "The actual code sample"]
    ]
  }

  @code_sample_mfa %Spark.Dsl.Entity{
    name: :code_sample_mfa,
    describe: "Define a code sample via MFA. The function must return a map with string keys: lang, source, and optionally label.",
    target: CodeSampleMfa,
    args: [:mfa],
    schema: [
      mfa: [
        type: :mfa,
        required: true,
        doc: "An MFA tuple {module, function, args} returning a code sample map"
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    describe: "Define OpenAPI metadata for an action",
    target: Action,
    args: [:name],
    schema: [
      name: [type: :atom, required: true]
    ],
    entities: [
      title: [@action_title],
      description: [@action_description],
      code_samples: [@code_sample],
      code_sample_mfas: [@code_sample_mfa],
      arguments: [@action_argument],
      attributes: [@action_attribute]
    ]
  }

  @attributes %Spark.Dsl.Section{
    name: :attributes,
    describe: "OpenAPI metadata for attributes",
    entities: [@attribute]
  }

  @calculations %Spark.Dsl.Section{
    name: :calculations,
    describe: "OpenAPI metadata for calculations",
    entities: [@calculation]
  }

  @relationships %Spark.Dsl.Section{
    name: :relationships,
    describe: "OpenAPI metadata for relationships",
    entities: [@relationship]
  }

  @actions %Spark.Dsl.Section{
    name: :actions,
    describe: "OpenAPI metadata for actions",
    entities: [@action]
  }

  @open_api %Spark.Dsl.Section{
    name: :open_api,
    describe: "OpenAPI metadata",
    sections: [@attributes, @calculations, @relationships, @actions]
  }

  use Spark.Dsl.Extension,
    sections: [@open_api],
    transformers: [AshOpenApi.Transformer]
end
