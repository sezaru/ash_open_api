defmodule AshOpenApi.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    attributes_metadata = build_entity_metadata(dsl_state, [:open_api, :attributes])
    calculations_metadata = build_entity_metadata(dsl_state, [:open_api, :calculations])
    relationships_metadata = build_entity_metadata(dsl_state, [:open_api, :relationships])
    actions_metadata = build_actions_metadata(dsl_state, attributes_metadata)

    dsl_state
    |> Spark.Dsl.Transformer.persist(:open_api_attributes, attributes_metadata)
    |> Spark.Dsl.Transformer.persist(:open_api_calculations, calculations_metadata)
    |> Spark.Dsl.Transformer.persist(:open_api_relationships, relationships_metadata)
    |> Spark.Dsl.Transformer.persist(:open_api_actions, actions_metadata)
    |> then(&{:ok, &1})
  end

  # Build metadata map for simple entities (attributes, calculations, relationships)
  defp build_entity_metadata(dsl_state, path) do
    dsl_state
    |> Spark.Dsl.Extension.get_entities(path)
    |> Enum.map(fn entity ->
      metadata = build_metadata_map(entity)
      {entity.name, metadata}
    end)
    |> Map.new()
  end

  # Build metadata map for actions with nested entities
  defp build_actions_metadata(dsl_state, attributes_metadata) do
    dsl_state
    |> Spark.Dsl.Extension.get_entities([:open_api, :actions])
    |> Enum.map(fn action ->
      action_metadata = build_action_metadata(action, attributes_metadata)
      {action.name, action_metadata}
    end)
    |> Map.new()
  end

  # Build metadata for a single action
  defp build_action_metadata(action, attributes_metadata) do
    %{}
    |> maybe_put(:title, extract_nested_value(action.title))
    |> maybe_put(:description, extract_nested_value(action.description))
    |> maybe_put(:code_samples, build_code_samples(action.code_samples))
    |> maybe_put(:code_sample_mfas, build_code_sample_mfas(action.code_sample_mfas))
    |> Map.put(:attributes, build_action_attributes(action.attributes, attributes_metadata))
    |> Map.put(:arguments, build_action_arguments(action.arguments))
  end

  # Build metadata for action attributes with merge logic
  defp build_action_attributes(attributes, defaults_metadata) do
    (attributes || [])
    |> Enum.map(fn attr ->
      default_config = Map.get(defaults_metadata, attr.name, %{})
      action_config = build_metadata_map(attr)
      merged_config = Map.merge(default_config, action_config)

      {attr.name, merged_config}
    end)
    |> Map.new()
  end

  # Build metadata for action arguments
  defp build_action_arguments(arguments) do
    (arguments || [])
    |> Enum.map(fn arg ->
      metadata = build_metadata_map(arg)
      {arg.name, metadata}
    end)
    |> Map.new()
  end

  # Build code samples list from inline DSL entities
  defp build_code_samples(nil), do: nil
  defp build_code_samples([]), do: nil

  defp build_code_samples(code_samples) do
    code_samples
    |> Enum.map(fn sample ->
      %{}
      |> Map.put(:lang, sample.lang)
      |> maybe_put(:label, sample.label)
      |> Map.put(:source, sample.source)
    end)
  end

  # Persist MFA tuples for code_sample_mfa entities (resolved lazily at runtime)
  defp build_code_sample_mfas(nil), do: nil
  defp build_code_sample_mfas([]), do: nil
  defp build_code_sample_mfas(entries), do: Enum.map(entries, & &1.mfa)

  # Build metadata map from entity fields
  defp build_metadata_map(entity) do
    %{}
    |> maybe_put(:title, entity.title)
    |> maybe_put(:description, entity.description)
    |> maybe_put(:example, entity.example)
  end

  # Extract value from nested entity (for action title/description)
  defp extract_nested_value([%{value: value}]), do: value
  defp extract_nested_value(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
