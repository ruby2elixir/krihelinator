defmodule Krihelinator.ImportExport do
  @moduledoc """
  Tools to export all of the data from the DB into a single json, and
  to populate the DB from an existing one.
  """

  @doc """
  Populate the DB with data from json string.

  json: A string.
  repo: An Ecto repo.
  """
  def import_data(data, repo) do
    decoded = decode_data(data)
    do_import_data(decoded, repo)
    Enum.each(decoded, &fix_postgres_next_val(&1.model, repo))
  end

  defp decode_data(data) do
    data
    |> Poison.decode!(keys: :atoms!)
    |> Enum.map(fn model_data ->
      %{model_data | model: String.to_existing_atom(model_data.model)}
    end)
  end

  defp do_import_data(data, repo) do
    data
    |> Stream.flat_map(fn %{model: model, items: items} ->
      Stream.map(items, &create_changeset(model, &1))
    end)
    |> Enum.each(&repo.insert!/1)
  end

  # Fix for #163, reset postgres next_val
  defp fix_postgres_next_val(model, repo) do
    table = model.__schema__(:source)
    sql = "SELECT setval('#{table}_id_seq', (SELECT MAX(id) from \"#{table}\"));"
    Ecto.Adapters.SQL.query(repo, sql, [])
  end


  defp create_changeset(model, item) do
    associations = Enum.filter(item, fn {key, _} -> is_association_key?(key) end)
    {id, params} = Map.pop(item, :id)

    model
    |> struct(id: id)
    |> model.changeset(params)
    |> Ecto.Changeset.change(associations)
  end

  defp is_association_key?(key) do
    key
    |> Atom.to_string()
    |> String.ends_with?("_id")
  end

  @doc """
  A wrapper around the `export_data` function with the relevant models and
  repo.
  """
  def export_krihelinator_data() do
    alias Krihelinator.Github, as: GH
    models = [GH.Language, GH.Showcase, GH.Repo, Krihelinator.History.Language]
    repo = Krihelinator.Repo
    export_data(models, repo)
  end

  @doc """
  Create a json string of the data.

  models: A list of models (modules). The model is passed to `repo.all`.
    Models can derive from `Poison.Encoder` with the `:only` option to restrict
    serialized fields.
  repo: A module that have an `all` function that is called with the models to
    get all of the items for each model.
  """
  def export_data(models, repo) do
    models
    |> Stream.map(fn (model) ->
      %{model: Atom.to_string(model), items: repo.all(model)}
    end)
    |> Poison.encode!()
  end
end
