defmodule AshOpenApi.Info.SchemaBuilder do
  @moduledoc """
  Schema building logic for converting Ash types to JSON schemas (plain maps).

  This module handles the conversion of Ash resource attributes, calculations,
  and arguments into OpenAPI schema definitions compatible with oaskit.
  """

  alias Ash.Type

  @doc """
  Build a schema from properties with context.

  Returns a tuple of {schema, required?}.
  """
  def build_schema(properties, context) do
    schema =
      %{}
      |> title(properties)
      |> description(properties)
      |> default(properties)
      |> type(properties, context)
      |> merge_metadata(properties, context)

    {schema, required?(properties)}
  end

  @doc """
  Build output schema for an action.
  """
  def build_output_schema(
        %{returns: Ash.Type.Struct, constraints: constraints},
        opts,
        resource_attributes_fn,
        resource_calculations_fn
      ) do
    resource = Keyword.fetch!(constraints, :instance_of)

    attributes = resource_attributes_fn.(resource)
    calculations = resource_calculations_fn.(resource)

    {properties, required} =
      attributes
      |> Kernel.++(calculations)
      |> Enum.map(fn {%{title: title} = argument, required?} ->
        {{title, argument}, {title, required?}}
      end)
      |> split_schemas_and_required()

    Map.merge(opts, %{type: :object, properties: properties, required: required})
  end

  def build_output_schema(
        %{returns: return_type, constraints: constraints},
        opts,
        _resource_attributes_fn,
        _resource_calculations_fn
      ) do
    # Build schema from the return type
    properties = %{name: :result, type: return_type, constraints: constraints, allow_nil?: false}
    {schema, _required?} = build_schema(properties, %{})

    # Merge with opts and return
    Map.merge(Map.new(opts), schema)
  end

  @doc """
  Split schemas and required into separate maps.
  """
  def split_schemas_and_required(schemas) do
    {schemas, required} = Enum.unzip(schemas)

    required =
      required
      |> Enum.filter(fn {_, required?} -> required? end)
      |> Enum.map(fn {key, _} -> key end)

    {Map.new(schemas), required}
  end

  # Private functions

  defp merge_metadata(schema, properties, context) do
    metadata = get_entity_metadata(properties, context)

    schema
    # Note: Don't merge :title here as it's used internally as an atom map key
    # OpenAPI title should be retrieved separately via get_metadata when building specs
    |> maybe_put(:description, metadata[:description])
    |> maybe_put(:example, metadata[:example])
  end

  defp maybe_put(schema, _key, nil), do: schema
  defp maybe_put(schema, key, value), do: Map.put(schema, key, value)

  defp get_entity_metadata(%{name: name}, context) do
    resource = Map.get(context, :resource)
    entity_type = Map.get(context, :entity_type)
    action_name = Map.get(context, :action_name)

    cond do
      is_nil(resource) ->
        %{}

      entity_type == :argument && action_name ->
        AshOpenApi.Info.get_metadata(resource, :argument, {action_name, name})

      entity_type in [:attribute, :calculation, :relationship] ->
        AshOpenApi.Info.get_metadata(resource, entity_type, name)

      true ->
        %{}
    end
  end

  defp get_entity_metadata(_, _), do: %{}

  defp title(schema, %{name: name}), do: Map.put(schema, :title, name)
  defp title(schema, _), do: schema

  defp description(schema, %{description: description}),
    do: Map.put(schema, :description, description)

  defp description(schema, _), do: schema

  defp default(schema, %{default: default}) when not is_function(default),
    do: Map.put(schema, :default, default)

  defp default(schema, _), do: schema

  defp required?(%{allow_nil?: allow_nil?}), do: not allow_nil?
  defp required?(_), do: false

  defp type(schema, %{type: type, name: name} = properties, context) do
    storage_type = storage_type(type)
    embedded_type? = embedded_type?(type)
    new_type? = new_type?(type)
    constraints = constraints!(type, properties)
    enriched_context = Map.put(context, :field_name, name)

    do_type(schema, type, storage_type, embedded_type?, new_type?, constraints, enriched_context)
  end

  defp type(schema, %{type: type} = properties, context) do
    storage_type = storage_type(type)
    embedded_type? = embedded_type?(type)
    new_type? = new_type?(type)
    constraints = constraints!(type, properties)

    do_type(schema, type, storage_type, embedded_type?, new_type?, constraints, context)
  end

  defp do_type(schema, type, _storage_type, true, false, _constraints, context) do
    properties = AshOpenApi.Info.resource_attributes(Map.get(context, :resource, type))

    Map.merge(schema, %{type: :object, properties: properties})
  end

  defp do_type(schema, type, _storage_type, false, true, constraints, context) do
    {sub_type, sub_storage_type} =
      if sub_storage_type = open_api_type(type) do
        {get_type(sub_storage_type), sub_storage_type}
      else
        {subtype_of(type), storage_type(type)}
      end

    do_type(schema, sub_type, sub_storage_type, false, false, constraints, context)
  end

  defp do_type(schema, Type.Integer, :integer, false, false, _constraints, _context) do
    Map.put(schema, :type, :integer)
  end

  defp do_type(schema, Type.Boolean, :boolean, false, false, _constraints, _context) do
    Map.put(schema, :type, :boolean)
  end

  defp do_type(schema, Type.Atom, :string, false, false, constraints, _context) do
    enum = Keyword.get(constraints, :one_of, [])

    Map.merge(schema, %{type: :string, enum: enum})
  end

  defp do_type(schema, Type.String, :string, false, false, _constraints, _context) do
    Map.merge(schema, %{type: :string, format: :binary})
  end

  defp do_type(schema, Type.DateTime, :utc_datetime, false, false, _constraints, _context) do
    Map.merge(schema, %{type: :string, format: :"date-time"})
  end

  defp do_type(schema, Type.UUID, :uuid, false, false, _constraints, _context) do
    Map.merge(schema, %{type: :string, format: :uuid})
  end

  defp do_type(schema, Type.UUIDv7, :uuid, false, false, _constraints, _context) do
    Map.merge(schema, %{type: :string, format: :uuid})
  end

  defp do_type(schema, Type.Map, :map, false, false, constraints, context) do
    case Keyword.get(constraints, :fields) do
      nil ->
        Map.put(schema, :type, :object)

      fields ->
        {properties, required} =
          fields
          |> Enum.map(fn {key, properties} ->
            {field_schema, required?} =
              properties |> Map.new() |> Map.put(:name, key) |> build_schema(context)

            {{key, field_schema}, {key, required?}}
          end)
          |> split_schemas_and_required()

        Map.merge(schema, %{type: :object, properties: properties, required: required})
    end
  end

  defp do_type(schema, Type.Union, :map, false, false, constraints, context) do
    union_variants = get_union_variants_metadata(context)

    types =
      constraints
      |> Keyword.fetch!(:types)
      |> Enum.map(fn {key, properties} ->
        {variant_schema, _required?} =
          properties |> Map.new() |> Map.put(:name, key) |> build_schema(context)

        variant_metadata = Map.get(union_variants, key, %{})

        variant_schema
        |> apply_variant_metadata(variant_metadata)
      end)

    Map.put(schema, :oneOf, types)
  end

  defp do_type(schema, Type.Struct, :map, false, false, constraints, context) do
    fields = Keyword.fetch!(constraints, :fields)

    {properties, required} =
      fields
      |> Enum.map(fn {key, properties} ->
        {field_schema, required?} =
          properties |> Map.new() |> Map.put(:name, key) |> build_schema(context)

        {{key, field_schema}, {key, required?}}
      end)
      |> split_schemas_and_required()

    Map.merge(schema, %{type: :object, properties: properties, required: required})
  end

  defp do_type(
         schema,
         {:array, sub_type},
         {:array, sub_storage_type},
         false,
         false,
         constraints,
         context
       ) do
    sub_constraints = Keyword.get(constraints, :items, [])
    sub_embedded_type? = embedded_type?(sub_type)
    sub_new_type? = new_type?(sub_type)

    items =
      do_type(
        %{},
        sub_type,
        sub_storage_type,
        sub_embedded_type?,
        sub_new_type?,
        sub_constraints,
        context
      )

    Map.merge(schema, %{type: :array, items: items})
  end

  defp storage_type(type), do: Type.storage_type(type)

  defp open_api_type(type) when is_atom(type) do
    if Kernel.function_exported?(type, :open_api_type, 0) do
      type.open_api_type()
    end
  end

  defp open_api_type(_), do: nil

  defp embedded_type?(type), do: Type.embedded_type?(type)

  defp new_type?(type), do: Type.NewType.new_type?(type)

  defp subtype_of(type), do: Type.NewType.subtype_of(type)

  defp get_type(type), do: Type.get_type(type)

  defp constraints!(_type, %{constraints: constraints}), do: constraints

  defp constraints!(type, _constraints) do
    case Ash.Type.init(type, []) do
      {:ok, constraints} -> constraints
      {:error, _} -> []
    end
  end

  defp get_union_variants_metadata(%{
         resource: resource,
         entity_type: :argument,
         action_name: action_name,
         field_name: field_name
       }) do
    metadata = AshOpenApi.Info.get_metadata(resource, :argument, {action_name, field_name})
    Map.get(metadata, :union_variants, %{})
  end

  defp get_union_variants_metadata(%{
         resource: resource,
         entity_type: entity_type,
         field_name: field_name
       })
       when entity_type in [:attribute, :calculation] do
    metadata = AshOpenApi.Info.get_metadata(resource, entity_type, field_name)
    Map.get(metadata, :union_variants, %{})
  end

  defp get_union_variants_metadata(_context), do: %{}

  defp apply_variant_metadata(schema, metadata) when map_size(metadata) == 0, do: schema

  defp apply_variant_metadata(schema, metadata) do
    schema
    |> maybe_put(:title, metadata[:title])
    |> maybe_put(:description, metadata[:description])
    |> maybe_put(:example, metadata[:example])
  end
end
