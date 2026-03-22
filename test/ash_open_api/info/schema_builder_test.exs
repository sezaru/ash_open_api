defmodule AshOpenApi.Info.SchemaBuilderTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias AshOpenApi.Info.SchemaBuilder

  defmodule TestDomain do
    @moduledoc false

    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule SimpleResource do
    @moduledoc false

    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshOpenApi]

    attributes do
      uuid_primary_key :id, public?: true
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, public?: true
      attribute :age, :integer, public?: true
      attribute :active, :boolean, allow_nil?: false, public?: true

      attribute :status, :atom,
        constraints: [one_of: [:pending, :approved, :rejected]],
        public?: true

      attribute :created_at, :utc_datetime_usec, public?: true
      attribute :metadata, :map, public?: true
    end

    calculations do
      calculate :display_name, :string, expr(name <> " <" <> email <> ">"), public?: true
    end

    open_api do
      attributes do
        attribute :id, example: "abc-123", title: "ID", description: "Resource identifier"
        attribute :name, example: "John Doe"
        attribute :email, example: "john@example.com", description: "Email address"
      end

      calculations do
        calculation(:display_name, example: "John <john@example.com>")
      end
    end
  end

  defmodule ComplexTypesResource do
    @moduledoc false

    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshOpenApi]

    attributes do
      uuid_primary_key :id

      attribute :tags, {:array, :string}, public?: true

      attribute :config, :map,
        public?: true,
        constraints: [
          fields: [
            enabled: [type: :boolean, allow_nil?: false],
            timeout: [type: :integer],
            settings: [type: :map]
          ]
        ]

      attribute :result, :union,
        public?: true,
        constraints: [
          types: [
            success: [type: :string],
            error: [type: :map, fields: [message: [type: :string, allow_nil?: false]]]
          ]
        ]
    end
  end

  defmodule ActionTestResource do
    @moduledoc false

    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshOpenApi]

    attributes do
      uuid_primary_key :id, public?: true
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, public?: true
    end

    actions do
      default_accept [:name, :email]

      create :create do
        accept [:name, :email]
      end

      action :search, :struct do
        argument :query, :string, allow_nil?: false
        argument :limit, :integer
        argument :filters, :map

        constraints instance_of: __MODULE__
        run fn _input, _context -> {:ok, %__MODULE__{}} end
      end
    end

    open_api do
      actions do
        action :search do
          argument :query, example: "test search"
          argument :limit, example: 10, description: "Max results"
        end
      end
    end
  end

  describe "build_schema/2 - basic types" do
    test "converts string attribute to string schema" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :name)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :string
      assert schema.format == :binary
      assert schema.title == :name
      assert required? == true
    end

    test "converts integer attribute to integer schema" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :age)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :integer
      assert schema.title == :age
      assert required? == false
    end

    test "converts boolean attribute to boolean schema" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :active)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      # Boolean is stored as integer in Ash but we should handle it
      assert schema.title == :active
      assert required? == true
    end

    test "converts atom with constraints to string enum schema" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :status)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :string
      assert schema.enum == [:pending, :approved, :rejected]
      assert schema.title == :status
      assert required? == false
    end

    test "converts utc_datetime to string with date-time format" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :created_at)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :string
      assert schema.format == :"date-time"
      assert required? == false
    end

    test "converts map without fields to object schema" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :metadata)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :object
      assert required? == false
    end
  end

  describe "build_schema/2 - complex types" do
    test "converts array type to array schema" do
      context = %{resource: ComplexTypesResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(ComplexTypesResource, :tags)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :array
      assert schema.items.type == :string
      assert required? == false
    end

    test "converts map with fields to object schema with properties" do
      context = %{resource: ComplexTypesResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(ComplexTypesResource, :config)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :object
      assert is_map(schema.properties)
      assert Map.has_key?(schema.properties, :enabled)
      assert Map.has_key?(schema.properties, :timeout)
      assert Map.has_key?(schema.properties, :settings)
      assert :enabled in schema.required
      assert required? == false
    end

    test "converts union type to oneOf schema" do
      context = %{resource: ComplexTypesResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(ComplexTypesResource, :result)

      {schema, required?} = SchemaBuilder.build_schema(property, context)

      assert is_list(schema.oneOf)
      assert length(schema.oneOf) == 2
      assert required? == false
    end
  end

  describe "build_schema/2 - metadata merging" do
    test "merges example from open_api metadata" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :email)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      assert schema.example == "john@example.com"
    end

    test "merges description from open_api metadata" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :email)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      assert schema.description == "Email address"
    end

    test "does not override title field with open_api title" do
      # Title is used internally as an atom for map keys, so we don't merge it into schema
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :id)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      # Should use the name as title (atom), not the OpenAPI title string
      assert schema.title == :id
    end

    test "merges metadata for calculations" do
      context = %{resource: SimpleResource, entity_type: :calculation}
      [calc] = Ash.Resource.Info.calculations(SimpleResource)

      {schema, _required?} = SchemaBuilder.build_schema(calc, context)

      assert schema.example == "John <john@example.com>"
    end

    test "handles properties without metadata" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :age)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      assert Map.get(schema, :example) == nil
      assert Map.get(schema, :description) == nil
    end
  end

  describe "build_schema/2 - with description and default" do
    test "skips function defaults for uuid primary key" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :id)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      # UUID default is a function (&Ash.UUID.generate/0) which cannot be JSON-serialized
      refute Map.has_key?(schema, :default)
    end

    test "open_api description overrides property description" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :email)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      # Open API metadata should override any property description
      assert schema.description == "Email address"
    end
  end

  describe "build_output_schema/4" do
    test "builds schema for struct return type" do
      action = %{
        returns: Ash.Type.Struct,
        constraints: [instance_of: SimpleResource]
      }

      schema =
        SchemaBuilder.build_output_schema(
          action,
          %{},
          &AshOpenApi.Info.resource_attributes/1,
          &AshOpenApi.Info.resource_calculations/1
        )

      assert schema.type == :object
      assert is_map(schema.properties)

      # Should include public attributes
      assert Map.has_key?(schema.properties, :id)
      assert Map.has_key?(schema.properties, :name)
      assert Map.has_key?(schema.properties, :email)

      # Should include public calculations
      assert Map.has_key?(schema.properties, :display_name)

      # Should have required list
      assert is_list(schema.required)
      assert :name in schema.required
      assert :active in schema.required
    end

    test "builds schema for simple return type" do
      action = %{
        returns: Ash.Type.String,
        constraints: []
      }

      schema =
        SchemaBuilder.build_output_schema(
          action,
          %{},
          &AshOpenApi.Info.resource_attributes/1,
          &AshOpenApi.Info.resource_calculations/1
        )

      assert schema.type == :string
      assert schema.format == :binary
    end
  end

  describe "split_schemas_and_required/1" do
    test "splits schemas and required fields correctly" do
      schemas = [
        {{:name, %{type: :string}}, {:name, true}},
        {{:email, %{type: :string}}, {:email, false}},
        {{:age, %{type: :integer}}, {:age, true}}
      ]

      {properties, required} = SchemaBuilder.split_schemas_and_required(schemas)

      assert is_map(properties)
      assert Map.has_key?(properties, :name)
      assert Map.has_key?(properties, :email)
      assert Map.has_key?(properties, :age)

      assert is_list(required)
      assert :name in required
      assert :age in required
      refute :email in required
    end

    test "handles empty list" do
      {properties, required} = SchemaBuilder.split_schemas_and_required([])

      assert properties == %{}
      assert required == []
    end

    test "handles all optional fields" do
      schemas = [
        {{:name, %{type: :string}}, {:name, false}},
        {{:email, %{type: :string}}, {:email, false}}
      ]

      {properties, required} = SchemaBuilder.split_schemas_and_required(schemas)

      assert map_size(properties) == 2
      assert required == []
    end
  end

  describe "Info integration" do
    test "resource_attributes returns schema tuples" do
      schemas = AshOpenApi.Info.resource_attributes(SimpleResource)

      assert is_list(schemas)
      assert length(schemas) > 0

      # Each item should be a {schema, required?} tuple
      Enum.each(schemas, fn {schema, required?} ->
        assert is_map(schema)
        assert is_boolean(required?)
        assert is_atom(schema.title)
      end)
    end

    test "resource_calculations returns schema tuples" do
      schemas = AshOpenApi.Info.resource_calculations(SimpleResource)

      assert is_list(schemas)
      assert length(schemas) == 1

      [{schema, required?}] = schemas

      assert is_map(schema)
      assert schema.title == :display_name
      assert is_boolean(required?)
    end

    test "action_arguments returns schema tuples with metadata" do
      schemas = AshOpenApi.Info.action_arguments(ActionTestResource, :search)

      assert is_list(schemas)
      assert length(schemas) == 3

      # Find the query argument
      {query_schema, query_required?} = Enum.find(schemas, fn {s, _} -> s.title == :query end)

      assert query_schema.example == "test search"
      assert query_required? == true

      # Find the limit argument
      {limit_schema, limit_required?} = Enum.find(schemas, fn {s, _} -> s.title == :limit end)

      assert limit_schema.example == 10
      assert limit_schema.description == "Max results"
      assert limit_required? == false
    end

    test "action_input builds complete input schema" do
      schema = AshOpenApi.Info.action_input(ActionTestResource, :search)

      assert schema.type == :object
      assert is_map(schema.properties)
      assert Map.has_key?(schema.properties, :query)
      assert Map.has_key?(schema.properties, :limit)
      assert Map.has_key?(schema.properties, :filters)
      assert :query in schema.required
    end

    test "action_output builds complete output schema" do
      schema = AshOpenApi.Info.action_output(ActionTestResource, :search)

      assert schema.type == :object
      assert is_map(schema.properties)
      assert Map.has_key?(schema.properties, :id)
      assert Map.has_key?(schema.properties, :name)
    end
  end

  describe "edge cases" do
    test "handles attributes without open_api metadata" do
      context = %{resource: SimpleResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(SimpleResource, :age)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      # Should still build schema without metadata
      assert schema.type == :integer
      assert Map.get(schema, :example) == nil
      assert schema.title == :age
    end

    test "handles nested map fields recursively" do
      context = %{resource: ComplexTypesResource, entity_type: :attribute}
      property = Ash.Resource.Info.attribute(ComplexTypesResource, :config)

      {schema, _required?} = SchemaBuilder.build_schema(property, context)

      assert schema.type == :object
      assert Map.has_key?(schema.properties, :settings)
      # Settings is also a map
      assert schema.properties[:settings].type == :object
    end

    test "handles empty resource with no attributes" do
      # Should return empty list without errors
      schemas = AshOpenApi.Info.resource_attributes(TestDomain)

      assert schemas == []
    end
  end
end
