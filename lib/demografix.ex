defmodule Demografix do
  @moduledoc """
  Official Elixir client for the Demografix APIs: genderize, agify, and nationalize.

  One client covers all three services. Each call returns the prediction fields
  plus a `Demografix.Quota` read from the response rate-limit headers. Batch calls
  return a `Demografix.Batch` of per-name predictions in input order plus one
  quota for the whole response.

  ## Construction

      client = Demografix.new()                       # free per-IP tier
      client = Demografix.new("YOUR_API_KEY")         # with a key
      client = Demografix.new("YOUR_API_KEY", timeout: 5_000)

  ## Results and errors

  Each function returns `{:ok, result}` or `{:error, %Demografix.Error{}}`. The
  bang variants (`genderize!/3` and so on) return the result or raise the error.

      {:ok, result} = Demografix.genderize(client, "peter")
      result.gender          # => "male"
      result.quota.remaining # => 24987

  ## Aggregate over a list

  The services are built for summarizing a group of names, not labeling one person.

      {:ok, batch} = Demografix.genderize_batch(client, ["peter", "lois", "kim"])

      batch.results
      |> Enum.frequencies_by(& &1.gender)
      # => %{"male" => 1, "female" => 2}
  """

  alias Demografix.{Agify, Batch, Client, Error, Genderize, Nationalize}

  @type t :: Client.t()

  @doc """
  Build a client. `api_key` is optional; omit it for the free per-IP tier.

  ## Options

    * `:timeout` — receive timeout in milliseconds. Defaults to `10_000`.
  """
  @spec new(String.t() | nil, keyword()) :: t()
  defdelegate new(api_key \\ nil, opts \\ []), to: Client

  @doc """
  Predict the gender of one name.

  ## Options

    * `:country_id` — ISO 3166-1 alpha-2 code to scope the prediction. Echoed
      back uppercase on the result.
  """
  @spec genderize(t(), String.t(), keyword()) :: {:ok, Genderize.t()} | {:error, Error.t()}
  defdelegate genderize(client, name, opts \\ []), to: Client

  @doc """
  Predict the gender of up to 10 names.

  More than 10 names raises a client-side `Demografix.Error` of kind `:validation`
  before any request. Accepts the same `:country_id` option as `genderize/3`.
  """
  @spec genderize_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  defdelegate genderize_batch(client, names, opts \\ []), to: Client

  @doc """
  Predict the age of one name. Accepts the same `:country_id` option as
  `genderize/3`.
  """
  @spec agify(t(), String.t(), keyword()) :: {:ok, Agify.t()} | {:error, Error.t()}
  defdelegate agify(client, name, opts \\ []), to: Client

  @doc """
  Predict the age of up to 10 names. More than 10 names raises a client-side
  validation error before any request.
  """
  @spec agify_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  defdelegate agify_batch(client, names, opts \\ []), to: Client

  @doc """
  Predict the nationality of one name. Nationalize takes no `country_id`.
  """
  @spec nationalize(t(), String.t(), keyword()) :: {:ok, Nationalize.t()} | {:error, Error.t()}
  defdelegate nationalize(client, name, opts \\ []), to: Client

  @doc """
  Predict the nationality of up to 10 names. More than 10 names raises a
  client-side validation error before any request.
  """
  @spec nationalize_batch(t(), [String.t()], keyword()) :: {:ok, Batch.t()} | {:error, Error.t()}
  defdelegate nationalize_batch(client, names, opts \\ []), to: Client

  @doc "Like `genderize/3`, but returns the result or raises `Demografix.Error`."
  @spec genderize!(t(), String.t(), keyword()) :: Genderize.t()
  def genderize!(client, name, opts \\ []), do: unwrap(genderize(client, name, opts))

  @doc "Like `genderize_batch/3`, but returns the result or raises `Demografix.Error`."
  @spec genderize_batch!(t(), [String.t()], keyword()) :: Batch.t()
  def genderize_batch!(client, names, opts \\ []), do: unwrap(genderize_batch(client, names, opts))

  @doc "Like `agify/3`, but returns the result or raises `Demografix.Error`."
  @spec agify!(t(), String.t(), keyword()) :: Agify.t()
  def agify!(client, name, opts \\ []), do: unwrap(agify(client, name, opts))

  @doc "Like `agify_batch/3`, but returns the result or raises `Demografix.Error`."
  @spec agify_batch!(t(), [String.t()], keyword()) :: Batch.t()
  def agify_batch!(client, names, opts \\ []), do: unwrap(agify_batch(client, names, opts))

  @doc "Like `nationalize/3`, but returns the result or raises `Demografix.Error`."
  @spec nationalize!(t(), String.t(), keyword()) :: Nationalize.t()
  def nationalize!(client, name, opts \\ []), do: unwrap(nationalize(client, name, opts))

  @doc "Like `nationalize_batch/3`, but returns the result or raises `Demografix.Error`."
  @spec nationalize_batch!(t(), [String.t()], keyword()) :: Batch.t()
  def nationalize_batch!(client, names, opts \\ []),
    do: unwrap(nationalize_batch(client, names, opts))

  defp unwrap({:ok, result}), do: result
  defp unwrap({:error, %Error{} = error}), do: raise(error)
end
