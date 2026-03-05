defmodule AshOpenApi.DslTest do
  @moduledoc false

  use ExUnit.Case, async: true

  defmodule TestDomain do
    @moduledoc false

    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TestResource do
    @moduledoc false

    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshOpenApi]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, public?: true
      attribute :status, :atom, constraints: [one_of: [:active, :inactive]], public?: true
    end

    calculations do
      calculate :display_name, :string, expr(name <> " (" <> email <> ")"), public?: true
      calculate :is_active, :boolean, expr(status == :active), public?: true
    end

    actions do
      default_accept [:name, :email, :status]
      defaults [:read, :destroy]

      create :create do
        accept [:name, :email, :status]
      end

      update :update do
        accept [:name, :email, :status]
      end

      action :custom_action, :struct do
        argument :query, :string, allow_nil?: false
        argument :limit, :integer

        constraints instance_of: __MODULE__
        run fn _input, _context -> {:ok, %__MODULE__{}} end
      end
    end

    open_api do
      attributes do
        attribute :id, example: "abc123", title: "Resource ID", description: "Unique identifier"
        attribute :name, example: "John Doe", title: "Full Name"
        attribute :email, example: "john@example.com", description: "Email address"
        attribute :status, example: "active"
      end

      calculations do
        calculation(:display_name, example: "John Doe (john@example.com)", title: "Display Name")
        calculation(:is_active, example: true, description: "Whether the resource is active")
      end

      actions do
        action :create do
          title "Create Resource"
          description "Creates a new resource with the provided attributes"

          code_sample(
            lang: "elixir",
            label: "Basic creation",
            source: """
            TestResource.create(%{name: "John", email: "john@example.com"})
            """
          )

          code_sample(
            lang: "curl",
            source: """
            curl -X POST /api/resources -d '{"name": "John"}'
            """
          )

          argument :name, example: "Jane Doe", title: "User Name"
          argument :email, example: "jane@example.com", description: "User email address"
          argument :status, example: "inactive"

          attribute :status,
            example: "pending",
            title: "Initial Status",
            description: "Status after creation"
        end

        action :update do
          title "Update Resource"

          argument :name, example: "Updated Name"
        end

        action :custom_action do
          description "Performs a custom action"

          code_sample(lang: "elixir", source: "TestResource.custom_action(%{query: \"test\"})")

          argument :query, example: "search term", title: "Search Query"
          argument :limit, example: 10, description: "Maximum results"
        end
      end
    end
  end

  describe "attributes metadata" do
    test "stores attribute metadata with all fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_attributes, %{})

      assert metadata[:id] == %{
               example: "abc123",
               title: "Resource ID",
               description: "Unique identifier"
             }
    end

    test "stores attribute metadata with partial fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_attributes, %{})

      assert metadata[:name] == %{example: "John Doe", title: "Full Name"}
      assert metadata[:email] == %{example: "john@example.com", description: "Email address"}
      assert metadata[:status] == %{example: "active"}
    end

    test "retrieves attribute metadata via Info.get_metadata" do
      assert AshOpenApi.Info.get_metadata(TestResource, :attribute, :id) == %{
               example: "abc123",
               title: "Resource ID",
               description: "Unique identifier"
             }

      assert AshOpenApi.Info.get_metadata(TestResource, :attribute, :name) == %{
               example: "John Doe",
               title: "Full Name"
             }
    end

    test "returns empty map for undefined attributes" do
      assert AshOpenApi.Info.get_metadata(TestResource, :attribute, :undefined) == %{}
    end
  end

  describe "calculations metadata" do
    test "stores calculation metadata with all fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_calculations, %{})

      assert metadata[:display_name] == %{
               example: "John Doe (john@example.com)",
               title: "Display Name"
             }
    end

    test "stores calculation metadata with partial fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_calculations, %{})

      assert metadata[:is_active] == %{
               example: true,
               description: "Whether the resource is active"
             }
    end

    test "retrieves calculation metadata via Info.get_metadata" do
      assert AshOpenApi.Info.get_metadata(TestResource, :calculation, :display_name) == %{
               example: "John Doe (john@example.com)",
               title: "Display Name"
             }
    end

    test "returns empty map for undefined calculations" do
      assert AshOpenApi.Info.get_metadata(TestResource, :calculation, :undefined) == %{}
    end
  end

  describe "actions metadata" do
    test "stores action-level title and description" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert metadata[:create][:title] == "Create Resource"

      assert metadata[:create][:description] ==
               "Creates a new resource with the provided attributes"

      assert metadata[:update][:title] == "Update Resource"
      assert metadata[:update][:description] == nil

      assert metadata[:custom_action][:title] == nil
      assert metadata[:custom_action][:description] == "Performs a custom action"
    end

    test "stores code samples for actions" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert [sample1, sample2] = metadata[:create][:code_samples]

      assert sample1 == %{
               lang: "elixir",
               label: "Basic creation",
               source: "TestResource.create(%{name: \"John\", email: \"john@example.com\"})\n"
             }

      assert sample2 == %{
               lang: "curl",
               source: "curl -X POST /api/resources -d '{\"name\": \"John\"}'\n"
             }
    end

    test "stores code samples without label" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert [sample] = metadata[:custom_action][:code_samples]

      assert sample == %{
               lang: "elixir",
               source: "TestResource.custom_action(%{query: \"test\"})"
             }
    end

    test "returns nil for actions without code samples" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert metadata[:update][:code_samples] == nil
    end

    test "retrieves action title via Info.action_title" do
      assert AshOpenApi.Info.action_title(TestResource, :create) == "Create Resource"
      assert AshOpenApi.Info.action_title(TestResource, :update) == "Update Resource"
      assert AshOpenApi.Info.action_title(TestResource, :custom_action) == nil
    end

    test "retrieves action description via Info.action_description" do
      assert AshOpenApi.Info.action_description(TestResource, :create) ==
               "Creates a new resource with the provided attributes"

      assert AshOpenApi.Info.action_description(TestResource, :custom_action) ==
               "Performs a custom action"
    end

    test "retrieves code samples via Info.action_code_samples" do
      samples = AshOpenApi.Info.action_code_samples(TestResource, :create)
      assert length(samples) == 2
      assert Enum.at(samples, 0)[:lang] == "elixir"
      assert Enum.at(samples, 1)[:lang] == "curl"

      samples = AshOpenApi.Info.action_code_samples(TestResource, :custom_action)
      assert length(samples) == 1

      assert AshOpenApi.Info.action_code_samples(TestResource, :update) == nil
    end
  end

  describe "action arguments metadata" do
    test "stores argument metadata with all fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert metadata[:custom_action][:arguments][:query] == %{
               example: "search term",
               title: "Search Query"
             }

      assert metadata[:custom_action][:arguments][:limit] == %{
               example: 10,
               description: "Maximum results"
             }
    end

    test "stores argument metadata with partial fields" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert metadata[:create][:arguments][:name] == %{example: "Jane Doe", title: "User Name"}

      assert metadata[:create][:arguments][:email] == %{
               example: "jane@example.com",
               description: "User email address"
             }

      assert metadata[:create][:arguments][:status] == %{example: "inactive"}
    end

    test "retrieves argument metadata via Info.get_metadata" do
      assert AshOpenApi.Info.get_metadata(TestResource, :argument, {:create, :name}) == %{
               example: "Jane Doe",
               title: "User Name"
             }

      assert AshOpenApi.Info.get_metadata(TestResource, :argument, {:custom_action, :query}) == %{
               example: "search term",
               title: "Search Query"
             }
    end

    test "returns empty map for undefined arguments" do
      assert AshOpenApi.Info.get_metadata(TestResource, :argument, {:create, :undefined}) == %{}
      assert AshOpenApi.Info.get_metadata(TestResource, :argument, {:undefined, :name}) == %{}
    end
  end

  describe "action attributes metadata with merge" do
    test "stores action-specific attribute metadata" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      assert metadata[:create][:attributes][:status] == %{
               example: "pending",
               title: "Initial Status",
               description: "Status after creation"
             }
    end

    test "merges action-specific metadata with default attribute metadata" do
      # Default attribute metadata
      attr_metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_attributes, %{})
      assert attr_metadata[:status] == %{example: "active"}

      # Action-specific metadata should override
      assert AshOpenApi.Info.get_metadata(TestResource, :action_attribute, {:create, :status}) ==
               %{
                 example: "pending",
                 title: "Initial Status",
                 description: "Status after creation"
               }
    end

    test "falls back to default attribute metadata when no action override" do
      # :id has default metadata but no action-specific override
      assert AshOpenApi.Info.get_metadata(TestResource, :action_attribute, {:create, :id}) == %{
               example: "abc123",
               title: "Resource ID",
               description: "Unique identifier"
             }
    end

    test "returns empty map for undefined action attributes" do
      assert AshOpenApi.Info.get_metadata(TestResource, :action_attribute, {:create, :undefined}) ==
               %{}
    end

    test "falls back to default metadata for undefined action" do
      # When action doesn't exist, it falls back to default attribute metadata if available
      assert AshOpenApi.Info.get_metadata(TestResource, :action_attribute, {:undefined, :status}) ==
               %{example: "active"}

      # But returns empty map if attribute itself doesn't have default metadata
      assert AshOpenApi.Info.get_metadata(
               TestResource,
               :action_attribute,
               {:undefined, :nonexistent}
             ) ==
               %{}
    end
  end

  describe "edge cases" do
    test "handles nil values gracefully" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      # Action with partial metadata
      assert metadata[:update][:description] == nil
      assert metadata[:update][:code_samples] == nil
    end

    test "handles empty actions" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      # Actions not defined in open_api block should have empty metadata
      assert metadata[:destroy] == nil
      assert metadata[:read] == nil
    end

    test "handles actions with only some nested entities" do
      metadata = Spark.Dsl.Extension.get_persisted(TestResource, :open_api_actions, %{})

      # :update only has title and one argument
      assert metadata[:update][:title] == "Update Resource"
      assert metadata[:update][:description] == nil
      assert metadata[:update][:code_samples] == nil
      assert map_size(metadata[:update][:arguments]) == 1
      assert map_size(metadata[:update][:attributes]) == 0
    end
  end
end
