defmodule AshOpenApi.Info do
  @moduledoc """
  Query API and schema generation for AshOpenApi extension.

  This module provides functions to generate OpenApiSpex schemas from
  Ash resources, automatically incorporating any OpenAPI metadata defined
  through the AshOpenApi extension.
  """

  alias AshOpenApi.Info.SchemaBuilder

  @doc """
  Generate an input schema for an action's arguments.
  """
  def action_input(resource, action, opts \\ []) do
    {properties, required} =
      resource
      |> action_arguments(action)
      |> Enum.map(fn {%{title: title} = argument, required?} ->
        {{title, argument}, {title, required?}}
      end)
      |> SchemaBuilder.split_schemas_and_required()

    opts |> Map.new() |> Map.merge(%{type: :object, properties: properties, required: required})
  end

  @doc """
  Generate an output schema for an action's return value.
  """
  def action_output(resource, action, opts \\ []) do
    opts = Map.new(opts)

    resource
    |> Ash.Resource.Info.action(action)
    |> SchemaBuilder.build_output_schema(opts, &resource_attributes/1, &resource_calculations/1)
  end

  @doc """
  Get all public resource attributes as schema tuples.
  """
  def resource_attributes(resource) do
    context = %{resource: resource, entity_type: :attribute}

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(& &1.public?)
    |> Enum.map(&SchemaBuilder.build_schema(&1, context))
  end

  @doc """
  Get all public resource calculations as schema tuples.
  """
  def resource_calculations(resource) do
    context = %{resource: resource, entity_type: :calculation}

    resource
    |> Ash.Resource.Info.calculations()
    |> Enum.filter(& &1.public?)
    |> Enum.map(&SchemaBuilder.build_schema(&1, context))
  end

  @doc """
  Get the description of an action.

  Returns the OpenAPI-defined description if available, otherwise falls back
  to the action's description field.
  """
  def action_description(resource, action) do
    metadata = get_metadata(resource, :action, action)

    metadata[:description] ||
      resource |> Ash.Resource.Info.action(action) |> Map.get(:description)
  end

  @doc """
  Get the title of an action.

  Returns the OpenAPI-defined title if available, otherwise returns nil.
  """
  def action_title(resource, action) do
    metadata = get_metadata(resource, :action, action)
    metadata[:title]
  end

  @doc """
  Get the code samples for an action.

  Returns a list of code sample maps, or nil if no samples are defined.
  Each map contains: %{lang: "...", source: "...", label: "..." (optional)}
  """
  def action_code_samples(resource, action) do
    metadata = get_metadata(resource, :action, action)
    metadata[:code_samples]
  end

  @doc """
  Get action arguments as schema tuples.
  """
  def action_arguments(resource, action) do
    context = %{resource: resource, entity_type: :argument, action_name: action}

    resource
    |> Ash.Resource.Info.action(action)
    |> Map.fetch!(:arguments)
    |> Enum.filter(& &1.public?)
    |> Enum.map(&SchemaBuilder.build_schema(&1, context))
  end

  @doc """
  Get OpenAPI metadata for a specific entity.

  Returns a map of metadata (e.g., `%{example: "value"}`) or an empty map
  if no metadata is defined.
  """
  def get_metadata(resource, entity_type, identifier)

  def get_metadata(resource, :attribute, name) do
    metadata_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_attributes, %{})
    Map.get(metadata_map, name, %{})
  end

  def get_metadata(resource, :argument, {action_name, arg_name}) do
    actions_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_actions, %{})

    case Map.get(actions_map, action_name) do
      nil -> %{}
      action_metadata -> Map.get(action_metadata.arguments, arg_name, %{})
    end
  end

  def get_metadata(resource, :action_attribute, {action_name, attr_name}) do
    actions_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_actions, %{})

    case Map.get(actions_map, action_name) do
      nil ->
        # Fall back to default attribute metadata
        get_metadata(resource, :attribute, attr_name)

      action_metadata ->
        case Map.get(action_metadata.attributes, attr_name) do
          nil ->
            # No action-specific override, fall back to default
            get_metadata(resource, :attribute, attr_name)

          metadata ->
            metadata
        end
    end
  end

  def get_metadata(resource, :calculation, name) do
    metadata_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_calculations, %{})
    Map.get(metadata_map, name, %{})
  end

  def get_metadata(resource, :relationship, name) do
    metadata_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_relationships, %{})
    Map.get(metadata_map, name, %{})
  end

  def get_metadata(resource, :action, name) do
    actions_map = Spark.Dsl.Extension.get_persisted(resource, :open_api_actions, %{})

    case Map.get(actions_map, name) do
      nil -> %{}
      action_metadata -> Map.take(action_metadata, [:title, :description, :code_samples])
    end
  end
end
